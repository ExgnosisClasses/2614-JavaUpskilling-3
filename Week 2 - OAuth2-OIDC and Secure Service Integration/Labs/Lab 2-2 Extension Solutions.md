# Lab 2-2 Extension: Reference Solutions

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 3 - OAuth2 / OIDC Foundations and Spring Security

This file contains reference solutions for the optional extension exercises in `Lab_2-2_Extension.md`. As with the main `Lab_2-2_Solutions.md`, the code shown here is one correct answer; alternatives exist and are noted where relevant.

**How to use this file:**
- Attempt the extensions before consulting this file.
- Each solution includes explanatory notes about why the design choices were made, not just the code itself.
- The extensions are optional and ungraded; these solutions are for self-study, not for instructor verification.

---

## Extension 1: JSON Error Responses

The two handlers are small and self-contained. Each one writes a JSON body and sets the appropriate HTTP status. The wiring into `SecurityConfig` is a single `.exceptionHandling(...)` call.

### `JsonAuthenticationEntryPoint.java` (in the `config` package)

```java
package com.example.bankapi.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Map;

@Component
public class JsonAuthenticationEntryPoint implements AuthenticationEntryPoint {
    private final ObjectMapper mapper = new ObjectMapper();

    @Override
    public void commence(HttpServletRequest request,
                         HttpServletResponse response,
                         AuthenticationException authException) throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        mapper.writeValue(response.getOutputStream(), Map.of(
                "error", "authentication_required",
                "message", "A valid Bearer token is required"
        ));
    }
}
```

### `JsonAccessDeniedHandler.java`

```java
package com.example.bankapi.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.Map;

@Component
public class JsonAccessDeniedHandler implements AccessDeniedHandler {
    private final ObjectMapper mapper = new ObjectMapper();

    @Override
    public void handle(HttpServletRequest request,
                       HttpServletResponse response,
                       AccessDeniedException accessDeniedException) throws IOException {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        mapper.writeValue(response.getOutputStream(), Map.of(
                "error", "access_denied",
                "message", "Your token does not include the required scope or role"
        ));
    }
}
```

### Wire into `SecurityConfig`

```java
@Bean
public SecurityFilterChain securityFilterChain(
        HttpSecurity http,
        JsonAuthenticationEntryPoint entryPoint,
        JsonAccessDeniedHandler accessDeniedHandler) throws Exception {

    http
        // ... existing rules unchanged ...
        .exceptionHandling(ex -> ex
                .authenticationEntryPoint(entryPoint)
                .accessDeniedHandler(accessDeniedHandler)
        );

    return http.build();
}
```

### Notes on the design

