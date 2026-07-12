# Lab 4.4: Adding a File Output to the Consumer

## Lab Overview

In this lab you will extend the consumer you built in Lab 4.3 by adding a second `StatisticsCollector` implementation. The new collector writes each statistic to a CSV file rather than printing it to the console. The consumer's listener does not change. The transformation does not change. The Kafka configuration does not change. Only the collector changes, and a single property in `application.yml` determines which one Spring uses.

This lab is the payoff for the design decision you made in Lab 4.3, when you defined `StatisticsCollector` as an interface with a console implementation. By making the output destination swappable, the consumer is ready to be extended with new outputs without touching the listener that drives them. The same pattern would let you add a database collector, a remote API collector, or anything else.

By the end of this lab you will:

- Add a new `StatisticsCollector` implementation that writes CSV records to a file
- Use Spring's `@ConditionalOnProperty` to select which collector is active based on a configuration value
- Use the `@PreDestroy` lifecycle hook to clean up resources when the application shuts down
- Understand the architectural value of designing for swappability

This lab is short and focused. It is meant to reinforce the architectural lesson from Lab 4.3 with a concrete, working extension.

## Prerequisites

- Lab 4.3 completed successfully, with a working consumer project
- Lab 4.2 producer project still available (we will run it alongside the consumer)
- The three-broker Kafka cluster from Lab 4.1 available
- The `transactions` topic exists on the cluster
- Java 21 installed and on your `PATH`
- IntelliJ IDEA Ultimate

If your Kafka cluster is not currently running, start it now:

```
cd C:\kafka-docker
docker compose up -d
```

Wait 30 to 60 seconds for all three brokers to come up, then verify:

```
docker compose ps
```

You should see `kafka1`, `kafka2`, and `kafka3` all showing state `Up`. Leave the cluster running for the rest of the lab.

## Section 1: Adding the File Collector

Open your `transconsumer` project in IntelliJ.

### 1.1 Create the Output Directory

The file collector will write to `C:\kafka-data\transactions-output.csv`. Create the directory now:

```
mkdir C:\kafka-data
```

We are using a neutral location outside the Kafka Docker directory and outside the project. This avoids two common issues: permission problems with directories created by other users, and accidental version-control tracking of generated output files.

Note that this directory is separate from the Docker volumes used by the Kafka cluster. The CSV file is written by the consumer (running on the Windows host), not by anything inside a container.

### 1.2 Make the Console Collector Conditional

Currently `ConsoleStatisticsCollector` is annotated with `@Service`, which registers it as the default `StatisticsCollector` bean. We are about to add a second implementation, so we need a way to choose between them.

Open `ConsoleStatisticsCollector.java` and add a `@ConditionalOnProperty` annotation:

```java
package com.example.transconsumer.service;

import com.example.transconsumer.model.TransactionStatistic;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(name = "app.collector", havingValue = "console", matchIfMissing = true)
public class ConsoleStatisticsCollector implements StatisticsCollector {

    private static final Logger log = LoggerFactory.getLogger(ConsoleStatisticsCollector.class);

    @Override
    public void collect(TransactionStatistic statistic) {
        log.info("Statistic -> {} {}",
            String.format("%-15s", statistic.type()),
            statistic.amount());
    }
}
```

The new annotation tells Spring: "only register this bean if the `app.collector` property has the value `console`, OR if the property is missing altogether." The `matchIfMissing = true` part is important — without it, the bean would not be registered when the property is absent, and the consumer would fail to start with no `StatisticsCollector` available.

This means the existing behavior (console output) is preserved as the default. If `app.collector` is not set in `application.yml`, or if it is explicitly set to `console`, you get the console collector.

### 1.3 Create the FileStatisticsCollector

In the `service` package, add `FileStatisticsCollector.java`:

```java
package com.example.transconsumer.service;

import com.example.transconsumer.model.TransactionStatistic;

import jakarta.annotation.PreDestroy;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.Instant;

@Service
@ConditionalOnProperty(name = "app.collector", havingValue = "file")
public class FileStatisticsCollector implements StatisticsCollector {

    private static final Logger log = LoggerFactory.getLogger(FileStatisticsCollector.class);
    private static final Path OUTPUT_PATH = Paths.get("C:/kafka-data/transactions-output.csv");

    private final BufferedWriter writer;

    public FileStatisticsCollector() throws IOException {
        Files.createDirectories(OUTPUT_PATH.getParent());
        boolean fileIsNew = !Files.exists(OUTPUT_PATH);

        this.writer = Files.newBufferedWriter(
            OUTPUT_PATH,
            StandardOpenOption.CREATE,
            StandardOpenOption.APPEND
        );

        if (fileIsNew) {
            writer.write("timestamp,type,amount");
            writer.newLine();
            writer.flush();
        }

        log.info("FileStatisticsCollector writing to {}", OUTPUT_PATH);
    }

    @Override
    public void collect(TransactionStatistic statistic) {
        try {
            writer.write(String.format("%s,%s,%s",
                Instant.now(),
                statistic.type(),
                statistic.amount()));
            writer.newLine();
            writer.flush();
        } catch (IOException e) {
            log.error("Failed to write statistic to file", e);
        }
    }

    @PreDestroy
    public void close() throws IOException {
        log.info("Closing file output writer");
        writer.close();
    }
}
```

Walk through this carefully — there are several patterns worth understanding.

**The `@ConditionalOnProperty(name = "app.collector", havingValue = "file")`** registers this bean only when the property is set to `file`. Notice there is no `matchIfMissing = true` here: this collector should only run when explicitly chosen.

**The constructor opens the file once, when Spring creates the bean.** It uses `Files.createDirectories` to ensure the parent directory exists, then opens a `BufferedWriter` in append mode. The bean's lifetime is the application's lifetime, so a single open file handle is held for the entire run. This is much more efficient than opening and closing the file for every record.

**The CSV header is written only when the file is new.** Because we are appending across runs, we do not want to write a header line every time the consumer restarts. The `fileIsNew` flag captures whether the file existed before we opened it, and we write the header only on first creation.

**The `collect` method writes one CSV line per statistic.** Each line has three fields: a timestamp, the transaction type, and the amount. The timestamp is generated at write time (`Instant.now()`) rather than coming from the original transaction. In a real analytics use case you might use the transaction's own timestamp; for this lab the write time is fine and demonstrates a useful auditing pattern (when did the consumer process this?).

**`writer.flush()` is called after every write.** Without this, lines would sit in the writer's internal buffer and only appear in the file when the buffer fills up or the writer closes. Flushing after each write means you can `type` the file and see fresh content while the consumer is running. The performance cost is small for our one-event-per-second rate; for very high-throughput producers you would batch flushes instead.

**The `@PreDestroy` annotation** registers the `close()` method as a Spring lifecycle callback. When the application shuts down (Ctrl+F2 in IntelliJ, Ctrl+C in a terminal, or a graceful shutdown signal), Spring will call this method before the bean is destroyed. This ensures the file writer is closed cleanly and any buffered data is flushed.

### 1.4 Configure the Active Collector

Open `application.yml` and add an `app:` section at the bottom of the file:

```yaml
spring:
  main:
    web-application-type: none
  application:
    name: transconsumer

  kafka:
    bootstrap-servers: localhost:9092,localhost:9094,localhost:9096
    consumer:
      group-id: transconsumergroup
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      properties:
        spring.json.use.type.headers: false
        spring.json.value.default.type: com.example.transconsumer.model.Transaction
        spring.json.trusted.packages: "com.example.transconsumer.model"

logging:
  level:
    com.example.transconsumer: INFO

app:
  collector: file
```

The `app.collector: file` setting tells Spring to use the `FileStatisticsCollector`. Spring evaluates the `@ConditionalOnProperty` annotations on each implementation, finds that `FileStatisticsCollector` matches and `ConsoleStatisticsCollector` does not, and registers only the file collector.

The `app:` prefix is an arbitrary choice for properties that belong to your application rather than to the Spring framework or to a library. By convention, application-specific properties are grouped under a prefix that identifies the application or feature area.

Notice that the Kafka configuration is unchanged from Lab 4.3. The three-broker cluster setup, the JSON deserialization, and the consumer group are all the same. Only the output mechanism is being modified.

## Section 2: Running the End-to-End Flow

### 2.1 Confirm the Producer Is Available

Open the Lab 4.2 producer project in a separate IntelliJ window. The three-broker Kafka cluster should already be running.

### 2.2 Start the Producer

Run `TransproducerApplication`. Confirm that you see transaction sends being logged. Leave it running.

