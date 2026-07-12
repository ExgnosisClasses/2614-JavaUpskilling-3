# Lab 4.1: Introduction to Kafka with a Three-Broker Docker Cluster

## Lab Overview

In this lab you will start a three-broker Kafka cluster running in Docker, learn how the cluster is organized, create a topic, and use Kafka's command-line tools to send and receive messages. You will also explore how Kafka assigns leader and follower roles across brokers, and you will observe what happens when one broker is stopped while the cluster continues to operate.

The goal is to develop a working understanding of how Kafka organizes data across multiple brokers, how producers and consumers interact with topics, and how Kafka's replication mechanism provides fault tolerance. This foundation prepares you for the Spring Kafka labs that follow.

By the end of this lab you will:

- Start and stop a three-broker Kafka cluster using Docker Compose
- Understand how brokers cooperate as a cluster
- Create a topic with replication and inspect its leader and follower assignments
- Produce and consume messages using Kafka's command-line tools
- Observe what happens when a consumer reads from the beginning of a topic versus from the latest offset
- Understand how message keys determine partition assignment and per-entity ordering
- See Kafka's replication mechanism handle a broker outage and recover

This lab uses only the Kafka command-line tools. No Spring Boot, no Java code. The next lab will build on this foundation by connecting a Spring Boot application to the same cluster.

## Prerequisites

- Docker Desktop installed and running on your VM
- At least 8 GB of RAM available
- A text editor (Notepad, VS Code, or similar)

You can verify your prerequisites by opening a Command Prompt and running:

```
docker --version
docker compose version
```

You should see Docker version 24.x or newer and Docker Compose version 2.x or newer.

If you previously ran a native Kafka broker on this machine, make sure it is stopped before starting this lab. The Docker cluster will try to bind to port 9092, and a running native broker would conflict with it. You can check by running:

```
netstat -ano | findstr :9092
```

If nothing is reported, no broker is running and you are ready to proceed.

## Section 1: Starting the Cluster

### 1.1 Create the Working Directory

You will keep your Docker Compose file in a dedicated directory. Open a Command Prompt and run:

```
mkdir C:\kafka-docker
cd C:\kafka-docker
```

All commands in this lab assume you are in `C:\kafka-docker` unless explicitly stated otherwise. Returning to this directory in any new Command Prompt window is the first step in every section.

### 1.2 Create the Docker Compose File

Create a file named `docker-compose.yml` in `C:\kafka-docker`. You can use Notepad:

```
notepad docker-compose.yml
```

When Notepad asks whether to create a new file, click Yes. Paste the following content into the file:

```yaml
services:
  kafka1:
    image: apache/kafka:4.1.1
    container_name: kafka1
    ports:
      - "9092:9092"
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: HOST://:9092,INTERNAL://:19092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: HOST://localhost:9092,INTERNAL://kafka1:19092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,HOST:PLAINTEXT,INTERNAL:PLAINTEXT
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka1:9093,2@kafka2:9093,3@kafka3:9093
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      CLUSTER_ID: KY_qlo8EQEK98t6e_j8kWA
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2

  kafka2:
    image: apache/kafka:4.1.1
    container_name: kafka2
    ports:
      - "9094:9094"
    environment:
      KAFKA_NODE_ID: 2
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: HOST://:9094,INTERNAL://:19092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: HOST://localhost:9094,INTERNAL://kafka2:19092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,HOST:PLAINTEXT,INTERNAL:PLAINTEXT
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka1:9093,2@kafka2:9093,3@kafka3:9093
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      CLUSTER_ID: KY_qlo8EQEK98t6e_j8kWA
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2

  kafka3:
    image: apache/kafka:4.1.1
    container_name: kafka3
    ports:
      - "9096:9096"
    environment:
      KAFKA_NODE_ID: 3
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: HOST://:9096,INTERNAL://:19092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: HOST://localhost:9096,INTERNAL://kafka3:19092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,HOST:PLAINTEXT,INTERNAL:PLAINTEXT
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka1:9093,2@kafka2:9093,3@kafka3:9093
      KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL
      CLUSTER_ID: KY_qlo8EQEK98t6e_j8kWA
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
```

Save the file and close Notepad.

This file defines three Kafka brokers as Docker services. Take a moment to scan it, since several of the settings are worth understanding.

#### What the Settings Mean

**`image: apache/kafka:4.1.1`** is the official Apache Kafka Docker image at version 4.1.1, the same version of Kafka used throughout this course.

**`KAFKA_NODE_ID`** is a unique numeric identifier for each broker in the cluster. The three brokers have node IDs 1, 2, and 3.

