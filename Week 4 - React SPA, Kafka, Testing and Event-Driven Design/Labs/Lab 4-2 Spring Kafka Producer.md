# Lab 4.2: Building a Spring Kafka Producer

## Lab Overview

In this lab you will build a Spring Boot application that produces a stream of transaction events to a Kafka topic on the three-broker cluster you set up in Lab 4.1. The application simulates an aggregator that collects transactions from many endpoints (ATMs, point-of-sale systems, online portals) and publishes each transaction as a Kafka event for downstream consumers to process.

The previous lab introduced Kafka at the command line, where you produced and consumed messages by typing into a terminal. This lab moves the producer side into a real Spring Boot application using Spring for Apache Kafka, while keeping the consumer side at the command line so you can verify what your producer is doing.

By the end of this lab you will:

- Create a Kafka topic with production-grade replication settings
- Build a Spring Boot Kafka producer using `KafkaTemplate`
- Use a record type as your event payload, serialized as JSON
- Configure the producer for durability and idempotency
- Use account ID as the message key to demonstrate per-entity ordering
- Observe partition assignment in real time using a `whenComplete` callback
- Verify the producer's behavior with the console consumer

This lab keeps the focus on the **producer** side of Spring Kafka. Lab 4.3 will build a Spring Boot consumer for the same topic.

## Prerequisites

- Lab 4.1 completed successfully
- The three-broker Kafka cluster from Lab 4.1 running in Docker
- Java 21 installed and on your `PATH`
- IntelliJ IDEA Ultimate
- Internet access to use Spring Initializr (`start.spring.io`)

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

## Section 1: Creating the Topic

### 1.1 Create the `transactions` Topic

From `C:\kafka-docker`, create the topic using the CLI inside the `kafka1` container:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --create --topic transactions --bootstrap-server localhost:19092 --partitions 3 --replication-factor 3 --config min.insync.replicas=2
```

You should see:

```
Created topic transactions.
```

Let's break down the new options:

- **`--replication-factor 3`** says there should be three copies of each partition, spread across the three brokers. This is the standard production replication factor and matches what you used in Lab 4.1.

- **`--config min.insync.replicas=2`** sets a topic-level configuration: writes acknowledged with `acks=all` must be replicated to at least 2 of the 3 in-sync replicas before the broker confirms success. This is the production-grade durability setting we discussed in the course material. Combined with `acks=all` on the producer side (which you will configure shortly), this means data is durable even if one broker fails.

The choice of three partitions is deliberate. With three partitions and a small set of account IDs as keys, you will be able to observe how Kafka's hash-based partitioning distributes events across partitions while keeping all events for the same account together on the same partition.

### 1.2 Verify the Topic

Confirm the topic was created and inspect its layout:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic transactions --bootstrap-server localhost:19092
```

You should see output similar to:

```
Topic: transactions   TopicId: ...   PartitionCount: 3   ReplicationFactor: 3   Configs: min.insync.replicas=2
        Topic: transactions   Partition: 0    Leader: 1   Replicas: 1,2,3   Isr: 1,2,3   Elr:    LastKnownElr:
        Topic: transactions   Partition: 1    Leader: 2   Replicas: 2,3,1   Isr: 2,3,1   Elr:    LastKnownElr:
        Topic: transactions   Partition: 2    Leader: 3   Replicas: 3,1,2   Isr: 3,1,2   Elr:    LastKnownElr:
```

(Your specific leader assignments may differ.) Three partitions, each with three replicas spread across the three brokers, all in-sync. Leadership distributed across the brokers. The `min.insync.replicas=2` setting is shown in the Configs column. The topic is now ready to receive events.

### 1.3 Why This Design

A few notes on the design choices, which you can refer back to as you build the producer:

**Three partitions** gives Kafka room to spread incoming traffic across multiple independent storage areas. In a production system with multiple consumer instances, partitions also enable parallel processing.

**Replication factor 3** is the standard production value, ensuring that data is held by three brokers and the cluster can tolerate the loss of any one broker without data loss.

