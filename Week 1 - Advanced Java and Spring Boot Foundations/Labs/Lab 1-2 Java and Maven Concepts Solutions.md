# Module 1: Advanced Java 17 for Enterprise Development
## Solutions and Answer Key

> **How to use this file:** Attempt every task and checkpoint question independently before consulting these solutions. Reading a solution without first attempting the problem significantly reduces the learning value. If your code compiles, runs, and produces the expected output, it is correct even if the wording or style differs from what is shown here.

---

## Exercise 1 - Records and Immutability

### Task 1.1 - RecordDemo.java (completed)

```java
package com.example.records;

public class RecordDemo {

    public static void main(String[] args) {

        Product laptop = new Product("P001", "Laptop Pro", 1299.99, 42);

        // TODO 1: Print the product using its auto-generated toString()
        System.out.println(laptop);
        // Output: Product[id=P001, name=Laptop Pro, price=1299.99, stockLevel=42]

        // TODO 2: Access individual fields using their accessor methods
        System.out.println("Name: " + laptop.name());
        System.out.println("Price: " + laptop.price());

        // TODO 3: Demonstrate value equality
        Product laptopCopy = new Product("P001", "Laptop Pro", 1299.99, 42);
        System.out.println("Are they equal? " + laptop.equals(laptopCopy));   // true
        System.out.println("Same reference? " + (laptop == laptopCopy));       // false
    }
}
```

**Expected output:**
```
Product[id=P001, name=Laptop Pro, price=1299.99, stockLevel=42]
Name: Laptop Pro
Price: 1299.99
Are they equal? true
Same reference? false
```

---

### Task 1.2 - RecordDemo.java (validation additions)

```java
// TODO 4: Attempt to create a Product with a negative price
try {
    Product invalid = new Product("P002", "Broken Item", -5.00, 10);
} catch (IllegalArgumentException e) {
    System.out.println("Caught: " + e.getMessage());
}
// Output: Caught: Price must be non-negative, got: -5.0

// TODO 5: Attempt to create a Product with a null id
try {
    Product invalid = new Product(null, "No ID Product", 10.00, 5);
} catch (IllegalArgumentException e) {
    System.out.println("Caught: " + e.getMessage());
}
// Output: Caught: Product id must not be blank
```

---

### Task 1.3 - RecordDemo.java (wither pattern)

```java
// TODO 6: Create a product, apply a price reduction, confirm original is unchanged
Product original = new Product("P003", "Wireless Headset", 249.99, 100);
Product discounted = original.withPrice(199.99);

System.out.println("Original:   " + original);
System.out.println("Discounted: " + discounted);
```

**Expected output:**
```
Original:   Product[id=P003, name=Wireless Headset, price=249.99, stockLevel=100]
Discounted: Product[id=P003, name=Wireless Headset, price=199.99, stockLevel=100]
```

---

### Exercise 1 Checkpoint Answers

**1. Why do records enforce immutability, and how does this affect how you model data updates?**

Records enforce immutability because all their fields are `private final` The compiler generates no setters and the values assigned at construction cannot be changed. This is by design because a record is intended to be a transparent, stable snapshot of data at a point in time.

The consequence for modeling updates is that you cannot modify a record in place. Instead, you create a new record instance with the changed value and leave the original untouched. The wither pattern (`withPrice`, `withStockLevel`) formalizes this: each method constructs and returns a new record, copying all unchanged fields from `this`. This approach eliminates entire classes of bugs caused by shared mutable state, because any code holding a reference to the original record is guaranteed its view of the data has not changed.

**2. What is the difference between a compact constructor and a regular constructor in a record?**

A regular constructor in a record includes a full parameter list and must explicitly assign `this.field = parameter` for every component. A compact constructor omits the parameter list entirely; the parameters are implicitly in scope using their names, and the field assignments happen automatically after the constructor body completes. You write only the validation or normalization logic that needs to run before the assignments, without repeating the assignments themselves. This makes compact constructors significantly less verbose and eliminates the risk of forgetting to assign a field.

**3. When would you NOT use a record?**

Three common situations:

- **Mutable state:** If a class needs fields that change after construction. For example, for a mutable session object that tracks accumulated state, a record is not appropriate. Records are immutable by design.
- **Inheritance hierarchies:** Records cannot extend other classes because they implicitly extend `java.lang.Record`. They cannot be extended themselves. If you need a class to participate in an inheritance hierarchy as either a parent or a child, use a regular class.
- **JPA entities:** JPA requires a no-argument constructor, and it manages the lifecycle of entity objects by mutating their fields directly after construction. Records provide neither, making them incompatible with JPA as entity types. Use records for DTOs that carry data to and from the persistence layer, but not for the entities themselves.

---

## Exercise 2 - Sealed Classes and Pattern Matching

### Task 2.2 - PaymentResultProcessor.java (describe method completed)

```java
package com.example.sealed;

public class PaymentResultProcessor {

    public String describe(PaymentResult result) {
        if (result instanceof PaymentResult.Approved a) {
            return "Payment of $" + a.amount() + " approved. Transaction: " + a.transactionId();

        } else if (result instanceof PaymentResult.Declined d) {
            return "Declined (code " + d.declineCode() + "): " + d.reason();

        } else if (result instanceof PaymentResult.Pending p) {
            return "Pending - Ref: " + p.referenceId() + ". " + p.message();

        } else {
            throw new IllegalStateException("Unhandled PaymentResult type: " + result.getClass());
        }
    }

    public static void main(String[] args) {
        var processor = new PaymentResultProcessor();

        var results = new PaymentResult[] {
            new PaymentResult.Approved("TXN-9921", 450.00),
            new PaymentResult.Declined("Insufficient funds", 51),
            new PaymentResult.Pending("REF-7744", "Awaiting bank confirmation")
        };

        for (PaymentResult r : results) {
            System.out.println(processor.describe(r));
        }
    }
}
```

**Expected output:**
```
Payment of $450.0 approved. Transaction: TXN-9921
Declined (code 51): Insufficient funds
Pending - Ref: REF-7744. Awaiting bank confirmation
```

---

### Task 2.3 - describe method with high-value logic (completed)

```java
public String describe(PaymentResult result) {
    if (result instanceof PaymentResult.Approved a) {
        if (a.amount() > 10_000) {
            return "HIGH-VALUE approval of $" + a.amount() + " - Transaction: " + a.transactionId();
        } else {
            return "Approval of $" + a.amount() + " - Transaction: " + a.transactionId();
        }

    } else if (result instanceof PaymentResult.Declined d) {
        return "Declined (code " + d.declineCode() + "): " + d.reason();

    } else if (result instanceof PaymentResult.Pending p) {
        return "Pending - Ref: " + p.referenceId() + ". " + p.message();

    } else {
        throw new IllegalStateException("Unhandled PaymentResult type: " + result.getClass());
    }
}
```

```java
// TODO 8: Add to main()
var highValue = new PaymentResult.Approved("TXN-8800", 25_000.00);
System.out.println(processor.describe(highValue));
// Output: HIGH-VALUE approval of $25000.0 - Transaction: TXN-8800
```

---

### Task 2.4 - isHighValueApproval and TODO 10 (completed)

```java
// TODO 9
public boolean isHighValueApproval(PaymentResult result) {
    return result instanceof PaymentResult.Approved a && a.amount() > 10_000;
}
```

```java
// TODO 10: Add to main()
var standard  = new PaymentResult.Approved("TXN-9921", 450.00);
var declined  = new PaymentResult.Declined("Insufficient funds", 51);
var pending   = new PaymentResult.Pending("REF-7744", "Awaiting bank confirmation");
var highValue = new PaymentResult.Approved("TXN-8800", 25_000.00);

System.out.println(processor.isHighValueApproval(standard));   // false
System.out.println(processor.isHighValueApproval(declined));   // false
System.out.println(processor.isHighValueApproval(pending));    // false
System.out.println(processor.isHighValueApproval(highValue));  // true
```

---

### Exercise 2 Checkpoint Answers

**1. What compile-time advantage do sealed classes provide over a plain interface when writing an exhaustive instanceof chain?**