### 2.3 Start the Consumer

Switch to the consumer project and run `TransconsumerApplication`.

In the consumer's startup output, look for the line:

```
FileStatisticsCollector writing to C:\kafka-data\transactions-output.csv
```

This confirms that the file collector was selected and the file was opened successfully. You will not see any `Statistic ->` console log lines this time, because the console collector is no longer active.

You will still see `Received key=... partition=... offset=...` lines, because the listener still logs each incoming record. Only the per-statistic output destination has changed.

### 2.4 Watch the File Grow

Open a new Command Prompt window and watch the file:

```
type C:\kafka-data\transactions-output.csv
```

You should see content like this:

```
timestamp,type,amount
2026-04-25T15:30:42.123Z,DEPOSIT,89.15
2026-04-25T15:30:42.456Z,SERVICE_CHARGE,12.00
2026-04-25T15:30:43.012Z,PURCHASE,247.32
2026-04-25T15:30:43.789Z,WITHDRAWAL,412.88
2026-04-25T15:30:44.234Z,PAYMENT,156.40
```

The header line is at the top. Each subsequent line is one transaction statistic, in CSV format. Run the `type` command a few more times and watch new lines appear at the bottom.

### 2.5 Open the File in Excel (Optional)

Because the output is standard CSV with a header line, Excel can open it directly. Double-click the file, or open Excel and import the CSV. You should see three columns (timestamp, type, amount) populated with the data.

This demonstrates one of the practical benefits of CSV as a format: it integrates with standard tooling without any extra effort. Real analytics pipelines often produce CSV exactly because so many downstream tools accept it natively.

### 2.6 Stop the Consumer Cleanly

In IntelliJ, click the red stop button on the consumer (or press Ctrl+F2). Watch the IntelliJ console for the shutdown sequence:

```
Closing file output writer
```

This is the `@PreDestroy` method running during graceful shutdown. The file is being closed cleanly, and any buffered data is flushed to disk.

If you stop the consumer abruptly (force-kill the JVM, close the window without using the stop button), the `@PreDestroy` method does not run. The OS will eventually close the file handle when the process dies, but the close will not be a clean Spring lifecycle event. For production applications, configuring proper shutdown handling is important.

### 2.7 Restart and Append

Start the consumer again. You should see another:

```
FileStatisticsCollector writing to C:\kafka-data\transactions-output.csv
```

But this time, no header is written, because the file already existed when the constructor opened it.

`type C:\kafka-data\transactions-output.csv` will show the original content from the previous run plus new lines being appended at the bottom. The CSV is now a cumulative record of every statistic the consumer has ever processed.

In a real system you might rotate this file daily or weekly, or stream it to a log aggregator. For a lab, the append-forever behavior is fine.

## Section 3: Optional Exploration

### 3.1 Switch Between Collectors

Stop the consumer. Open `application.yml` and change the property:

```yaml
app:
  collector: console
```

Start the consumer again. You should see:

- No `FileStatisticsCollector writing to...` line at startup
- Console output resumes: `Statistic -> PURCHASE         247.32`
- The CSV file is no longer being written to

This is a dynamic switch: by changing one line in configuration, you have changed which output the consumer uses, with no code changes and no rebuild. Spring evaluated the conditions at startup and registered only the matching bean.

This is the architectural value of the design pattern from Lab 4.3, made concrete. The listener, the deserialization, the transformation, and the Kafka configuration are all unchanged. Only the output target changed, and it changed by changing data, not code.

You can switch back and forth as many times as you like. When you are done, set `app.collector: file` again so the next steps work.

### 3.2 What Happens with No Setting

For practice, comment out the `app.collector` line:

```yaml
# app:
#   collector: file
```

Start the consumer. Because of the `matchIfMissing = true` on `ConsoleStatisticsCollector`, it activates by default when the property is absent. The console output resumes.

This default behavior is a deliberate design choice: if a configuration value is missing, fall back to the safest, simplest behavior (console logging) rather than failing to start. Other defaults are valid in different scenarios, but for a worker that produces side effects, "if nothing is configured, just log to console" is usually the right behavior.

Restore the `app.collector: file` setting before continuing.

### 3.3 Stop a Broker and Watch the File Keep Growing