**`KAFKA_PROCESS_ROLES: broker,controller`** declares that each container is acting as both a Kafka broker (handling client traffic and storing partition data) and a KRaft controller (participating in cluster metadata consensus). In a production cluster you might separate these roles onto different machines, but for a lab the combined role is simpler.

**The three listeners on each broker.** This is the most important configuration detail to understand, because it solves a subtle Docker networking problem.

Each broker exposes three named listeners:

- **`HOST`** is the listener that clients running on your Windows machine connect to. It is bound to a different port on each broker (9092, 9094, 9096), and those ports are mapped through to the host so that you can reach them at `localhost:9092`, `localhost:9094`, and `localhost:9096`.
- **`INTERNAL`** is the listener that other containers in the Docker network use to talk to this broker. It is bound to port 19092 on every broker, and the advertised address uses the container's hostname (`kafka1:19092`, `kafka2:19092`, `kafka3:19092`).
- **`CONTROLLER`** is used only for KRaft metadata traffic between controllers. It is bound to port 9093 and is not exposed to clients at all.

**`KAFKA_ADVERTISED_LISTENERS`** is what each broker tells clients to use when they need to connect. The key insight is that the answer depends on *who is asking*. A client connecting via the `HOST` listener gets back addresses like `localhost:9092`. A client connecting via the `INTERNAL` listener gets back addresses like `kafka1:19092`. Both sets of addresses point to the same brokers, just by different routes.

**Why we need both listeners.** Inside the Docker network, `localhost:9094` means "this container's own port 9094," not "the kafka2 container." So if `kafka1` told clients to reach `kafka2` at `localhost:9094`, clients inside the network would fail. By giving each broker an internal hostname-based address that other containers can resolve, the cluster works correctly for both in-network clients (like the CLI tools we run with `docker compose exec`) and external clients (like the Spring Boot applications we will build later, running on the Windows host).

**`KAFKA_INTER_BROKER_LISTENER_NAME: INTERNAL`** tells the brokers to use the internal listener when communicating with each other. They use hostnames inside the Docker network, never the host's port mappings.

**`KAFKA_LISTENER_SECURITY_PROTOCOL_MAP`** declares the security protocol for each named listener. All three use PLAINTEXT (no encryption) since this is a lab. In production you would use SSL or SASL for the client-facing listeners.

**`KAFKA_CONTROLLER_QUORUM_VOTERS`** is the list of brokers that participate in the KRaft controller quorum. All three brokers are listed because all three are acting as controllers. The port `9093` is the controller listener port.

**`CLUSTER_ID`** is the unique identifier that identifies this Kafka cluster. In a multi-broker cluster, every broker must use the same cluster ID. The value here is shared across all three brokers.

**The replication factor settings at the bottom** apply to Kafka's internal topics (`__consumer_offsets`, `__transaction_state`, etc.). With three brokers available, these internal topics are configured to be replicated across all three brokers, with at least two replicas in-sync at all times. This is the production-grade configuration we discussed in the course material.

### 1.3 Start the Cluster

Now start all three brokers with a single command:

```
docker compose up -d
```

The `-d` flag runs the containers in detached mode, meaning they run in the background and the terminal returns to you immediately. Docker will pull the `apache/kafka:4.1.1` image if it has not been downloaded before (which can take a minute the first time), then start the three containers.

After the command finishes, verify the cluster is running:

```
docker compose ps
```

You should see all three containers listed with state `running`:

```
NAME      IMAGE                STATUS         PORTS
kafka1    apache/kafka:4.1.1   Up 30 seconds  0.0.0.0:9092->9092/tcp
kafka2    apache/kafka:4.1.1   Up 30 seconds  0.0.0.0:9094->9094/tcp
kafka3    apache/kafka:4.1.1   Up 30 seconds  0.0.0.0:9096->9096/tcp
```

Brokers take 30 to 60 seconds to fully start. If you ran commands immediately after `docker compose up`, you might get connection errors. Wait until all three containers show `Up` and the broker has had time to initialize.

### 1.4 Watch the Broker Logs

If you want to see what is happening inside one of the brokers as it starts, run:

```
docker compose logs -f kafka1
```

The `-f` flag follows the log (similar to `tail -f` on Linux). You will see broker startup logs, KRaft controller election messages, and metadata initialization. When you see a line similar to:

```
[KafkaRaftServer nodeId=1] Kafka Server started
```

…the broker is ready. Press Ctrl+C to stop following the logs (this does not stop the broker; it just exits the log viewer).

You can view the logs for the other brokers similarly:

```
docker compose logs -f kafka2
docker compose logs -f kafka3
```

### 1.5 Running Kafka CLI Commands

Throughout this lab you will run Kafka's command-line tools to create topics, list them, and send and receive messages. The CLI tools live inside the broker containers at `/opt/kafka/bin/`, and on Linux they have a `.sh` extension (because they are shell scripts).