With a plain interface, the compiler has no way of knowing how many implementations exist. Anyone in any package could add one at any time. An `instanceof` chain over a plain interface can never be verified as exhaustive by the compiler, and the IDE can only guess at completeness.

With a sealed interface, the compiler knows the complete list of permitted subtypes at compile time. IDEs like IntelliJ can therefore warn you immediately when your `instanceof` chain does not cover all permitted subtypes, and if you use a switch expression over a sealed type in Java 21, the compiler enforces exhaustiveness as a hard error. In Java 17, the sealed declaration still gives your IDE the information it needs to flag gaps as warnings, and it communicates the design intent unambiguously to anyone reading the code.

**2. The final else branch throws an IllegalStateException. When would it ever execute, and what does its presence tell a reader of the code?**

It should never execute as long as the `instanceof` chain covers every permitted subtype of the sealed interface. The sealed declaration guarantees that no other subtypes can exist at runtime.

However, its presence communicates something important: the author has thought about completeness and has made the gap explicit rather than silently returning `null` or an empty string. 

If a future developer adds a new permitted subtype to `PaymentResult` and forgets to update `describe`, the method will throw immediately on the first call with the new type, It converts a potential logic bug into an immediate runtime exception with a clear message, which is far easier to diagnose.

**3. Why is the combined instanceof and && expression guaranteed to be null-safe?**

`instanceof` always returns `false` when the left-hand operand is `null`. If `result` is null, the `instanceof PaymentResult.Approved a` check evaluates to `false`, and because `&&` short-circuits, the right-hand side (`a.amount() > 10_000`) is never evaluated. The pattern variable `a` is only bound and in scope when the `instanceof` check succeeds, which cannot happen for a null reference. This means you never need a separate null check before using the pattern variable.

---

## Exercise 3 - Streams and Functional Programming

### Task 3.1 - StreamDemo.java (TODO 10 completed)

```java
List<String> highValueCompleted = orders.stream()
        .filter(o -> "COMPLETED".equals(o.status()))
        .filter(o -> o.totalAmount() > 500.00)
        .map(Order::orderId)
        .collect(Collectors.toList());

System.out.println("High-value completed order IDs: " + highValueCompleted);
```

**Expected output:**
```
High-value completed order IDs: [O001, O006, O008]
```

---

### Task 3.2 - Aggregation (TODO 11 completed)

```java
double totalRevenue = orders.stream()
        .filter(o -> "COMPLETED".equals(o.status()))
        .mapToDouble(Order::totalAmount)
        .sum();

long pendingCount = orders.stream()
        .filter(o -> "PENDING".equals(o.status()))
        .count();

OptionalDouble averageOrderValue = orders.stream()
        .mapToDouble(Order::totalAmount)
        .average();

System.out.printf("Total revenue (COMPLETED): $%.2f%n", totalRevenue);
System.out.println("Pending order count: " + pendingCount);
averageOrderValue.ifPresent(avg -> System.out.printf("Average order value: $%.2f%n", avg));
```

**Expected output:**
```
Total revenue (COMPLETED): $4719.49
Pending order count: 2
Average order value: $649.31
```

---

### Task 3.3 - Grouping (TODO 12 and TODO 13 completed)

```java
// TODO 12
Map<String, List<Order>> byCategory = orders.stream()
        .collect(Collectors.groupingBy(Order::category));

byCategory.forEach((category, categoryOrders) ->
        System.out.println(category + ": " + categoryOrders.size() + " order(s)"));

// TODO 13
Map<String, Double> revenueByCategory = orders.stream()
        .collect(Collectors.groupingBy(
                Order::category,
                Collectors.summingDouble(Order::totalAmount)
        ));

revenueByCategory.forEach((cat, rev) ->
        System.out.printf("%-15s $%.2f%n", cat, rev));
```

**Expected output:**
```
CLOTHING: 2 order(s)
BOOKS: 2 order(s)
ELECTRONICS: 4 order(s)
CLOTHING        $197.50
BOOKS           $56.99
ELECTRONICS     $4939.99
```

