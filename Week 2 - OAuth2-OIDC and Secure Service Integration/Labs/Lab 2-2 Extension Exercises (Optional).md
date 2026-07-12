# Lab 2-2 Extension Exercises

**Note, these labs have not been fully tested. If you find errors, use Copilot to debug.**

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 3 - OAuth2 / OIDC Foundations and Spring Security

These optional extension exercises go beyond the required Lab 2-2 tasks. They are not graded and are not required to complete the module. They exist to give faster learners deeper challenges that require additional research, experimentation, or design judgement.

Solutions are provided at the end of the module.

**Prerequisite:** complete Lab 2-2 (all five exercises) before attempting these extensions. Each extension builds on code you have already written.

---

## Extension 1: JSON Error Responses (extends Exercise 2)

By default, Spring Security returns 401 and 403 responses with plain-text or HTML bodies. For a REST API consumed by a JavaScript client, JSON error bodies are much friendlier. The client can parse them, display structured error messages, and react to specific error codes.

Add a custom `AuthenticationEntryPoint` and `AccessDeniedHandler` that return JSON error responses like:

```json
{"error": "authentication_required", "message": "A valid Bearer token is required"}
```

and

```json
{"error": "access_denied", "message": "Your token does not include the required scope or role"}
```

**Steps:**

1. Create `JsonAuthenticationEntryPoint` that implements `AuthenticationEntryPoint`. In `commence(...)`, write a JSON body with `error: "authentication_required"` and set status 401.
2. Create `JsonAccessDeniedHandler` that implements `AccessDeniedHandler`. In `handle(...)`, write a JSON body with `error: "access_denied"` and set status 403.
3. Wire both into the security configuration:
   ```java
   .exceptionHandling(ex -> ex
           .authenticationEntryPoint(jsonAuthenticationEntryPoint)
           .accessDeniedHandler(jsonAccessDeniedHandler))
   ```
4. Re-run the tests from Exercise 2's Task 2.4 (specifically Steps 3 and 5) and verify the response body is now JSON instead of Spring Security's default text.

**Things to think about:**

- Where would you add a `timestamp` or `path` field to make these errors more useful for client-side logging?
- The two handlers each have an `ObjectMapper`. Is there a reason to share one bean across them, or is per-handler isolation simpler?
- How would a client distinguish between "token expired" and "token signature invalid"? Both currently fall into the same 401 bucket. What additional information would Spring Security's `BearerTokenAuthenticationException` give you, and where would you read it?

---

## Extension 2: TransactionService with Ownership-Aware Method Security (extends Exercise 4)

Exercise 4 built `AccountService` with method-level authorization. Now build a `TransactionService` that puts the same patterns to work for the third domain model.

**Requirements:**

The `TransactionService` should provide at least two methods, both protected with `@PreAuthorize`:

- `postTransaction(Transaction tx)` - create a new transaction. Allowed if and only if all of these are true:
  - The caller has the `SCOPE_transaction.create` scope.
  - The caller is either a teller OR the owner of the account referenced by `tx.accountId()`.
  - **Auditors are explicitly forbidden** from creating transactions. The auditor's scope set does not include `transaction.create`, so the scope check alone catches this, but make sure your tests verify it.

- `findByAccountId(String accountId)` - read all transactions for a given account. Allowed if all of these are true:
  - The caller has the `SCOPE_transaction.read` scope.
  - The caller is a teller, an auditor, OR the owner of the account.

Reuse the `AccountOwnership` helper bean you built in Exercise 4 to encode the ownership check.

**Tests to write:**

- Owner posts a transaction to their own account (succeeds).
- Owner posts a transaction to someone else's account (denied).
- Teller posts a transaction to any account (succeeds).
- Auditor attempts to post a transaction (denied because they lack the scope).
- Auditor reads transactions for any account (succeeds).
- Account holder reads transactions for their own account (succeeds).
- Account holder reads transactions for someone else's account (denied).

**Things to think about:**

- The `postTransaction` rule has two branches in the `or` clause. Is there a case where adding a third branch (say, a `SUPERVISOR` role) would be cleaner as a separate `@PreAuthorize` on a different method that internally calls `postTransaction`?
- If a teller posts a transaction on behalf of an account holder, the audit log should probably record both: the teller did it, but it was for the holder's account. How would you record both identities in the `AuditService` from Exercise 3?
- Auditors have `transaction.read` but not `transaction.create`. What if a stakeholder later asks for an "auditor with limited write access" role? Where would that complication land in your design - new role, new scope, both?

---

## Reference Solutions

Reference implementations for both extensions are in `Lab 2-2 Extension Solutions.md`.
