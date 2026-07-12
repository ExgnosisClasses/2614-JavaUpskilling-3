Lab 1-2 : Java and Maven Concepts 
## Hands-On Exercises

> **Course:** MD282 - Java Full-Stack Development  
> **Module:** 1 - Advanced Java for Enterprise Development  
> **Estimated time per exercise:** 30-60 minutes

---

## How to Use These Exercises

Each exercise is self-contained and builds on the concepts introduced in the module lectures. They are designed to be completed in IntelliJ IDEA using the Java 17 SDK. You will find:

- **Context** - why this feature exists and when to reach for it
- **Instructions** - step-by-step tasks to complete
- **Starter code** - copy this into IntelliJ to begin
- **Checkpoints** - questions to verify your understanding
- **Extension tasks** - optional challenges for faster learners

> **Tip:** Resist the urge to look ahead. Try to make the code compile and pass the checks on your own before reading the hints.

---

## Exercise 1 - Records and Immutability

**Estimated time:** 30-45 minutes  
**Topics covered:** Records, immutability, compact constructors, `with`-style copy patterns

### Context

In enterprise Java applications, a large proportion of classes exist purely to carry data between layers: from the database to a service, from a service to a controller, and from a controller to a client. Historically, writing these classes required a significant amount of repetitive boilerplate: private fields, a constructor, getters, `equals()`, `hashCode()`, and `toString()`. The Java 16 `record` keyword eliminates all of that boilerplate while enforcing immutability by design.

Records are not simply a syntax shortcut. They communicate intent: a `record` tells any reader of the code that this type is a transparent, immutable carrier of data, nothing more and nothing less. This makes them ideal for Data Transfer Objects (DTOs), value objects, and API response/request models.

### Setup

Create a new **Maven** project in IntelliJ (File -> New -> Project -> Maven Archetype -> `maven-archetype-quickstart`, SDK 17). Using a Maven project ensures that `src/main/java` is automatically configured as the source root, which is required for package declarations to resolve correctly.

Once the project is created, set the compiler source and target to 17 in `pom.xml`:

```xml
<properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
</properties>
```

Then create the `com.example.records` package by right-clicking `src/main/java` in the Project tool window and selecting **New -> Package**, typing `com.example.records`. The resulting structure on disk will be:

```
src/
  main/
    java/            <-- source root (marked blue in IntelliJ)
      com/
        example/
          records/   <-- package com.example.records
```

> **Why this matters:** The `package` declaration in a Java file must match the directory path *relative to the source root*, not relative to the project root. With `src/main/java` as the source root, a file at `src/main/java/com/example/records/Product.java` correctly maps to `package com.example.records`. If `src` were the source root instead, the compiler would expect the declaration to be `package main.java.com.example.records`, which is not a valid package name for production code.

### Task 1.1 - Your First Record

Create a file `Product.java` in the `records` package:

```java
package com.example.records;

// A record automatically generates:
//   - private final fields for each component
//   - a canonical constructor
//   - public accessor methods (no "get" prefix -- just name())
//   - equals(), hashCode(), and toString()

public record Product(String id, String name, double price, int stockLevel) {
}
```

Now create `RecordDemo.java` to explore the record:

```java
package com.example.records;

public class RecordDemo {

    public static void main(String[] args) {

        Product laptop = new Product("P001", "Laptop Pro", 1299.99, 42);

        // TODO 1: Print the product using its auto-generated toString()
        System.out.println(laptop);

        // TODO 2: Access individual fields using their accessor methods
        // Note: accessors in records match the field name exactly -- laptop.name(), NOT laptop.getName()
        System.out.println("Name: " + laptop.name());
        System.out.println("Price: " + laptop.price());

        // TODO 3: Demonstrate value equality
        Product laptopCopy = new Product("P001", "Laptop Pro", 1299.99, 42);
        System.out.println("Are they equal? " + laptop.equals(laptopCopy));   // should be true
        System.out.println("Same reference? " + (laptop == laptopCopy));       // should be false
    }
}
```

Run the program and verify the output. Notice that you got `equals()` and `toString()` for free.

### Task 1.2 - Compact Constructors for Validation

Records can include a *compact constructor* (a constructor body without the parameter list) to validate or normalize data before it is stored. The field assignments still happen automatically after the compact constructor body runs.

```java
package com.example.records;

public record Product(String id, String name, double price, int stockLevel) {

    // Compact constructor: validates inputs before the fields are assigned.
    // You do NOT re-assign this.id, this.name, etc. -- that happens automatically.
    public Product {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("Product id must not be blank");
        }
        if (price < 0) {
            throw new IllegalArgumentException("Price must be non-negative, got: " + price);
        }
        if (stockLevel < 0) {
            throw new IllegalArgumentException("Stock level must be non-negative");
        }
        // Normalize the name so it is always trimmed
        name = name == null ? "" : name.trim();
    }
}
```