To run a CLI tool inside a broker, use `docker compose exec` with the full path to the script:

```
docker compose exec kafka1 /opt/kafka/bin/<script-name>.sh <arguments>
```

For example, to check the Kafka version:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --version
```

You should see `4.1.1` reported.

#### Choosing the Right Bootstrap Server

When running CLI commands from inside a broker container, use `--bootstrap-server localhost:19092` (the internal listener port). This makes the CLI tool connect to the local broker via its INTERNAL listener, which then advertises the internal hostnames of all brokers. Other CLI commands that need to reach a different broker can do so using those hostnames.

If you were running the CLI tool from your Windows host instead (which we will not do in this lab, but you might in production), you would use `--bootstrap-server localhost:9092` instead. The HOST listener would advertise the `localhost:9092`, `localhost:9094`, `localhost:9096` addresses, which would be the correct addresses from the host's perspective.

For consistency, this lab uses `kafka1` and the internal port (`localhost:19092`) for all CLI commands. You can run CLI commands from any of the three brokers (`kafka1`, `kafka2`, or `kafka3`); the result will be the same.

If you find the full path tedious to type, your Command Prompt's history (up-arrow) lets you recall and edit prior commands quickly, and most lab commands only differ from each other in their arguments.

### 1.6 Important: Do Not Delete Topics

Throughout this course, **do not run any topic deletion commands**. Even though Kafka has a setting to enable topic deletion, deleting a topic can leave artifacts that complicate subsequent labs. If you accidentally create a topic with the wrong name, just leave it alone and create a new one with the correct name. Stale topics do no harm.

## Section 2: Creating and Inspecting a Topic

In this section you will create a topic with three partitions and replication factor 3, then inspect how Kafka has assigned leaders and followers across the three brokers.

### 2.1 Creating a Topic with Replication

Create a topic called `labone` with three partitions and replication factor 3:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --create --topic labone --bootstrap-server localhost:19092 --partitions 3 --replication-factor 3
```

You should see:

```
Created topic labone.
```

Let's break down what each part of that command means:

- `docker compose exec kafka1` runs the command inside the `kafka1` container.
- `/opt/kafka/bin/kafka-topics.sh` is the Kafka CLI tool for managing topics.
- `--create` is the action.
- `--topic labone` is the topic name.
- `--bootstrap-server localhost:19092` tells the CLI tool how to find the cluster. Every Kafka client connects to a "bootstrap server" first, fetches cluster metadata, and then talks to the appropriate brokers from there. We are using port 19092 because that is the INTERNAL listener — appropriate for clients running inside the Docker network.
- `--partitions 3` says the topic should be divided into three partitions. Partitions are how Kafka achieves parallelism within a topic.
- `--replication-factor 3` says there should be three copies of each partition, spread across different brokers. This is the replication factor we discussed in the course material as the production standard.

#### Why Replication Factor 3 Matters

If we had only a single broker, the only choice for replication factor would be 1: there would be only one broker, so there could only be one copy of each partition. Now that you have a three-broker cluster, you can use replication factor 3, which is the standard production value. Every partition has three copies, spread across the three brokers. If one broker fails, the other two brokers still have a copy of every partition, and the cluster keeps running. You will see this in action later in the lab.

### 2.2 Listing Topics

List all topics that exist on the cluster:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:19092
```

You should see `labone` in the output. You may also see internal topics whose names start with double underscores (`__consumer_offsets`, `__cluster_metadata`). These are Kafka's own internal bookkeeping topics:

- `__consumer_offsets` is where Kafka stores the committed positions of every consumer group across every partition. When a consumer crashes and restarts, it reads its offsets from here.
- `__cluster_metadata` is where the KRaft controller stores cluster-wide metadata: which topics exist, which broker leads which partition, which configurations are set.

### 2.3 Describing a Topic

Get a detailed view of `labone`:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic labone --bootstrap-server localhost:19092
```

The output looks something like this:

```
Topic: labone   TopicId: ...   PartitionCount: 3   ReplicationFactor: 3   Configs:
        Topic: labone   Partition: 0    Leader: 2   Replicas: 2,3,1   Isr: 2,3,1   Elr:    LastKnownElr:
        Topic: labone   Partition: 1    Leader: 3   Replicas: 3,1,2   Isr: 3,1,2   Elr:    LastKnownElr:
        Topic: labone   Partition: 2    Leader: 1   Replicas: 1,2,3   Isr: 1,2,3   Elr:    LastKnownElr:
```

(Your specific leader assignments may differ, since Kafka spreads leadership across brokers based on cluster state.)

This output is much more interesting than it would be with a single broker. Let's interpret it.

