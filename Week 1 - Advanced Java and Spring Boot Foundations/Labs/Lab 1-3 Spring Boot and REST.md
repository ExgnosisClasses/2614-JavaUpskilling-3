# Lab 1-3: Spring Boot Architecture and REST API Design
## Hands-On Exercises

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 2 - Spring Boot Architecture & REST API Design
> **Estimated time per exercise:** 30–60 minutes

---

## How to Use These Exercises

Each exercise is self-contained and builds directly on the concepts introduced in the module lectures. They are designed to be completed in IntelliJ IDEA using a Spring Boot project generated from Spring Initializr.

- **Context**:  why this concept matters and what problem it solves
- **Setup**:  how to structure the project and files before you start
- **Tasks**:  step-by-step work to complete, including starter code with `TODO` markers
- **Checkpoints**: questions that test conceptual understanding, not just code completion


> **Note** - The extension exercises are not required to complete the module, but they provide an opportunity to deepen your understanding and practice applying the concepts in a more complex scenario. They are designed to be more challenging and may require additional research or experimentation.
>
> Suggested solution to the extension exercises will be provided at the end of the module to remove the temptation to cut and paste the solution before trying it yourself.
>

> **Tip:** Work through the exercises in order. Each one builds on the project structure established in the first. If you get stuck on a `TODO`, re-read the relevant section of the lecture slides before looking at the solution file.

> **Capstone alignment:** The domain model in this lab; customers, accounts, transactions, is intentionally aligned with the banking domain you will use in your capstone project. The structure of the service layer, the controllers, and the error handling you build here are directly carried forward and extended in later modules (database persistence, security, messaging). Treat this lab as the skeleton of the capstone, not as a throwaway exercise.

---

## Starter Project

All exercises in this module share a single Spring Boot project. Create it once and use it throughout.

### Create the project with Spring Initializr