> Note: Map iteration order is not guaranteed. Your category order may differ but the values will be the same.

---

### Task 3.4 - FlatMap (TODO 14 completed)

```java
List<String> allSkus = carts.stream()
        .flatMap(cart -> cart.itemSkus().stream())
        .collect(Collectors.toList());

List<String> distinctSkus = carts.stream()
        .flatMap(cart -> cart.itemSkus().stream())
        .distinct()
        .sorted()
        .collect(Collectors.toList());

System.out.println("All SKUs (with duplicates): " + allSkus);
System.out.println("Distinct SKUs sorted: " + distinctSkus);
```

**Expected output:**
```
All SKUs (with duplicates): [SKU-A, SKU-B, SKU-C, SKU-B, SKU-D, SKU-A, SKU-E]
Distinct SKUs sorted: [SKU-A, SKU-B, SKU-C, SKU-D, SKU-E]
```

---

### Task 3.5 - Antipattern rewrite (TODO 15 completed)

```java
// The antipattern mutates a list defined outside the stream.
// The correct stream version uses collect():
List<String> idsCorrect = orders.stream()
        .filter(o -> o.totalAmount() > 100)
        .map(Order::orderId)
        .collect(Collectors.toList());

// The equivalent loop version (equally correct):
List<String> idsLoop = new ArrayList<>();
for (Order o : orders) {
    if (o.totalAmount() > 100) {
        idsLoop.add(o.orderId());
    }
}
```

---

### Exercise 3 Checkpoint Answers

**1. What is the difference between an intermediate and a terminal operation? Give two examples of each.**

An **intermediate** operation transforms a stream into another stream. It is lazy, meaning that it does not execute until a terminal operation is invoked. Examples: `filter()` (removes elements that do not match a predicate) and `map()` (transforms each element to a new value).

A **terminal** operation consumes the stream and produces a result or a side effect. It triggers the execution of all the intermediate operations in the pipeline. Examples: `collect()` (assembles elements into a collection or other container) and `count()` (returns the number of elements).

A stream pipeline must have exactly one terminal operation. Without one, no intermediate operations execute at all.

**2. Why is mutating a variable from outside the stream inside a forEach or map an antipattern?**

Streams are designed for pipelines where each step transforms data without side effects. Mutating an external variable inside a lambda breaks this model in two ways.

First, it makes the code harder to reason about. The whole point of a stream pipeline is that you can read it top to bottom and understand what it produces. When a lambda has a hidden side effect on an external variable, the behavior of the pipeline is no longer self-contained.

Second, it is dangerous in parallel streams. If `stream()` is changed to `parallelStream()` multiple threads will call the lambda concurrently. Mutating an `ArrayList` from multiple threads simultaneously causes data corruption. Using `collect()` is thread-safe because the Streams framework manages the accumulation correctly in both sequential and parallel contexts.

**3. Give two scenarios where a plain for loop is preferable to a stream pipeline.**

- **Early exit on a condition:** A `for` loop with `break` is cleaner than `findFirst()` when the intent is simply "find the first element matching a condition and stop." The loop version is immediately readable to any developer regardless of their Streams familiarity.
- **Complex stateful logic across elements:** When each iteration depends on the result of the previous one. For example, computing a running total or building a result that accumulates across elements in a non-trivial way. A loop expresses this more clearly. Streams are designed for independent, element-by-element transformations. Forcing stateful accumulation into a stream makes the code harder to follow than the equivalent loop.

---

## Exercise 4 - Switch Expressions

### Task 4.1 - baseShippingFee (TODO 16 completed)

```java
public double baseShippingFee(ShippingTier tier) {
    return switch (tier) {
        case STANDARD  -> 4.99;
        case EXPRESS   -> 12.99;
        case OVERNIGHT -> 24.99;
        case SAME_DAY  -> 39.99;
    };
}
```

---

### Task 4.2 - discountRate (TODO 17 completed)