The first line summarizes the topic: a unique TopicId, three partitions, replication factor 3.

The next three lines describe each partition individually:

- **`Leader: 2`** for partition 0 means broker 2 is the leader for that partition. All produces and consumes for partition 0 go through broker 2.
- **`Replicas: 2,3,1`** lists all the brokers that hold a copy of the partition. The order matters: the first broker (broker 2 in this case) is the preferred leader, and the rest are followers.
- **`Isr: 2,3,1`** is the In-Sync Replica set: the brokers whose copies are currently up-to-date with the leader. In a healthy cluster all replicas are in-sync, so the ISR is the same as the Replicas list.
- **`Elr`** and **`LastKnownElr`** relate to "eligible leader replicas," a more recent KRaft feature. For this lab they will typically be empty.

#### Reading the Leader Distribution

Look at the Leader column across the three partitions. You should see that leadership is spread across the three brokers — partition 0 led by one broker, partition 1 by another, partition 2 by the third. This is Kafka's load-balancing strategy: rather than concentrating all the work on one broker, the leadership is distributed so that produce and consume traffic is balanced across the cluster.

If all three partitions happened to be led by the same broker, that broker would receive all the traffic for the topic. With distributed leadership, the load is spread.

#### What This Tells You

For every partition in `labone`, three brokers hold a copy of the data: one as leader, two as followers. The followers continuously pull from the leader to stay up-to-date. If the leader fails, one of the followers is promoted to take over.

This is the foundation of Kafka's fault tolerance. We will exercise this mechanism later in the lab.

## Section 3: Producing and Consuming Messages

Now you will see Kafka in action, sending messages from a producer to a consumer through the topic.

### 3.1 Starting a Console Producer

In your Command Prompt, start a console producer for the `labone` topic:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-producer.sh --topic labone --bootstrap-server localhost:19092
```

Nothing visible happens immediately. The producer is waiting for input. It looks like the command hung, but it is actually waiting for you to type messages. Each line you type and press Enter on will be sent as a single message to the topic.

**Do not type anything yet.** Leave the producer waiting. You will start the consumer next.

### 3.2 Starting a Console Consumer

Open a **new** Command Prompt window. Change to the working directory:

```
cd C:\kafka-docker
```

In the new window, start a consumer for the `labone` topic:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-consumer.sh --topic labone --bootstrap-server localhost:19092
```

Like the producer, it will appear to hang. This is correct: the consumer is now polling Kafka for new messages, but no messages have been produced yet, so it sits silently.

#### What the Consumer Is Doing

By default, a console consumer started this way reads only **new** messages — messages that arrive after it starts. If messages were already in the topic from a previous run, the consumer would not see them. This is the `auto.offset.reset=latest` behavior we will discuss in the lecture material on consumer offsets.

This is one of the most common surprises for developers new to Kafka: starting a consumer does not automatically replay history.

### 3.3 Sending Messages

Switch back to the first window (the producer). Type a message and press Enter:

```
Hello Kafka
```

Switch to the second window (the consumer). You should see the message appear:

```
Hello Kafka
```

The message has flowed from your typing in the producer, through the cluster, to the consumer. Type a few more messages in the producer:

```
This is message two
And another one
The third message in the lab
```

Each one should appear in the consumer window, in the order you sent them.

#### What Just Happened

When you typed a message in the producer:

1. The producer process serialized your text into bytes.
2. Because there is no key on these messages, the producer chose a partition using a sticky-partitioning strategy.
3. The producer connected to the leader broker for the chosen partition and sent the message.
4. The leader appended the message to its log, then waited for followers to replicate it.
5. The leader assigned the message an offset within that partition.
6. Your consumer was polling for new messages on all three partitions, found this one available, fetched it, and printed it to the console.

The whole round trip happens in milliseconds, even with the replication step. The fact that you see messages appear in the consumer in the same order you typed them is partly a coincidence of the sticky-partitioning behavior — if the producer happened to switch partitions mid-stream, you might see slight reordering. Within a single partition, order is always preserved; across partitions, it is not.

### 3.4 Observing Asynchrony

Stop the consumer in the second window by pressing Ctrl+C. Notice that the producer in the first window is unaffected — it does not know or care that there is no consumer. Kafka does not have a concept of "the consumer is gone."

Now type a few more messages in the producer:

```
The consumer is gone
But I can still send
These are accumulating in the topic
```

These messages are flowing into the cluster and being stored, even though no consumer is reading them. This is one of Kafka's defining properties: producers and consumers are decoupled in time. The producer publishes; messages persist; consumers read on their own schedule.

### 3.5 Reading from the Beginning