1. Open [https://start.spring.io](https://start.spring.io) in a browser
2. Configure the project as follows:

| Setting | Value                 |
|---|-----------------------|
| Project | Maven                 |
| Language | Java                  |
| Spring Boot | 3.5.x (latest stable) |
| Group | `com.example`         |
| Artifact | `bank`                |
| Packaging | Jar                   |
| Java | 21                    |

3. Add the following dependencies using the search box on the right:
   - **Spring Web**: the Spring MVC framework and embedded Tomcat server
   - **Spring Boot DevTools**: automatic restart on file changes during development
   - **Validation**: the Bean Validation (JSR-380) integration

4. Click **Generate**, unzip the downloaded archive, and open the folder in IntelliJ IDEA using **File → Open**

5. When IntelliJ finishes indexing, open the Maven tool window (View → Tool Windows → Maven) and confirm there are no download errors

### Verify the project starts

Open `BankApplication.java` in `src/main/java/com/example/bank` and run it (click the green play button in the gutter, or press `Shift+F10`). You should see output ending with:

```
Started BankApplication in X.XXX seconds
```

If Tomcat starts on port 8080 you are ready to begin.

### Package structure to create before Exercise 1

Right-click `src/main/java/com/example/bank` in the Project tool window and create the following sub-packages now. Creating them up front avoids context-switching later:

```
com.example.bank
├── controller
├── service
├── model
└── exception
```

---

## Exercise 1: The Layered Architecture in Practice

**Estimated time:** 30–40 minutes
**Topics covered:** Layered architecture, stereotype annotations (`@RestController`, `@Service`), constructor injection, the role of each layer, Java 21 records and sealed types

### Context

Spring Boot's layered architecture is the mechanism by which the framework separates three fundamentally different concerns: HTTP communication, business logic, and data access. Each layer has a single, well-defined responsibility, and the annotations that mark each class tell Spring's IoC container exactly which role that class plays.

The architecture you will build in this exercise is the same structure used throughout the rest of this course and in the capstone. Understanding *why* each class lives in its own layer and what happens when that boundary is violated is more important than the mechanics of writing the code itself.

The key principle: controllers know about HTTP, services know about business logic, and neither knows about the internals of the other. The controller calls the service; the service does not call the controller. Dependencies flow in one direction only.

The domain you are building is a small retail banking service. There are three entities: `Customer`, `Account`, and `Transaction`. A customer holds one or more accounts; an account has a balance, a type (checking or savings), and a status (open or closed); a transaction is a credit (money in) or debit (money out) applied to a single account. This vocabulary is what the rest of the course and the capstone build on.

### Task 1.1: The Domain Model

Create three model files in the `model` package. These are Java 21 records and a sealed interface. Records generate constructors, accessors, `equals`, `hashCode`, and `toString` automatically. A sealed interface restricts which classes are allowed to implement it, only the types you `permit` can extend it, which lets the compiler enforce that you have handled every possible case in a `switch`.

#### Enums

```java
package com.example.bank.model;

// Two enums for fixed sets of values.
// Using enums instead of strings means a typo in code is a compile error,
// and IDEs can autocomplete the legal values.
public enum AccountType {
    CHECKING, SAVINGS
}
```

```java
package com.example.bank.model;

public enum AccountStatus {
    OPEN, CLOSED
}
```

#### `Customer.java`

```java
package com.example.bank.model;

import java.util.List;

// A customer owns one or more accounts. The customer's id is generated
// server-side; in this lab it is set during seeding.
public record Customer(
        String id,
        String name,
        List<String> accountNumbers  // references to Account.accountNumber, not Account objects
) {}
```



### Design Note 1

Why store account numbers rather than account objects? Separation of identity from state. 
- The customer record references accounts by their stable identifier; the actual account data lives in the account store
- If we embedded full account objects inside customers, every balance update would require rewriting the customer record too.

#### `Account.java`

```java
package com.example.bank.model;

import java.math.BigDecimal;

// Balance is BigDecimal, not double. Money must never be stored as a
// floating-point type because of representational error
// (0.1 + 0.2 != 0.3 in double). This is non-negotiable in a banking domain.
public record Account(
        String accountNumber,   // stable identifier, e.g. "ACC-1001"
        String customerId,      // foreign key to Customer.id
        AccountType type,
        AccountStatus status,
        BigDecimal balance
) {}
```
### Design Note 2

The instinct "records are immutable, but balance changes, so a record must be wrong" treats the object and the data as the same thing. They're not.

The account (the conceptual entity, identified by ACC-1001) has a balance that changes over time

An Account record is an immutable snapshot of that account at one moment

Every balance update produces a new Account value and replaces the old one in the store.
- The old value is discarded.
- From outside the service, "the account's balance changed" is exactly what's observable.
- The fact that internally we swapped one immutable snapshot for another is an implementation detail.

This is the same pattern as String.
- Strings are immutable, but you constantly "change" them: s = s + "x" produces a new string and reassigns the variable.

Immutability is actually the right default here, especially for money
- In a banking domain, mutable shared state is a category of potential bugs
- Thread safety is free.
   - Tomcat is multithreaded.
   - Two simultaneous reads of ACC-1001 will see two distinct immutable snapshots, they cannot see a half-updated balance.
   - A mutable Account with a setter would need synchronization on every field access.

- Audit and undo become trivial.
   - Want to keep the prior balance for an audit log? Just keep the reference to the old record.
   - With a mutable object you'd have to defensively clone before every mutation.

- Equality and caching behave correctly.
   - Records have value-based equals.
   - A cached Account won't silently change underneath the cache because someone elsewhere called a setter.
- The compiler stops a whole class of bugs
   - No setter means no accidental balance change deep inside some method you forgot about.

#### `Transaction.java`

A transaction is a sealed interface with two record implementations: `CreditTransaction` and `DebitTransaction`. The sealed declaration tells the compiler "no class other than these two may implement `Transaction`." This is what makes exhaustive pattern matching possible later.

```java
package com.example.bank.model;

import java.math.BigDecimal;
import java.time.Instant;

// Sealed: only the types listed in `permits` may implement this interface.
// All transactions share these four fields, exposed via the interface methods.
// A record's accessor methods automatically satisfy an interface's abstract
// methods of the same name, so each permitted record only has to declare
// its components -- no method bodies needed.
public sealed interface Transaction
        permits CreditTransaction, DebitTransaction {

    String transactionId();
    String accountNumber();
    BigDecimal amount();
    Instant timestamp();
}
```

```java
package com.example.bank.model;

import java.math.BigDecimal;
import java.time.Instant;

// A credit increases the account balance (deposit, from the bank's perspective).
public record CreditTransaction(
        String transactionId,
        String accountNumber,
        BigDecimal amount,
        Instant timestamp
) implements Transaction {}
```

```java
package com.example.bank.model;

import java.math.BigDecimal;
import java.time.Instant;

// A debit decreases the account balance (withdrawal).
public record DebitTransaction(
        String transactionId,
        String accountNumber,
        BigDecimal amount,
        Instant timestamp
) implements Transaction {}
```

> **Out of scope for this lab:** A transfer between two accounts is a *pair* of transactions; a debit from the source and a credit to the destination, applied atomically. Transfers are not part of this lab. They are revisited in the database module where transactional integrity is enforced by the database layer.

### Task 1.2: The Service Layer

Create two service classes in the `service` package. The services own the business logic and the in-memory data stores. Notice that they have no awareness of HTTP: no `@RequestMapping`, no `HttpServletRequest`, no `ResponseEntity`.

#### `CustomerService.java`

```java
package com.example.bank.service;

import com.example.bank.model.Customer;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

// @Service marks this class as a Spring-managed bean in the service layer.
// It is functionally identical to @Component but communicates intent:
// this class contains business logic, not HTTP handling or data access.
@Service
public class CustomerService {

    // In-memory store keyed by customer ID.
    // ConcurrentHashMap is used here because Tomcat is multithreaded and may
    // handle concurrent requests. This is not a concern you would manage manually
    // with a real database.
    private final Map<String, Customer> store = new ConcurrentHashMap<>();

    public CustomerService() {
        // Seed data -- customers and their account numbers.
        // The accounts themselves are seeded in AccountService and must
        // use the same account numbers listed here.
        store.put("C001", new Customer("C001", "Alice Nguyen",
                List.of("ACC-1001", "ACC-1002")));
        store.put("C002", new Customer("C002", "Bob Patel",
                List.of("ACC-1003")));
        store.put("C003", new Customer("C003", "Carla Romero",
                List.of("ACC-1004", "ACC-1005")));
    }

    public List<Customer> findAll() {
        // TODO 1: Return all customers from the store.
        // Hint: store.values() returns a Collection -- wrap it in a new ArrayList
        // (or use List.copyOf) so callers cannot mutate the internal store.
    }

    public Optional<Customer> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }
}
```

#### `AccountService.java`

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
        // Seeded accounts. The account numbers and customerIds match
        // the references in CustomerService.
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

    // Internal helper -- not exposed via the controller.
    // Used during seeding and by the transaction-processing logic in Exercise 3
    // to write back an updated account record after the balance changes.
    Account save(Account account) {
        store.put(account.accountNumber(), account);
        return account;
    }

    // TODO 2: Implement updateBalance(String accountNumber, BigDecimal newBalance).
    // Because Account is an immutable record, you cannot mutate the balance.
    // Instead:
    //   1. Look up the existing account by number.
    //   2. If absent, return Optional.empty().
    //   3. If present, construct a NEW Account record with the same
    //      accountNumber, customerId, type, and status, but the new balance.
    //   4. Put the new record into the store, replacing the old one.
    //   5. Return Optional.of(updatedAccount).
    public Optional<Account> updateBalance(String accountNumber, BigDecimal newBalance) {
        // your code here
    }
}
```

> **Why records make balance updates look strange.** A record is immutable: once constructed, none of its fields can be reassigned. To "update" the balance you construct a new `Account` value with the new balance and store it. This is intentional. Immutability removes whole classes of concurrency bugs and makes reasoning about state straightforward. the value you read from the map is the value as it was; if a balance changes between two reads, you see two distinct `Account` instances, never a partially-updated one.

### Task 1.3: The Controller Layer

Create two controller classes in the `controller` package. These are the HTTP boundary of the application. Their only job is to translate HTTP into service calls and service results back into HTTP.

#### `CustomerController.java`

```java
package com.example.bank.controller;