```java
public double discountRate(ShippingTier tier, double orderTotal) {
    return switch (tier) {
        case STANDARD, EXPRESS -> 0.0;

        case OVERNIGHT -> {
            if (orderTotal > 200) {
                yield 0.10;
            } else {
                yield 0.05;
            }
        }

        case SAME_DAY -> {
            if (orderTotal > 500) {
                yield 0.15;
            } else {
                yield 0.08;
            }
        }
    };
}
```

### Task 4.3 - Expected output

```
STANDARD   base=$4.99  discount=0%  final=$4.99
EXPRESS    base=$12.99  discount=0%  final=$12.99
OVERNIGHT  base=$24.99  discount=10%  final=$22.49
SAME_DAY   base=$39.99  discount=8%  final=$36.79
```

> With `orderTotal = 350.00`: OVERNIGHT qualifies for 10% (350 > 200). SAME_DAY gets 8% (350 is not > 500).

---

### Exercise 4 Checkpoint Answers

**1. What prevents fall-through in switch expressions?**

The arrow (`->`) syntax. In a traditional switch statement, each `case` falls through to the next unless terminated with `break`. In a switch expression, every arm is terminated by the arrow itself and execution does not continue to the next case. There is no `break` required and no fall-through possible. Multiple labels can share a single arm (`case STANDARD, EXPRESS -> 0.0`) but that is a deliberate grouping, not accidental fall-through.

**2. When is yield required vs when can you use the arrow directly?**

The arrow (`->`) can be used when the entire result is a single expression: `case STANDARD -> 4.99`. When the case arm needs multiple statements. For example, an `if/else` to compute the result, you use a block `{ }` and `yield` to specify the value that the block produces: `case OVERNIGHT -> { if (...) yield 0.10; else yield 0.05; }`. Think of `yield` as the `return` statement for a switch block case.

**3. What happens at compile time if you add a new constant to the enum and forget to handle it in the switch expression?**

The compiler produces an error: the switch expression is not exhaustive. Unlike a traditional switch statement, a switch expression must cover every possible value of the type it switches on, because it must always produce a value. Adding `ECONOMY` to `ShippingTier` without adding a corresponding case arm causes a compile error on the switch expression immediately, before any code can run. This is one of the primary safety advantages of switch expressions over switch statements.

---

## Exercise 5 - Maven Fundamentals

### Task 5.1 - Annotated pom.xml

```xml
<project>
    <!--
        groupId:    Identifies your organisation or project group, typically a reversed domain name.
        artifactId: The name of this specific module or deliverable.
        version:    The current version. SNAPSHOT means it is still in development.
        Together these three form the artifact's "coordinates" -- the globally unique
        address used by Maven to locate and cache this artifact in any repository.
    -->
    <groupId>com.example</groupId>
    <artifactId>my-service</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <properties>
        <!--
            Declaring compiler versions as properties rather than directly in the
            plugin configuration means they can be inherited, overridden in child
            modules, or referenced elsewhere in the POM using ${maven.compiler.source}.
            It also keeps the version information in one place for the whole project.
        -->
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.2</version>
            <!--
                scope=test: this jar is placed on the classpath only during
                test compilation and test execution. It is excluded from the
                final packaged JAR, keeping production artifacts free of
                test frameworks.
            -->
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
```

---

### Task 5.2 - Corrected AppTest.java

```java
package com.example;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AppTest {

    @Test
    void appShouldWork() {
        assertTrue(true);
    }
}
```

### Task 5.2 - Final pom.xml

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>my-service</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>com.fasterxml.jackson.core</groupId>
                <artifactId>jackson-databind</artifactId>
                <version>2.17.1</version>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <dependencies>
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
            <!-- No version here -- inherited from dependencyManagement -->
        </dependency>

        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
            </plugin>
        </plugins>
    </build>