In the second window, restart the consumer with an additional flag:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-consumer.sh --topic labone --bootstrap-server localhost:19092 --from-beginning
```

This time the `--from-beginning` flag tells the consumer to start reading from the earliest available offset on each partition, rather than from the latest. You should see all the messages you have produced so far, including the ones produced while the consumer was stopped.

#### Why This Matters

This demonstrates two important Kafka properties:

**Messages are durable.** They were stored on disk by the brokers as soon as they were produced (and replicated to multiple brokers). The consumer being absent did not cause any loss of data.

**Consumers control their own position.** The consumer decided where in the log to start reading. With `--from-beginning` it started at offset 0; without it, it would start at the latest offset. In real applications, consumer groups remember where they left off and resume from there automatically. Console consumers without a group don't track position between runs, which is why this flag exists.

You may notice that the messages are not necessarily in the same order you typed them. They are grouped by partition: within each partition the order is preserved, but the consumer reads partitions independently and interleaves their output. This is the per-partition ordering guarantee discussed in the lecture material.

### 3.6 Producing Messages with Keys

Stop the producer in the first window with Ctrl+C, then restart it with a new option that lets you specify keys:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-producer.sh --topic labone --bootstrap-server localhost:19092 --property "parse.key=true" --property "key.separator=:"
```

Now when you produce a message, you can prefix it with a key followed by a colon. Try these:

```
alpha:placed an order
beta:logged in
alpha:updated profile
gamma:created account
delta:purchased item
beta:logged out
alpha:checked out
epsilon:browsed catalog
delta:added to cart
zeta:redeemed coupon
```

Switch to the second window to see them appear (the consumer should still be running with `--from-beginning`).

These ten messages use six different keys, with `alpha` appearing three times, `beta` and `delta` twice, and the others once. We use a variety of keys (rather than just two or three) so that the partition distribution is clearly visible across all three partitions.

#### What Keys Do

When a producer includes a key, Kafka hashes the key and uses the hash to deterministically choose a partition. This means **every message with the same key always goes to the same partition.** All three `alpha` messages above went to the same partition. Both `beta` messages went to the same partition (possibly a different one). Both `delta` messages went to the same partition.

This is the mechanism for per-entity ordering. If you want all events for a particular customer, account, or order to be processed in order, you give them the same key. Kafka guarantees order within a partition, so events with the same key are guaranteed to be processed in the order they were produced.

This is a foundational concept for the next lab. When you build a Spring Boot producer, you will choose a key for each message based on whatever entity the events are about, and that choice will determine ordering for downstream consumers.

#### Verify with Describe

Stop the consumer (Ctrl+C in the second window). Restart it with an option that shows which partition each message came from:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-consumer.sh --topic labone --bootstrap-server localhost:19092 --from-beginning --property "print.partition=true" --property "print.key=true" --property "key.separator= | "
```

Look at the output. You should see entries like:

```
Partition:0   gamma   |  created account
Partition:1   alpha   |  placed an order
Partition:1   alpha   |  updated profile
Partition:1   alpha   |  checked out
Partition:1   epsilon |  browsed catalog
Partition:2   beta    |  logged in
Partition:2   beta    |  logged out
Partition:2   delta   |  purchased item
Partition:2   delta   |  added to cart
Partition:2   zeta    |  redeemed coupon
```

(Your specific partition assignments will likely be different — the hashing is deterministic but the assignment of keys to partitions depends on the hash algorithm and the partition count, so don't be surprised if your `alpha` lands on partition 0 instead of partition 1. What matters is the invariant: same key → same partition, every time.)

Notice the consistency: all three `alpha` messages are on the same partition, both `beta` messages are on the same partition, both `delta` messages are on the same partition. The single-occurrence keys (`gamma`, `epsilon`, `zeta`) each landed on whichever partition their hash dictated.

The ordering within each partition matches the order you produced them in. Across partitions, the order is interleaved as the consumer reads from each partition independently.

This is per-key ordering in action. It is one of the most important properties Kafka offers and one of the most common patterns you will use in real applications.

#### A Note About Partition Distribution

With only three partitions and a small set of keys, it is possible for several distinct keys to hash to the same partition. For example, you might see `alpha`, `epsilon`, and one of the other keys all on the same partition. This is normal Kafka behavior — the partition count limits how many distinct "buckets" the hashes can fall into, so collisions between unrelated keys are expected.

What's important is that the *grouping* by key is preserved: every message with a given key always goes to the same partition. The partition might be shared with other keys, but each key sticks to its own partition consistently.

In production systems, you generally have many more distinct keys (thousands or millions) and more partitions (typically 10 to 100), so the per-partition distribution averages out and no single partition is dominated by any one key.

## Section 4: Exploring Leader and Follower Roles

This section explores how Kafka assigns roles to brokers and what those roles mean for the data flow. The exercises here build directly on the `--describe` output you saw in Section 2.3.

Stop the consumer and producer if they are still running (Ctrl+C in each window). The CLI commands in this section are quick and read-only, so you do not need them running.

### 4.1 Look at Where the Data Lives

You created the `labone` topic with replication factor 3. Every partition has three copies, spread across the three brokers. Let's confirm this by looking at where the data is stored on each broker.

Each broker holds its own copy of every partition's log files inside the container. You can list them with:

```
docker compose exec kafka1 ls /tmp/kafka-logs/

