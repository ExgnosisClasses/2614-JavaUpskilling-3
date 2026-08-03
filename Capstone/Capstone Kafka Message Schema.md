# Capstone Supplement: Kafka Statistics Message Schema

#### Version 1.0  June 29

This defines the message the BankService publishes to Kafka for transaction
statistics: the topic, the payload shape, when a message is sent, and the producer
configuration. It pairs with the Data Model (the transaction types) and the
Business Rules (which transactions are published).

The payload is **JSON**, serialized with Spring Kafka's `JsonSerializer`, the same
mechanism as Labs 4.2 and 4.3. Spring configuration is **YAML**, consistent with
the other components. (A formal Avro schema with a Schema Registry is the
enterprise-grade alternative, but it adds a registry container and more config than
this capstone needs, so it is out of scope.)

---

## What changed from the labs

In Lab 4.2 the producer was a standalone simulator that published whole
`Transaction` objects, and Lab 4.3's consumer did the anonymizing transform. In the
capstone, the producer lives inside the BankService and publishes the
**already-anonymized** statistic, because anonymization is the BankService's
responsibility. Concretely:

- The producer is part of `bankapi`, not a separate simulator.
- It publishes only on a `COMPLETED` transaction. `FAILED` transactions are never
  published.
- An internal transfer publishes **two** messages, one for the `TRANSFER_OUT` leg
  and one for the `TRANSFER_IN` leg.
- The cluster is a single broker, so the topic uses replication factor 1.

---

## The topic

| Property | Value |
|----------|-------|
| Name | `transaction-stats` |
| Partitions | 1 |
| Replication factor | 1 (single broker) |

Created once (also shown in the environment runbook):

```
docker exec capstone-kafka /opt/kafka/bin/kafka-topics.sh \
  --create --topic transaction-stats \
  --bootstrap-server localhost:9092 \
  --partitions 1 --replication-factor 1
```

The lab topic was named `transactions` with three partitions and replication factor
3. The capstone topic is named for what it carries (anonymized statistics, not whole
transactions) and is sized for one broker.

---

## The message

**Key:** the transaction type as a string (for example `DEPOSIT`). With a single
partition the key does not affect placement, but keying by type keeps the producer
consistent with the lab and groups a type's events in order.

**Value:** a JSON object with exactly two fields.

| Field | JSON type | Values |
|-------|-----------|--------|
| `type` | string | `DEPOSIT`, `WITHDRAWAL`, `TRANSFER_IN`, `TRANSFER_OUT`, `PAYMENT` |
| `amount` | number | positive, two decimal places |

Example message value:

```json
{ "type": "PAYMENT", "amount": 50.00 }
```

You model this value as a small two-field type (a record is the natural
choice) whose fields serialize to exactly `type` and `amount`. The JSON example
above is the contract that type must match.

**Anonymization** is the point of this shape. The message deliberately omits the
transaction id, account id, customer, and timestamp, so the stream supports
aggregate analytics (counts and totals per type) without being traceable to an
individual or an account. Do not add identifying fields back in.

---

## When a message is published

The producer is called from the **service layer**, after the transaction has been
committed, once per `COMPLETED` transaction row:

- A deposit, withdrawal, or payment publishes one message.
- An internal transfer publishes two, one per leg, because each leg is its own
  committed transaction.
- A `FAILED` transaction publishes nothing.

Publishing after the database commit (not before) means the statistics stream
never reports a transaction that did not actually happen.

---

## Producer configuration (bankapi)

Added to the BankService `application.yml`:

```yaml
spring:
  kafka:
    bootstrap-servers: localhost:9092
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
      acks: all

app:
  kafka:
    topic: transaction-stats
```

`acks: all` on a single broker means the one leader acknowledges the write. The
`StringSerializer` keys and `JsonSerializer` values mirror Lab 4.2.

The publisher itself is a small service students write: it wraps the
auto-configured `KafkaTemplate`, and for each statistic sends a record whose key is
the transaction type and whose value is the two-field statistic, to the configured
topic. The service layer calls this publisher once for each committed `COMPLETED`
transaction (once per leg for a transfer).

---

## Delivery semantics (required choice)

The rubric expects your team to choose a delivery guarantee and justify it. The
three options and what each requires of the producer:

- **At most once.** `acks: 0` or `1`, no retries. Fast, but a broker hiccup can
  drop a statistic. Never duplicates.
- **At least once.** `acks: all` plus retries (the configuration above, with
  `retries` greater than zero, which is the Spring default). Never drops a
  statistic, but a retry after a partial failure can publish a duplicate.
- **Exactly once.** Idempotent producer (`enable.idempotence: true`) plus
  transactions. No loss and no duplicates, at the cost of more configuration and
  throughput.

For an anonymized statistics stream, at-least-once is the pragmatic choice: a
duplicated `(type, amount)` skews a count slightly, while a lost one is worse, and
exactly-once is heavier than the value of the data warrants. Your team may choose
differently; the deliverable is the choice plus the reasoning, not a specific
answer.

---

## Consumer to CSV (stretch)

The CSV consumer is a stretch deliverable; the required path is the producer above.
If you build it, it is the Lab 4.3 and 4.4 consumer with the transform already done
(the message is already `(type, amount)`), so the listener just appends a row.

Consumer `application.yml`:

```yaml
spring:
  kafka:
    bootstrap-servers: localhost:9092
    consumer:
      group-id: statsconsumergroup
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      properties:
        spring.json.use.type.headers: false
        spring.json.value.default.type: com.example.statsconsumer.model.TransactionStat
        spring.json.trusted.packages: "com.example.statsconsumer.model"
```

`use.type.headers: false` plus an explicit `value.default.type` is the same pattern
as Lab 4.3: the producer stamps a type header naming the BankService's class, which
the consumer does not have, so the consumer ignores the header and deserializes into
its own `TransactionStat` instead.

A `@KafkaListener` on the `transaction-stats` topic receives each statistic and
appends one CSV line per message (for example `PAYMENT,50.00`). Because the message
already carries `(type, amount)`, there is no transform step, unlike Lab 4.3.

---

## Smoke test

With the producer running and a transaction committed through the system, read the
topic from the broker:

```
docker exec capstone-kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --topic transaction-stats --bootstrap-server localhost:9092 \
  --from-beginning --property print.key=true --property key.separator=" | "
```

A committed payment of 50.00 shows as:

```
PAYMENT | {"type":"PAYMENT","amount":50.00}
```

An internal transfer shows two lines, one `TRANSFER_OUT` and one `TRANSFER_IN`. A
failed transaction shows nothing.