import com.example.bank.model.Customer;
import com.example.bank.service.CustomerService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

// @RestController combines @Controller and @ResponseBody.
// Every method return value is serialized directly to JSON.
// Without @ResponseBody, Spring MVC would treat the return value as a view name.
@RestController
// @RequestMapping sets the base path for all endpoints in this class.
// /api/v1 is the version prefix -- set at the class level so every
// method inherits it. No version logic goes inside a method body.
@RequestMapping("/api/v1/customers")
public class CustomerController {

    // Constructor injection is the only correct way to inject dependencies in Spring.
    // Spring instantiates this controller and injects the service at startup.
    // The field is final, which means this object cannot be created without it.
    private final CustomerService customerService;

    public CustomerController(CustomerService customerService) {
        this.customerService = customerService;
    }

    // GET /api/v1/customers
    @GetMapping
    public List<Customer> getAll() {
        return customerService.findAll();
    }

    // GET /api/v1/customers/{id}
    // @PathVariable binds the {id} placeholder in the URL to the method parameter.
    @GetMapping("/{id}")
    public ResponseEntity<Customer> getById(@PathVariable String id) {
        // TODO 3: Call customerService.findById(id).
        // If the customer is found, return ResponseEntity.ok(customer) -- 200.
        // If it is not found, return ResponseEntity.notFound().build() -- 404.
        // Use the Optional's map/orElse pattern, not an if statement.
    }
}
```

#### `AccountController.java`

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

    // GET /api/v1/accounts
    @GetMapping
    public List<Account> getAll() {
        return accountService.findAll();
    }

    // GET /api/v1/accounts/{accountNumber}
    @GetMapping("/{accountNumber}")
    public ResponseEntity<Account> getByAccountNumber(@PathVariable String accountNumber) {
        // TODO 4: Same pattern as TODO 3 -- map/orElse using findByAccountNumber.
    }
}
```

> **No `POST`, `PUT`, `PATCH`, or `DELETE` for customers or accounts.** In this lab the bank is read-only for these entities; onboarding a customer and opening an account are out of scope. The only write operation is creating a transaction (Exercise 3), which moves money on an existing account. Accept this constraint: it makes the surface area small enough to focus on the core teaching points, and it matches the real-world boundary between an "account servicing" API and an "account opening" API.

### Task 1.4: Verify with curl or a REST client

Start the application and verify each endpoint. Use curl, the IntelliJ HTTP client (a `.http` file), or any REST tool you prefer.

Create a file `requests.http` in the project root with the following content to use IntelliJ's built-in HTTP client:

```http
### List all customers
GET http://localhost:8080/api/v1/customers

### Get a single customer
GET http://localhost:8080/api/v1/customers/C001

### Get a customer that does not exist
GET http://localhost:8080/api/v1/customers/UNKNOWN

### List all accounts
GET http://localhost:8080/api/v1/accounts

### Get a single account
GET http://localhost:8080/api/v1/accounts/ACC-1001
```

Click the green play button next to each request in IntelliJ to execute it. Verify:
- The customer list returns 3 customers with their account numbers
- A GET for `C001` returns `200` with a JSON body containing two account numbers
- A GET for `UNKNOWN` returns `404`
- The account list returns 5 accounts with mixed types and statuses

### Checkpoints

1. The controller imports nothing from `java.sql` and the service imports nothing from `org.springframework.web`. Why is maintaining this separation important as the application grows?
2. `CustomerService` is annotated `@Service` and `CustomerController` is annotated `@RestController`. Both are specializations of `@Component`. What does this annotation tell the IoC container to do at startup?
3. `Account.balance` is `BigDecimal` rather than `double`. What concrete error would using `double` here introduce in a banking application?
4. `Transaction` is declared `sealed`. What does the compiler now refuse to allow that it would have permitted if the interface were not sealed? Why does this matter for the transaction processing in Exercise 3?

### Extension Task

Add a `GET /api/v1/customers/{id}/accounts` endpoint that returns the list of full `Account` objects (not just numbers) belonging to a customer. You will need to inject `AccountService` into `CustomerController` and look up each account number. Return `404` if the customer does not exist.

---

## Exercise 2: Configuration, Profiles, and the Environment Abstraction

**Estimated time:** 30–45 minutes
**Topics covered:** `application.yml`, typed configuration with `@ConfigurationProperties`, Spring Profiles, environment-specific overrides

### Context

A production banking service must run in multiple environments: local development, a shared integration environment, and production, each with different configuration values. Hard-coding configuration inside a class is not an option because it forces a recompile and redeploy for every environment change.

Spring Boot solves this with a layered configuration model. The base `application.yml` holds defaults. Profile-specific files (`application-dev.yml`, `application-prod.yml`) overlay those defaults with environment-specific values. Environment variables override both. This hierarchy means that a developer can run the application locally with a development configuration while the same JAR file, with no changes to its code, runs in production with production values.

In this exercise, you will also use `@ConfigurationProperties`, which is the idiomatic Spring approach to reading configuration. It binds a group of related properties to a typed Java class, ensuring configuration values have compile-time safety, are easy to test, and are navigable in the IDE.

### Task 2.1: Base Configuration

Open `src/main/resources/application.yml`. Replace its contents with:

```yaml
# application.yml -- base configuration, loaded in every environment
spring:
  application:
    name: bank-service

server:
  port: 8080

bank:
  # Maximum size of a single credit or debit transaction in dollars.
  # This is a real banking control -- production systems enforce per-transaction
  # limits to mitigate fraud and operational risk.
  transaction-limit: 10000
  # Daily aggregate limit per account, applied across all transactions.
  daily-limit: 25000
  # A label identifying which environment this service is running in
  environment-label: local
```

### Task 2.2: Profile-Specific Overrides

Create two new files in `src/main/resources`:

**`application-dev.yml`**

```yaml
# Overlays application.yml when the 'dev' profile is active
bank:
  environment-label: development
  transaction-limit: 500   # smaller limit so devs trip the rule more often
```