</project>
```

---

### Exercise 5 Checkpoint Answers

**1. What are the four most common Maven dependency scopes and when would you use each one?**

- **compile** (default, no tag required): the dependency is available during compilation, testing, and at runtime in the final artifact. Use for any library your production code directly imports and uses.
- **test**: available only during test compilation and test execution, excluded from the final artifact. Use for testing frameworks (JUnit, Mockito) and test utilities.
- **provided**: available during compilation but not included in the final artifact, because the runtime environment is expected to supply it. Use for the Servlet API in a WAR deployed to an application server, or the Lombok annotation processor.
- **runtime**: not needed for compilation but required at runtime. Use for JDBC drivers -- your code compiles against the JDBC API, but the specific driver implementation is only needed when the application actually runs.

**2. Why does mvn package also run mvn test automatically?**

Maven's build lifecycle is a fixed, ordered sequence of phases. Each phase implies all preceding phases. `package` depends on `test`, which depends on `compile`, which depends on `validate`. Running `mvn package` executes every phase from `validate` through to `package` in order. This is by design -- it ensures you cannot accidentally package code that has not been compiled and tested. To skip tests (not recommended in CI), use the flag `-DskipTests`.

**3. What problem does dependencyManagement solve that ordinary dependencies does not?**

`<dependencies>` puts a library on the classpath immediately -- it is active for the module that declares it. `<dependencyManagement>` is a version and configuration registry only: it declares what version and scope to use for a dependency, but does not activate that dependency for any module. Child modules or sibling modules that need the dependency declare it in their own `<dependencies>` block without specifying a version, inheriting it from the registry.

The problem it solves is version drift across a multi-module project. Without it, ten modules each declaring their own version of the same library will inevitably diverge as developers update some but not others. `<dependencyManagement>` in the parent POM makes version upgrades a one-line change that automatically applies to every module.

**4. What does SNAPSHOT indicate and why does it matter in a team environment?**

`SNAPSHOT` indicates that the version is not stable -- it represents the current state of development and may change at any time. Maven treats SNAPSHOT dependencies differently from release versions: it re-checks the repository for a newer snapshot on every build (or at configurable intervals), whereas a release version is cached permanently once downloaded.

In a team environment this matters because it means a build that passes today may produce different output tomorrow if a snapshot dependency changes. It also means that if module A depends on module B at a SNAPSHOT version, developers working on module B can push changes that immediately affect module A's build without changing any version number. SNAPSHOT versions should never be declared as dependencies in production releases -- before releasing, all SNAPSHOT dependencies must be replaced with stable release versions.

---

## Exercise 6 - Putting It All Together

### Supporting types needed

The `ProductCatalogueService` references a `Product` type with six fields. Add this record to the `com.example.catalogue` package:

```java
package com.example.catalogue;

public record Product(
        String id,
        String name,
        double price,
        int stockLevel,
        String category,
        String status
) {}
```

You also need to add `import java.util.List;` to `SearchResult.java`:

```java
package com.example.catalogue;

import java.util.List;

public sealed interface SearchResult
        permits SearchResult.Success, SearchResult.Empty, SearchResult.InvalidRequest {

    record Success(List<ProductSummary> products, int totalCount) implements SearchResult {}
    record Empty(String reason) implements SearchResult {}
    record InvalidRequest(String validationError) implements SearchResult {}
}
```

---

### Task 6.1 - ProductCatalogueService.java (completed)

```java
package com.example.catalogue;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

public class ProductCatalogueService {

    private final List<Product> products = List.of(
        new Product("P001", "Laptop Pro",        1299.99, 42,  "ELECTRONICS", "ACTIVE"),
        new Product("P002", "USB-C Hub",           45.00, 200, "ELECTRONICS", "ACTIVE"),
        new Product("P003", "Wireless Headset",   249.99,  0,  "ELECTRONICS", "OUT_OF_STOCK"),
        new Product("P004", "Desk Chair",         399.00, 15,  "FURNITURE",   "ACTIVE"),
        new Product("P005", "Monitor Stand",       89.99, 75,  "FURNITURE",   "ACTIVE"),
        new Product("P006", "Mechanical Keyboard", 129.99, 30, "ELECTRONICS", "ACTIVE"),
        new Product("P007", "Legacy Printer",      59.99,  5,  "ELECTRONICS", "DISCONTINUED")
    );

