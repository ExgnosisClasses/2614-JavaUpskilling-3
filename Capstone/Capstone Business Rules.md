# Capstone Specification: Business Rules

#### Version  1.0 
This supplement defines the rules that decide when an operation is allowed and
when it is declined. It pairs with the API Contract and the Data Model. The status codes follow the taxonomy defined in the contract.

Every rule here is enforced in the **service layer**. The database constraints
(`CHECK (amount > 0)`, the foreign keys, the status and type `CHECK`s) and the
balance audit trigger are backstops and side effects, not the primary validation gate.

Keeping the rules in one layer is a deliberate design decision.
- This design keeps business logic out of the database so the persistence store stays loosely coupled
- We can think of the business rules as being the "semantics" which are defined by the business
- The database rules are "syntactic" such as range rules, non-null constraints, uniqueness and data types for example.
- If we were to implement an overdraft policy, for example, it would be implemented in the service layer, specifically, that an account balance can be negative. We should be able to do this without changingg our database constraints.

Each rule has an identifier (for example `BR-F1`) so the API contract, the test
suite, and the grading conversation can refer to a rule precisely.

---

## Evaluation order

A request is checked in this order. The first validity gate that fails determines the
response; subsequent validity gates are not evaluated. 

A request that clears every gate
executes.

1. **Authenticated?** No valid token, no principal. Fail to **401**.
2. **Authorized by role?** Caller lacks the role the operation requires. Fail to **403**.
3. **Well formed?** Missing or invalid fields. Fail to **400**.
4. **Target exists?** Account or customer not found. Fail to **404**.
5. **Authorized by ownership?** account_holder acting outside own accounts, or a teller transfer spanning two customers. Fail to **403**.
6. **Account active?** A money movement against an inactive account. Fail to **422**, no row written.
7. **Sufficient funds?** A debit larger than the balance. Fail to **422**, FAILED row written.
8. **External call (payment only).** Mock returns 503. Respond **502**, FAILED row written.
9. **Execute**: persist the transaction(s), update balances, audit fires, publish to Kafka.

Implementing this order is your application is something you need to demonstrate.
-  Authorization is decided before resource state
-  Resource state is verified before any funds are moved

The same input should always produce the same status code.

---

## Rule catalog

### Access and identity

- **BR-A1** Every endpoint except `GET /api/health` requires a valid
  authenticated token. Violation returns 401.
- **BR-A2** Deposits and withdrawals require the `teller` role. Violation returns 403.
- **BR-A3** Account status changes and the transaction report require the
  `teller` role. Violation returns 403.
- **BR-A4** An `account_holder` may read or act on only accounts whose owning
  customer matches the caller's resolved `customer_id`. Violation returns 403.
- **BR-A5** In a teller-initiated transfer, both accounts must belong to the
  same customer. A cross-customer transfer returns 403.
- **BR-A6** A referenced account or customer that does not exist returns 404.

### Account state

- **BR-S1** No money movement (deposit, withdrawal, either transfer leg, or payment) may be performed on an `INACTIVE` account. Violation returns 422 and **no transaction row is written**, because an inactive account is not
  permitted to transact at all.
- **BR-S2** An `INACTIVE` account remains visible in account reads. Only money
  movement is blocked, not visibility.
- **BR-S3** Only a teller may change an account's status (see BR-A3). Activating  an inactive account is the path that brings it into service. (Stretch.)

### Input validation

- **BR-V1** `amount` must be present, numeric, greater than zero, and at most two
  decimal places. Violation returns 400. The database `CHECK (amount > 0)` is a
  backstop; the service rejects first so the caller gets a 400, not a database error.
- **BR-V2** A transfer must include `toAccountId`, and it must differ from the
  source account. Violation returns 400.
- **BR-V3** A payment must include a non-empty `reference`. Violation returns 400.
- **BR-V4** Malformed JSON or unknown required fields return 400.

### Funds

- **BR-F1** A debit (withdrawal, transfer debit leg, or payment) is allowed only
  if the source balance is greater than or equal to the amount. Violation returns
  422 and records a **FAILED** transaction (the debit, `TRANSFER_OUT`, or
  `PAYMENT` leg only); no balance changes.
- **BR-F2** Balances may not go below zero in this version; there is no overdraft.
  See Extension points if you want to try and implement overdrafts.

### Transfer

- **BR-T1** An internal transfer debits the source as `TRANSFER_OUT` and credits
  the destination as `TRANSFER_IN` for the same amount, writing two transactions
  and one `transfers` row, all in a single database transaction. Either all of it
  commits or all of it rolls back.
- **BR-T2** Source and destination must differ (BR-V2) and both must be ACTIVE
  (BR-S1).
- **BR-T3** On success both legs are `COMPLETED` and the `transfers` row is
  written. On insufficient funds a single FAILED `TRANSFER_OUT` is written and no
  `transfers` row is created (BR-F1).

### Payment

- **BR-P1** A payment debits a single account and is recorded as one `PAYMENT`
  transaction. There is no `transfers` row, because the counterparty is external.