**`application-prod.yml`**

```yaml
# Overlays application.yml when the 'prod' profile is active
bank:
  environment-label: production
  daily-limit: 50000       # higher daily limit for production traffic
```

### Task 2.3: Typed Configuration with `@ConfigurationProperties`

Create `BankProperties.java` in a new `config` sub-package:

```java
package com.example.bank.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.math.BigDecimal;

// @ConfigurationProperties binds all properties under the "bank" prefix
// to the fields of this class at application startup.
// The field names use camelCase in Java; Spring Boot automatically maps
// kebab-case property names (transaction-limit) to camelCase (transactionLimit).
@ConfigurationProperties(prefix = "bank")
public class BankProperties {

    // Defaults are used only if the property is absent from every config source.
    private BigDecimal transactionLimit = new BigDecimal("10000");
    private BigDecimal dailyLimit = new BigDecimal("25000");
    private String environmentLabel = "unknown";

    // TODO 5: Generate getters and setters for all three fields.
    // Spring Boot's binding mechanism requires standard JavaBean setters to
    // write the values, and getters for other classes to read them.
    // Use IntelliJ's generator: Alt+Insert (Windows/Linux) or Cmd+N (Mac)
    // → "Getter and Setter" → select all fields.
}
```

### Task 2.4: Enable and Inject the Properties

Open `BankApplication.java` and add the `@EnableConfigurationProperties` annotation:

```java
package com.example.bank;

import com.example.bank.config.BankProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

// @EnableConfigurationProperties registers BankProperties as a Spring bean
// and tells the binding mechanism to populate it from the environment.
@SpringBootApplication
@EnableConfigurationProperties(BankProperties.class)
public class BankApplication {
    public static void main(String[] args) {
        SpringApplication.run(BankApplication.class, args);
    }
}
```

Now inject `BankProperties` into a diagnostic controller. Create `InfoController.java` in the `controller` package;  keeping diagnostics out of the customer and account controllers is good hygiene.

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

    // TODO 6: Add the constructor that accepts and stores BankProperties.
    // Spring will inject it automatically because it is a registered bean.

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

### Task 2.5: Activate a Profile and Observe the Difference

Run the application twice with different active profiles and compare the `/api/v1/info` response each time.

**Without a profile (uses base `application.yml`):**

Run the application normally. Call `GET http://localhost:8080/api/v1/info`.

Expected:
```json
{
  "environment": "local",
  "transactionLimit": 10000,
  "dailyLimit": 25000
}
```

**With the `dev` profile active:**

In IntelliJ, open **Run → Edit Configurations**, find your Spring Boot run configuration, and add `dev` to the **Active profiles** field. Restart and call the same endpoint.

Expected:
```json
{
  "environment": "development",
  "transactionLimit": 500,
  "dailyLimit": 25000
}
```

Notice that `dailyLimit` remains `25000` from the base file because `application-dev.yml` does not override it. This is the overlay mechanic at work.

### Checkpoints

1. The `application-dev.yml` file only declares two properties. What happens to the third (`dailyLimit`)? Where does its value come from at runtime?
2. Why is `@ConfigurationProperties` preferred over injecting individual values with `@Value("${bank.transaction-limit}")`? Think about what happens when you have 15 related properties.
3. In a containerized deployment, how would you activate the `prod` profile without modifying any file inside the JAR? Which Spring Boot property controls the active profile?
4. The `environmentLabel` property has a default value set directly on the field in `BankProperties`. When would that default actually be used?

---

## Exercise 3: Resource-Oriented URL Design and HTTP Method Semantics

**Estimated time:** 30–45 minutes
**Topics covered:** Resource-oriented URLs, sub-resources, HTTP method semantics (GET/POST), query parameters vs path variables, idempotency

### Context

REST is a set of constraints on how distributed systems communicate. The most important of those constraints, the uniform interface, requires that URLs identify resources and that HTTP methods carry the semantics of the operation being performed. When this separation is maintained, every layer of the infrastructure (caches, load balancers, API gateways, monitoring tools) can reason about requests without reading the body.

The most common REST design mistake is treating the URL as a command. `/createTransaction`, `/getAccountById`, `/closeAccount` are all antipatterns. They move intent from the HTTP method (where it belongs) into the URL (where it does not belong). The correct design is `/accounts` with `GET` to read and `/accounts/{n}/transactions` with `POST` to create a transaction.

In this exercise, you will add the `Transaction` resource. It is modeled as a sub-resource of `Account` because a transaction has no meaning without the account it applies to. You will use Java 21 pattern matching to dispatch on the transaction type inside the service layer.

### Task 3.1: The Transaction Service

Create `TransactionService.java` in the `service` package. This service owns the business logic for processing a transaction: validate that the account exists and is open, apply the balance change, and record the transaction.

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

    // Constructor injection -- AccountService is a Spring bean and Spring
    // wires it in automatically.
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

    /**
     * Process a credit or debit against an existing account.
     * - Verifies the account exists (404 via exception handler if not).
     * - Verifies the account is OPEN (422 via exception handler if not).
     * - Computes the new balance.
     * - For debits, verifies sufficient funds (422 if not).
     * - Persists the updated account and the transaction record.
     */
    public Transaction process(String accountNumber, TransactionType type, BigDecimal amount) {

        Account account = accountService.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new AccountNotFoundException(accountNumber));

        if (account.status() != AccountStatus.OPEN) {
            throw new BusinessRuleException("ACCOUNT_NOT_OPEN",
                    "Cannot post a transaction to a closed account: " + accountNumber);
        }
        if (amount.signum() <= 0) {
            throw new BusinessRuleException("INVALID_AMOUNT",
                    "Transaction amount must be greater than zero");
        }

        // TODO 7: Compute the new balance based on the transaction type.
        //   - For TransactionType.CREDIT, newBalance = account.balance() + amount
        //   - For TransactionType.DEBIT,  newBalance = account.balance() - amount,
        //     but only if account.balance() >= amount. If insufficient funds,
        //     throw new BusinessRuleException("INSUFFICIENT_FUNDS", ...).
        // Use BigDecimal.add and BigDecimal.subtract -- do not convert to double.
        BigDecimal newBalance;
        // your code here

        // Write back the updated account record (creates a new Account value
        // because Account is immutable -- see AccountService.updateBalance).
        accountService.updateBalance(accountNumber, newBalance);

        // TODO 8: Construct the appropriate Transaction record.
        // Use a switch expression on `type`:
        //   - CREDIT -> new CreditTransaction(id, accountNumber, amount, Instant.now())
        //   - DEBIT  -> new DebitTransaction (id, accountNumber, amount, Instant.now())
        // Generate the id with: "TXN-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase()
        // The switch must be exhaustive -- because TransactionType is an enum, the
        // compiler will reject a non-exhaustive switch.
        String txnId = "TXN-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        Transaction txn;
        // your code here

        store.put(txn.transactionId(), txn);
        return txn;
    }
}
```

You also need a small enum that the controller uses to communicate the action type. Add this to the `model` package:

```java
package com.example.bank.model;