    public SearchResult search(ProductSearchRequest request) {
        Optional<String> validationError = validate(request);
        if (validationError.isPresent()) {
            return new SearchResult.InvalidRequest(validationError.get());
        }

        List<ProductSummary> matches = products.stream()
                .filter(p -> p.category().equalsIgnoreCase(request.category()))
                .filter(p -> p.price() >= request.minPrice() && p.price() <= request.maxPrice())
                .filter(p -> request.status() == null || request.status().isBlank()
                        || p.status().equalsIgnoreCase(request.status()))
                .map(p -> new ProductSummary(p.id(), p.name(), p.price(), p.category()))
                .collect(Collectors.toList());

        if (matches.isEmpty()) {
            return new SearchResult.Empty(
                    "No products found in category '" + request.category() +
                    "' within price range $" + request.minPrice() + " - $" + request.maxPrice());
        }

        return new SearchResult.Success(matches, matches.size());
    }

    private Optional<String> validate(ProductSearchRequest request) {
        if (request.category() == null || request.category().isBlank()) {
            return Optional.of("category must not be blank");
        }
        if (request.minPrice() < 0) {
            return Optional.of("minPrice must be >= 0");
        }
        if (request.maxPrice() <= request.minPrice()) {
            return Optional.of("maxPrice must be greater than minPrice");
        }
        return Optional.empty();
    }
}
```

---

### Task 6.2 - CatalogueDemo.java (completed)

```java
package com.example.catalogue;

import java.util.stream.Collectors;

public class CatalogueDemo {

    public static void main(String[] args) {
        var service = new ProductCatalogueService();

        var result1 = service.search(new ProductSearchRequest("ELECTRONICS", 50.00, 300.00, "ACTIVE"));
        System.out.println("Test 1: " + describeResult(result1));

        var result2 = service.search(new ProductSearchRequest("ELECTRONICS", 500.00, 100.00, null));
        System.out.println("Test 2: " + describeResult(result2));

        var result3 = service.search(new ProductSearchRequest("FURNITURE", 1000.00, 5000.00, "ACTIVE"));
        System.out.println("Test 3: " + describeResult(result3));
    }

