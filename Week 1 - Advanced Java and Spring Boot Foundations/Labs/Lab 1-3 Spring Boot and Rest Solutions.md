# Lab 1-3: Spring Boot Architecture and REST API Design
## Reference Solutions

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 2 - Spring Boot Architecture & REST API Design
> **Companion to:** `Lab_1-3_Spring_Boot_and_REST.md` (banking domain)

---

## How to Use This Solutions File

This file contains the completed code for every `TODO` marker in the lab, plus the answers to the reasoning tasks (idempotency analysis, version-increment decision, checkpoints). Use it to verify your own work, not as a copy-paste source.

Each section below is mapped to the corresponding exercise and task in the lab. The final section (after Exercise 5) lays out the complete final project structure with every file in its final, fully-integrated state, useful as a reference once you have finished all five exercises and want to confirm your project matches.

---

## Project Structure (final)

```
bank/
├── pom.xml
├── requests.http
├── VERSION_NOTES.md
└── src/main/
    ├── java/com/example/bank/
    │   ├── BankApplication.java
    │   ├── config/
    │   │   └── BankProperties.java
    │   ├── controller/
    │   │   ├── AccountController.java
    │   │   ├── AccountControllerV2.java
    │   │   ├── CustomerController.java
    │   │   ├── InfoController.java
    │   │   └── TransactionController.java
    │   ├── exception/
    │   │   ├── AccountNotFoundException.java
    │   │   ├── ApiError.java
    │   │   ├── BusinessRuleException.java
    │   │   ├── GlobalExceptionHandler.java
    │   │   └── ResourceNotFoundException.java
    │   ├── model/
    │   │   ├── Account.java
    │   │   ├── AccountStatus.java
    │   │   ├── AccountType.java
    │   │   ├── AccountV2.java
    │   │   ├── CreditTransaction.java
    │   │   ├── Customer.java
    │   │   ├── DebitTransaction.java
    │   │   ├── Transaction.java
    │   │   └── TransactionType.java
    │   └── service/
    │       ├── AccountService.java
    │       ├── CustomerService.java
    │       └── TransactionService.java
    └── resources/
        ├── application.yml
        ├── application-dev.yml
        └── application-prod.yml
```

---

## Exercise 1: The Layered Architecture in Practice

### Task 1.1: The Domain Model

No TODOs in this task. All four model files (`AccountType`, `AccountStatus`, `Customer`, `Account`) and the three transaction files (`Transaction` interface, `CreditTransaction`, `DebitTransaction`) are complete as shown in the lab.

### Task 1.2: `CustomerService.java` (TODO 1)

```java
package com.example.bank.service;

import com.example.bank.model.Customer;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class CustomerService {

    private final Map<String, Customer> store = new ConcurrentHashMap<>();

    public CustomerService() {
        store.put("C001", new Customer("C001", "Alice Nguyen",
                List.of("ACC-1001", "ACC-1002")));
        store.put("C002", new Customer("C002", "Bob Patel",
                List.of("ACC-1003")));
        store.put("C003", new Customer("C003", "Carla Romero",
                List.of("ACC-1004", "ACC-1005")));
    }

    // --- TODO 1: return all customers, defensive copy ---
    public List<Customer> findAll() {
        return List.copyOf(store.values());
    }

    public Optional<Customer> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }
}
```

`List.copyOf` produces an immutable snapshot of the values at call time. Callers can't add to or remove from it, and any later changes inside the store aren't visible to the copy. For a read-only API this is the safer default than `new ArrayList<>(...)`.

**Note:** In Exercise 4 (Task 4.4) `findById` is replaced with an exception-throwing version. The final form is shown at the end of this document.

### Task 1.2: `AccountService.java` (TODO 2)

```java
package com.example.bank.service;

import com.example.bank.model.Account;
import com.example.bank.model.AccountStatus;
import com.example.bank.model.AccountType;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class AccountService {

    private final Map<String, Account> store = new ConcurrentHashMap<>();

    public AccountService() {
        save(new Account("ACC-1001", "C001", AccountType.CHECKING,
                AccountStatus.OPEN, new BigDecimal("2500.00")));
        save(new Account("ACC-1002", "C001", AccountType.SAVINGS,
                AccountStatus.OPEN, new BigDecimal("15000.00")));
        save(new Account("ACC-1003", "C002", AccountType.CHECKING,
                AccountStatus.OPEN, new BigDecimal("780.50")));
        save(new Account("ACC-1004", "C003", AccountType.CHECKING,
                AccountStatus.OPEN, new BigDecimal("3200.00")));
        save(new Account("ACC-1005", "C003", AccountType.SAVINGS,
                AccountStatus.CLOSED, new BigDecimal("0.00")));
    }

    public List<Account> findAll() {
        return List.copyOf(store.values());
    }

    public Optional<Account> findByAccountNumber(String accountNumber) {
        return Optional.ofNullable(store.get(accountNumber));
    }

    Account save(Account account) {
        store.put(account.accountNumber(), account);
        return account;
    }

    // --- TODO 2: rebuild the immutable record with a new balance ---
    public Optional<Account> updateBalance(String accountNumber, BigDecimal newBalance) {
        Account existing = store.get(accountNumber);
        if (existing == null) {
            return Optional.empty();
        }
        Account updated = new Account(
                existing.accountNumber(),
                existing.customerId(),
                existing.type(),
                existing.status(),
                newBalance
        );
        store.put(accountNumber, updated);
        return Optional.of(updated);
    }
}
```

The "update" is really a replacement: build a new `Account` value with every field copied except `balance`, then put it in the map. From the caller's point of view the account's balance changed; internally one immutable snapshot replaced another. This is the canonical Java-21 idiom for record updates (and is what languages with built-in `with` expressions do under the hood).

### Task 1.3: `CustomerController.java` (TODO 3)

```java
package com.example.bank.controller;

import com.example.bank.model.Customer;
import com.example.bank.service.CustomerService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/customers")
public class CustomerController {

    private final CustomerService customerService;

    public CustomerController(CustomerService customerService) {
        this.customerService = customerService;
    }

    @GetMapping
    public List<Customer> getAll() {
        return customerService.findAll();
    }

    // --- TODO 3: Optional map/orElse pattern ---
    @GetMapping("/{id}")
    public ResponseEntity<Customer> getById(@PathVariable String id) {
        return customerService.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}
```

### Task 1.3: `AccountController.java` (TODO 4)