**`min.insync.replicas=2`** combined with the producer's `acks=all` setting means that writes are only acknowledged when at least 2 brokers have received the data. This gives the producer a strong durability guarantee: an acknowledged write is on at least 2 disks.

**Topic name `transactions`** uses a simple noun. In a larger system you might use a more structured name like `banking.transactions.recorded`, but for a single-team lab the simple name is fine.

## Section 2: Building the Spring Boot Producer

### 2.1 Generate the Project with Spring Initializr

Open a browser and go to https://start.spring.io.

Configure the project as follows:

| Setting | Value |
|---|---|
| Project | Maven |
| Language | Java |
| Spring Boot | **3.5.x** (the latest 3.5 patch release shown) |
| Group | `com.example` |
| Artifact | `transproducer` |
| Name | `transproducer` |
| Description | `Spring Kafka producer for transaction events` |
| Package name | `com.example.transproducer` |
| Packaging | Jar |
| Java | 21 |

**Important: Spring Boot version.** Make sure you explicitly select a 3.5.x version from the Spring Boot dropdown. If Spring Initializr defaults to 4.0.x, change it back to 3.5.x. Spring Boot 4.0 introduced significant package changes that are not compatible with the lab content. The course materials, examples, and broader ecosystem all target 3.5.x.

**Important: Artifact name.** Use `transproducer` (no hyphens, no underscores). Hyphens in the artifact name cause Spring Initializr to substitute underscores in the generated package name, which is awkward to work with. A single concatenated word avoids this entirely.

Add the following dependencies:

- **Spring for Apache Kafka**
- **Spring Boot Actuator** (useful for diagnostics later)
- **Spring Web** (this brings Jackson onto the classpath, which `JsonSerializer` needs to serialize your event objects)

The Spring Web dependency is included specifically for its transitive Jackson dependency, including the JSR-310 module needed to serialize Java time types like `Instant`. We will configure the application not to start an embedded web server, so the Tomcat that Spring Web brings in will be inert.

Click **Generate**, save the resulting ZIP file, extract it, and open the project in IntelliJ.

### 2.2 The Project Structure

Once IntelliJ has finished indexing, you should see a standard Spring Boot project layout:

```
transproducer/
├── pom.xml
└── src/
    └── main/
        ├── java/
        │   └── com/example/transproducer/
        │       └── TransproducerApplication.java
        └── resources/
            └── application.properties
```

You will modify `application.properties` to be a YAML file shortly.

### 2.3 Verify the Spring Boot Version

Open `pom.xml` and confirm the parent version is 3.5.x:

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.5.x</version>
    <relativePath/>
</parent>
```

If the version shows `4.0.x`, change it to a 3.5 release (for example `3.5.6`) and reload Maven by clicking the Maven reload icon in IntelliJ. The lab will not work correctly on Spring Boot 4.0 because the auto-configuration class structure changed in that release.

### 2.4 Configure the Application

Delete the default `application.properties` file and create a new file named `application.yml` in the same `src/main/resources` directory. Add the following configuration:

```yaml
spring:
  main:
    web-application-type: none
  application:
    name: transproducer

  kafka:
    bootstrap-servers: localhost:9092,localhost:9094,localhost:9096
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
      acks: all
      properties:
        enable.idempotence: true
        linger.ms: 10

logging:
  level:
    com.example.transproducer: INFO
