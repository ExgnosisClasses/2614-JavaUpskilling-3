# Advanced Java 17/21: References and Further Reading

**Java Full Stack Development**

---

## Official Documentation

The resources below are drawn from the official Oracle Java documentation, OpenJDK JEPs (JDK Enhancement Proposals), the Apache Maven project site, and the Baeldung Java reference library. They cover the modern language features, functional programming idioms, and build tooling introduced in this module.

---

### Java 21 Documentation Home

The official Oracle documentation hub for Java 21, including the language specification, API reference, and release notes. The authoritative starting point for any question about Java 21 language behavior or standard library APIs.

[docs.oracle.com/en/java/javase/21](https://docs.oracle.com/en/java/javase/21/)

---

### JEP 395: Records

The original JDK Enhancement Proposal specifying the Records feature, including design rationale, semantics, and restrictions. Reading the JEP gives insight into why Records are designed the way they are, which is more durable knowledge than any tutorial.

[openjdk.org/jeps/395](https://openjdk.org/jeps/395)

---

### JEP 409: Sealed Classes

The JEP specifying sealed classes and interfaces, covering the `permits` clause, the interaction with pattern matching, and the motivation for closed type hierarchies in domain modeling.

[openjdk.org/jeps/409](https://openjdk.org/jeps/409)

---

### JEP 441: Pattern Matching for switch

The JEP specifying pattern matching in switch expressions and statements, including guarded patterns, dominance rules, and exhaustiveness checking. Directly relevant to the cleaner dispatch logic you will write in service and mapping layers.

[openjdk.org/jeps/441](https://openjdk.org/jeps/441)

---

### JEP 361: Switch Expressions

The JEP that finalized switch expressions as a standard language feature in Java 14, introducing arrow-case syntax and the `yield` statement. Foundational reading before tackling pattern matching in switch.

[openjdk.org/jeps/361](https://openjdk.org/jeps/361)

---

### Java Stream API — java.util.stream Package Documentation

The official Javadoc for the `java.util.stream` package, covering `Stream`, `Collectors`, `Optional`, and the full set of intermediate and terminal operations. Keep this open while working through any streams exercise.

[docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/stream/package-summary.html](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/stream/package-summary.html)

---

### Apache Maven: Getting Started Guide

The official introduction to Maven covering project structure, the POM, dependency management, the build lifecycle, and plugin configuration. Essential background for students coming from NuGet and .NET build tooling.

[maven.apache.org/guides/getting-started/index.html](https://maven.apache.org/guides/getting-started/index.html)

---

### Maven in Five Minutes

A condensed walkthrough for generating a project, adding a dependency, and running a build. Useful as a fast orientation before the first lab session.

[maven.apache.org/guides/getting-started/maven-in-five-minutes.html](https://maven.apache.org/guides/getting-started/maven-in-five-minutes.html)

---

### Introduction to the POM

Detailed coverage of the `pom.xml` file: coordinates, dependency scopes, dependency management, inheritance, and aggregation. Understanding this document is the foundation of effective Maven use in any enterprise project.

[maven.apache.org/guides/introduction/introduction-to-the-pom.html](https://maven.apache.org/guides/introduction/introduction-to-the-pom.html)

---

## Tutorials and Articles

The resources below provide hands-on, worked examples that complement the official specification reading above. Baeldung is a well-maintained reference site widely used by enterprise Java developers; its articles are regularly updated to track new Java releases.

---

### Baeldung: Java Records

A practical tutorial covering record declaration, compact constructors, custom accessors, and the interaction between records and frameworks such as Jackson and JPA. Includes clear before/after comparisons with traditional POJOs that are directly applicable to the DTO patterns used in this course.

[baeldung.com/java-record-keyword](https://www.baeldung.com/java-record-keyword)

---

### Baeldung: Sealed Classes and Interfaces

A worked guide to defining sealed hierarchies, combining sealed classes with records, and leveraging exhaustiveness checking in switch expressions. Covers the real-world use case of modeling a closed set of domain variants.

[baeldung.com/java-sealed-classes-interfaces](https://www.baeldung.com/java-sealed-classes-interfaces)

---

### Baeldung: Pattern Matching for instanceof

Covers the `instanceof` pattern binding introduced in Java 16, which is the conceptual precursor to full switch pattern matching. Useful for understanding how pattern matching composes with existing type-check idioms in legacy code you will encounter during modernization work.

[baeldung.com/java-pattern-matching-instanceof](https://www.baeldung.com/java-pattern-matching-instanceof)

---

### Baeldung: Pattern Matching for switch

A practical walkthrough of switch pattern matching in Java 21, including guarded patterns with `when`, sealed class exhaustiveness, and the null case. Closely aligned with the switch expression and pattern matching topics covered in this module.

[baeldung.com/java-switch-pattern-matching](https://www.baeldung.com/java-switch-pattern-matching)

---

### Baeldung: The Java 8 Stream API Tutorial

A comprehensive reference tutorial covering the full Stream API: creation, intermediate operations, terminal operations, collectors, parallel streams, and common pitfalls. Even for Java 17/21 development, this remains the most thorough freely available treatment of the API.

[baeldung.com/java-8-streams](https://www.baeldung.com/java-8-streams)

---

### Baeldung: Functional Interfaces in Java

Covers `Function`, `Predicate`, `Consumer`, `Supplier`, `BiFunction`, and method references. Understanding these building blocks is essential before applying functional composition patterns in real service code.

[baeldung.com/java-8-functional-interfaces](https://www.baeldung.com/java-8-functional-interfaces)

---

### Baeldung: Immutability in Java

A focused article on what immutability means in Java, how to achieve it with final fields, defensive copies, and records, and why it matters for thread safety and predictable service behavior in Spring-managed beans.

[baeldung.com/java-immutable-object](https://www.baeldung.com/java-immutable-object)

---

### Baeldung: Introduction to Maven

A tutorial-style introduction to Maven covering project setup, dependency resolution, the standard directory layout, and running builds with common goals. A good bridge between the official Maven docs and practical day-to-day usage.

[baeldung.com/maven](https://www.baeldung.com/maven)

---

## Additional Readings and References for Deeper Study

The resources below go beyond the module material and are recommended for students who want a more thorough grounding in modern Java idioms and the reasoning behind them.

---

### Dev.java — The Official Java Developer Resource Site

Oracle's community-facing Java developer site, with tutorials, articles, and code examples maintained by the Java Platform Group. Particularly useful for finding worked examples of new features from the people who designed them.

[dev.java](https://dev.java/)


---

### Java Language Updates — Oracle Documentation

A concise running summary of every language feature added from Java 9 onward, with links to the detailed documentation for each. Useful for quickly locating what version introduced a feature and how it fits into the broader evolution of the language.

[docs.oracle.com/en/java/javase/21/language/java-language-changes.html](https://docs.oracle.com/en/java/javase/21/language/java-language-changes.html)

---

### InfoQ: Java News and Articles

InfoQ's Java channel covers in-depth articles on new releases, feature previews, JVM performance, and enterprise Java patterns. The writing is aimed at working engineers rather than beginners, making it a practical resource for staying current as the platform evolves.

[infoq.com/java](https://www.infoq.com/java/)

---