// The shape of the field in the inbound POST body that says
// "credit this account" or "debit this account".
// This is separate from the sealed Transaction hierarchy because
// the wire contract and the internal model are independently versioned.
public enum TransactionType {
    CREDIT, DEBIT
}
```

> **Why two type representations?** `TransactionType` is the *wire* contract, what the client sends in JSON. `CreditTransaction` / `DebitTransaction` are the *domain* representation. what the service stores and reasons about. They happen to align today, but separating them means the wire format can evolve (a new transaction type) without forcing every domain method to change at the same time.

### Task 3.2: The Transaction Controller

The transaction endpoint is a sub-resource of an account: `/api/v1/accounts/{accountNumber}/transactions`. A transaction without an account has no domain meaning, so the parent's identity is part of the URL.

Create `TransactionController.java` in the `controller` package:

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

    // GET /api/v1/transactions
    // Top-level list of all transactions across all accounts.
    // In a real system this would be paginated and access-controlled;
    // for the lab it returns the full list.
    @GetMapping("/api/v1/transactions")
    public List<Transaction> getAll() {
        return transactionService.findAll();
    }

    // GET /api/v1/accounts/{accountNumber}/transactions
    // Sub-resource listing: just the transactions for one account.
    @GetMapping("/api/v1/accounts/{accountNumber}/transactions")
    public List<Transaction> getByAccount(@PathVariable String accountNumber) {
        return transactionService.findByAccountNumber(accountNumber);
    }

    // POST /api/v1/accounts/{accountNumber}/transactions
    // Create a transaction. The body specifies the action (CREDIT or DEBIT)
    // and the amount. The accountNumber comes from the URL, not the body --
    // the URL identifies the target.
    @PostMapping("/api/v1/accounts/{accountNumber}/transactions")
    public ResponseEntity<Transaction> create(
            @PathVariable String accountNumber,
            @RequestBody TransactionRequest request,
            UriComponentsBuilder ucb) {

        // TODO 9: Call transactionService.process(accountNumber, request.type(), request.amount()).
        // Build the Location URI pointing to the new transaction:
        //   /api/v1/transactions/{transactionId}
        // Return ResponseEntity.created(location).body(saved).
        // 201, not 200 -- 201 signals resource creation and carries the new resource's URI.
    }

    // Request body record -- declared inside the controller because it is
    // a controller-layer concern (the wire contract). The service uses
    // primitives (TransactionType + BigDecimal), not this record.
    public record TransactionRequest(TransactionType type, BigDecimal amount) {}
}
```



### Task 3.3: Reason About Idempotency

Answer these questions *before* looking at the checkpoints below. Write your answers in a comment block at the top of `TransactionController.java`.

Which of the endpoints you have built are idempotent, and which are not? For each endpoint, state what would happen if the client sent the same request twice.

Consider:
- `GET /api/v1/accounts/ACC-1001/transactions` sent twice
- `POST /api/v1/accounts/ACC-1001/transactions` sent twice with `{ "type": "DEBIT", "amount": 100.00 }`
- `GET /api/v1/accounts/ACC-1001` sent twice

Now reason about the business impact specifically. In a banking context, a non-idempotent `POST` is not just a design concern,  it is a money concern. What would you add to the API contract to make the `POST` safe to retry after a network timeout?

### Checkpoints

1. Why does the path for creating a transaction start with `/accounts/{accountNumber}/transactions` rather than simply `/transactions` with the account number in the body? What does the hierarchical structure communicate to the client and to the infrastructure?
2. The `POST` endpoint takes `accountNumber` from the URL, not from the request body. Why is this the correct design?
3. `GET` and idempotent methods can be retried freely. `POST` cannot. In a banking context, what specific harm could a blind retry cause, and what is the standard pattern (mentioned in lecture) for making `POST` retry-safe?
4. The `Transaction` interface is sealed. The switch expression in `process` covers `CREDIT` and `DEBIT`. If someone later adds a `FeeTransaction` to the sealed hierarchy, what happens to the existing switch statement at compile time? Why is this an architectural benefit?

---

## Exercise 4: HTTP Status Code Discipline and the Error Contract

**Estimated time:** 40–60 minutes
**Topics covered:** HTTP status code semantics, `@ControllerAdvice`, `@ExceptionHandler`, structured error payloads aligned with RFC 7807, the 200-with-error antipattern

### Context

Status codes are the primary communication mechanism between an API and every layer that interacts with it. They are a contract. A load balancer decides whether to retry a request based on the status code. A circuit breaker decides whether to open based on the rate of 5xx responses. A monitoring dashboard raises an alert when there is a spike in 4xx codes. If the application returns `200 OK` for every response and encodes the real outcome in the body, every one of these capabilities is disabled.

In a banking context the cost of this antipattern is especially clear. A `200 OK` returned on a failed debit looks identical to a successful debit at the network layer. The retry logic in the upstream client sees no error and does not know to back off; the monitoring system sees no error and does not raise an alert; the customer's mobile app shows "Success" because that is what the HTTP layer said.