```java
package com.example.bank.controller;

import com.example.bank.model.Account;
import com.example.bank.service.AccountService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/accounts")
public class AccountController {

    private final AccountService accountService;

    public AccountController(AccountService accountService) {
        this.accountService = accountService;
    }

    @GetMapping
    public List<Account> getAll() {
        return accountService.findAll();
    }

    // --- TODO 4: same map/orElse pattern ---
    @GetMapping("/{accountNumber}")
    public ResponseEntity<Account> getByAccountNumber(@PathVariable String accountNumber) {
        return accountService.findByAccountNumber(accountNumber)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}
```

### Exercise 1 Checkpoint Answers

1. **Layering enables independent evolution.** If the service depends on `org.springframework.web` it cannot be called from a scheduled job, a Kafka consumer, or a CLI; it is coupled to HTTP forever. If the controller knows about `java.sql` it cannot evolve its persistence layer (in-memory → Oracle, planned for the database module) without touching HTTP code. The boundary makes each layer independently replaceable. In the capstone, this same separation is what will let you swap the `ConcurrentHashMap` for Spring Data JPA without changing a single controller method.

2. **Component scanning at startup.** `@Component`, `@Service`, `@RestController` are all stereotypes detected by Spring's component scan. Spring instantiates each one as a bean in the application context and wires its dependencies via constructor injection. The stereotype names are documentation because they tell the next developer (and tools) which layer a class belongs to. Functionally `@Service` and `@RestController` could both be `@Component`, but they would communicate nothing.

3. **Floating-point representational error.** `0.1 + 0.2 != 0.3` in `double` because binary floating-point cannot exactly represent most decimal fractions. After many small transactions an account's `double` balance drifts by fractions of a cent; which, over millions of accounts, becomes a regulatory and audit problem. `BigDecimal` represents decimals exactly and is the only correct choice for money. This is a non-negotiable industry standard, not a style preference.

4. **The sealed restriction.** Without `sealed`, any class anywhere in the codebase (or any dependency) could `implements Transaction` and the compiler would have no way to know. With `sealed ... permits CreditTransaction, DebitTransaction`, only those two types may implement the interface, and the compiler enforces it. This is why a `switch` over a sealed type can be **exhaustive at compile time** because the compiler knows every case. In Exercise 3 you will write a switch on `TransactionType`; if a future requirement adds `FeeTransaction` to the sealed hierarchy, every existing switch becomes a compile error pointing you to every place that needs updating. That is an architectural benefit, not a syntactic one.

### Exercise 1 Extension: Customer accounts endpoint

Inject `AccountService` into `CustomerController` and add a method that returns the full account objects for a customer:

```java
private final CustomerService customerService;
private final AccountService accountService;

public CustomerController(CustomerService customerService,
                          AccountService accountService) {
    this.customerService = customerService;
    this.accountService = accountService;
}

@GetMapping("/{id}/accounts")
public ResponseEntity<List<Account>> getAccounts(@PathVariable String id) {
    return customerService.findById(id)
            .map(customer -> customer.accountNumbers().stream()
                    .map(accountService::findByAccountNumber)
                    .flatMap(Optional::stream)
                    .toList())
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
}
```

`flatMap(Optional::stream)` is the idiomatic way to drop empty `Optional`s from a stream: it expands to an empty stream when the optional is empty and a single-element stream when it is present.

---

## Exercise 2: Configuration, Profiles, and the Environment Abstraction

### Task 2.1: `application.yml`

```yaml
spring:
  application:
    name: bank-service

server:
  port: 8080

bank:
  transaction-limit: 10000
  daily-limit: 25000
  environment-label: local
```

### Task 2.2: Profile overlays

`application-dev.yml`:

```yaml
bank:
  environment-label: development
  transaction-limit: 500
```

`application-prod.yml`:

```yaml
bank:
  environment-label: production
  daily-limit: 50000
```

### Task 2.3: `BankProperties.java` (TODO 5)

```java
package com.example.bank.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.math.BigDecimal;

@ConfigurationProperties(prefix = "bank")
public class BankProperties {

    private BigDecimal transactionLimit = new BigDecimal("10000");
    private BigDecimal dailyLimit = new BigDecimal("25000");
    private String environmentLabel = "unknown";

    // --- TODO 5: getters and setters ---
    public BigDecimal getTransactionLimit() { return transactionLimit; }
    public void setTransactionLimit(BigDecimal transactionLimit) { this.transactionLimit = transactionLimit; }

    public BigDecimal getDailyLimit() { return dailyLimit; }
    public void setDailyLimit(BigDecimal dailyLimit) { this.dailyLimit = dailyLimit; }

    public String getEnvironmentLabel() { return environmentLabel; }
    public void setEnvironmentLabel(String environmentLabel) { this.environmentLabel = environmentLabel; }
}
```

`BankProperties` cannot be a record. Spring Boot's `@ConfigurationProperties` binding (in its default form) needs a no-arg constructor plus setters to populate fields one at a time as it discovers properties. Records have only the canonical constructor and no setters, so they need the constructor-binding variant which is out of scope for this lab.

### Task 2.4: `BankApplication.java` and `InfoController.java` (TODO 6)

`BankApplication.java` is complete as shown in the lab. The `InfoController` constructor:

```java
package com.example.bank.controller;

import com.example.bank.config.BankProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/info")
public class InfoController {

    private final BankProperties properties;

    // --- TODO 6: constructor injection ---
    public InfoController(BankProperties properties) {
        this.properties = properties;
    }

    @GetMapping
    public Map<String, Object> info() {
        return Map.of(
                "environment", properties.getEnvironmentLabel(),
                "transactionLimit", properties.getTransactionLimit(),
                "dailyLimit", properties.getDailyLimit()
        );
    }
}
```

### Exercise 2 Checkpoint Answers

1. **Layered overlay.** `dailyLimit` is not declared in `application-dev.yml`, so its value falls through to the base `application.yml` (`25000`). Profile files are overlays, not replacements, only the keys they declare override the base. This is why a profile file can be small: it states the differences, not the whole configuration.

2. **`@ConfigurationProperties` vs `@Value`.** With 15 related properties, `@Value` requires 15 field-level annotations scattered across however many classes use them, no compile-time validation, no IDE navigation between Java and YAML, no group-level relocation, and no easy way to test the configuration in isolation. `@ConfigurationProperties` binds the whole group to one typed class with one annotation, gives autocompletion in YAML (via the Spring Boot config processor), and is trivially testable as a POJO.

3. **`SPRING_PROFILES_ACTIVE`.** Set the environment variable `SPRING_PROFILES_ACTIVE=prod` (or pass `--spring.profiles.active=prod` on the command line). The Spring property is `spring.profiles.active`. The JAR contents do not change between environments, only the environment does. This is the entire point of profiles: build once, deploy many.