Update `RecordDemo.main()` to test validation:

```java
// TODO 4: Attempt to create a Product with a negative price.
// Wrap it in a try/catch and print the exception message.
try {
    Product invalid = new Product("P002", "Broken Item", -5.00, 10);
} catch (IllegalArgumentException e) {
    System.out.println("Caught: " + e.getMessage());
}

// TODO 5: Attempt to create a Product with a null id and observe the result.
```

### Task 1.3 - The "Wither" Pattern (Immutable Updates)

Records are immutable: you cannot change a field after construction. When you need a modified copy, the idiomatic approach is to create a new record from the existing one:

```java
package com.example.records;

public record Product(String id, String name, double price, int stockLevel) {

    public Product {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("Product id must not be blank");
        }
        if (price < 0) {
            throw new IllegalArgumentException("Price must be non-negative, got: " + price);
        }
        if (stockLevel < 0) {
            throw new IllegalArgumentException("Stock level must be non-negative");
        }
        name = name == null ? "" : name.trim();
    }

    // "Wither" methods produce a new Product with one field changed.
    // All other fields are copied from the current instance.
    public Product withPrice(double newPrice) {
        return new Product(this.id, this.name, newPrice, this.stockLevel);
    }

    public Product withStockLevel(int newStockLevel) {
        return new Product(this.id, this.name, this.price, newStockLevel);
    }
}
```

```java
// In RecordDemo.main():

// TODO 6: Create a product, apply a price reduction using withPrice(), 
// and print both the original and the discounted version.
// Confirm the original is unchanged.

Product original = new Product("P003", "Wireless Headset", 249.99, 100);
Product discounted = original.withPrice(199.99);

System.out.println("Original:   " + original);
System.out.println("Discounted: " + discounted);
```

### Checkpoints

Answer these in your own words before moving on:

1. Why do records enforce immutability, and how does this affect how you model data updates?
2. What is the difference between a compact constructor and a regular constructor in a record?
3. When would you **not** use a record? (Think: mutable state, inheritance hierarchies, JPA entities.)

---

## Exercise 2 - Sealed Classes and Pattern Matching

**Estimated time:** 45-60 minutes  
**Topics covered:** Sealed classes, `permits`, pattern matching with `instanceof`, exhaustive type dispatch

### Context

A sealed class defines a closed hierarchy: the compiler knows every class that can extend it. This matters for correctness. Without sealed classes, a chain of `instanceof` checks over a type hierarchy is potentially incomplete: a new subclass added by another developer silently breaks the logic. Sealed classes make the hierarchy explicit and allow the IDE and compiler to flag missing cases.

Pattern matching with `instanceof`, finalized as a standard feature in Java 16, is the primary tool used in these exercises. It lets you test a type and bind the result to a typed variable in a single expression, eliminating the explicit cast that was previously required.

Java 21 introduced pattern matching directly inside `switch` expressions, which produces more concise code when dispatching over a sealed hierarchy. That syntax is covered in the Java 21 module. In Java 17, the same exhaustive dispatch is achieved cleanly using `instanceof` chains, as shown in these exercises.

### Setup

Create a new package `com.example.sealed`.

### Task 2.1 - Modeling a Closed Domain with Sealed Classes

In a payment processing domain, every payment attempt has a definite outcome. Model this with a sealed hierarchy:

```java
package com.example.sealed;

// The sealed interface declares every permitted subtype.
// These subtypes must be in the same package (or same file, or same module).
public sealed interface PaymentResult
        permits PaymentResult.Approved, PaymentResult.Declined, PaymentResult.Pending {

    // Each permitted type is a record -- a concise, immutable data carrier.
    record Approved(String transactionId, double amount) implements PaymentResult {}

    record Declined(String reason, int declineCode) implements PaymentResult {}

    record Pending(String referenceId, String message) implements PaymentResult {}
}
```

### Task 2.2 - Exhaustive Dispatch with instanceof

Create `PaymentResultProcessor.java`. Because `PaymentResult` is sealed, you know at compile time that the only possible subtypes are `Approved`, `Declined`, and `Pending`. The `instanceof` chain below handles all three. If a subtype were ever added to the sealed interface and this method was not updated, the final `else` branch would throw an exception, making the gap immediately visible.

