# Capstone Supplement: Persistence and the Service Layer (JPA)

#### Version 1.0 June 29

This supplement assumes you have completed the JPA labs. It does not re-teach
entity mapping or Spring Data. Its purpose is to reinforce how the persistence
layer fits into the capstone's layered architecture and the boundaries that the
grading cares about. It pairs with the Data Model (the schema) and the Business
Rules supplement (the rules the service enforces).

The reference implementation of the entities and repositories is held separately by
your instructor. Build them yourself first; the point of this part of the capstone
is the boundaries, not the boilerplate.

---

## 1. The layered architecture

Every request flows down through the same layers, and each layer depends only on the
one below it.

```
HTTP request
   |
   v
Controller     HTTP concerns only: read DTOs, return DTOs and status codes.
   |           No business logic. Authentication is established by the filter chain.
   v
Service        Business rules, authorization (@PreAuthorize, ownership),
   |           transaction boundaries (@Transactional), orchestration.
   |           Maps entities to and from DTOs. Wraps persistence errors.
   |           Calls the Kafka publisher and the payment client.
   v
Repository     Spring Data JPA interfaces. Data access only, no business logic.
   |
   v
Entity  <-->   Oracle. The schema is owned by the DDL script; the audit trigger
               fires here on a balance update.
```

Two rules make this real rather than decorative. The controller never injects or
calls a repository directly; it only calls the service. And the entity never reaches
upward: it carries no business decisions and no knowledge of HTTP.

Because the schema is owned by the DDL script (loaded at container start), Hibernate
maps onto existing tables and must not generate or alter them. Set `ddl-auto: none`.
Also set `spring.jpa.open-in-view: false`, so lazy associations cannot be loaded
from the controller layer; that forces the service to fetch what it needs explicitly
and keeps the layering honest.

---

## 2. The repository is how the service reaches the data

The service layer depends on Spring Data repository interfaces, injected through the
constructor. It does not use `EntityManager` directly except where a feature
requires it (the transfer's pessimistic lock is the one likely case). The
repositories expose the lookups the service needs: a customer by `customer_number`
(to resolve the token's `sub` for ownership), accounts by customer, an account by
number, and a transaction history for an account.

A single business operation composes several repository calls inside one
`@Transactional` service method. The internal transfer is the clearest example: it
reads both accounts, writes two transaction rows and one transfer row, and updates
two balances, and all of it commits together or rolls back together. The repository
provides the data access; the service owns the orchestration and the transaction
boundary.

One boundary to hold: do not return entities to the controller as the response
body. Map them to DTOs or view records at the service boundary. Entities are managed,
mutable, and tied to the persistence context; letting them escape couples the API
shape to the table shape and invites lazy-loading surprises.

---

## 3. The audit trigger is a database side effect, not entity code

The balance audit trigger lives in the database (see the Data Model). It fires
automatically on an update to `accounts.balance` and writes an `account_audit` row
in the same transaction. Your code never writes audit rows. There is no audit
insert in any service or entity, and you do not map `account_audit` for writing.

The implication for JPA is small but worth stating: when the service changes a
managed `Account`'s balance and the transaction commits, Hibernate emits the
`UPDATE`, and that `UPDATE` is what fires the trigger. So the balance change must be
a real managed-entity update (dirty checking, or an explicit save), not a native
bulk update that bypasses the persistence context. If you ever read the audit data
(for a report, say), map a read-only entity over `account_audit`; never write to it.

This is a deliberate teaching contrast. The audit is enforced by the database, so
the application cannot forget it or forge it. That is exactly the property an audit
trail needs, and it is why this one concern lives in a trigger while every business
rule does not.

---

## 4. Wrap vendor errors into domain exceptions

The service layer and everything above it must speak the domain's language, never
Oracle's. An `ORA-` code, a SQLState, a constraint name, or a vendor exception type
must not reach the controller.

Spring gives you the first half of this for free. Through a repository, Spring
translates JDBC `SQLException`s into its own `DataAccessException` hierarchy, so the
service already sees `DataIntegrityViolationException`,
`CannotAcquireLockException`, and similar, rather than raw Oracle errors. That is a
vendor-neutral persistence vocabulary.

The capstone asks you to take the second step: catch the cases the service actually
cares about and rethrow a domain exception that the controller's exception handler
maps to the API contract's status codes. A lost race on the transfer's row lock
becomes a domain "account is busy, retry" rather than a leaked
`CannotAcquireLockException`. A duplicate natural key becomes a domain conflict.
Everything the service does not specifically handle becomes a single generic
persistence-failure domain exception that maps to a 500, with the vendor detail
logged, not returned.

The reason this matters is decoupling. The service's view of the data is domain
objects and domain exceptions. If Oracle were swapped for another database, the
service and controller would not change; only the persistence layer and its
exception translation would. Tie your business logic to `ORA-00001` and you have
welded the service to Oracle.

Keep one distinction sharp. Business-rule rejections are not vendor errors. Insufficient
funds and an inactive account are checked by the service before the database is
touched, and they produce a 422 with no Oracle exception involved. The check
constraints in the schema (`amount > 0`, the status and type values) are backstops,
not your rule engine. Do not implement a business rule by catching a check-constraint
violation; validate first, and let the constraint catch only what should never
happen.

---

## 5. Business rules live in the service, not the entity

Entities are mapping and state. They hold no rule that decides whether an operation
is allowed. There is no "if balance is too low, throw" inside `Account`. Every BR
rule from the Business Rules supplement, ownership, active-account, sufficient-funds,
role checks, lives in the service.

An entity may carry a tiny, decision-free helper such as adjusting its own balance,
but the decision to allow or deny the adjustment is the service's. Three reasons
this boundary is enforced and graded:

The rules are testable in isolation. A service method with mocked repositories
verifies the rule without a database, which is most of your unit-test value.

The rules have one home. Scattering them between entity, service, and database makes
them impossible to reason about; the service is the single place to read the policy.

The rules often need a view no single entity has, ownership spans the token and the
customer, a transfer spans two accounts and two legs. Only the service sees enough to
decide.

---

## Configuration summary

In the BankService `application.yml`, the persistence-relevant settings are:

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: none          # schema is owned by the DDL script
    open-in-view: false       # no lazy loading from the controller layer
    properties:
      hibernate.dialect: org.hibernate.dialect.OracleDialect
```

The datasource, the UUID generation strategy, and the Oracle connection details are
covered in the environment runbook.

---

## How to know you got the boundaries right

Two checks, which also map to the test strategy:

A service method's business rule can be unit-tested with the repository mocked and no
database running. If a rule cannot be tested without Oracle, it has probably leaked
into the entity or the database.

An integration test against a real Oracle (Testcontainers) confirms the mapping and
that a committed balance change produced an `account_audit` row. The audit row
appearing is the proof that the trigger and the managed-entity update are wired
correctly.

---

## Notes 

- The companion reference file (`Capstone JPA Reference Solution.md`) contains the
  entity classes, the enums, the repositories, and a compact example of the
  vendor-error translation. This will not be provided as part of the capstone but will be available later as a reference.
- The one design point most often one incorrectly is letting an entity enforce a
  rule (an overdraft guard inside `Account`). The unit-test check above surfaces it
  quickly.