This exercise builds on the broker-failure exercise from Lab 4.1 and the one you tried in Lab 4.3, this time observing it from the file collector's perspective.

With both producer and consumer running and the file collector active, open a Command Prompt:

```
cd C:\kafka-docker
docker compose stop kafka2
```

Then watch the CSV file:

```
type C:\kafka-data\transactions-output.csv
```

After a brief pause (during which the cluster elects new leaders and the producer/consumer reconnect), new lines should continue being appended. The end-to-end pipeline — producer to Kafka cluster to consumer to CSV file — keeps working through the broker outage.

The CSV file is just persistent storage on your local disk. The Kafka cluster is providing the durable transport between the producer and consumer, and the cluster's replication ensures that the data flowing through that pipeline is not lost when a broker goes down. Three brokers, replication factor 3, `min.insync.replicas=2`, and `acks=all` — the production-grade durability setup you configured in Lab 4.2 — all working together.

Bring the broker back when you're done:

```
docker compose start kafka2
```

### 3.4 Sidebar: Kafka Connect

What you have built in this lab is, in effect, a small custom version of what Kafka Connect's `FileStreamSinkConnector` does out of the box. Kafka Connect is a separate framework for moving data between Kafka and external systems without writing code. You configure it with a JSON file and run it as a separate process; it consumes from a topic and writes to a file (or database, or S3 bucket, or many other destinations) using pre-built connectors.

So why didn't we use Kafka Connect for this lab? Two reasons:

**The consumer's responsibility is broader than just writing.** The Lab 4.3 listener transforms `Transaction` into `TransactionStatistic`. It logs the partition and offset. It might, in a future lab, do validation, enrichment, or fan out to multiple destinations. Kafka Connect is great for "consume and dump to destination" — once you need any meaningful processing in between, you are writing code, and the natural place to write that code is a Spring Kafka application.

**This lab is teaching software engineering, not tooling.** The lesson here is "design for swappable implementations" — a pattern you will use everywhere, in Kafka and outside it. Kafka Connect is a specific tool that is worth knowing exists, but it is not what we are teaching today.

In a production system you would use Connect for the "boring" pipelines (ingest a topic to a data lake, mirror data from one cluster to another) and write Spring Kafka applications for anything that involves business logic. Both are valid; they solve different problems.

## Section 4: Wrapping Up

### 4.1 What to Leave Running

You can stop the producer and consumer. The CSV file remains on disk and can be inspected anytime. The Kafka cluster can be left running or stopped (with `docker compose down` to remove the containers, or `docker compose stop` to keep the data for a later session) as you prefer.

### 4.2 What You Have Learned

In this lab you have:

- Added a second `StatisticsCollector` implementation without changing any other class
- Used `@ConditionalOnProperty` to make Spring select an implementation based on a configuration value
- Used `@PreDestroy` to clean up file resources on application shutdown
- Switched between two implementations by changing a single line of configuration
- Seen the practical value of designing for swappability

The bigger takeaway is architectural. The Lab 4.3 design — interface plus implementations, listener depending on the interface — created a seam in the application. This lab plugged a new implementation into that seam without disturbing anything else. In a real codebase, this is what good design feels like in daily work: extensions land lightly, and the existing tests, behaviors, and assumptions hold.

If a future lab adds a database insert, the change will look almost identical to this one. New collector class, new configuration value, listener unchanged.

### 4.3 Self-Check

Before moving on, you should be able to answer these questions:

1. What does `@ConditionalOnProperty` do, and what would happen if you set `app.collector: redis` (a value that no implementation recognizes)?
2. Why does `ConsoleStatisticsCollector` have `matchIfMissing = true` but `FileStatisticsCollector` does not?
3. What does `@PreDestroy` do, and what would go wrong if the file collector did not have it?
4. Why does the constructor write the CSV header only when the file is new, rather than every time the consumer starts?
5. Why does the `collect` method call `writer.flush()` after every write?
6. The listener class (`TransactionListener`) was not modified at all in this lab. What design decision in Lab 4.3 made that possible?
7. If you wanted to add a third implementation that wrote to a database, what classes would you need to create or modify?
8. The Kafka cluster configuration was not changed at all in this lab. Why is that significant? What does it tell you about the boundary between the Kafka concerns and the application concerns?

If any of these are unclear, review the relevant section of the lab before continuing.

## End of Lab 4.4