4. **Default never used here.** The default `"unknown"` is only used when no `bank.environment-label` property is not defined anywhere including; the base YAML, a profile, an environment variable, or a command-line argument. In this project, `application.yml` always defines it, so the default never fires. It exists as a safety net for misconfigured deployments where the base YAML is somehow missing.

---

## Exercise 3: Resource-Oriented URL Design and HTTP Method Semantics

### Task 3.1: `TransactionService.java` (TODO 7, TODO 8)

```java
package com.example.bank.service;

import com.example.bank.exception.AccountNotFoundException;
import com.example.bank.exception.BusinessRuleException;
import com.example.bank.model.*;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Service
public class TransactionService {

    private final Map<String, Transaction> store = new ConcurrentHashMap<>();
    private final AccountService accountService;

    public TransactionService(AccountService accountService) {
        this.accountService = accountService;
    }

    public List<Transaction> findAll() {
        return List.copyOf(store.values());
    }

    public List<Transaction> findByAccountNumber(String accountNumber) {
        return store.values().stream()
                .filter(t -> t.accountNumber().equals(accountNumber))
                .collect(Collectors.toList());
    }

    public Transaction process(String accountNumber, TransactionType type, BigDecimal amount) {

        // Before Exercise 4 this used Optional.orElseThrow.
        // After Exercise 4 AccountService.findByAccountNumber throws directly.
        // Both versions of the line are shown. Use whichever matches your stage.
        // Transitional (Exercise 3):
        //   Account account = accountService.findByAccountNumber(accountNumber)
        //           .orElseThrow(() -> new AccountNotFoundException(accountNumber));
        // Final (after Exercise 4):
        Account account = accountService.findByAccountNumber(accountNumber);

        if (account.status() != AccountStatus.OPEN) {
            throw new BusinessRuleException("ACCOUNT_NOT_OPEN",
                    "Cannot post a transaction to a closed account: " + accountNumber);
        }
        if (amount.signum() <= 0) {
            throw new BusinessRuleException("INVALID_AMOUNT",
                    "Transaction amount must be greater than zero");
        }

        // --- TODO 7: compute new balance, reject overdrafts ---
        // Switch *expression* (note the `=` and the trailing semicolon).
        // The compiler enforces exhaustiveness over the enum, which guarantees
        // newBalance is definitely assigned. A statement-style switch would
        // produce a "variable might not have been initialized" compile error.
        BigDecimal newBalance = switch (type) {
            case CREDIT -> account.balance().add(amount);
            case DEBIT -> {
                if (account.balance().compareTo(amount) < 0) {
                    throw new BusinessRuleException("INSUFFICIENT_FUNDS",
                            "Account " + accountNumber + " has insufficient funds for debit of " + amount);
                }
                yield account.balance().subtract(amount);
            }
        };

        accountService.updateBalance(accountNumber, newBalance);

        // --- TODO 8: construct the right Transaction record ---
        String txnId = "TXN-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        Transaction txn = switch (type) {
            case CREDIT -> new CreditTransaction(txnId, accountNumber, amount, Instant.now());
            case DEBIT  -> new DebitTransaction(txnId, accountNumber, amount, Instant.now());
        };

        store.put(txn.transactionId(), txn);
        return txn;
    }
}
```

Both arms use **switch expressions**, not statement-style switches. This matters for more than style: a switch expression over an enum is exhaustive at compile time, which gives `newBalance` definite assignment. A statement-style switch would compile-error with `variable newBalance might not have been initialized` because the definite-assignment analyzer doesn't prove that every arm of a statement-switch assigns the variable.

It is also the architectural payoff of the sealed type. If a `FeeTransaction` is added to either the `TransactionType` enum or the sealed `Transaction` hierarchy, both switches become compile errors that point directly at the lines that need updating. The build fails until every case is handled. With a non-exhaustive switch, the new case would silently fall through at runtime.

`BigDecimal.compareTo(other) < 0` is the correct comparison. Never use `equals` for `BigDecimal` value comparisons (`new BigDecimal("1.0").equals(new BigDecimal("1.00"))` is `false` because the scale differs), and never use `<` because `BigDecimal` is an object, not a primitive.

The `yield` keyword in the `DEBIT` arm produces a value from the enclosing block,  it is the switch-expression equivalent of `return` from a method. A `throw` in the same block is fine; control either `yield`s a value or throws, both of which satisfy the compiler.

### Task 3.2 – `TransactionController.java` (TODO 9)

```java
package com.example.bank.controller;

import com.example.bank.model.Transaction;
import com.example.bank.model.TransactionType;
import com.example.bank.service.TransactionService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.util.UriComponentsBuilder;

import java.math.BigDecimal;
import java.net.URI;
import java.util.List;

/*
 * Idempotency analysis (Task 3.4):
 *
 *  GET    /api/v1/transactions                         — IDEMPOTENT, SAFE.
 *  GET    /api/v1/accounts/{n}/transactions            — IDEMPOTENT, SAFE.
 *  GET    /api/v1/accounts/{n}                         — IDEMPOTENT, SAFE.
 *      Same request twice returns the same data; no server state changes.
 *      Safe to retry freely on network failure.
 *
 *  POST   /api/v1/accounts/{n}/transactions            — NOT IDEMPOTENT.
 *      Two identical POSTs create two distinct transactions with different
 *      IDs and apply the balance change twice. In banking terms: the customer
 *      is debited (or credited) twice. This is a money concern, not just a
 *      design concern.
 *
 *      Mitigation: the idempotency-key pattern. The client generates a unique
 *      key (typically a UUID) and sends it in an `Idempotency-Key` header.
 *      The server stores the result of the first successful request keyed by
 *      that header. If the same key arrives again (because the client timed
 *      out and retried), the server returns the cached response instead of
 *      processing a second transaction. This is the standard solution used
 *      by Stripe, Square, and most banking APIs.
 */
@RestController
public class TransactionController {

    private final TransactionService transactionService;

    public TransactionController(TransactionService transactionService) {
        this.transactionService = transactionService;
    }

    @GetMapping("/api/v1/transactions")
    public List<Transaction> getAll() {
        return transactionService.findAll();
    }

    @GetMapping("/api/v1/accounts/{accountNumber}/transactions")
    public List<Transaction> getByAccount(@PathVariable String accountNumber) {
        return transactionService.findByAccountNumber(accountNumber);
    }

    // --- TODO 9: process and respond with 201 + Location header ---
    @PostMapping("/api/v1/accounts/{accountNumber}/transactions")
    public ResponseEntity<Transaction> create(
            @PathVariable String accountNumber,
            @RequestBody TransactionRequest request,
            UriComponentsBuilder ucb) {

        Transaction saved = transactionService.process(
                accountNumber, request.type(), request.amount());

        URI location = ucb.path("/api/v1/transactions/{transactionId}")
                .buildAndExpand(saved.transactionId())
                .toUri();

        return ResponseEntity.created(location).body(saved);
    }

    public record TransactionRequest(TransactionType type, BigDecimal amount) {}
}
```