The `@ControllerAdvice` + `@ExceptionHandler` pattern in Spring Boot is the mechanism for centralizing exception-to-status-code mappings. Controllers throw domain exceptions; the advice translates them to HTTP responses. Controllers contain no `try/catch` blocks and no `ResponseEntity` construction for error cases. This is a clean separation of concerns: the controller declares intent, and the advice handles outcomes.

In this exercise you will build a domain exception hierarchy, a centralized exception handler, and a structured error payload that follows RFC 7807.

### Task 4.1: Domain Exception Classes

Create three exception classes in the `exception` package.

`ResourceNotFoundException.java`  which is the parent for all "X does not exist" errors:

```java
package com.example.bank.exception;

// Thrown when a requested resource does not exist.
// Subclasses carry the resource-type-specific message.
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

`AccountNotFoundException.java` which is a specialized "account does not exist" subtype already used in `TransactionService`:

```java
package com.example.bank.exception;

public class AccountNotFoundException extends ResourceNotFoundException {
    public AccountNotFoundException(String accountNumber) {
        super("Account", accountNumber);
    }
}
```

`BusinessRuleException.java` which is thrown when the request was well-formed but violates a business rule (closed account, insufficient funds, amount out of range):

```java
package com.example.bank.exception;

// Thrown when a request is syntactically valid but violates a business rule.
// This maps to 422 Unprocessable Entity, not 400 Bad Request.
// 400 means the request could not be understood.
// 422 means the request was understood but the domain rejected it.
public class BusinessRuleException extends RuntimeException {

    private final String errorCode;

    public BusinessRuleException(String errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public String getErrorCode() { return errorCode; }
}
```

### Task 4.2: A Structured Error Payload

Create `ApiError.java` in the `exception` package. This is the payload returned in the body of every error response. Its structure follows RFC 7807 Problem Details for HTTP APIs.

```java
package com.example.bank.exception;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;
import java.util.List;

// @JsonInclude(NON_NULL) tells Jackson not to serialize fields that are null.
// The "fieldErrors" field is only relevant for validation failures;
// it should be absent from the JSON for other error types.
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiError {

    private final String status;       // e.g. "404 NOT_FOUND"
    private final String errorCode;    // machine-readable code, e.g. "ACCOUNT_NOT_FOUND"
    private final String message;      // human-readable description
    private final Instant timestamp;
    private final List<FieldError> fieldErrors;  // non-null only for 400 validation failures

    // TODO 10: Write the constructor that accepts four parameters
    // (status, errorCode, message, fieldErrors) and assigns them.
    // Set timestamp to Instant.now() inside the constructor.

    // Getters -- required for Jackson serialization
    public String getStatus() { return status; }
    public String getErrorCode() { return errorCode; }
    public String getMessage() { return message; }
    public Instant getTimestamp() { return timestamp; }
    public List<FieldError> getFieldErrors() { return fieldErrors; }

    // Nested record for per-field validation errors
    public record FieldError(String field, String message) {}
}
```

### Task 4.3: The Global Exception Handler

Create `GlobalExceptionHandler.java` in the `exception` package. This class centralizes all exception-to-HTTP mappings. No controller or service class will reference `HttpStatus` or construct a `ResponseEntity` for error cases.

```java
package com.example.bank.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.List;
import java.util.stream.Collectors;

// @RestControllerAdvice = @ControllerAdvice + @ResponseBody.
// Every method in this class can return a plain object and Spring will
// serialize it to JSON, just like @RestController does for normal endpoints.
// This class applies to all controllers in the application by default.
@RestControllerAdvice
public class GlobalExceptionHandler {

    // Handles ResourceNotFoundException (and its subclasses like
    // AccountNotFoundException) -- returns 404
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiError> handleNotFound(ResourceNotFoundException ex) {
        // TODO 11: Build an ApiError with:
        //   status = "404 NOT_FOUND"
        //   errorCode = ex.getResourceType().toUpperCase() + "_NOT_FOUND"
        //              (e.g. "ACCOUNT_NOT_FOUND" for an AccountNotFoundException)
        //   message = ex.getMessage()
        //   fieldErrors = null
        // Return ResponseEntity with status HttpStatus.NOT_FOUND and the ApiError as the body.
    }

    // Handles BusinessRuleException -- returns 422
    @ExceptionHandler(BusinessRuleException.class)
    public ResponseEntity<ApiError> handleBusinessRule(BusinessRuleException ex) {
        // TODO 12: Build an ApiError with:
        //   status = "422 UNPROCESSABLE_ENTITY"
        //   errorCode = ex.getErrorCode()      (e.g. "INSUFFICIENT_FUNDS", "ACCOUNT_NOT_OPEN")
        //   message = ex.getMessage()
        //   fieldErrors = null
        // Return ResponseEntity with status HttpStatus.UNPROCESSABLE_ENTITY.
    }

    // Handles validation failures from @Valid -- returns 400
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