```

You should see entries like:

```
__cluster_metadata-0
__consumer_offsets-0
__consumer_offsets-1
...
labone-0
labone-1
labone-2
```

Notice the three `labone-*` directories. Each of them holds the broker's copy of one partition. Run the same command on the other two brokers:

```
docker compose exec kafka2 ls /tmp/kafka-logs/
docker compose exec kafka3 ls /tmp/tmp/kafka-logs/

```

All three brokers have all three `labone-*` directories. Each one is a complete replica of every partition. This is what replication factor 3 means in concrete physical terms: the data exists three times, once on each broker.

### 4.2 Re-Read the Describe Output

Now revisit the `--describe` output, this time with a closer eye on the roles:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic labone --bootstrap-server localhost:19092
```

Pick one partition from the output and study it. For example, suppose you see:

```
Topic: labone   Partition: 0    Leader: 2   Replicas: 2,3,1   Isr: 2,3,1
```

This tells you:

- **Three brokers (2, 3, and 1) hold a copy** of partition 0
- **Broker 2 is the current leader** of partition 0
- **All three brokers are in-sync** — their copies are caught up to the leader

When a producer wants to write to partition 0, it sends the write to broker 2. Broker 2 appends the message to its log, then waits for brokers 3 and 1 to fetch and replicate the message. Once enough replicas have acknowledged, the write is considered durable and the producer's acknowledgment is sent back.

When a consumer wants to read from partition 0, by default it also reads from broker 2 (the leader). Brokers 3 and 1 have copies of the data, but they don't typically serve reads — they exist to provide redundancy.

#### Why Leaders Handle All Traffic

This "leader handles everything" design might seem inefficient. Why don't followers serve reads too, spreading the load?

The reason is consistency. If consumers could read from any replica, they might read from a follower that hasn't caught up yet, seeing slightly older data than another consumer reading from the leader. By routing all reads and writes through the leader, Kafka guarantees that every consumer sees the same view of the partition.

In recent versions of Kafka, there is an opt-in feature called "fetch from follower" that allows reads from followers under specific conditions (mainly to reduce cross-datacenter traffic). For now, the simple "leader handles everything" model is what you should expect.

### 4.3 Look at Leadership Distribution

Look at the leader column across all three partitions in your `--describe` output. They should be spread across the three brokers. Run the describe command for some of the internal topics too:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic __consumer_offsets --bootstrap-server localhost:19092
```

You will see a long list (the `__consumer_offsets` topic typically has 50 partitions). Look at the leader column. The leadership should be spread reasonably evenly across the three brokers, even though many partitions are involved.

This is the cluster's way of balancing load. With many partitions in many topics, leadership ends up roughly distributed, and no single broker carries a disproportionate share of the traffic.

### 4.4 Check the Cluster's Controller

The KRaft controller is one of the brokers, elected to coordinate cluster-wide decisions like leader elections and topic configurations. You can ask the cluster which broker is currently the controller:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:19092 describe --status
```

The output will look something like:

```
ClusterId:              KY_qlo8EQEK98t6e_j8kWA
LeaderId:               1
LeaderEpoch:            1
HighWatermark:          412
MaxFollowerLag:         0
MaxFollowerLagTimeMs:   0
CurrentVoters:          [1,2,3]
CurrentObservers:       []
```

`LeaderId: 1` tells you that broker 1 is currently acting as the KRaft controller (the broker that coordinates cluster-wide metadata decisions). Note that the controller role is separate from being a partition leader: the controller manages cluster metadata, while partition leaders handle data traffic for specific partitions.

`CurrentVoters: [1,2,3]` tells you all three brokers are participating in the controller quorum, meaning any of them could take over as controller if the current one fails.

## Section 5: Exercise: Stop a Broker and Observe the Effects

This is the most important exercise in the lab. You will stop one of the three brokers and observe how Kafka's replication mechanism keeps the cluster running. Then you will restart the broker and see how it rejoins.

### 5.1 Note the Current State