### Exercise 3 Checkpoint Answers

1. **Hierarchy communicates ownership.** `/accounts/{accountNumber}/transactions` tells readers, SDK generators, caches, and gateways that transactions are sub-resources owned by a specific account. A flat `/transactions` with the account in the body hides that relationship — the caching layer would see all transaction POSTs as targeting one endpoint and would lose per-account locality. The hierarchical form also makes the parent's existence a precondition: a 404 on the parent account is a natural response, surfaced by the URL itself.

2. **Single source of truth.** The path variable is authoritative because the URL identifies the resource. If the body also carried `accountNumber` and the two differed, you would have two contradictory statements of identity in one request — and an attacker could potentially debit one account by addressing another. Taking the account number from the URL only eliminates the ambiguity and the attack surface.

3. **Retry-safety in banking.** A `POST` retry after a network timeout can result in a duplicate debit or credit — the customer sees the same withdrawal posted twice on their statement. The standard mitigation is the **idempotency-key pattern**: the client generates a unique key per logical request (a UUID) and sends it in the `Idempotency-Key` header. The server stores the first successful response keyed by that header and returns the same response for any retry with the same key. This is what Stripe, Square, and major banking APIs use.

4. **Compile-time exhaustiveness.** Because `Transaction` is sealed and `TransactionType` is an enum, the switch expression in `process` is required by the compiler to cover every case. If `FeeTransaction` is added to the sealed hierarchy and a corresponding `FEE` enum constant is added to `TransactionType`, every existing switch becomes a compile error pointing you to the exact line that needs updating. You cannot ship code that silently ignores the new case — the build fails. With a non-sealed interface or string-based type, the compiler would have no way to know and the new case could quietly be dropped at runtime.

---

## Exercise 4: HTTP Status Code Discipline and the Error Contract

### Task 4.1: Exception classes

No TODOs — the three exception classes (`ResourceNotFoundException`, `AccountNotFoundException`, `BusinessRuleException`) are complete as shown in the lab.

### Task 4.2 – `ApiError.java` (TODO 10)

```java
package com.example.bank.exception;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;
import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiError {

    private final String status;
    private final String errorCode;
    private final String message;
    private final Instant timestamp;
    private final List<FieldError> fieldErrors;

    // --- TODO 10 ---
    public ApiError(String status, String errorCode, String message,
                    List<FieldError> fieldErrors) {
        this.status = status;
        this.errorCode = errorCode;
        this.message = message;
        this.timestamp = Instant.now();
        this.fieldErrors = fieldErrors;
    }

    public String getStatus() { return status; }
    public String getErrorCode() { return errorCode; }
    public String getMessage() { return message; }
    public Instant getTimestamp() { return timestamp; }
    public List<FieldError> getFieldErrors() { return fieldErrors; }

    public record FieldError(String field, String message) {}
}
```

### Task 4.3 – `GlobalExceptionHandler.java` (TODO 11, 12, 13)

```java
package com.example.bank.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.List;
import java.util.stream.Collectors;

@RestControllerAdvice
public class GlobalExceptionHandler {

    // --- TODO 11 ---
    // Handles ResourceNotFoundException AND AccountNotFoundException polymorphically
    // (because AccountNotFoundException extends ResourceNotFoundException).
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiError> handleNotFound(ResourceNotFoundException ex) {
        ApiError error = new ApiError(
                "404 NOT_FOUND",
                ex.getResourceType().toUpperCase() + "_NOT_FOUND",
                ex.getMessage(),
                null
        );
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    // --- TODO 12 ---
    @ExceptionHandler(BusinessRuleException.class)
    public ResponseEntity<ApiError> handleBusinessRule(BusinessRuleException ex) {
        ApiError error = new ApiError(
                "422 UNPROCESSABLE_ENTITY",
                ex.getErrorCode(),
                ex.getMessage(),
                null
        );
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body(error);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiError> handleValidation(MethodArgumentNotValidException ex) {
        List<ApiError.FieldError> fieldErrors = ex.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(fe -> new ApiError.FieldError(fe.getField(), fe.getDefaultMessage()))
                .collect(Collectors.toList());

        ApiError error = new ApiError(
                "400 BAD_REQUEST",
                "VALIDATION_FAILURE",
                "One or more fields failed validation",
                fieldErrors
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
    }

    // --- TODO 13 ---
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> handleUnexpected(Exception ex) {
        System.err.println("Unhandled exception: " + ex.getMessage());
        ApiError error = new ApiError(
                "500 INTERNAL_SERVER_ERROR",
                "INTERNAL_ERROR",
                "An unexpected error occurred. Please contact support.",
                null
        );
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
    }
}
```

### Task 4.4 – Service refactor (TODO 14, TODO 15)

`CustomerService.findById` (TODO 14):

```java
public Customer findById(String id) {
    Customer customer = store.get(id);
    if (customer == null) {
        throw new ResourceNotFoundException("Customer", id);
    }
    return customer;
}
```

`AccountService.findByAccountNumber` (TODO 15):

```java
public Account findByAccountNumber(String accountNumber) {
    Account account = store.get(accountNumber);
    if (account == null) {
        throw new AccountNotFoundException(accountNumber);
    }
    return account;
}
```

The corresponding controller methods then collapse to one-liners. See the consolidated final files at the end.

In `TransactionService.process`, the lookup line simplifies:

```java
// Before (transitional):
Account account = accountService.findByAccountNumber(accountNumber)
        .orElseThrow(() -> new AccountNotFoundException(accountNumber));

// After:
Account account = accountService.findByAccountNumber(accountNumber);
```

### Exercise 4 Checkpoint Answers

1. **Polymorphic dispatch on exception type.** `@ExceptionHandler(ResourceNotFoundException.class)` is matched not only by exact-type matches but also by subtypes. `AccountNotFoundException extends ResourceNotFoundException`, so when one is thrown, Spring walks the class hierarchy looking for a handler and finds `handleNotFound`. The `resourceType` field on the parent class is set to `"Account"` by the subclass constructor, so the resulting `errorCode` is `ACCOUNT_NOT_FOUND` is specific to the subclass, with no extra handler needed. This is the same dispatch rule as Java's `catch` blocks.