- **BR-P2** Pre-conditions (active account BR-S1, sufficient funds BR-F1) are
  checked **before** the external call. If they fail, no external call is made.
- **BR-P3** The external payment mock is then called. On success (201) the account
  is debited and the `PAYMENT` is `COMPLETED`, returning 201. On failure (mock
  returns 503) a FAILED `PAYMENT` is recorded, the account is not debited, and
  bankapi returns 502.
- **BR-P4** Test hook: an amount of `999.99` deterministically drives the mock's
  failure path.
  - This is an arbitrary decision by it makes your job easier since you don't have code any transaction logic for the external mock

### Cash operations (teller)

- **BR-C1** A deposit credits the account and is recorded as one `DEPOSIT`
  transaction. No funds check applies.
- **BR-C2** A withdrawal debits the account and is recorded as one `WITHDRAWAL`
  transaction, subject to the funds rule BR-F1.
- **BR-C3** Both require the teller role (BR-A2) and an ACTIVE account (BR-S1).

### Side effects

- **BR-X1** Any committed balance change writes an `account_audit` row
  automatically via the database trigger. FAILED transactions change no balance
  and therefore produce no audit row.
- **BR-K1** Every `COMPLETED` transaction is published to the Kafka statistics
  topic, anonymized to `(type, amount)`. FAILED transactions are not published. A
  transfer publishes two messages, one for the `TRANSFER_OUT` leg and one for the
  `TRANSFER_IN` leg.

---

## Consolidated outcome matrix

The single reference for what each outcome produces.

| Condition | Status | transactions row | balance change | audit row | Kafka |
|-----------|--------|------------------|----------------|-----------|-------|
| Success: deposit or withdrawal | 201 | one (COMPLETED) | yes | yes | yes |
| Success: transfer | 201 | two (COMPLETED) | yes (both) | yes (both) | two |
| Success: payment | 201 | one (COMPLETED) | yes | yes | yes |
| Missing or invalid token | 401 | no | no | no | no |
| Wrong role | 403 | no | no | no | no |
| Ownership or cross-customer | 403 | no | no | no | no |
| Malformed request | 400 | no | no | no | no |
| Account or customer not found | 404 | no | no | no | no |
| Inactive account | 422 | no | no | no | no |
| Insufficient funds | 422 | one (FAILED) | no | no | no |
| External payment failure | 502 | one (FAILED) | no | no | no |

---

## Worked examples

These double as integration test cases.

1. **Customer transfer, happy path.** A customer transfers 100.00 between two of
   their own ACTIVE accounts with enough balance. Result: 201, two COMPLETED
   transactions plus a transfers row, both balances updated, two audit rows, two
   Kafka messages. (BR-T1, BR-T3, BR-X1, BR-K1.)

2. **Customer transfer, insufficient funds.** Same customer, amount exceeds the
   source balance. Result: 422, one FAILED `TRANSFER_OUT`, no transfers row, no
   balance change, no audit row, no Kafka. (BR-F1, BR-T3.)

3. **Customer reads another customer's account.** Result: 403, nothing written.
   (BR-A4.)

4. **Teller deposits to the seeded inactive account.** Result: 422, no row.
   The teller then activates the account via the status endpoint (stretch), and
   the same deposit now returns 201. (BR-S1, BR-S3, BR-C1.)

5. **Customer payment that the processor rejects.** Customer pays 999.99 from an
   ACTIVE account with a sufficient balance. Pre-checks pass, the mock returns
   503. Result: 502, one FAILED `PAYMENT`, no debit, no audit row, no Kafka.
   (BR-P2, BR-P3, BR-P4.)

6. **Customer attempts a deposit.** A customer (not a teller) calls the deposit
   endpoint. Result: 403, nothing written. (BR-A2.)

---

## Extension points

Because the rules live in the service layer, each of these is a localized change.

There suggested extensions are provided if your team wants to try something more challenging. Attempting these, even if you don't get them working, count as "Exceeds Expectations" as long as you can explain your design and show the code.

- **Overdraft.** Relax BR-F1 and BR-F2 to permit the balance to fall to a
  negative floor (a per-account or per-product limit) rather than zero. A debit
  within the limit then succeeds and is `COMPLETED` instead of `FAILED`.
- **Daily or per-transaction limits.** Add a rule that declines amounts above a
  threshold, returning 422 with a FAILED row, parallel to BR-F1.
- **Idempotency.** Require an idempotency key on money-movement requests so a
  retried submission does not double-post. This pairs with the REST extensibility
  criterion in the rubric.

---

## A note on existence versus authorization

This specification returns 403 when an `account_holder` references an account they do not
own (BR-A4), per the contract. An alternative hardening choice is to return 404 in
that case as well, so a caller cannot distinguish "exists but not yours" from
"does not exist" and therefore cannot enumerate account ids. Either is defensible;
403 is simpler and is what the contract currently specifies. Flag if you want the
enumeration-resistant 404 behavior instead, and I will align both documents.

---

### End