    private static String describeResult(SearchResult result) {
        if (result instanceof SearchResult.Success s) {
            return "Found " + s.totalCount() + " product(s): " +
                    s.products().stream().map(ProductSummary::name).collect(Collectors.joining(", "));

        } else if (result instanceof SearchResult.Empty e) {
            return "No results: " + e.reason();

        } else if (result instanceof SearchResult.InvalidRequest i) {
            return "Bad request: " + i.validationError();

        } else {
            throw new IllegalStateException("Unhandled SearchResult type: " + result.getClass());
        }
    }
}
```

**Expected output:**
```
Test 1: Found 2 product(s): USB-C Hub, Mechanical Keyboard
Test 2: Bad request: maxPrice must be greater than minPrice
Test 3: No results: No products found in category 'FURNITURE' within price range $1000.0 - $5000.0
```

---

### Exercise 6 Checkpoint Answers

**1. How does using a sealed SearchResult type improve the contract between the service and its callers compared to throwing exceptions or returning null?**

Throwing exceptions and returning null both require the caller to know about error states through documentation or convention rather than through the type system. A caller that forgets to check for null or does not catch the right exception compiles and runs fine until it encounters the missing case at runtime.

A sealed `SearchResult` type encodes every possible outcome directly in the return type. The caller receives a `SearchResult` and must handle `Success`, `Empty`, and `InvalidRequest` to do anything useful with it. This makes the contract explicit and visible without reading documentation. With the `instanceof` chain, the IDE will warn if a permitted subtype is not handled. The three outcomes are first-class values, not exceptional control flow, which means they can be logged, passed around, returned from another method, or stored -- none of which is practical with exceptions.

**2. The search method accepts a ProductSearchRequest record. What advantages does this give you over accepting five separate method parameters?**

Passing five separate parameters creates a fragile method signature. Adding a sixth parameter is a breaking change that requires every call site to be updated. Parameters of the same type (for example, two `String` parameters for `category` and `status`) can be silently swapped by a caller, and the compiler will not catch it.

A `ProductSearchRequest` record groups all the search criteria into a named, self-documenting object. Adding a new search criterion means adding a field to the record rather than changing the method signature. The field names make the intent explicit at every call site (`new ProductSearchRequest("ELECTRONICS", 50.00, 300.00, "ACTIVE")` is still readable). The record also provides `equals()` and `toString()` for free, which is useful for logging and testing. Validation logic can be centralised on the request object itself using a compact constructor.

**3. Could you replace the filter/map steps with a single for loop? Which approach do you prefer and why?**

Yes, a loop would produce identical results:

```java
List<ProductSummary> matches = new ArrayList<>();
for (Product p : products) {
    if (p.category().equalsIgnoreCase(request.category())
            && p.price() >= request.minPrice()
            && p.price() <= request.maxPrice()
            && (request.status() == null || request.status().isBlank()
                || p.status().equalsIgnoreCase(request.status()))) {
        matches.add(new ProductSummary(p.id(), p.name(), p.price(), p.category()));
    }
}
```

The stream version is preferable here for two reasons. First, the pipeline expresses each filtering criterion as a separate, named step -- each `filter` call is independently readable and independently modifiable. The loop version combines all conditions into one compound boolean expression that is harder to scan. Second, the stream version makes the intent explicit: filter, then transform, then collect. The loop conflates all three steps inside a single block.

The loop would be preferable if the filtering logic were stateful -- for example, if you needed to carry information from one iteration into the next -- or if the logic were so simple that a single line `for` with `break` captured the intent more directly than a pipeline.

---

## Final Reflection Answers

**1. You are designing a REST API response type that can represent either a successful payload, a validation error, or a server-side failure. How would you model this using the features from this module?**

Use a sealed interface with three permitted record subtypes -- exactly the same pattern as `SearchResult`:

```java
public sealed interface ApiResponse<T>
        permits ApiResponse.Ok, ApiResponse.ValidationError, ApiResponse.ServerError {

    record Ok<T>(T body) implements ApiResponse<T> {}
    record ValidationError<T>(String field, String message) implements ApiResponse<T> {}
    record ServerError<T>(String errorCode, String detail) implements ApiResponse<T> {}
}
```

The generic type `T` allows the same response wrapper to carry different payload types for different endpoints. Controllers dispatch on the result using an `instanceof` chain and map each subtype to the appropriate HTTP status code: `Ok` -> 200, `ValidationError` -> 400, `ServerError` -> 500. This keeps error handling explicit, type-safe, and co-located with the response model rather than scattered across exception handlers.

**2. A colleague writes a Stream pipeline that calls .forEach() to populate a List defined outside the stream. How would you explain the problem and demonstrate the correct approach?**

The problem is that the lambda passed to `forEach` has a side effect on a variable defined outside the stream. This violates the stream's contract that lambdas should be stateless and non-interfering. The practical consequences are: the code is misleading (a stream pipeline should produce a value, not silently mutate an external variable), it breaks immediately if someone switches to `parallelStream()` because `ArrayList` is not thread-safe, and it cannot be composed or reused as a building block in a larger pipeline.

The correct approach is to let the stream own its output using `collect()`:

```java
// Wrong
List<String> ids = new ArrayList<>();
orders.stream()
      .filter(o -> o.totalAmount() > 100)
      .forEach(o -> ids.add(o.orderId()));

// Correct
List<String> ids = orders.stream()
      .filter(o -> o.totalAmount() > 100)
      .map(Order::orderId)
      .collect(Collectors.toList());
```

**3. You see a dependency with scope=provided. What do you think it means?**

Based on the pattern of the other scopes: `provided` means the dependency is needed to compile the code but will not be included in the final artifact, because the environment where the code runs is expected to supply it.

This is correct. The name comes from "provided by the container." The canonical example is the Jakarta Servlet API in a web application: your code compiles against `HttpServletRequest`, `HttpServletResponse`, and so on, but the servlet container (Tomcat, Jetty) ships those classes itself. Including them in your WAR would create a conflict. Declaring the dependency `provided` gives the compiler what it needs without bundling the classes into the output.

---

*End of Module 1 Solutions*