2. **Information disclosure in banking.** The raw exception message can leak class names, SQL fragments, file paths, stack frames, internal account IDs, or third-party library internals. In a banking context, a particularly bad leak would be database schema names or column hints (`ORA-12899: value too large for column ACCT_INTERNAL_ID`) which give an attacker a map of the data model. The generic message keeps the wire payload safe; the real exception is logged server-side where only operators see it. PII, customer identifiers, internal account numbers, and any stack details belong in logs, never in error responses.

3. **400 vs 422.** `400 Bad Request` means the request could not be parsed or violated the protocol because malformed JSON, missing required field, wrong type, or other JSON error. The client should fix its request format. `422 Unprocessable Entity` means the request was well-formed and understood, but the *content* violates a business rule. For the bank: `{ "type": "DEBIT", "amount": "abc" }` is `400` (amount is not a number); `{ "type": "DEBIT", "amount": 999999 }` against an account with $500 is `422` (the bank understood you and refused). Clients reformatting their JSON cannot fix a 422; they have to change the data or accept the refusal.

4. **Machine-readable codes vs human-readable messages.** `message` is for humans reading logs and developer-tool consoles. `errorCode` is a stable identifier client code branches on. A mobile-banking app receiving `INSUFFICIENT_FUNDS` can show a localized "You don't have enough money in this account" screen and offer to transfer from savings. Receiving `ACCOUNT_NOT_OPEN` shows a different screen ("This account has been closed. Please contact support."). Both have the same status (422), so the status alone is insufficient. The English message can be reworded for clarity without breaking clients; the code is part of the contract and cannot be changed without a version bump (see Exercise 5).

---

## Exercise 5 – API Versioning Strategy

### Task 5.1 – `AccountControllerV2.java` (TODO 16, TODO 17)

```java
package com.example.bank.controller;

import com.example.bank.model.AccountV2;
import com.example.bank.service.AccountService;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v2/accounts")
public class AccountControllerV2 {

    private final AccountService accountService;

    public AccountControllerV2(AccountService accountService) {
        this.accountService = accountService;
    }

    // --- TODO 16 ---
    @GetMapping
    public List<AccountV2> getAll() {
        return accountService.findAll().stream()
                .map(a -> new AccountV2(
                        a.accountNumber(),
                        a.customerId(),
                        a.type(),
                        a.status(),
                        a.balance(),
                        a.balance(),     // availableBalance — same as balance for the lab
                        "USD"
                ))
                .collect(Collectors.toList());
    }

    // --- TODO 17 ---
    @GetMapping("/{accountNumber}")
    public AccountV2 getByAccountNumber(@PathVariable String accountNumber) {
        var a = accountService.findByAccountNumber(accountNumber);
        return new AccountV2(
                a.accountNumber(),
                a.customerId(),
                a.type(),
                a.status(),
                a.balance(),
                a.balance(),
                "USD"
        );
    }
}
```

The mapping logic is duplicated across the two methods. In a production codebase you would extract it into a private `toV2(Account)` helper or a dedicated mapper bean. For the lab, the explicit duplication is left in place so the wire shape is obvious at the call site.

### Task 5.2 – Deprecation headers on v1 (TODO 18)

Add to `AccountController`:

```java
import jakarta.servlet.http.HttpServletResponse;

@ModelAttribute
public void addDeprecationHeaders(HttpServletResponse response) {
    response.setHeader("Deprecation", "true");
    response.setHeader("Sunset", "Sat, 01 Nov 2026 00:00:00 GMT");
    response.setHeader("Link", "</api/v2/accounts>; rel=\"successor-version\"");
}
```

### Task 5.4 – Version-increment decision table (`VERSION_NOTES.md`)

| Proposed change | Breaking? | Reasoning |
|---|---|---|
| Add an optional `nickname` field to v2 response | **No** | Adding a field is non-breaking *provided clients deserialize tolerantly* (ignore unknown fields). This is the requirement Jackson enforces by default. Clients that lock their deserializers turn this into a breaking change for themselves. |
| Remove the `currency` field from v2 response | **Yes — v3** | Removing a field breaks every client that reads it. Removal requires a new version. |
| Change `balance` from `BigDecimal` to `String` in v2 response | **Yes — v3** | Type changes are breaking. A client deserializing into a numeric field will fail or coerce incorrectly. Especially damaging for money fields where silent coercion can shift decimal places. |
| Make the `amount` field on the transaction POST required | **Yes — v3** | Tightening a precondition rejects requests that previously succeeded. Loosening preconditions is non-breaking; tightening them is not. |
| Add a new endpoint `GET /api/v2/accounts/{n}/statements` | **No** | New endpoints don't affect existing callers. Safe to add to v2. |
| Rename error code `INSUFFICIENT_FUNDS` to `BALANCE_TOO_LOW` | **Yes — v3** | Error codes are part of the contract. Mobile apps and partner integrations branch on them. Renaming silently routes every existing handler into the catch-all branch. The mobile-banking app that used to offer "Transfer from savings" on `INSUFFICIENT_FUNDS` now offers nothing. |
| Add a new `TransactionType.FEE` value that can appear in responses | **Yes — v3** | Adding an enum value to a response is breaking. Existing clients with exhaustive switches over the v2 enum will fail on the new value, and clients that map to their own enums will throw on deserialization. Adding the value to *requests* would be non-breaking (server accepts more); adding it to *responses* is breaking (clients receive more). |

### Exercise 5 Checkpoint Answers

1. **A v2 controller as a new class avoids version-branching.** A separate class means no method ever has to ask "which version am I serving?" The router answers that question once, at the URL level. An `if (version == 2)` branch inside a single controller couples the two versions' lifecycles, makes the v1 sunset risky (you can't delete the v2 branch without touching v1 code), and produces a class that grows quadratically as more versions accumulate. Independent classes can be deleted independently. When v1 is sunset, you delete `AccountController.java` and `Account.java`, and the build still passes.

2. **A `Sunset` commitment.** Setting `Sunset: Sat, 01 Nov 2026 00:00:00 GMT` is a public promise that v1 will remain functional until that date and that clients have until then to migrate. The team owes proactive communication (release notes, deprecation logs, deprecation-warning headers escalating in volume as the date approaches, direct outreach to known integrators). In a banking context specifically: mobile-app teams (so they can ship an update through the app stores, which themselves have multi-week review cycles), partner banks, ATM-controller vendors, internal reporting and reconciliation teams, and the compliance team (regulatory filings often reference specific API versions). The Sunset header is a contract; set it deliberately.

