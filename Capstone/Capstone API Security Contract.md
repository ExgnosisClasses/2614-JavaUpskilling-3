# Capstone Specification: API Contract and Endpoint Security

#### Version 1,0 - June 29

This supplement defines the BankService (bankapi) REST contract and the
authorization rules for each endpoint. The BFF passes these requests through
to bankapi unchanged, so the contract below is also the effective contract
seen from the SPA.

*Changes since v0.1: added the public `GET /api/health` endpoint; resolved the
three open items (no validation trigger, application-owned UUIDs, 422 for the
inactive-account case).*

---

## Assumptions applied in this sspec

- Two roles only: `account_holder` and `teller`. No other roles are used.
- Customers authenticate with their `customer_number` (for example `487-978493`).
  Bank staff authenticate with a staff username (for example `teller1`). Staff
  are **not** stored in the database; they exist only in the authorization server.
- The token `sub` claim carries the login identity: the `customer_number` for a
  customer, the staff username for a teller.
- Money fields are `BigDecimal` end to end and are serialized as JSON numbers
  with two decimal places.
- Base path is `/api`. Versioning is left as a documented extension point
  (a future `/api/v1`), not implemented now.

---

## Identity and ownership

bankapi resolves the caller's identity from the validated JWT, then enforces
ownership at the service layer.

- For an `account_holder`, bankapi reads `sub`, looks up the matching row in
  `customers` by `customer_number`, and obtains `customer_id`. Every account the
  caller touches must have that `customer_id`. Any attempt to read or act on an
  account belonging to another customer returns **403**.
- For a `teller`, there is no ownership filter on reads: a teller may view any
  customer's accounts. The one ownership rule that still applies is that the two
  accounts in a single internal transfer must belong to the **same** customer.
  A cross-customer transfer is rejected.

---

## Status code taxonomy

A single, consistent mapping is expected across all endpoints. Correct,
differentiated status codes are part of the REST grading.

| Code | Meaning in this project |
|------|--------------------------|
| 200  | Successful read |
| 201  | Transaction created (deposit, withdrawal, transfer, payment) |
| 400  | Malformed request (missing field, non-positive amount, bad JSON) |
| 401  | Missing or invalid token (no authenticated principal) |
| 403  | Authenticated but not allowed: wrong role, or ownership violation |
| 422  | Well-formed request rejected by a business rule (inactive account, insufficient funds) |
| 502  | External payment service failed; bankapi maps the upstream failure to Bad Gateway |

The 401 versus 403 split matters: 401 means "we do not know who you are," 403
means "we know who you are and you may not do this."

The 422 versus 403 split matters too: 403 is an authorization decision about the
*caller*; 422 is a decision about the *state of the resource* and is independent
of who is asking.

---

## FAILED transaction policy

Not every rejection produces a `transactions` row. The rule is whether a valid
attempt actually reached the point of moving money.

- **Insufficient funds** on a withdrawal, transfer, or payment: record a
  `FAILED` transaction (the debit leg only, for a transfer), do not change any
  balance, return **422**.
- **External payment failure** (mock returns 503): record a `FAILED` `PAYMENT`
  transaction, do not debit, return **502**.
- **Inactive account**: reject before any transaction is created. No row is
  written, because an inactive account is not permitted to transact at all.
  Return **422**.
- Note for the statistics producer: `FAILED` transactions are **not** published
  to Kafka.

---

## Endpoints

### Public

| Method and path | Roles | Request | Success | Notable failures |
|-----------------|-------|---------|---------|------------------|
| `GET /api/health` | none (public) | n/a | 200, `{ "status": "up" }` | n/a |

This is the only unauthenticated endpoint. The filter chain must `permitAll()`
this single path while requiring authentication for every other `/api/**`
route. It gives students one concrete contrast between a public and a protected
route in the `SecurityFilterChain`, and a trivial liveness check usable by the
demo and by container orchestration.

### Reads

| Method and path | Roles | Ownership rule | Success | Notable failures |
|-----------------|-------|----------------|---------|------------------|
| `GET /api/accounts` | account_holder | Returns only the caller's own accounts | 200, account list | 403 if a teller calls it |
| `GET /api/customers/{customerNumber}/accounts` | teller | Any customer | 200, that customer's accounts | 404 if customer not found |
| `GET /api/accounts/{accountId}` | account_holder, teller | account_holder must own the account | 200, account detail | 403 ownership, 404 not found |
| `GET /api/accounts/{accountId}/transactions` | account_holder, teller | account_holder must own the account | 200, transaction history | 403 ownership, 404 not found |

The inactive account still appears in `GET /api/accounts`. It is visible; it
simply cannot be transacted on.

### Money movement