```

A walkthrough of what each setting does:

**`spring.main.web-application-type: none`** tells Spring Boot not to start an embedded web server. The Spring Web dependency we included brings in Tomcat, but we do not need a web server for a producer service: it has no HTTP endpoints, accepts no web requests, and serves no user traffic. Disabling the web server avoids port conflicts when running multiple Spring Boot Kafka applications on the same machine (as you will in Lab 4.3 when running the producer alongside a consumer), starts the application faster, and produces cleaner startup logs.

This pattern is common in real systems: many Spring Boot applications are not web applications, but rather background workers that process events, run scheduled jobs, or publish to queues. The Spring Web dependency is still useful for these applications because it brings in shared infrastructure like Jackson, but the embedded server itself is overhead. `web-application-type: none` is the standard way to declare "I am a service worker, not a web app."

**`bootstrap-servers: localhost:9092,localhost:9094,localhost:9096`** tells the producer where to find the Kafka cluster. All three brokers are listed because the producer is running on the Windows host and reaches the brokers via the host port mappings on the HOST listener. Listing all three is best practice: if the first broker is unavailable when the producer starts, it can bootstrap via either of the other two. After the initial connection, the producer fetches cluster metadata and connects directly to the partition leaders.

Note that this is different from the bootstrap address used by the CLI tools running inside the broker containers in Section 1, which used `localhost:19092` (the INTERNAL listener). The Spring application is an external client and uses the HOST listener addresses.

**`key-serializer`** is set to `StringSerializer` because we will use account IDs (strings) as keys.

**`value-serializer`** is `JsonSerializer`, which uses Jackson to convert your event objects to JSON byte arrays. This is the most common choice for development.

**`acks: all`** means the producer waits for the partition leader and all in-sync replicas to acknowledge the write before considering it successful. Combined with the topic's `min.insync.replicas=2` setting and replication factor 3, this gives you the production-grade durability guarantee: every acknowledged write has been replicated to at least 2 brokers. If one broker fails, no data is lost.

**`enable.idempotence: true`** tells the producer to assign sequence numbers to records and tells the broker to deduplicate retries. Without this, network blips that trigger producer retries could cause duplicate records.

**`linger.ms: 10`** tells the producer to wait up to 10 milliseconds for additional records to join a batch before sending. This trades a small amount of latency for significantly improved throughput.

These settings appear in `application.yml` so they can be changed without rebuilding the application. The split between top-level Spring keys (`acks`) and nested `properties:` keys (`enable.idempotence`) is a Spring Boot quirk: the most common settings have curated names, while less common settings pass through the `properties:` map to the underlying Kafka client.

### 2.5 Define the Transaction Record

Create a new package `com.example.transproducer.model` and add two new files inside it.

First, the transaction type enum. Create `TransactionType.java`:

```java
package com.example.transproducer.model;

public enum TransactionType {
    DEPOSIT,
    WITHDRAWAL,
    PURCHASE,
    SERVICE_CHARGE,
    PAYMENT
}
```

Then the transaction record itself. Create `Transaction.java`:

```java
package com.example.transproducer.model;

import java.math.BigDecimal;
import java.time.Instant;

public record Transaction(
    String id,
    String accountId,
    BigDecimal amount,
    TransactionType type,
    Instant timestamp
) {}
```

A few notes on the design choices:

**Using a record** instead of a traditional class with getters and setters is the modern Java idiom. Records are immutable by default, which is exactly the right shape for events: an event represents something that happened, and "what happened" should not change after the fact. Records also have automatic `equals`, `hashCode`, and `toString`, which makes logging and debugging easier.

**`BigDecimal` for `amount`** is used instead of `double` because floating-point arithmetic is not safe for currency. The classic example is that `0.1 + 0.2` does not equal `0.3` in double-precision floating point. Always use `BigDecimal` for money in Java.

**`Instant` for `timestamp`** is used instead of `long`. `Instant` is self-describing (it represents a point in time) and has a clean string representation in logs. Jackson's JSR-310 module (brought in by the Spring Web dependency) knows how to serialize `Instant` to ISO-8601 strings automatically.

### 2.6 Create the Transaction Generator

Create another new package `com.example.transproducer.service` and add a class `TransactionGenerator.java`:

```java
package com.example.transproducer.service;

import com.example.transproducer.model.Transaction;
import com.example.transproducer.model.TransactionType;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

public class TransactionGenerator {

    private static final List<String> ACCOUNT_IDS = List.of(
        "A-001", "A-002", "A-003", "A-004", "A-005",
        "A-006", "A-007", "A-008", "A-009", "A-010"
    );