3. **Tolerant readers.** Adding a field is only non-breaking if clients deserialize tolerantly and ignore unknown fields rather than fail on them. Jackson does this by default (`FAIL_ON_UNKNOWN_PROPERTIES=false`). Well-written banking clients should be tolerant on read and strict on write (Postel's law). Clients that lock their deserializers turn every additive change into a breaking change for themselves; in a banking context where mobile apps may take weeks to update through app stores, this matters.

4. **Error contract is part of the API contract.** Client code branches on error codes to decide retry vs surface-to-user vs trigger fallback. A mobile-banking app that responds to `INSUFFICIENT_FUNDS` by offering a transfer-from-savings dialog will silently lose that capability if the code is renamed without a version bump — every error of that type now hits the generic catch-all branch. Error responses must be versioned with the same discipline as success responses.

---

## Final Consolidated Source Files

These are the **end-state** versions of every file after all five exercises are complete and integrated. If you finish the lab, your code should match these.

### `BankApplication.java`

```java
package com.example.bank;

import com.example.bank.config.BankProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(BankProperties.class)
public class BankApplication {
    public static void main(String[] args) {
        SpringApplication.run(BankApplication.class, args);
    }
}
```

### `config/BankProperties.java`

```java
package com.example.bank.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import java.math.BigDecimal;

@ConfigurationProperties(prefix = "bank")
public class BankProperties {

    private BigDecimal transactionLimit = new BigDecimal("10000");
    private BigDecimal dailyLimit = new BigDecimal("25000");
    private String environmentLabel = "unknown";

    public BigDecimal getTransactionLimit() { return transactionLimit; }
    public void setTransactionLimit(BigDecimal transactionLimit) { this.transactionLimit = transactionLimit; }

    public BigDecimal getDailyLimit() { return dailyLimit; }
    public void setDailyLimit(BigDecimal dailyLimit) { this.dailyLimit = dailyLimit; }

    public String getEnvironmentLabel() { return environmentLabel; }
    public void setEnvironmentLabel(String environmentLabel) { this.environmentLabel = environmentLabel; }
}
```

### `model/AccountType.java`

```java
package com.example.bank.model;

public enum AccountType {
    CHECKING, SAVINGS
}
```

### `model/AccountStatus.java`

```java
package com.example.bank.model;

public enum AccountStatus {
    OPEN, CLOSED
}
```

### `model/TransactionType.java`

```java
package com.example.bank.model;

public enum TransactionType {
    CREDIT, DEBIT
}
```

### `model/Customer.java`

```java
package com.example.bank.model;

import java.util.List;

public record Customer(
        String id,
        String name,
        List<String> accountNumbers
) {}
```

### `model/Account.java`

```java
package com.example.bank.model;

import java.math.BigDecimal;

public record Account(
        String accountNumber,
        String customerId,
        AccountType type,
        AccountStatus status,
        BigDecimal balance
) {}
```

### `model/AccountV2.java`

```java
package com.example.bank.model;

import java.math.BigDecimal;

public record AccountV2(
        String accountNumber,
        String customerId,
        AccountType accountType,
        AccountStatus status,
        BigDecimal balance,
        BigDecimal availableBalance,
        String currency
) {}
```

### `model/Transaction.java`

```java
package com.example.bank.model;

import java.math.BigDecimal;
import java.time.Instant;

public sealed interface Transaction
        permits CreditTransaction, DebitTransaction {
    String transactionId();
    String accountNumber();
    BigDecimal amount();
    Instant timestamp();
}
```

### `model/CreditTransaction.java`

```java
package com.example.bank.model;

import java.math.BigDecimal;
import java.time.Instant;

public record CreditTransaction(
        String transactionId,
        String accountNumber,
        BigDecimal amount,
        Instant timestamp
) implements Transaction {}
```

### `model/DebitTransaction.java`

```java
package com.example.bank.model;

import java.math.BigDecimal;
import java.time.Instant;

public record DebitTransaction(
        String transactionId,
        String accountNumber,
        BigDecimal amount,
        Instant timestamp
) implements Transaction {}
```

### `service/CustomerService.java` (final)

```java
package com.example.bank.service;

import com.example.bank.exception.ResourceNotFoundException;
import com.example.bank.model.Customer;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class CustomerService {

    private final Map<String, Customer> store = new ConcurrentHashMap<>();

    public CustomerService() {
        store.put("C001", new Customer("C001", "Alice Nguyen",
                List.of("ACC-1001", "ACC-1002")));
        store.put("C002", new Customer("C002", "Bob Patel",
                List.of("ACC-1003")));
        store.put("C003", new Customer("C003", "Carla Romero",
                List.of("ACC-1004", "ACC-1005")));
    }

    public List<Customer> findAll() {
        return List.copyOf(store.values());
    }

    // After Exercise 4: throws instead of returning Optional.
    public Customer findById(String id) {
        Customer customer = store.get(id);
        if (customer == null) {
            throw new ResourceNotFoundException("Customer", id);
        }
        return customer;
    }
}
```

### `service/AccountService.java` (final)

```java
package com.example.bank.service;

import com.example.bank.exception.AccountNotFoundException;
import com.example.bank.model.Account;
import com.example.bank.model.AccountStatus;
import com.example.bank.model.AccountType;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class AccountService {

    private final Map<String, Account> store = new ConcurrentHashMap<>();

    public AccountService() {
        save(new Account("ACC-1001", "C001", AccountType.CHECKING,
                AccountStatus.OPEN, new BigDecimal("2500.00")));
        save(new Account("ACC-1002", "C001", AccountType.SAVINGS,
                AccountStatus.OPEN, new BigDecimal("15000.00")));
        save(new Account("ACC-1003", "C002", AccountType.CHECKING,
                AccountStatus.OPEN, new BigDecimal("780.50")));
        save(new Account("ACC-1004", "C003", AccountType.CHECKING,
                AccountStatus.OPEN, new BigDecimal("3200.00")));
        save(new Account("ACC-1005", "C003", AccountType.SAVINGS,
                AccountStatus.CLOSED, new BigDecimal("0.00")));
    }

    public List<Account> findAll() {
        return List.copyOf(store.values());
    }

    // After Exercise 4: throws instead of returning Optional.
    public Account findByAccountNumber(String accountNumber) {
        Account account = store.get(accountNumber);
        if (account == null) {
            throw new AccountNotFoundException(accountNumber);
        }
        return account;
    }

    Account save(Account account) {
        store.put(account.accountNumber(), account);
        return account;
    }

    public Optional<Account> updateBalance(String accountNumber, BigDecimal newBalance) {
        Account existing = store.get(accountNumber);
        if (existing == null) {
            return Optional.empty();
        }
        Account updated = new Account(
                existing.accountNumber(),
                existing.customerId(),
                existing.type(),
                existing.status(),
                newBalance
        );
        store.put(accountNumber, updated);
        return Optional.of(updated);
    }
}
```

### `service/TransactionService.java` (final)

```java
package com.example.bank.service;

import com.example.bank.exception.BusinessRuleException;
import com.example.bank.model.*;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Service
public class TransactionService {

    private final Map<String, Transaction> store = new ConcurrentHashMap<>();
    private final AccountService accountService;

    public TransactionService(AccountService accountService) {
        this.accountService = accountService;
    }

    public List<Transaction> findAll() {
        return List.copyOf(store.values());
    }

    public List<Transaction> findByAccountNumber(String accountNumber) {
        return store.values().stream()
                .filter(t -> t.accountNumber().equals(accountNumber))
                .collect(Collectors.toList());
    }

    public Transaction process(String accountNumber, TransactionType type, BigDecimal amount) {

        Account account = accountService.findByAccountNumber(accountNumber);

        if (account.status() != AccountStatus.OPEN) {
            throw new BusinessRuleException("ACCOUNT_NOT_OPEN",
                    "Cannot post a transaction to a closed account: " + accountNumber);
        }
        if (amount == null || amount.signum() <= 0) {
            throw new BusinessRuleException("INVALID_AMOUNT",
                    "Transaction amount must be greater than zero");
        }

        BigDecimal newBalance = switch (type) {
            case CREDIT -> account.balance().add(amount);
            case DEBIT -> {
                if (account.balance().compareTo(amount) < 0) {
                    throw new BusinessRuleException("INSUFFICIENT_FUNDS",
                            "Account " + accountNumber + " has insufficient funds for debit of " + amount);
                }
                yield account.balance().subtract(amount);
            }
        };

        accountService.updateBalance(accountNumber, newBalance);

        String txnId = "TXN-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        Transaction txn = switch (type) {
            case CREDIT -> new CreditTransaction(txnId, accountNumber, amount, Instant.now());
            case DEBIT  -> new DebitTransaction(txnId, accountNumber, amount, Instant.now());
        };

        store.put(txn.transactionId(), txn);
        return txn;
    }
}
```

### `controller/CustomerController.java` (final)

```java
package com.example.bank.controller;

import com.example.bank.model.Customer;
import com.example.bank.service.CustomerService;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/customers")
public class CustomerController {

    private final CustomerService customerService;

    public CustomerController(CustomerService customerService) {
        this.customerService = customerService;
    }

    @GetMapping
    public List<Customer> getAll() {
        return customerService.findAll();
    }

    @GetMapping("/{id}")
    public Customer getById(@PathVariable String id) {
        return customerService.findById(id);  // throws → 404 via GlobalExceptionHandler
    }
}
```

### `controller/AccountController.java` (final)

```java
package com.example.bank.controller;

import com.example.bank.model.Account;
import com.example.bank.service.AccountService;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/accounts")
public class AccountController {

    private final AccountService accountService;

    public AccountController(AccountService accountService) {
        this.accountService = accountService;
    }

    @ModelAttribute
    public void addDeprecationHeaders(HttpServletResponse response) {
        response.setHeader("Deprecation", "true");
        response.setHeader("Sunset", "Sat, 01 Nov 2026 00:00:00 GMT");
        response.setHeader("Link", "</api/v2/accounts>; rel=\"successor-version\"");
    }

    @GetMapping
    public List<Account> getAll() {
        return accountService.findAll();
    }

    @GetMapping("/{accountNumber}")
    public Account getByAccountNumber(@PathVariable String accountNumber) {
        return accountService.findByAccountNumber(accountNumber);  // throws → 404
    }
}
```

### `controller/AccountControllerV2.java` (final)

```java
package com.example.bank.controller;

import com.example.bank.model.AccountV2;
import com.example.bank.service.AccountService;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v2/accounts")
public class AccountControllerV2 {

    private final AccountService accountService;

    public AccountControllerV2(AccountService accountService) {
        this.accountService = accountService;
    }

    @GetMapping
    public List<AccountV2> getAll() {
        return accountService.findAll().stream()
                .map(a -> new AccountV2(
                        a.accountNumber(), a.customerId(),
                        a.type(), a.status(),
                        a.balance(), a.balance(), "USD"))
                .collect(Collectors.toList());
    }

    @GetMapping("/{accountNumber}")
    public AccountV2 getByAccountNumber(@PathVariable String accountNumber) {
        var a = accountService.findByAccountNumber(accountNumber);
        return new AccountV2(
                a.accountNumber(), a.customerId(),
                a.type(), a.status(),
                a.balance(), a.balance(), "USD");
    }
}
```

### `controller/TransactionController.java` (final)

```java
package com.example.bank.controller;

import com.example.bank.model.Transaction;
import com.example.bank.model.TransactionType;
import com.example.bank.service.TransactionService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.util.UriComponentsBuilder;

import java.math.BigDecimal;
import java.net.URI;
import java.util.List;

@RestController
public class TransactionController {

    private final TransactionService transactionService;

    public TransactionController(TransactionService transactionService) {
        this.transactionService = transactionService;
    }

    @GetMapping("/api/v1/transactions")
    public List<Transaction> getAll() {
        return transactionService.findAll();
    }

    @GetMapping("/api/v1/accounts/{accountNumber}/transactions")
    public List<Transaction> getByAccount(@PathVariable String accountNumber) {
        return transactionService.findByAccountNumber(accountNumber);
    }

    @PostMapping("/api/v1/accounts/{accountNumber}/transactions")
    public ResponseEntity<Transaction> create(
            @PathVariable String accountNumber,
            @RequestBody TransactionRequest request,
            UriComponentsBuilder ucb) {
        Transaction saved = transactionService.process(
                accountNumber, request.type(), request.amount());
        URI location = ucb.path("/api/v1/transactions/{transactionId}")
                .buildAndExpand(saved.transactionId())
                .toUri();
        return ResponseEntity.created(location).body(saved);
    }

    public record TransactionRequest(TransactionType type, BigDecimal amount) {}
}
```

### `controller/InfoController.java`

```java
package com.example.bank.controller;

import com.example.bank.config.BankProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/info")
public class InfoController {

    private final BankProperties properties;

    public InfoController(BankProperties properties) {
        this.properties = properties;
    }

    @GetMapping
    public Map<String, Object> info() {
        return Map.of(
                "environment", properties.getEnvironmentLabel(),
                "transactionLimit", properties.getTransactionLimit(),
                "dailyLimit", properties.getDailyLimit()
        );
    }
}
```

### `exception/ResourceNotFoundException.java`

```java
package com.example.bank.exception;

public class ResourceNotFoundException extends RuntimeException {
    private final String resourceType;
    private final String resourceId;

    public ResourceNotFoundException(String resourceType, String resourceId) {
        super(resourceType + " not found: " + resourceId);
        this.resourceType = resourceType;
        this.resourceId = resourceId;
    }

    public String getResourceType() { return resourceType; }
    public String getResourceId() { return resourceId; }
}
```

### `exception/AccountNotFoundException.java`

```java
package com.example.bank.exception;

public class AccountNotFoundException extends ResourceNotFoundException {
    public AccountNotFoundException(String accountNumber) {
        super("Account", accountNumber);
    }
}
```

### `exception/BusinessRuleException.java`

```java
package com.example.bank.exception;

public class BusinessRuleException extends RuntimeException {
    private final String errorCode;

    public BusinessRuleException(String errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public String getErrorCode() { return errorCode; }
}
```

### `exception/ApiError.java`

```java
package com.example.bank.exception;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;
import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiError {

    private final String status;
    private final String errorCode;
    private final String message;
    private final Instant timestamp;
    private final List<FieldError> fieldErrors;

    public ApiError(String status, String errorCode, String message,
                    List<FieldError> fieldErrors) {
        this.status = status;
        this.errorCode = errorCode;
        this.message = message;
        this.timestamp = Instant.now();
        this.fieldErrors = fieldErrors;
    }

    public String getStatus() { return status; }
    public String getErrorCode() { return errorCode; }
    public String getMessage() { return message; }
    public Instant getTimestamp() { return timestamp; }
    public List<FieldError> getFieldErrors() { return fieldErrors; }

    public record FieldError(String field, String message) {}
}
```

### `exception/GlobalExceptionHandler.java`

```java
package com.example.bank.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.List;
import java.util.stream.Collectors;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiError> handleNotFound(ResourceNotFoundException ex) {
        ApiError error = new ApiError(
                "404 NOT_FOUND",
                ex.getResourceType().toUpperCase() + "_NOT_FOUND",
                ex.getMessage(),
                null
        );
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @ExceptionHandler(BusinessRuleException.class)
    public ResponseEntity<ApiError> handleBusinessRule(BusinessRuleException ex) {
        ApiError error = new ApiError(
                "422 UNPROCESSABLE_ENTITY",
                ex.getErrorCode(),
                ex.getMessage(),
                null
        );
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body(error);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiError> handleValidation(MethodArgumentNotValidException ex) {
        List<ApiError.FieldError> fieldErrors = ex.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(fe -> new ApiError.FieldError(fe.getField(), fe.getDefaultMessage()))
                .collect(Collectors.toList());

        ApiError error = new ApiError(
                "400 BAD_REQUEST",
                "VALIDATION_FAILURE",
                "One or more fields failed validation",
                fieldErrors
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> handleUnexpected(Exception ex) {
        System.err.println("Unhandled exception: " + ex.getMessage());
        ApiError error = new ApiError(
                "500 INTERNAL_SERVER_ERROR",
                "INTERNAL_ERROR",
                "An unexpected error occurred. Please contact support.",
                null
        );
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
    }
}
```

### `resources/application.yml`

```yaml
spring:
  application:
    name: bank-service

server:
  port: 8080

bank:
  transaction-limit: 10000
  daily-limit: 25000
  environment-label: local
```

### `resources/application-dev.yml`

```yaml
bank:
  environment-label: development
  transaction-limit: 500
```

### `resources/application-prod.yml`

```yaml
bank:
  environment-label: production
  daily-limit: 50000
```

### `requests.http` (consolidated)

```http
### List all customers
GET http://localhost:8080/api/v1/customers

### Get a single customer
GET http://localhost:8080/api/v1/customers/C001

### Get a customer that does not exist (404 + ApiError body)
GET http://localhost:8080/api/v1/customers/UNKNOWN

### List all accounts (v1 — response includes Deprecation/Sunset headers)
GET http://localhost:8080/api/v1/accounts

### Get a single account
GET http://localhost:8080/api/v1/accounts/ACC-1001

### Environment info
GET http://localhost:8080/api/v1/info

### List all transactions
GET http://localhost:8080/api/v1/transactions

### Credit $250 to ACC-1001
POST http://localhost:8080/api/v1/accounts/ACC-1001/transactions
Content-Type: application/json

{ "type": "CREDIT", "amount": 250.00 }

### Debit $100 from ACC-1001
POST http://localhost:8080/api/v1/accounts/ACC-1001/transactions
Content-Type: application/json

{ "type": "DEBIT", "amount": 100.00 }

### Transactions for ACC-1001
GET http://localhost:8080/api/v1/accounts/ACC-1001/transactions

### Debit a closed account — 422 ACCOUNT_NOT_OPEN
POST http://localhost:8080/api/v1/accounts/ACC-1005/transactions
Content-Type: application/json

{ "type": "DEBIT", "amount": 50.00 }

### Debit more than the balance — 422 INSUFFICIENT_FUNDS
POST http://localhost:8080/api/v1/accounts/ACC-1003/transactions
Content-Type: application/json

{ "type": "DEBIT", "amount": 999999.00 }

### Credit a non-existent account — 404 ACCOUNT_NOT_FOUND
POST http://localhost:8080/api/v1/accounts/ACC-9999/transactions
Content-Type: application/json

{ "type": "CREDIT", "amount": 10.00 }

### v2 accounts — accountType, availableBalance, currency
GET http://localhost:8080/api/v2/accounts

### v2 single account
GET http://localhost:8080/api/v2/accounts/ACC-1001
```

---

## Notes for Instructors

- `TransactionService.process` is shown in both transitional and final forms. Students who do the exercises strictly in order will write the transitional version during Exercise 3 (where `AccountService.findByAccountNumber` still returns `Optional`) and update it during Exercise 4. The "Final Consolidated Source Files" section is the end-state.
- The idempotency comment block at the top of `TransactionController.java` (Task 3.4) is reasoning, not code. Encourage students to write it before reading the checkpoint answers.
- The version-increment table is the artifact of Task 5.4 and should be saved as `VERSION_NOTES.md` in the project root.
- The `Sunset` header date is `01 Nov 2026`. Adjust as needed for your course delivery cohort so the date remains in the future.
- The `record` vs. `class` choice for `Account` is a common student question — the lab callout explains it, but be prepared to walk through "the account changes; the `Account` snapshot does not" in person. The same explanation will recur in the database module when entities become mutable JPA objects, which is the right time to contrast the two patterns directly.

---

*End of Solutions File*