Before stopping anything, capture the current state of the cluster. Run:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic labone --bootstrap-server localhost:19092
```

Write down (or save the output of) the current leaders and ISR sets. For example:

```
Partition: 0    Leader: 2   Replicas: 2,3,1   Isr: 2,3,1
Partition: 1    Leader: 3   Replicas: 3,1,2   Isr: 3,1,2
Partition: 2    Leader: 1   Replicas: 1,2,3   Isr: 1,2,3
```

Pick the broker that is leading the most partitions (or just pick `kafka2` to make the lab consistent with what follows). We will stop that broker and watch what happens.

### 5.2 Stop kafka2

Stop the `kafka2` container gracefully:

```
docker compose stop kafka2
```

This sends a SIGTERM signal to the container, asking it to shut down cleanly. After a few seconds, verify it has stopped:

```
docker compose ps
```

You should see `kafka1` and `kafka3` still running, with `kafka2` either gone from the list or shown in an exited state.

### 5.3 Observe the Effect on the Topic

Now describe the `labone` topic again:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic labone --bootstrap-server localhost:19092
```

The output now shows the impact of losing broker 2. You should see something like:

```
Topic: labone   TopicId: ...   PartitionCount: 3   ReplicationFactor: 3   Configs:
        Topic: labone   Partition: 0    Leader: 3   Replicas: 2,3,1   Isr: 3,1   Elr:    LastKnownElr:
        Topic: labone   Partition: 1    Leader: 3   Replicas: 3,1,2   Isr: 3,1   Elr:    LastKnownElr:
        Topic: labone   Partition: 2    Leader: 1   Replicas: 1,2,3   Isr: 1,3   Elr:    LastKnownElr:
```

Compare this to what you wrote down before. Several things have changed:

**The ISR has shrunk for every partition.** Broker 2 is no longer in the In-Sync Replica set for any partition, because it cannot communicate with the cluster. The Replicas column still lists broker 2 — that broker is still *supposed* to have a copy — but the ISR shows the brokers whose copies are currently up-to-date and reachable.

**A new leader was elected for the partitions that broker 2 was leading.** In our example, broker 2 was leading partition 0. Now broker 3 is leading that partition. Kafka automatically promoted one of the surviving followers to leader as soon as it detected that broker 2 was unreachable.

**Partitions that broker 2 was NOT leading still have the same leader.** Partitions 1 and 2 in our example were already led by other brokers, so their leaders did not change. Only their ISR shrank.

This is the heart of Kafka's fault tolerance. The cluster lost one of three brokers, but every partition still has a leader and at least two replicas in-sync. Producers and consumers can keep working.

### 5.4 Verify the Cluster Still Works

Confirm that the cluster is still operational by producing and consuming a message. In one Command Prompt window:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-producer.sh --topic labone --bootstrap-server localhost:19092
```

Type a message:

```
This message is being produced while kafka2 is down
```

In another Command Prompt window:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-console-consumer.sh --topic labone --bootstrap-server localhost:19092
```

You should see the message you just produced appear in the consumer. The cluster is fully operational despite the broker outage. Stop both the producer and consumer when you are done (Ctrl+C in each).

### 5.5 Restart kafka2

Now bring `kafka2` back online:

```
docker compose start kafka2
```

Wait about 30 seconds for the broker to fully start up and catch up with the cluster. You can watch it rejoining by viewing its logs:

```
docker compose logs -f kafka2
```

You will see messages about the broker connecting to the controller, fetching metadata, and catching up on the partitions it holds copies of. When the rejoin is complete, press Ctrl+C to stop following the logs.

### 5.6 Observe the Recovery

Describe the `labone` topic one more time:

```
docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic labone --bootstrap-server localhost:19092
```

You should now see something like:

```
Topic: labone   TopicId: ...   PartitionCount: 3   ReplicationFactor: 3   Configs:
        Topic: labone   Partition: 0    Leader: 3   Replicas: 2,3,1   Isr: 3,1,2   Elr:    LastKnownElr:
        Topic: labone   Partition: 1    Leader: 3   Replicas: 3,1,2   Isr: 3,1,2   Elr:    LastKnownElr:
        Topic: labone   Partition: 2    Leader: 1   Replicas: 1,2,3   Isr: 1,3,2   Elr:    LastKnownElr:
```

Two changes since the broker came back:

**Broker 2 has rejoined the ISR for every partition.** Its copies caught up with the leaders, so it is back in the In-Sync Replica set.

**Leadership did not automatically move back.** Even though broker 2 was originally leading partition 0, partition 0 is still led by broker 3 (the broker that was promoted when broker 2 went down). Kafka does not automatically move leadership back to the original broker; that would cause unnecessary disruption.

Eventually, a process called "preferred leader election" can rebalance leadership back to the original assignments. This typically runs automatically on a schedule, or can be triggered manually with `kafka-leader-election.sh`. For this lab, the current state is fine.

### 5.7 What You Just Saw