    private static final TransactionType[] TYPES = TransactionType.values();

    public Transaction generate() {
        ThreadLocalRandom random = ThreadLocalRandom.current();

        String accountId = ACCOUNT_IDS.get(random.nextInt(ACCOUNT_IDS.size()));
        TransactionType type = TYPES[random.nextInt(TYPES.length)];
        BigDecimal amount = BigDecimal.valueOf(random.nextDouble(1.00, 500.00))
                                       .setScale(2, RoundingMode.HALF_UP);

        return new Transaction(
            UUID.randomUUID().toString(),
            accountId,
            amount,
            type,
            Instant.now()
        );
    }
}
```

This class generates random transactions from a fixed pool of 10 account IDs. The small pool is deliberate: with 10 accounts and 3 partitions, you will see multiple transactions per account, and you will be able to verify that each account's transactions consistently land on the same partition.

The amount is generated as a random double between 1.00 and 500.00, then converted to a `BigDecimal` with 2 decimal places.

Note that we have not added the `@Service` annotation yet. We will register this as a Spring bean in the next step.

### 2.7 Create the Publisher Service

Create the class that uses `KafkaTemplate` to publish transactions. In the same `service` package, add `TransactionPublisher.java`:

```java
package com.example.transproducer.service;

import com.example.transproducer.model.Transaction;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;

@Service
public class TransactionPublisher {

    private static final Logger log = LoggerFactory.getLogger(TransactionPublisher.class);
    private static final String TOPIC = "transactions";

    private final KafkaTemplate<String, Object> kafkaTemplate;