    // Catch-all for any unhandled exception -- returns 500
    // Security note: the response body intentionally contains no stack trace,
    // no exception class name, and no internal message.
    // Those details are available in the server logs, not in the HTTP response.
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> handleUnexpected(Exception ex) {
        // TODO 13: Build an ApiError with:
        //   status = "500 INTERNAL_SERVER_ERROR"
        //   errorCode = "INTERNAL_ERROR"
        //   message = "An unexpected error occurred. Please contact support."
        //   fieldErrors = null
        // Log the real exception (System.err is fine for now -- a real app uses SLF4J).
        // Return ResponseEntity with status HttpStatus.INTERNAL_SERVER_ERROR.
    }
}
```

### Task 4.4: Push the Exception Through the Read Path

Update `CustomerService.findById` and `AccountService.findByAccountNumber` to be exception-throwing rather than `Optional`-returning. The controllers become simpler because they call the service and return the result, because the 404 case is now handled by `GlobalExceptionHandler`.

In `CustomerService`:

```java
public Customer findById(String id) {
    // TODO 14: Look up the customer in the store.
    // If found, return it. If not, throw new ResourceNotFoundException("Customer", id).
}
```

In `AccountService`:

```java
public Account findByAccountNumber(String accountNumber) {
    // TODO 15: Same pattern, but throw new AccountNotFoundException(accountNumber).
}
```

> **Note:** These changes return `Customer` and `Account` directly, not `Optional`. Update the controllers. `CustomerController.getById` and `AccountController.getByAccountNumber` collapse to a one-liner that just calls the service.

Also update `TransactionService.process`. The lookup line was already written to throw `AccountNotFoundException`, but it called `orElseThrow` on an `Optional`. Now that the service throws directly:

```java
Account account = accountService.findByAccountNumber(accountNumber);
// (the orElseThrow is no longer needed)
```

### Task 4.5: Verify the Error Contract

Add to `requests.http`:

```http
### List all transactions (initially empty)
GET http://localhost:8080/api/v1/transactions

### Credit $250 to ACC-1001
POST http://localhost:8080/api/v1/accounts/ACC-1001/transactions
Content-Type: application/json

{ "type": "CREDIT", "amount": 250.00 }

### Debit $100 from ACC-1001
POST http://localhost:8080/api/v1/accounts/ACC-1001/transactions
Content-Type: application/json

{ "type": "DEBIT", "amount": 100.00 }

### List transactions for ACC-1001 (expect two)
GET http://localhost:8080/api/v1/accounts/ACC-1001/transactions

### Verify the balance changed: 2500.00 + 250.00 - 100.00 = 2650.00
GET http://localhost:8080/api/v1/accounts/ACC-1001

### Attempt to debit a closed account -- expect 422 (after Exercise 4)
POST http://localhost:8080/api/v1/accounts/ACC-1005/transactions
Content-Type: application/json

{ "type": "DEBIT", "amount": 50.00 }
```

Expected results:
- A POST returns `201` with a `Location` header pointing to the new transaction
- The JSON body of the returned transaction includes a `transactionId`, the `accountNumber`, the `amount`, and a `timestamp`
- A follow-up GET on the account shows the new balance
- The list of transactions for `ACC-1001` returns the two you just created

> **Note:** Until you complete Exercise 4, the closed-account and insufficient-funds cases will still throw exceptions, but the HTTP response will be a generic `500`. Exercise 4 maps those exceptions to clean `422` responses with structured error bodies.

Add and run the following tests

```http
### Request a customer that does not exist
GET http://localhost:8080/api/v1/customers/UNKNOWN

### Debit a closed account -- should return 422 with errorCode ACCOUNT_NOT_OPEN
POST http://localhost:8080/api/v1/accounts/ACC-1005/transactions
Content-Type: application/json

{ "type": "DEBIT", "amount": 50.00 }

### Debit more than the balance -- should return 422 with errorCode INSUFFICIENT_FUNDS
POST http://localhost:8080/api/v1/accounts/ACC-1003/transactions
Content-Type: application/json

{ "type": "DEBIT", "amount": 999999.00 }

### Credit a non-existent account -- should return 404
POST http://localhost:8080/api/v1/accounts/ACC-9999/transactions
Content-Type: application/json

{ "type": "CREDIT", "amount": 10.00 }
```

Restart the application and execute each request. Verify:
- The not-found cases return `404`
- The business-rule cases return `422` with a domain-meaningful `errorCode`
- The body contains `errorCode`, `message`, `timestamp`, and `status`
- The body does not contain a stack trace or internal class names

### Checkpoints

1. `AccountNotFoundException` extends `ResourceNotFoundException`. There is no separate `@ExceptionHandler` for it. How does Spring still route it through `handleNotFound`?
2. The catch-all `Exception` handler deliberately omits the exception message from the response body. Why? In a banking context, what specific information must never leak in an error response?
3. `BusinessRuleException` maps to `422 Unprocessable Entity` rather than `400 Bad Request`. What is the semantic difference between these two status codes, and why does it matter to the client?
4. The `errorCode` field uses values like `INSUFFICIENT_FUNDS` and `ACCOUNT_NOT_OPEN`. Why is this field necessary when the `message` field already describes the problem in English? Consider how a mobile-banking app's UI would react to each code.

---

## Exercise 5: API Versioning Strategy

**Estimated time:** 25–35 minutes
**Topics covered:** URL path versioning, breaking vs non-breaking changes, deprecation headers, the version increment decision

### Context

An API that cannot evolve without breaking its callers is an API that cannot be maintained. Versioning is a commitment made from the first line of code. The version prefix in the URL (`/api/v1/accounts`) is the mechanism by which a service can introduce a breaking change in v2 while v1 continues to serve existing clients unchanged.

For a banking API the stakes are unusually high. Mobile banking apps, branch teller software, ATM controllers, partner integrations, and downstream reporting systems all depend on the same backend contract. A breaking change without a version bump cascades into customer-visible failures within minutes.

The most important discipline in API versioning is knowing precisely which changes require a version increment and which do not. A version bump is expensive: the old version must be maintained, clients must migrate, and two code paths must coexist for the deprecation period. Understanding the decision precisely prevents both over-versioning (bumping for non-breaking changes) and under-versioning (silently breaking clients).

### Task 5.1: Introduce a v2 Account Contract

Your v1 `Account` response includes `accountNumber`, `customerId`, `type`, `status`, and `balance`. A v2 contract changes the response shape:
- `type` is renamed to `accountType` (a breaking rename)
- A new `currency` field is added (default `"USD"`)
- A new `availableBalance` field is added alongside the existing `balance`

In a real bank `availableBalance` differs from `balance` because of pending holds, but for this lab it is the same number, the field exists to demonstrate the additive change.

Create a v2 response model in the `model` package:

```java
package com.example.bank.model;

import java.math.BigDecimal;

// v2 response shape. A separate record, not a modified Account.
// v1 and v2 coexist independently.
public record AccountV2(
        String accountNumber,
        String customerId,
        AccountType accountType,        // renamed from "type" -- the breaking change
        AccountStatus status,
        BigDecimal balance,
        BigDecimal availableBalance,    // new field
        String currency                 // new field
) {}
```

Create `AccountControllerV2.java` in the `controller` package:

```java
package com.example.bank.controller;

import com.example.bank.model.AccountV2;
import com.example.bank.service.AccountService;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.stream.Collectors;

// Version prefix changes to v2 at the class level.
// No version-branching logic inside any method.
// The version is an address, not a condition.
@RestController
@RequestMapping("/api/v2/accounts")
public class AccountControllerV2 {