- Spring auto-wires `JsonAuthenticationEntryPoint` and `JsonAccessDeniedHandler` into the `securityFilterChain` method as constructor-style parameters because both are `@Component`s. You could also inject them via `@Bean` arguments or build them inline; the result is the same.
- The `ObjectMapper` is instantiated per-handler. For a lab this is fine. In a larger application you would inject the Spring-managed `ObjectMapper` bean (the one Spring Boot configures by default with the modules you've added) for consistency with the rest of the application's JSON handling.
- The reflection prompts in the extension file ask about adding `timestamp` and `path` fields, distinguishing token-expired from token-invalid, etc. These are good production hardening steps but they are not required for the basic extension to work.

### Things-to-think-about answers

- **Adding `timestamp` and `path`:** include them in the `Map.of(...)` body. `path` comes from `request.getRequestURI()`; `timestamp` from `Instant.now().toString()`. Be careful with `Map.of` and null values - it rejects them, so any optional field needs a non-null default or a `HashMap`.

- **Sharing an `ObjectMapper`:** the Spring Boot auto-configured bean is already thread-safe and is preconfigured with the Jackson modules your application has on the classpath (date handling, Java 8 types, etc.). For consistency across your application's JSON serialization, inject that bean rather than constructing a fresh one. The trade-off is a tiny dependency cost (the handlers now require the application context to be present, which they already do as components anyway).

- **Distinguishing token-expired from token-invalid:** the `AuthenticationException` passed to `commence(...)` is often a `BearerTokenAuthenticationException` (or wraps an `OAuth2AuthenticationException`). Its `getError()` method returns a `BearerTokenError` whose `errorCode` is `"invalid_token"` and whose `description` may say "Jwt expired at ..." vs "An error occurred while attempting to decode the Jwt." You can inspect this and pick a more specific error string. There is no clean Spring API that handed you a `TokenExpiredException` directly; you parse the description string or check the underlying cause chain. This is a long-running pain point in Spring Security and worth understanding before you build error-handling around it.

---

## Extension 2: TransactionService with Ownership-Aware Method Security

The service uses the same patterns as `AccountService`: `@PreAuthorize` with scope, role, and ownership checks, with the ownership helper reused from Exercise 4.

### `TransactionService.java` (in the `service` package)

```java
package com.example.bankapi.service;

import com.example.bankapi.model.Transaction;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

@Service
public class TransactionService {

    private final List<Transaction> store = new CopyOnWriteArrayList<>();

    @PreAuthorize(
        "hasAuthority('SCOPE_transaction.create') "
        + "and (hasRole('TELLER') "
        + "     or @accountOwnership.isOwner(#tx.accountId(), authentication))"
    )
    public Transaction postTransaction(Transaction tx) {
        store.add(tx);
        return tx;
    }

    @PreAuthorize(
        "hasAuthority('SCOPE_transaction.read') "
        + "and (hasRole('TELLER') or hasRole('AUDITOR') "
        + "     or @accountOwnership.isOwner(#accountId, authentication))"
    )
    public List<Transaction> findByAccountId(String accountId) {
        return store.stream()
                .filter(t -> t.accountId().equals(accountId))
                .toList();
    }
}
```

### Tests

`TransactionServiceSecurityTest.java` (in `src/test/java/com/example/bankapi/service`):

```java
package com.example.bankapi.service;

import com.example.bankapi.model.Transaction;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.security.test.context.support.WithAnonymousUser;

import java.math.BigDecimal;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class TransactionServiceSecurityTest {

    @Autowired private TransactionService transactionService;

    // Required because Exercise 5 adds DownstreamAccountService which depends
    // on a WebClient bean that needs OAuth2 client configuration. The mock
    // satisfies the dependency without needing the real WebClient.
    @MockBean private DownstreamAccountService downstreamAccountService;

    // --- postTransaction tests ---

    @Test
    @WithMockUser(username = "C001",
                  authorities = {"SCOPE_transaction.create", "ROLE_ACCOUNT_HOLDER"})
    void ownerCanPostToOwnAccount() {
        // C001 (alice) owns A001
        var tx = new Transaction("T001", "A001", "DEPOSIT",
                new BigDecimal("100.00"), Instant.now());
        var result = transactionService.postTransaction(tx);
        assertThat(result).isNotNull();
        assertThat(result.id()).isEqualTo("T001");
    }

    @Test
    @WithMockUser(username = "C001",
                  authorities = {"SCOPE_transaction.create", "ROLE_ACCOUNT_HOLDER"})
    void ownerCannotPostToSomeoneElsesAccount() {
        // C001 trying to post to A003 (owned by C002, bob)
        var tx = new Transaction("T002", "A003", "DEPOSIT",
                new BigDecimal("100.00"), Instant.now());
        assertThatThrownBy(() -> transactionService.postTransaction(tx))
                .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    @WithMockUser(username = "EM01",
                  authorities = {"SCOPE_transaction.create", "ROLE_TELLER"})
    void tellerCanPostToAnyAccount() {
        // Teller can post to A003 even though they don't own it
        var tx = new Transaction("T003", "A003", "DEPOSIT",
                new BigDecimal("100.00"), Instant.now());
        var result = transactionService.postTransaction(tx);
        assertThat(result).isNotNull();
    }

    @Test
    @WithMockUser(username = "AUD01",
                  authorities = {"SCOPE_transaction.read", "ROLE_AUDITOR"})
    void auditorCannotPostAnyTransaction() {
        // Auditor has only transaction.read, not transaction.create.
        // The scope check denies them before role/ownership are even considered.
        var tx = new Transaction("T004", "A001", "DEPOSIT",
                new BigDecimal("100.00"), Instant.now());
        assertThatThrownBy(() -> transactionService.postTransaction(tx))
                .isInstanceOf(AccessDeniedException.class);
    }

    // --- findByAccountId tests ---

    @Test
    @WithMockUser(username = "C001",
                  authorities = {"SCOPE_transaction.read", "ROLE_ACCOUNT_HOLDER"})
    void accountHolderCanReadOwnAccountTransactions() {
        // C001 reading transactions for A001 (their own account)
        var result = transactionService.findByAccountId("A001");
        assertThat(result).isNotNull();
        // Empty is fine; we're testing the auth, not the data
    }

    @Test
    @WithMockUser(username = "C001",
                  authorities = {"SCOPE_transaction.read", "ROLE_ACCOUNT_HOLDER"})
    void accountHolderCannotReadOtherAccountTransactions() {
        // C001 trying to read transactions for A003 (bob's account)
        assertThatThrownBy(() -> transactionService.findByAccountId("A003"))
                .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    @WithMockUser(username = "AUD01",
                  authorities = {"SCOPE_transaction.read", "ROLE_AUDITOR"})
    void auditorCanReadAnyAccountTransactions() {
        // Auditor reads any account's transactions; role check carries them through
        var result = transactionService.findByAccountId("A003");
        assertThat(result).isNotNull();
    }

    @Test
    @WithMockUser(username = "EM01",
                  authorities = {"SCOPE_transaction.read", "ROLE_TELLER"})
    void tellerCanReadAnyAccountTransactions() {
        var result = transactionService.findByAccountId("A005");
        assertThat(result).isNotNull();
    }
}
```

### Notes on the design

The auditor case is the most pedagogically interesting test in this set. The deny is not because of the role; it's because the scope is missing. If the auditor's scope set ever included `transaction.create`, the role check `hasRole('TELLER')` would carry them through the second branch of the `or` clause - which would silently authorize the action. Roles and scopes catch different misconfigurations:

- The **scope check** catches "this token was not requested with enough permissions" (a token-level concern that can vary even for the same user across different sessions, applications, or device contexts).
- The **role check** catches "this user is not in a position to do this regardless of token" (a user-level concern that follows the user across all their tokens).

Both checks together mean: this token must have been issued with the create scope (a token concern) AND the user behind the token must be the right kind of actor (a user concern). Missing either fails the authorization, which is the right behavior.

### Things-to-think-about answers

- **`SUPERVISOR` role as a third branch vs a separate method:** if the supervisor role does the same operation under the same conditions as a teller does, just add `or hasRole('SUPERVISOR')` to the existing `@PreAuthorize`. If the supervisor needs a *different* permission set (say, they can post but only after a manager-approval workflow), put it on a separate method - `postSupervisorTransaction(...)` - with its own `@PreAuthorize`. The boundary is whether the authorization rule is logically the same or merely numerically similar.

- **Recording both teller and account-holder identities in the audit log:** the audit log currently records `authentication.getName()`, which is the actor. To also record the affected account holder, pass it explicitly: `auditService.logEvent("POST_TRANSACTION", tx.accountId() + " (holder=" + lookupHolder(tx.accountId()) + ")")`. Or extend `AuditService` to accept a third parameter for the holder. Either way, the audit log captures the principal whose token authenticated the request AND the customer whose data was affected - two different facts, both worth logging.

- **"Auditor with limited write access":** this is a sign the role/scope distinction is being asked to express something a single dimension cannot. Options: (a) a new role like `SENIOR_AUDITOR` that adds the missing scopes; (b) a new scope like `audit.adjust` that only this role can request; (c) refactor toward a permission-per-action model where roles become collections of permissions. In real banking systems the answer is usually (c), with roles defined in an external policy store rather than hardcoded. For the lab, (a) is the simplest extension and the right entry point to the design conversation.

---

*End of Lab 2-2 Extension Reference Solutions*