    public TransactionPublisher(KafkaTemplate<String, Object> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void publish(Transaction transaction) {
        CompletableFuture<SendResult<String, Object>> future =
            kafkaTemplate.send(TOPIC, transaction.accountId(), transaction);

        future.whenComplete((result, ex) -> {
            if (ex != null) {
                log.error("Failed to publish transaction {} for account {}",
                    transaction.id(), transaction.accountId(), ex);
            } else {
                var metadata = result.getRecordMetadata();
                log.info("Sent {} {} {} {} -> partition {}, offset {}",
                    transaction.id(),
                    transaction.accountId(),
                    transaction.type(),
                    transaction.amount(),
                    metadata.partition(),
                    metadata.offset());
            }
        });
    }
}
```

This is the most important class in the lab. Walk through it carefully.

**The `@Service` annotation** registers this class as a Spring-managed bean so it can be injected into other components.

**The constructor takes `KafkaTemplate<String, Object>`**. Spring Boot's auto-configuration creates a `KafkaTemplate` bean with type parameters that match the auto-configured producer factory. Using `<String, Object>` here matches the auto-configured bean: the key is consistently a `String` (because we configured `StringSerializer`), and the value is `Object` (because `JsonSerializer` can serialize any class Jackson can handle, including our `Transaction` record). Declaring a more specific type like `KafkaTemplate<String, Transaction>` would not match the auto-configured bean and would cause a `Could not autowire` error.

**The `publish` method calls `kafkaTemplate.send(...)`** with three arguments: the topic name, the key (which is the account ID), and the value (the full transaction object). Using `accountId` as the key is the central design decision in this lab. Kafka will hash the account ID and choose a partition based on the hash, ensuring that all transactions for the same account always land on the same partition.

**The `send` method returns a `CompletableFuture`**. This is the asynchronous send pattern. The actual network call to Kafka happens on a background thread; the application thread is unblocked immediately and can continue producing more transactions.

**The `whenComplete` callback** runs when the broker acknowledges the send (or when the send fails). On success, we log the assigned partition and offset along with the transaction details. This is the producer-side equivalent of the partition and offset visibility you saw on the consumer side in Lab 4.1. On failure, we log the error.

This callback pattern is the standard production approach: not blocking on the send (which would defeat the async architecture) but also not ignoring the result (which would silently drop failures).

### 2.8 Wire Up Scheduling

We want to produce one transaction per second. Spring's scheduling support is the idiomatic way to do this.

First, enable scheduling in your application class. Open `TransproducerApplication.java` and add the `@EnableScheduling` annotation:

```java
package com.example.transproducer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class TransproducerApplication {

    public static void main(String[] args) {
        SpringApplication.run(TransproducerApplication.class, args);
    }
}
```

Then create the scheduled job. In the `service` package, add `TransactionScheduler.java`:

```java
package com.example.transproducer.service;

import com.example.transproducer.model.Transaction;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class TransactionScheduler {

    private final TransactionGenerator generator = new TransactionGenerator();
    private final TransactionPublisher publisher;

    public TransactionScheduler(TransactionPublisher publisher) {
        this.publisher = publisher;
    }

    @Scheduled(fixedRate = 1000)
    public void publishTransaction() {
        Transaction transaction = generator.generate();
        publisher.publish(transaction);
    }
}
```

The `@Scheduled(fixedRate = 1000)` annotation tells Spring to invoke this method every 1000 milliseconds. The method generates one random transaction and hands it off to the publisher. The publisher's call returns immediately because of the asynchronous send pattern, so the scheduler is never blocked.

Note that we are creating the `TransactionGenerator` directly with `new` rather than registering it as a Spring bean. This is a deliberate simplification for the lab; in a larger application you would typically make it a `@Component` or `@Service` to enable testing and configuration.

### 2.9 Run the Producer

You are now ready to run the application. In IntelliJ, open `TransproducerApplication.java` and click the green run arrow next to the `main` method.

You should see Spring Boot start up. Because of the `web-application-type: none` setting, no embedded Tomcat will be started and you will not see any "Tomcat started on port 8080" messages. The producer will connect to the Kafka cluster, fetch metadata about the `transactions` topic, and start publishing. Within a second or two of startup, log lines should begin appearing:

```
Sent 6f8a3c4d-... A-007 PURCHASE 247.32 -> partition 1, offset 0
Sent b1d92e7f-... A-002 DEPOSIT 89.15 -> partition 0, offset 0
Sent 9c4a1b2e-... A-007 WITHDRAWAL 412.88 -> partition 1, offset 1
Sent e3f7d8a1-... A-005 PAYMENT 156.40 -> partition 2, offset 0
Sent a8b2c4d6-... A-002 SERVICE_CHARGE 12.00 -> partition 0, offset 1
```

(Your specific transactions will be different, but the pattern should be similar.)

Take a moment to study the output. Look at the partition assignments:

- All transactions for account `A-007` should land on the same partition every time
- All transactions for account `A-002` should land on the same partition every time
- Different accounts may land on different partitions

This is per-key partitioning in action. The producer is hashing each `accountId` and using the result to choose a partition deterministically. Because the hash is deterministic, the same account always maps to the same partition.

#### A Note on Partition Distribution

With only 10 account IDs and 3 partitions, some accounts will land on the same partition as others. That is normal: the hash space is divided into 3 buckets, and 10 keys necessarily share some buckets. What matters for ordering is that each individual account's events all go to the same bucket, which they do.

Leave the producer running in IntelliJ.

## Section 3: Verifying with the Console Consumer

Now you will use the command-line console consumer from Lab 4.1 to read the messages your producer is publishing. This lets you verify the producer's behavior from a completely independent vantage point.

### 3.1 Start the Console Consumer

Open a new Command Prompt window. Change to the Kafka Docker directory:

```
cd C:\kafka-docker
```

Start the console consumer for the `transactions` topic:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-consumer.sh --topic transactions --bootstrap-server localhost:19092 --from-beginning --property "print.partition=true" --property "print.key=true" --property "key.separator= | "
```

This is the same pattern you used at the end of Lab 4.1, with the topic changed to `transactions`. Breakdown of the options:

- **`--bootstrap-server localhost:19092`** is the INTERNAL listener port, used because the consumer is running inside the `kafka1` container. Recall that this is different from the producer's bootstrap addresses (the HOST listener ports `9092`, `9094`, `9096`), which the producer uses because it runs on the Windows host.
- **`--from-beginning`** tells the consumer to start reading from offset 0 rather than from the latest offset. This way, you see all the messages your producer has sent so far, not just new ones.
- **`print.partition=true`** prefixes each line with the partition the message came from.
- **`print.key=true`** shows the message key (the account ID) alongside the value.
- **`key.separator= | "`** uses a pipe character with spaces as the visual separator between the key and the value.

### 3.2 Read the Output

You should see output like this:

```
Partition:0   A-002 | {"id":"b1d92e7f-...","accountId":"A-002","amount":89.15,"type":"DEPOSIT","timestamp":"2026-04-25T01:55:32.412Z"}
Partition:0   A-002 | {"id":"a8b2c4d6-...","accountId":"A-002","amount":12.00,"type":"SERVICE_CHARGE","timestamp":"2026-04-25T01:55:34.418Z"}
Partition:1   A-007 | {"id":"6f8a3c4d-...","accountId":"A-007","amount":247.32,"type":"PURCHASE","timestamp":"2026-04-25T01:55:31.402Z"}
Partition:1   A-007 | {"id":"9c4a1b2e-...","accountId":"A-007","amount":412.88,"type":"WITHDRAWAL","timestamp":"2026-04-25T01:55:33.415Z"}
Partition:2   A-005 | {"id":"e3f7d8a1-...","accountId":"A-005","amount":156.40,"type":"PAYMENT","timestamp":"2026-04-25T01:55:33.620Z"}
```

The consumer is showing each message with its partition, key, and JSON-serialized value.

### 3.3 What to Observe

Take a few minutes to watch the output and confirm these properties:

**Per-account ordering on the same partition.** Pick any account ID, for example `A-007`. Every line for `A-007` should show the same partition number. Because all of one account's events land on one partition, and Kafka guarantees order within a partition, you have a guarantee that this account's transactions will be processed in the order they were produced.

**Cross-reference with the producer's logs.** Switch to your IntelliJ console and find a recent `A-007` log line. Note its partition and offset. Now find the same transaction (same UUID) in the consumer's output. The partition should match, and the offset, while not printed by default, can be verified by counting from the start.

**Different accounts may land on different partitions.** Notice that `A-002` appears on partition 0, `A-007` on partition 1, `A-005` on partition 2 (your specific assignments may differ). This is the hashing in action: account IDs are mapped to partitions deterministically but with no enforced grouping.

**Some accounts may share partitions.** With 10 account IDs and 3 partitions, multiple accounts will inevitably end up on the same partition. That is expected. Within a partition, events from different accounts are interleaved in the order they arrived; ordering is preserved per-account, but not across accounts.

### 3.4 Stop and Restart the Consumer

While the producer is still running, stop the consumer with Ctrl+C. Wait a few seconds (during which the producer continues sending), then restart the consumer **without** the `--from-beginning` flag:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-consumer.sh --topic transactions --bootstrap-server localhost:19092 --property "print.partition=true" --property "print.key=true" --property "key.separator= | "
```

This time the consumer starts at the *latest* offset on each partition. You will see only new transactions, not the ones produced while the consumer was stopped. The events produced during the gap are still in Kafka's storage on disk; the consumer just chose to start from the head of the log instead of the beginning.

This demonstrates that the producer and consumer are fully decoupled in time. The producer keeps producing whether or not anyone is reading.

### 3.5 Stopping the Producer

When you are done observing, stop the producer by clicking the red stop button in IntelliJ (or pressing Ctrl+F2 in IntelliJ). The producer will shut down cleanly, the scheduler will stop firing, and any in-flight sends will complete.

You can leave the consumer running and the broker cluster running for the next section, or stop them as well.

## Section 4: Optional Exploration

These exercises are not required, but they reinforce concepts that will appear later in the course.

### 4.1 Try Keying by Type Instead of Account

Open `TransactionPublisher.java` and temporarily change the key from `accountId` to `type.name()`:

```java
kafkaTemplate.send(TOPIC, transaction.type().name(), transaction);
```

Restart the producer and watch the partition distribution. You will see:

- Only 5 distinct keys (one per `TransactionType`)
- All transactions for the same type always land on the same partition
- The partition distribution is uneven; some partitions get a lot more traffic than others

This is the **hot partition problem** discussed in the course material. Keying by a low-cardinality field like `type` results in poor load distribution. With more types than partitions, multiple types share a partition; with fewer types than partitions, some partitions get no traffic at all.

When you are done experimenting, change the key back to `transaction.accountId()`.

### 4.2 Watch Per-Partition Throughput

While the producer is running and using `accountId` as the key, run this command in a third Command Prompt window:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-get-offsets.sh --topic transactions --bootstrap-server localhost:19092
```

This shows the current end offset for each partition. Run it a few times over 30 seconds and watch the offsets advance. You will see that the partitions advance at slightly different rates depending on how many of your 10 account IDs hash to each one.

### 4.3 Restart the Producer

Stop the producer in IntelliJ, then start it again. Watch the offsets in the producer's log. The first transaction's offset for each partition will not be 0 anymore: it will continue from wherever the previous run left off. This is because the cluster is keeping the existing log on disk.

If you wanted to start from a clean slate, you would need to recreate the cluster from scratch (`docker compose down` followed by `docker compose up -d` and then recreating the topic). But remember the warning: do not run topic deletion commands on this lab setup.

## Section 5: Wrapping Up

### 5.1 What to Leave Running

For the next lab you will need:

- The three-broker Kafka cluster still running (or be prepared to start it)
- The `transactions` topic — it persists as long as the cluster's storage is intact

You can stop the producer (it will not be reused; Lab 4.3 will create a different application).

You can close the consumer; you will not need it for Lab 4.3.

### 5.2 What You Have Learned

In this lab you have:

- Created a Kafka topic with production-grade replication settings (RF 3, `min.insync.replicas=2`)
- Configured a Spring Boot application with Spring for Apache Kafka
- Configured the application to run as a service worker rather than a web application
- Defined an event payload using a Java record with proper types (`BigDecimal`, `Instant`)
- Configured a producer for durable, idempotent delivery against a three-broker cluster
- Used `KafkaTemplate` to publish events asynchronously
- Used the `whenComplete` callback to observe partition and offset assignment in real time
- Used `accountId` as the message key to demonstrate per-entity ordering
- Verified your producer's behavior from a completely independent consumer

The conceptual foundation for the next lab is now in place. You have seen how a Spring Boot producer maps onto Kafka's underlying mechanics: the JSON serialization, the partition selection by key hash, the batching and asynchronous send, and the metadata returned in the acknowledgment. Lab 4.3 will build the consumer side using the same Spring Kafka library.

### 5.3 Self-Check

Before moving on to Lab 4.3, you should be able to answer these questions:

1. Why did all transactions for the same account ID always land on the same partition?
2. What would happen if you increased the partition count of the `transactions` topic from 3 to 6 while the producer was running?
3. Why is `BigDecimal` used for the `amount` field instead of `double`?
4. What does the `whenComplete` callback receive on success, and what does it receive on failure?
5. Why is `acks=all` combined with `enable.idempotence=true` the recommended production setting for the producer? How does the topic's `min.insync.replicas=2` setting relate to these?
6. What happens to events produced while a consumer is stopped, and why?
7. Why did we declare the `KafkaTemplate` field as `KafkaTemplate<String, Object>` rather than `KafkaTemplate<String, Transaction>`?
8. What does `spring.main.web-application-type: none` do, and why is it appropriate for this producer application?
9. The Spring producer uses `localhost:9092,localhost:9094,localhost:9096` as its bootstrap servers, but the CLI consumer inside the container uses `localhost:19092`. Why are they different?

If any of these are unclear, review the relevant section of the lab before continuing.

## End of Lab 4.2