    private final AccountService accountService;

    public AccountControllerV2(AccountService accountService) {
        this.accountService = accountService;
    }

    @GetMapping
    public List<AccountV2> getAll() {
        // TODO 16: Call accountService.findAll() and map each Account to AccountV2:
        //   - accountNumber, customerId, status, balance map directly
        //   - "type" -> "accountType"
        //   - availableBalance = balance (for the lab, they are the same number)
        //   - currency = "USD"
    }

    @GetMapping("/{accountNumber}")
    public AccountV2 getByAccountNumber(@PathVariable String accountNumber) {
        // TODO 17: Call accountService.findByAccountNumber(accountNumber) --
        // it throws AccountNotFoundException directly (after Exercise 4),
        // so no Optional handling is required.
        // Map the returned Account to AccountV2 the same way.
    }
}
```

### Task 5.2: Deprecation Headers for v1

The v1 controllers should signal their deprecation to well-written clients. Add a `@ModelAttribute` method to `AccountController` (v1) that adds deprecation headers to every response.

```java
// Add to AccountController (the v1 controller)

import jakarta.servlet.http.HttpServletResponse;

// @ModelAttribute methods without a return value are executed before every
// request-handling method in the same controller class.
// This is the correct place to add headers that should appear on every response.
@ModelAttribute
public void addDeprecationHeaders(HttpServletResponse response) {
    // TODO 18: Add these three headers to every v1 response:
    //   Deprecation: true
    //   Sunset: Sat, 01 Nov 2026 00:00:00 GMT
    //   Link: </api/v2/accounts>; rel="successor-version"
}
```

### Task 5.3: Verify Both Versions

Add to `requests.http`:

```http
### v1 endpoint -- should include Deprecation and Sunset headers in the response
GET http://localhost:8080/api/v1/accounts

### v2 endpoint -- response body has "accountType" instead of "type"
###                and includes "availableBalance" and "currency"
GET http://localhost:8080/api/v2/accounts
```

Restart and execute both requests. In the v1 response, expand the response headers panel and verify `Deprecation: true` is present. In the v2 response, verify the body uses `accountType` rather than `type` and contains the two new fields.

### Task 5.4: The Version Increment Decision

For each change listed below, decide: does this change require a new version increment (v3), or is it non-breaking and can be made to v2 without a bump? Write your reasoning as a comment in a new file `VERSION_NOTES.md` in the project root.

| Proposed change | Breaking? |
|---|---|
| Add an optional `nickname` field to the v2 account response | ? |
| Remove the `currency` field from the v2 account response | ? |
| Change `balance` from `BigDecimal` to `String` in the v2 response | ? |
| Make the `amount` field on the transaction POST body required (currently could be null) | ? |
| Add a new endpoint `GET /api/v2/accounts/{n}/statements` | ? |
| Rename the error code `INSUFFICIENT_FUNDS` to `BALANCE_TOO_LOW` | ? |
| Add a new `TransactionType.FEE` value that can be returned in `GET /transactions` responses | ? |

### Checkpoints

1. The v2 controller is a new class (`AccountControllerV2`) rather than a modified version of `AccountController`. Why is this the correct design? What would be wrong with adding an `if (version == 2)` branch inside the existing controller?
2. The `Sunset` header communicates a specific date. What obligation does setting this header create for the team that owns the API? In a banking context, who specifically needs to be notified before that date?
3. Adding a new field to a response is listed as potentially non-breaking. Under what condition does it become breaking? What does this imply about how well-written banking clients should deserialize JSON?
4. Why must the error code contract (`INSUFFICIENT_FUNDS`, `ACCOUNT_NOT_OPEN`) be versioned alongside the success response contract?

---

## Summary and Reflection

After completing all five exercises, you have built a versioned, layered Spring Boot REST API for a small retail-banking service with structured error handling and environment-aware configuration. The table below maps each exercise back to the core concepts from the module:

| Exercise | Concept | Key Insight |
|---|---|---|
| 1 – Layered Architecture | `@RestController`, `@Service`, constructor injection, records, sealed types | Each layer has one responsibility; HTTP concerns do not reach the service layer; immutable records make state changes explicit |
| 2 – Configuration & Profiles | `application.yml`, `@ConfigurationProperties`, profile overlays | Configuration is externalised, typed, and environment-aware without code changes |
| 3 – URL & HTTP Method Design | Resource-oriented URLs, sub-resources, idempotency, pattern matching on sealed types | URLs identify resources; HTTP methods carry semantics; the sealed hierarchy makes the transaction switch exhaustive at compile time |
| 4 – Status Codes & Error Contract | `@ControllerAdvice`, `@ExceptionHandler`, RFC 7807 | Status codes are a contract, not a detail; the 200-with-error pattern blinds every layer that depends on them |
| 5 – Versioning | URL path versioning, breaking changes, deprecation headers | Version from day one; a v2 controller is a new class, not a modified v1 controller |

### Final Reflection Questions

Take 10 minutes to answer these before your next session:

1. A colleague argues that `@ControllerAdvice` is over-engineering and that it is simpler for each controller method to catch its own exceptions and return the appropriate `ResponseEntity`. What production problems does the centralized approach prevent that the inline approach does not? Frame your answer with a banking example.

2. Your service currently stores data in `ConcurrentHashMap`s. A future module will replace these with an Oracle database. Which classes will need to change? Which will not? Does the layered architecture make this replacement easier or harder, and why?

3. A customer reports that a `POST /accounts/ACC-1001/transactions` sometimes results in two identical debits being applied to their account. Based on what you know about idempotency and the idempotency-key pattern, what would you add to the API contract to allow clients (mobile banking apps, ATM controllers) to retry safely?

4. Your capstone will extend this code with persistence, authentication, and event publishing. Looking at the structure you have built, which of the three layers do you expect to change the most when these capabilities are added? Which the least? Why?

---