```java
package com.example.sealed;

public class PaymentResultProcessor {

    /**
     * Returns a user-friendly message describing the payment outcome.
     *
     * The instanceof chain is exhaustive because PaymentResult is sealed --
     * the only permitted subtypes are the three handled below.
     */
    public String describe(PaymentResult result) {
        // TODO 7: Complete this method.
        // The first case is provided. Add the remaining two branches
        // for Declined and Pending, accessing their fields via the
        // pattern variable (d and p respectively).

        if (result instanceof PaymentResult.Approved a) {
            return "Payment of $" + a.amount() + " approved. Transaction: " + a.transactionId();

        // TODO: add else-if branch for PaymentResult.Declined d

        // TODO: add else-if branch for PaymentResult.Pending p

        } else {
            // This branch should never be reached while the sealed hierarchy
            // is handled completely above.
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

Run the program and confirm all three results are described correctly.

### Task 2.3 - Conditional Logic Within a Branch

Extend the `describe` method to distinguish between high-value and normal approvals. Because `instanceof` gives you a typed variable, you can add any further conditions using a plain `if` statement inside the branch:

```java
public String describe(PaymentResult result) {
    if (result instanceof PaymentResult.Approved a) {
        // The pattern variable `a` is in scope here.
        // Use a plain if to apply further conditions within the branch.
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
// TODO 8: In main(), add a high-value Approved result and confirm
// the HIGH-VALUE branch fires correctly.
var highValue = new PaymentResult.Approved("TXN-8800", 25_000.00);
System.out.println(processor.describe(highValue));
```

> **Note:** Java 21 introduced pattern matching directly in `switch` expressions using the `case Type variable ->` syntax, along with `when` guard clauses for conditional logic. The `instanceof` chain above is the standard Java 17 equivalent and produces identical behaviour. You will see the switch-based syntax when the course covers Java 21 features.

### Task 2.4 - Single-Type Checks with instanceof

The `instanceof` pattern is also useful when you only care about one specific type and want to take a branch without writing a full dispatch chain:

```java
// TODO 9: Add this method to PaymentResultProcessor.
// It should return true if the result is an Approved payment over $10,000.
// Use a single instanceof check combined with && to test the condition
// in one expression -- no explicit cast and no separate if block required.

public boolean isHighValueApproval(PaymentResult result) {
    // Hint: result instanceof PaymentResult.Approved a && a.amount() > 10_000
    return false; // replace with your implementation
}
```

Add the following to `main()` to verify:

```java
// TODO 10: Test isHighValueApproval against all four results and print each outcome.
// Expected: false, false, false, true (for the highValue result added in Task 2.3)
```

### Checkpoints

1. What compile-time advantage do sealed classes provide over a plain interface when writing an exhaustive `instanceof` chain?
2. The final `else` branch in `describe()` throws an `IllegalStateException`. When would that branch ever execute, and what does its presence tell a reader of the code?
3. In Task 2.4, the condition `result instanceof PaymentResult.Approved a && a.amount() > 10_000` combines a type check and a value check in one expression. Why is this safe -- specifically, why is it guaranteed that `a` is not null when `a.amount()` is evaluated?

---

## Exercise 3 - Streams and Functional Programming

**Estimated time:** 45-60 minutes  
**Topics covered:** Stream pipeline construction, intermediate vs terminal operations, `map`, `filter`, `flatMap`, `collect`, `groupingBy`, method references, when to prefer loops

### Context

The Streams API, introduced in Java 8, brings a declarative, pipeline-based style to collection processing. Rather than writing `for` loops that accumulate results into mutable variables, you describe *what* you want (filter these, transform those, collect into a map) and the runtime figures out how to execute it.

In enterprise applications, Streams are used heavily in service layers: transforming database results into DTOs, grouping records for reporting, filtering collections before returning them to callers. Understanding both their power and their limits (when a loop is actually clearer) is a mark of a professional Java engineer.

### Setup

Create a new package `com.example.streams`. Add this starter data class:

```java
package com.example.streams;

public record Order(
        String orderId,
        String customerId,
        String category,
        double totalAmount,
        String status   // "COMPLETED", "PENDING", "CANCELLED"
) {}
```

### Task 3.1 - Basic Pipeline: Filter, Map, Collect

Create `StreamDemo.java` with a sample dataset:

```java
package com.example.streams;

import java.util.List;
import java.util.stream.Collectors;

public class StreamDemo {

    static List<Order> sampleOrders() {
        return List.of(
            new Order("O001", "C01", "ELECTRONICS", 1200.00, "COMPLETED"),
            new Order("O002", "C02", "CLOTHING",    85.50,   "COMPLETED"),
            new Order("O003", "C01", "ELECTRONICS", 340.00,  "PENDING"),
            new Order("O004", "C03", "BOOKS",       22.99,   "CANCELLED"),
            new Order("O005", "C02", "BOOKS",       34.00,   "COMPLETED"),
            new Order("O006", "C03", "ELECTRONICS", 2500.00, "COMPLETED"),
            new Order("O007", "C01", "CLOTHING",    112.00,  "PENDING"),
            new Order("O008", "C04", "ELECTRONICS", 899.99,  "COMPLETED")
        );
    }

    public static void main(String[] args) {
        List<Order> orders = sampleOrders();

        // TODO 10: Produce a list of order IDs for all COMPLETED orders
        // whose totalAmount exceeds 500.00.
        // Use a stream pipeline: filter -> map -> collect
        List<String> highValueCompleted = orders.stream()
            // .filter(...)
            // .map(...)
            // .collect(...)
            ;

        System.out.println("High-value completed order IDs: " + highValueCompleted);
        // Expected: [O001, O006, O008]
    }
}
```

### Task 3.2 - Aggregation: Sum, Count, Average

```java
// TODO 11: Using streams, calculate:
//   a) The total revenue from COMPLETED orders (sum of totalAmount)
//   b) The number of PENDING orders
//   c) The average order value across ALL orders

// Hint for (a): look at mapToDouble(...).sum()
// Hint for (b): filter then count()
// Hint for (c): mapToDouble(...).average() returns an OptionalDouble

double totalRevenue = orders.stream()
    /* your pipeline here */
    .mapToDouble(Order::totalAmount)
    .sum(); // remove or adapt as needed

long pendingCount = 0; // TODO: replace with a stream pipeline

OptionalDouble averageOrderValue = OptionalDouble.empty(); // TODO: replace

System.out.printf("Total revenue (COMPLETED): $%.2f%n", totalRevenue);
System.out.println("Pending order count: " + pendingCount);
averageOrderValue.ifPresent(avg -> System.out.printf("Average order value: $%.2f%n", avg));
```

> **Note on method references:** `Order::totalAmount` is a method reference, shorthand for `o -> o.totalAmount()`. Use method references wherever the lambda body is a single method call; they improve readability significantly.

### Task 3.3 - Grouping with Collectors.groupingBy

```java
import java.util.Map;
import java.util.stream.Collectors;

// TODO 12: Group orders by category.
// The result should be a Map<String, List<Order>>.
// Then print each category and the number of orders in it.

Map<String, List<Order>> byCategory = orders.stream()
    .collect(Collectors.groupingBy(Order::category));

byCategory.forEach((category, categoryOrders) ->
    System.out.println(category + ": " + categoryOrders.size() + " order(s)"));
```

Now extend this: group by category, but instead of collecting the full `Order` objects, collect only the total revenue per category:

```java
// TODO 13: Produce a Map<String, Double> of total revenue per category.
// Hint: Collectors.groupingBy with a downstream Collectors.summingDouble(...)

Map<String, Double> revenueByCategory = orders.stream()
    .collect(/* your collector here */);

revenueByCategory.forEach((cat, rev) ->
    System.out.printf("%-15s $%.2f%n", cat, rev));
```

### Task 3.4 - FlatMap for Nested Collections

Add a new record to represent a `Cart`:

```java
package com.example.streams;

import java.util.List;

public record Cart(String cartId, String customerId, List<String> itemSkus) {}
```

```java
// In StreamDemo.main():

List<Cart> carts = List.of(
    new Cart("CART-1", "C01", List.of("SKU-A", "SKU-B", "SKU-C")),
    new Cart("CART-2", "C02", List.of("SKU-B", "SKU-D")),
    new Cart("CART-3", "C03", List.of("SKU-A", "SKU-E"))
);

// TODO 14: Produce a flat list of ALL item SKUs across all carts.
// Then find the distinct SKUs.
// Hint: use flatMap(cart -> cart.itemSkus().stream())

List<String> allSkus = carts.stream()
    /* .flatMap(...) */
    /* .collect(...) */
    ;

List<String> distinctSkus = carts.stream()
    /* .flatMap(...) */
    /* .distinct() */
    /* .sorted() */
    /* .collect(...) */
    ;

System.out.println("All SKUs (with duplicates): " + allSkus);
System.out.println("Distinct SKUs sorted: " + distinctSkus);
// Expected distinct: [SKU-A, SKU-B, SKU-C, SKU-D, SKU-E]
```

### Task 3.5 - When NOT to Use Streams

Read the following two implementations and answer the checkpoint questions below:

```java
// Version A -- Stream
Optional<Order> firstCancelled = orders.stream()
    .filter(o -> "CANCELLED".equals(o.status()))
    .findFirst();

// Version B -- Enhanced for loop
Order firstCancelledLoop = null;
for (Order o : orders) {
    if ("CANCELLED".equals(o.status())) {
        firstCancelledLoop = o;
        break;
    }
}
```

```java
// TODO 15: The following uses a stream to accumulate state across elements.
// This is an antipattern. Identify WHY, and rewrite it as a loop.

// ANTIPATTERN: side-effecting stream
List<String> ids = new ArrayList<>();
orders.stream()
    .filter(o -> o.totalAmount() > 100)
    .forEach(o -> ids.add(o.orderId()));   // mutating external state inside a stream

// Correct version uses collect():
List<String> idsCorrect = orders.stream()
    .filter(o -> o.totalAmount() > 100)
    .map(Order::orderId)
    .collect(Collectors.toList());
```

### Checkpoints

1. What is the difference between an *intermediate* operation and a *terminal* operation in a stream pipeline? Give two examples of each.
2. Why is mutating a variable from outside the stream inside a `forEach` or `map` an antipattern?
3. Give two scenarios where a plain `for` loop is preferable to a stream pipeline.

---

## Exercise 4 - Switch Expressions

**Estimated time:** 30 minutes  
**Topics covered:** Switch expressions (arrow form), switch as an expression, exhaustiveness, `yield`

### Context

The traditional `switch` *statement* in Java had several long-standing problems: fall-through between cases was a common source of bugs, the `break` requirement was easy to forget, and it could not be used as an expression (it could not return a value). Java 14 introduced switch *expressions* that fix all of these: arrow cases eliminate fall-through, exhaustiveness is enforced by the compiler when switching on enums and sealed types, and the switch can produce a value directly.

### Setup

Create a package `com.example.switchexpr`.

### Task 4.1 - Arrow-Case Switch Expression

```java
package com.example.switchexpr;

public class ShippingCalculator {

    public enum ShippingTier { STANDARD, EXPRESS, OVERNIGHT, SAME_DAY }

    /**
     * TODO 16: Rewrite this method using a switch EXPRESSION (arrow form).
     * The method should return a base shipping fee (double) per tier.
     * Use the arrow form: case X -> value;
     * Make it exhaustive -- handle every enum constant.
     */
    public double baseShippingFee(ShippingTier tier) {
        // Old switch statement version (do NOT keep this -- replace it):
        double fee = 0;
        switch (tier) {
            case STANDARD:   fee = 4.99;  break;
            case EXPRESS:    fee = 12.99; break;
            case OVERNIGHT:  fee = 24.99; break;
            case SAME_DAY:   fee = 39.99; break;
        }
        return fee;
    }
    // Your switch expression version should look like:
    // return switch (tier) {
    //     case STANDARD  -> 4.99;
    //     ...
    // };
}
```

### Task 4.2 - Switch Expression with yield

When the result requires multiple statements (not just a single expression), use `yield` inside a block:

```java
/**
 * TODO 17: Implement this method.
 * Return a discount rate (0.0 to 1.0) based on ShippingTier.
 * - STANDARD and EXPRESS: no discount (0.0)
 * - OVERNIGHT: 10% discount if the order total > 200, else 5%
 * - SAME_DAY: 15% discount if order total > 500, else 8%
 *
 * Use a switch expression. For OVERNIGHT and SAME_DAY, use a block with yield.
 */
public double discountRate(ShippingTier tier, double orderTotal) {
    return switch (tier) {
        case STANDARD, EXPRESS -> 0.0;  // multiple labels on one arrow case

        case OVERNIGHT -> {
            // Use yield to return from a block case
            if (orderTotal > 200) {
                yield 0.10;
            } else {
                yield 0.05;
            }
        }

        case SAME_DAY -> {
            // TODO: implement the SAME_DAY logic using yield
            yield 0.0; // replace this
        }
    };
}
```

### Task 4.3 - Tying it Together

```java
public static void main(String[] args) {
    var calc = new ShippingCalculator();

    for (ShippingTier tier : ShippingTier.values()) {
        double orderTotal = 350.00;
        double base = calc.baseShippingFee(tier);
        double discount = calc.discountRate(tier, orderTotal);
        double finalFee = base * (1 - discount);

        System.out.printf("%-10s base=$%.2f  discount=%.0f%%  final=$%.2f%n",
            tier, base, discount * 100, finalFee);
    }
}
```

### Checkpoints

1. What prevents fall-through in switch expressions?
2. When is `yield` required vs. when can you use the arrow (`->`) directly?
3. What happens at compile time if you add a new constant to the enum and forget to handle it in the switch expression?

---

## Exercise 5 - Maven Fundamentals

**Estimated time:** 30-45 minutes  
**Topics covered:** POM structure, dependency scopes, the build lifecycle, running goals, dependency management section

### Context

Maven is the dominant build and dependency management tool in the enterprise Java ecosystem. Its central concept is *convention over configuration*: a standard directory layout and a standard lifecycle mean that any developer who has seen one Maven project can orient themselves in any other. Understanding Maven is a prerequisite for everything else in this course -- every Spring Boot project you build will be managed by Maven.

### Setup

This exercise does not require writing Java code. You will work entirely with the `pom.xml` file and the Maven command line (or the Maven tool window in IntelliJ).

Create a new Maven project in IntelliJ: File -> New -> Project -> Maven Archetype -> `maven-archetype-quickstart`.

### Task 5.1 - Understand the POM Structure

Open the generated `pom.xml`. Locate and annotate the following sections by adding XML comments explaining each one:

```xml
<project>
    <!-- TODO 18: Add a comment explaining what groupId, artifactId, 
         and version represent, and how they form the project's "coordinates" -->
    <groupId>com.example</groupId>
    <artifactId>my-service</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <properties>
        <!-- TODO 19: Add a comment explaining why compiler source/target 
             versions are set here rather than directly in the plugin config -->
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- TODO 20: Add this dependency and annotate the scope -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.2</version>
            <!-- The "test" scope means this jar is available during
                 compilation and execution of tests, but is NOT included
                 in the final packaged artifact -->
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
```

### Task 5.2 - Add Dependencies and Fix the Generated Test Class

The `maven-archetype-quickstart` archetype generates a `pom.xml` and an `AppTest.java` file. Before adding dependencies, you need to address a compatibility problem with the generated test class.

**Step 1 -- Examine the generated AppTest.java**

Open `src/test/java/com/example/AppTest.java`. You will see it imports from `junit.framework.*` and extends `TestCase`. This is **JUnit 3** style, which was current when the archetype was first written. Your POM declares **JUnit 5** (`junit-jupiter`), which uses an entirely different package structure. The two are incompatible, which is why the project fails to compile with `package junit.framework does not exist`.

**Step 2 -- Replace AppTest.java with a JUnit 5 test**

Delete the contents of `AppTest.java` and replace them with:

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

The key differences from the generated file:
- No `extends TestCase` -- JUnit 5 tests are plain classes with no required superclass
- `@Test` is from `org.junit.jupiter.api.Test`, not `junit.framework`
- Test methods are package-private, not `public void testXxx()`
- Assertions come from `org.junit.jupiter.api.Assertions`

**Step 3 -- Add the Surefire plugin**

The default Surefire plugin version bundled with the archetype only understands JUnit 3 and 4. Without an explicit Surefire declaration, `mvn test` will compile successfully but silently skip all JUnit 5 tests, reporting zero tests run. Add the following `<build>` section to your `pom.xml`:

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-surefire-plugin</artifactId>
            <version>3.2.5</version>
        </plugin>
    </plugins>
</build>
```

**Step 4 -- Add the production dependency**

Now add the Jackson dependency to your `<dependencies>` section:

```xml
<dependencies>

    <!-- Production dependency: available at compile time and runtime -->
    <dependency>
        <groupId>com.fasterxml.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>2.17.1</version>
        <!-- No <scope> tag = compile scope (the default) -->
    </dependency>

    <!-- Test dependency: only on the test classpath -->
    <dependency>
        <groupId>org.junit.jupiter</groupId>
        <artifactId>junit-jupiter</artifactId>
        <version>5.10.2</version>
        <scope>test</scope>
    </dependency>

</dependencies>
```

**Step 5 -- Verify**

Reload the Maven project (click the Maven tool window reload icon), then run `mvn test` from the terminal. You should see output confirming that one test ran and passed:

```
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
```

In IntelliJ, open the **Maven** tool window (View -> Tool Windows -> Maven). Expand **Dependencies** and observe that Jackson appears under compile scope and JUnit under test scope.

> **Tip:** Right-click a dependency in the Maven tool window and choose "Show in Diagram" to visualize the full transitive dependency graph. Notice how jackson-databind pulls in jackson-core and jackson-annotations automatically -- these are *transitive dependencies*.

> **Why does the archetype generate outdated code?** The `maven-archetype-quickstart` archetype has existed since the early days of Maven and its generated test class has not kept pace with JUnit's evolution. This is a common real-world situation: project templates and scaffolding tools lag behind library releases. Always verify that generated code is compatible with the dependency versions declared in the POM before running a build.

### Task 5.3 - Dependency Management Section

When multiple modules share a dependency, the `<dependencyManagement>` section lets you declare versions once and have child modules inherit them without specifying versions themselves. Practice this pattern even in a single-module project:

```xml
<dependencyManagement>
    <dependencies>
        <!-- TODO 21: Move the Jackson version into dependencyManagement.
             In the <dependencies> section below, remove the <version> tag
             from the jackson-databind entry and verify the build still works. -->
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
</dependencies>
```

### Task 5.4 - Running the Maven Lifecycle

Open the IntelliJ Terminal (or your system terminal inside the project root) and run each of the following Maven goals. Observe the output and understand what each phase does before invoking the next:

```bash
# Compile source code only
mvn compile

# Compile and run tests
mvn test

# Package the compiled code into a JAR (runs compile + test first)
mvn package

# Remove all build output (the target/ directory)
mvn clean

# Full clean build -- most common command in daily use
mvn clean package

# Skip tests (useful during active development, not recommended for CI)
mvn clean package -DskipTests
```

> **Lifecycle phases run in order.** Running `mvn package` automatically executes `validate -> compile -> test -> package`. You do not need to run each phase separately.

After running `mvn package`, find the generated JAR file in the `target/` directory and note its name format: `artifactId-version.jar`.

### Checkpoints

1. What are the four most common Maven dependency scopes and when would you use each one?
2. Why does `mvn package` also run `mvn test` automatically?
3. What problem does `<dependencyManagement>` solve that ordinary `<dependencies>` does not?
4. You see `1.0.0-SNAPSHOT` in a version number. What does `SNAPSHOT` indicate, and why does it matter in a team environment?

---

## Exercise 6 - Putting It All Together: A Product Catalogue Service Layer

**Estimated time:** 45-60 minutes  
**Topics covered:** Combines Records, Sealed Classes, Streams, and Switch Expressions in a realistic service layer scenario

### Context

This exercise simulates a service layer method you would write inside a real Spring Boot application. The goal is to reinforce how Java 17 features work together as professional-grade tools, not as isolated curiosities.

### Setup

Create a package `com.example.catalogue`. Create the following types:

```java
// The domain entity held in the service's data store
package com.example.catalogue;

public record Product(
        String id,
        String name,
        double price,
        int stockLevel,
        String category,
        String status     // "ACTIVE", "DISCONTINUED", "OUT_OF_STOCK"
) {}
```

```java
// Request DTO
package com.example.catalogue;

public record ProductSearchRequest(
        String category,
        double minPrice,
        double maxPrice,
        String status      // "ACTIVE", "DISCONTINUED", "OUT_OF_STOCK"
) {}
```

```java
// Result types using a sealed hierarchy
package com.example.catalogue;

import java.util.List;

public sealed interface SearchResult
        permits SearchResult.Success, SearchResult.Empty, SearchResult.InvalidRequest {

    record Success(List<ProductSummary> products, int totalCount) implements SearchResult {}
    record Empty(String reason) implements SearchResult {}
    record InvalidRequest(String validationError) implements SearchResult {}
}
```

```java
// Summary DTO returned in search results
package com.example.catalogue;

public record ProductSummary(String id, String name, double price, String category) {}
```

### Task 6.1 - Implement the Search Service

```java
package com.example.catalogue;

import java.util.List;
import java.util.stream.Collectors;

public class ProductCatalogueService {

    // Simulated data store
    private final List<Product> products = List.of(
        new Product("P001", "Laptop Pro",       1299.99, 42,  "ELECTRONICS", "ACTIVE"),
        new Product("P002", "USB-C Hub",          45.00, 200, "ELECTRONICS", "ACTIVE"),
        new Product("P003", "Wireless Headset",  249.99,  0,  "ELECTRONICS", "OUT_OF_STOCK"),
        new Product("P004", "Desk Chair",        399.00, 15,  "FURNITURE",   "ACTIVE"),
        new Product("P005", "Monitor Stand",      89.99, 75,  "FURNITURE",   "ACTIVE"),
        new Product("P006", "Mechanical Keyboard",129.99, 30, "ELECTRONICS", "ACTIVE"),
        new Product("P007", "Legacy Printer",     59.99,  5,  "ELECTRONICS", "DISCONTINUED")
    );

    /**
     * TODO 22: Implement this method.
     *
     * Rules:
     * 1. Validate the request:
     *    - category must not be null or blank → return InvalidRequest
     *    - minPrice must be >= 0 → return InvalidRequest
     *    - maxPrice must be > minPrice → return InvalidRequest
     *
     * 2. Filter products by:
     *    - matching category (case-insensitive)
     *    - price within [minPrice, maxPrice] inclusive
     *    - status matching the request status (if provided; null/blank means "include all")
     *
     * 3. Map each matching Product to a ProductSummary
     *
     * 4. If no products match, return Empty with an appropriate reason message.
     *
     * 5. Otherwise return Success with the list and count.
     *
     * Use streams for filtering and mapping.
     * Use a private helper method to build the response message.
     */
    public SearchResult search(ProductSearchRequest request) {
        // Your implementation here
        return new SearchResult.Empty("Not implemented yet");
    }
}
```

> **Hint for step 1:** Consider writing a private `validate(ProductSearchRequest)` method that returns an `Optional<String>` -- empty if valid, containing the error message if invalid.

### Task 6.2 - Exercise the Service

```java
package com.example.catalogue;

import java.util.stream.Collectors;

public class CatalogueDemo {

    public static void main(String[] args) {
        var service = new ProductCatalogueService();

        // Test 1: Valid search with results
        var result1 = service.search(new ProductSearchRequest("ELECTRONICS", 50.00, 300.00, "ACTIVE"));

        // TODO 23: Use an instanceof chain to produce a message for each SearchResult type.
        // Use the pattern variable in each branch to access the type's fields.
        String message1 = describeResult(result1);
        System.out.println("Test 1: " + message1);

        // Test 2: Invalid request (maxPrice < minPrice)
        var result2 = service.search(new ProductSearchRequest("ELECTRONICS", 500.00, 100.00, null));
        // TODO 24: Print the result using describeResult
        System.out.println("Test 2: " + describeResult(result2));

        // Test 3: Valid search with no matching results
        var result3 = service.search(new ProductSearchRequest("FURNITURE", 1000.00, 5000.00, "ACTIVE"));
        // TODO 25: Print the result
        System.out.println("Test 3: " + describeResult(result3));
    }

    // TODO 26: Implement this helper using an instanceof chain over the three
    // SearchResult subtypes: Success, Empty, and InvalidRequest.
    private static String describeResult(SearchResult result) {
        if (result instanceof SearchResult.Success s) {
            return "Found " + s.totalCount() + " product(s): " +
                s.products().stream().map(ProductSummary::name).collect(Collectors.joining(", "));

        // TODO: add else-if for SearchResult.Empty e

        // TODO: add else-if for SearchResult.InvalidRequest i

        } else {
            throw new IllegalStateException("Unhandled SearchResult type: " + result.getClass());
        }
    }
}
```

### Checkpoints

1. How does using a sealed `SearchResult` type improve the contract between the service and its callers compared to throwing exceptions or returning null?
2. The search method accepts a `ProductSearchRequest` record. What advantages does this give you over accepting five separate method parameters?
3. Looking at your stream pipeline: could you replace the filter/map steps with a single `for` loop? In this case, which approach do you prefer and why?

---

## Summary and Reflection

After completing all six exercises, you have worked with every major feature covered in Module 1:

| Feature | Exercise | Key Insight |
|---|---|---|
| Records | 1 | Immutable data carriers with zero boilerplate; use compact constructors for validation |
| Sealed classes | 2 | Closed hierarchies make every permitted subtype explicit and known at compile time |
| Pattern matching with instanceof | 2, 6 | Eliminates casting; combine with `&&` for single-expression type-and-value checks |
| Streams | 3, 6 | Declarative pipeline processing; prefer `collect` over mutating external state |
| Switch expressions | 4, 6 | Arrow cases eliminate fall-through; `yield` for multi-statement blocks |
| Maven | 5 | Convention-based build tool; dependency scopes control classpath membership |

### Final Reflection Questions

Take 10 minutes to answer these before your next session:

1. You are designing a REST API response type that can represent either a successful payload, a validation error, or a server-side failure. How would you model this using the features from this module?

2. A colleague writes a Stream pipeline that calls `.forEach()` to populate a `List` that is defined outside the stream. You know this is wrong. How would you explain the problem and demonstrate the correct approach?

3. You open a `pom.xml` and see a dependency with `<scope>provided</scope>`. You have not encountered this scope in the exercises. Based on your understanding of the other scopes, what do you think `provided` means? (You can verify with the Maven documentation.)

---

## Reference: Key Java 17 Syntax Quick-Card

```java
// Record
public record Point(int x, int y) {}

// Compact constructor
public record Product(String id, double price) {
    public Product { if (price < 0) throw new IllegalArgumentException(); }
}

// Sealed interface with permitted subtypes
public sealed interface Shape permits Circle, Rectangle {}
public record Circle(double radius) implements Shape {}
public record Rectangle(double w, double h) implements Shape {}

// Exhaustive instanceof dispatch (Java 17 standard)
public String describe(Shape shape) {
    if (shape instanceof Circle c) {
        return "Circle r=" + c.radius();
    } else if (shape instanceof Rectangle r) {
        return "Rect " + r.w() + "x" + r.h();
    } else {
        throw new IllegalStateException("Unhandled shape: " + shape.getClass());
    }
}

// Single-type check with combined condition (no cast required)
if (shape instanceof Circle c && c.radius() > 10) {
    System.out.println("Large circle");
}

// Note: pattern matching directly in switch (case Circle c -> ...)
// is available as a standard feature from Java 21 onwards.

// Stream pipeline
List<String> names = orders.stream()
    .filter(o -> o.status().equals("COMPLETED"))
    .map(Order::name)
    .sorted()
    .collect(Collectors.toList());

// groupingBy
Map<String, Long> countByStatus = orders.stream()
    .collect(Collectors.groupingBy(Order::status, Collectors.counting()));

// Switch expression with yield
double fee = switch (tier) {
    case STANDARD -> 4.99;
    case OVERNIGHT -> {
        if (orderTotal > 200) yield 0.10;
        else yield 0.05;
    }
};
```

---

*End of Module 1 Exercises*