In a single exercise, you witnessed:

- A cluster operating with three brokers, all replicas in-sync
- One broker going offline gracefully
- The cluster detecting the failure and electing new leaders for the affected partitions
- The cluster continuing to accept produces and serve consumers despite the failure
- The broker coming back online and rejoining the cluster
- The replication mechanism catching the returning broker up so that all replicas are in-sync again

This is what enterprise-grade messaging means in practice. Kafka clusters routinely lose brokers (due to hardware failure, network issues, deployments, or maintenance) and keep operating. The replication mechanism is what makes that possible, and you have now seen it work on your own machine.

## Section 6: Wrapping Up

### 6.1 What to Leave Running

For the next lab you will need:

- The Kafka cluster still running (all three brokers)
- The `labone` topic — it will persist as long as the cluster's storage is intact

You can close the producer and consumer windows. They are short-lived clients and easy to restart.

### 6.2 Stopping the Cluster

When you are done with the lab and ready to shut everything down, run:

```
docker compose down
```

This stops all three containers and removes them. The data they stored will be lost (because we did not configure persistent volumes), so next time you start the cluster you will need to recreate any topics you want to use.

If you want to stop the cluster but keep the data for next time, use:

```
docker compose stop
```

Then restart with:

```
docker compose start
```

For lab purposes, `docker compose down` followed by `docker compose up -d` next session is the simplest pattern.

### 6.3 What You Have Learned

In this lab you have:

- Started a three-broker Kafka cluster in KRaft mode using Docker Compose
- Configured each broker with separate listeners for in-network clients and external host clients
- Created a topic with three partitions and replication factor 3
- Sent and received messages using Kafka's command-line tools
- Observed how message keys determine partition assignment and per-entity ordering
- Examined leader and follower roles across the cluster
- Stopped a broker and observed the cluster's automatic recovery
- Restarted the broker and watched it rejoin the cluster

These concepts (broker, topic, partition, leader, follower, ISR, replication, consumer offset, key, ordering) are exactly what Spring for Apache Kafka wraps in its programming model. In the next lab you will use a Spring Boot application to produce messages to this cluster, and you will see how the abstractions you have just touched at the command line map onto the Spring annotations and configuration.

### 6.4 Quick Reference

All commands assume you are in `C:\kafka-docker`. The Kafka CLI tools live inside the broker containers at `/opt/kafka/bin/` and have the `.sh` extension. CLI commands running inside a broker use `--bootstrap-server localhost:19092` (the INTERNAL listener). Clients running from your Windows host (such as the Spring Boot applications in later labs) use `--bootstrap-server localhost:9092,localhost:9094,localhost:9096` instead.

| Command | Purpose |
|---|---|
| `docker compose up -d` | Start the three-broker cluster |
| `docker compose ps` | Check that brokers are running |
| `docker compose logs -f kafka1` | Watch logs of a specific broker |
| `docker compose stop kafka2` | Stop a specific broker |
| `docker compose start kafka2` | Restart a specific broker |
| `docker compose stop` | Stop all brokers (keep data) |
| `docker compose down` | Stop all brokers and remove containers (data lost) |
| `docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:19092` | List all topics |
| `docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --describe --topic <name> --bootstrap-server localhost:19092` | Describe a topic |
| `docker compose exec kafka1 /opt/kafka/bin/kafka-topics.sh --create --topic <name> --partitions <N> --replication-factor 3 --bootstrap-server localhost:19092` | Create a topic |
| `docker compose exec kafka1 /opt/kafka/bin/kafka-console-producer.sh --topic <name> --bootstrap-server localhost:19092` | Start a console producer |
| `docker compose exec kafka1 /opt/kafka/bin/kafka-console-consumer.sh --topic <name> --bootstrap-server localhost:19092 [--from-beginning]` | Start a console consumer |

### 6.5 Self-Check

Before moving on to Lab 4.2, you should be able to answer these questions:

1. When you create a topic with three partitions and replication factor 3 on a three-broker cluster, how many copies of each partition exist, and where are they?
2. What is the difference between the leader of a partition and a follower? Which one handles produce requests?
3. What does the ISR (In-Sync Replica set) tell you? What does it mean for a replica to be "in-sync"?
4. When you stopped a broker, why did some partitions get new leaders and others did not?
5. When you restarted the broker, why did it not automatically take back leadership of the partitions it used to lead?
6. If a producer sends a message with key `customer-42`, which partition does it go to? Does the replication factor change the answer?
7. What is the difference between starting a console consumer with and without `--from-beginning`?
8. Why does this lab configure each broker with two client listeners (HOST and INTERNAL)? What problem does that solve?

If any of these are unclear, review the relevant section of the lab before continuing.

## End of Lab 4.1