| Method and path | Roles | Request body | Success | Business-rule failures |
|-----------------|-------|--------------|---------|------------------------|
| `POST /api/accounts/{accountId}/transfers` | account_holder, teller | `{ "toAccountId": <id>, "amount": <decimal> }` | 201, `{ transferId, status: COMPLETED }`; writes two transactions plus one transfer row; debits source, credits destination | 403 if either account is not owned (account_holder) or accounts span two customers (teller); 422 insufficient funds (writes FAILED debit leg); 422 if either account inactive (no row) |
| `POST /api/accounts/{accountId}/payments` | account_holder, teller | `{ "amount": <decimal>, "reference": <string> }` | 201, `{ txnId, status: COMPLETED }`; calls payment mock, on 201 debits and writes a `PAYMENT` row | 422 insufficient funds (writes FAILED); 422 inactive (no row); 502 if mock returns 503 (writes FAILED, no debit) |
| `POST /api/accounts/{accountId}/deposits` | teller | `{ "amount": <decimal> }` | 201, `{ txnId, status: COMPLETED }`; writes a `DEPOSIT` row, credits balance | 403 if not a teller; 422 inactive (no row) |
| `POST /api/accounts/{accountId}/withdrawals` | teller | `{ "amount": <decimal> }` | 201, `{ txnId, status: COMPLETED }`; writes a `WITHDRAWAL` row, debits balance | 403 if not a teller; 422 insufficient funds (writes FAILED); 422 inactive (no row) |

The payment endpoint is the only one that calls an external service. For the
required path the mock is unauthenticated. Securing that call with a
client-credentials token (reusing the Lab 2-3 bearer-token filter) is a
documented stretch that maps to the endpoint-hardening Exceeds criterion.

### Administration (stretch)

| Method and path | Roles | Request body | Success | Failures |
|-----------------|-------|--------------|---------|----------|
| `PUT /api/accounts/{accountId}/status` | teller | `{ "status": "ACTIVE" | "INACTIVE" }` | 200, updated account | 403 if not a teller, 404 not found |
| `GET /api/reports/transactions` | teller | n/a | 200, per-type counts and totals | 403 if not a teller |

The status endpoint is also the natural way to bring the one seeded-inactive
account to life during the demo, which makes it a good stretch to attempt even
though account activation is not on the required path.

---

## What students implement, and where

This contract is enforced at two layers deliberately, which is itself a grading
point (authorization at multiple layers, denies by default).

**Controller / filter chain (capstone part 5).** Students work only with the
Spring Security filter chain (`SecurityFilterChain`), not with older
`WebSecurityConfigurerAdapter` style. The filter chain establishes
authentication (validate the JWT, populate the principal and authorities), the
coarse rule that every `/api/**` endpoint requires an authenticated caller, and
the one exception that `GET /api/health` is `permitAll()`. Role-coarse rules
(for example, the report endpoint is teller-only) may also be expressed here.

**Service layer (capstone part 6).** Fine-grained authorization lives on the
service methods with `@PreAuthorize` and similar annotations. This is where the
role checks for deposit and withdrawal live, and where the ownership checks live,
because ownership depends on data (resolving `sub` to a `customer_id` and
comparing it to the account's owner) that the filter chain does not have.

A worked example of the two layers for a teller-only operation:

```java
@PreAuthorize("hasRole('teller')")
public TransactionResult deposit(Long accountId, BigDecimal amount) { ... }
```

and an ownership check expressed against the resolved customer:

```java
@PreAuthorize("hasRole('teller') or @ownership.ownsAccount(authentication, #accountId)")
public AccountView getAccount(Long accountId) { ... }
```

`@ownership.ownsAccount` is a small bean students write that performs the
`sub` to `customer_id` resolution and the comparison. It keeps the SpEL readable
and puts the data-dependent rule in testable Java.

---

## Error response shape

A single error model across all endpoints, consistent with the Module 2 global
exception handler:

```json
{
  "timestamp": "2026-06-27T14:00:00Z",
  "status": 422,
  "error": "Unprocessable Entity",
  "message": "Account A-002 is inactive and cannot be transacted on",
  "path": "/api/accounts/2/withdrawals"
}
```

Messages should be useful but must not leak internals (no stack traces, no SQL,
no token contents).

---

## Decisions resolved since v0.1

- **No validation trigger.** All business validation (inactive account,
  insufficient funds, and any future overdraft policy) is enforced in the
  service layer. The single Oracle trigger students implement is the balance
  audit trigger, which is sufficient to demonstrate trigger competency and keeps
  business logic out of the database so the persistence layer stays loosely
  coupled.
- **Application-owned UUIDs.** Transaction and transfer ids are generated in the
  application with Hibernate `@UuidGenerator`, not by Oracle. This avoids
  coupling the entity layer to Oracle-specific functions in case the persistence
  database changes, and lets the service know an id before insert. Downstream
  consequence: in the DataModel DDL, `txn_id`, `transfer_id`, `debit_txn_id`,
  and `credit_txn_id` become `VARCHAR2(36)` (canonical hyphenated form) and the
  `RAWTOHEX(SYS_GUID())` defaults are removed.
- **Inactive-account rejection uses 422**, not 409.

### Tracked downstream (not blocking this contract)

- DataModel DDL update per the UUID decision above (widths to 36, defaults
  removed).
- Integration-test approach: Testcontainers-Oracle is required for the
  audit-trigger and full-fidelity runs; lighter persistence slices may use H2
  now that ids no longer depend on Oracle functions. Detailed in the
  test-strategy note.
