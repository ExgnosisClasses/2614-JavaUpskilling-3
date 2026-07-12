# Spring Boot Architecture & REST API Design: References and Further Reading

**Java Full Stack Development**

---

## Official Documentation

The resources below are drawn from the official Spring Framework documentation, the Spring Boot reference guide, and the Spring Initializr project site. They cover the auto-configuration model, profiles, layered architecture, validation, and REST design features introduced in this module.

---

### Spring Boot Reference Documentation

The authoritative reference for Spring Boot, covering the full auto-configuration model, externalized configuration, profiles, starters, actuator, testing, and deployment. Every topic in this module has a corresponding section here. Bookmark this as your first stop for any Spring Boot question not answered in course materials.

[docs.spring.io/spring-boot/reference](https://docs.spring.io/spring-boot/reference/)

---

### Spring Boot Starters

The official listing of all first-party Spring Boot starters, with descriptions of what each one brings onto the classpath and when to use it. Understanding what a starter pulls in — and why — is foundational to diagnosing auto-configuration behavior and avoiding dependency conflicts.

[docs.spring.io/spring-boot/reference/using/build-systems.html#using.build-systems.starters](https://docs.spring.io/spring-boot/reference/using/build-systems.html#using.build-systems.starters)

---

### Auto-Configuration

The Spring Boot reference section on how auto-configuration works: condition annotations, the auto-configuration report, and how to selectively exclude or override auto-configured beans. Reading this demystifies the "magic" that experienced developers need to understand in order to debug and customize Spring Boot applications confidently.

[docs.spring.io/spring-boot/reference/using/auto-configuration.html](https://docs.spring.io/spring-boot/reference/using/auto-configuration.html)

---

### Externalized Configuration

Covers the full property source priority order, `application.properties` and `application.yml`, type-safe configuration with `@ConfigurationProperties`, and how Spring Boot resolves values across environment variables, command-line arguments, and profile-specific files.

[docs.spring.io/spring-boot/reference/features/external-config.html](https://docs.spring.io/spring-boot/reference/features/external-config.html)

---

### Profiles

The reference documentation for Spring profiles, including activating profiles, profile-specific configuration files, and the `@Profile` annotation. Essential for managing environment-specific configuration across development, test, staging, and production in the way enterprise applications require.

[docs.spring.io/spring-boot/reference/features/profiles.html](https://docs.spring.io/spring-boot/reference/features/profiles.html)

---

### Spring MVC: Annotated Controllers

The Spring Framework reference covering `@RestController`, `@RequestMapping`, `@PathVariable`, `@RequestBody`, `@ResponseStatus`, and the full model for building REST endpoints with Spring MVC. The canonical reference for everything related to how Spring handles HTTP requests in a Boot application.

[docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller.html](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller.html)

---

### Spring MVC: Validation

Documents the integration of Bean Validation (JSR-380) into Spring MVC, including `@Valid`, `@Validated`, binding result handling, and constraint annotations. Covers both method-level and class-level validation, which are both used in the service and controller layers of a well-structured Spring Boot application.

[docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-validation.html](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-validation.html)

---

### Spring MVC: Error Responses and `@ExceptionHandler`

The reference documentation for `@ExceptionHandler`, `@ControllerAdvice`, `ResponseEntityExceptionHandler`, and the RFC 9457 Problem Details support introduced in Spring 6. Directly relevant to the global exception handling and standard error model topics in this module.

[docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-exceptionhandler.html](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-exceptionhandler.html)

---

### Spring Initializr

The official project scaffolding tool for generating new Spring Boot projects with the correct dependencies, packaging, and build configuration. Familiarity with Initializr removes friction at the start of every new project or lab exercise.

[start.spring.io](https://start.spring.io/)

---

### Jakarta Bean Validation 3.0 Specification

The specification for the Bean Validation API used by Spring Boot's `spring-boot-starter-validation`. The constraint annotation reference and the extension model sections are the most practically useful for day-to-day enterprise development.

[jakarta.ee/specifications/bean-validation/3.0](https://jakarta.ee/specifications/bean-validation/3.0/)

---

## Tutorials and Articles

The resources below provide worked examples and opinionated guidance that complement the official reference documentation. They are drawn from Baeldung, the Spring blog, and widely referenced industry sources on REST API design.

---

### Baeldung: Spring Boot Tutorial — Bootstrap a Simple Application

A concise walkthrough of creating a Spring Boot application from scratch, covering project structure, the main application class, and running the application from the command line and from within IntelliJ IDEA. A useful orientation for students encountering Spring Boot for the first time.

[baeldung.com/spring-boot](https://www.baeldung.com/spring-boot)

---

### Baeldung: Spring Boot Auto-Configuration

A practical explanation of how `@EnableAutoConfiguration` works, how to inspect the auto-configuration report using the `--debug` flag, and how to write your own conditional configuration. Bridges the gap between the official reference and the hands-on understanding needed to diagnose unexpected bean wiring in a real project.

[baeldung.com/spring-boot-autoconfiguration](https://www.baeldung.com/spring-boot-autoconfiguration)

---

### Baeldung: Spring Profiles

A worked guide to defining and activating profiles, using `@Profile` on beans, and managing profile-specific `application.properties` and `application.yml` files. Includes testing considerations that are directly applicable to the multi-environment configuration lab.

[baeldung.com/spring-profiles](https://www.baeldung.com/spring-profiles)

---

### Baeldung: @ConfigurationProperties in Spring Boot

Covers type-safe externalized configuration using `@ConfigurationProperties`, binding nested properties, validation of configuration values, and the advantages over direct `@Value` injection for anything beyond trivial single-value properties. This is the pattern to reach for in any non-trivial enterprise configuration.

[baeldung.com/configuration-properties-in-spring-boot](https://www.baeldung.com/configuration-properties-in-spring-boot)

---

### Baeldung: Layered Architecture in Spring Boot

A tutorial demonstrating the standard Controller–Service–Repository layering used in Spring Boot enterprise applications, including the responsibilities and dependencies of each layer, transaction boundaries, and how the layers interact with Spring's component model.

[baeldung.com/spring-boot-clean-architecture](https://www.baeldung.com/spring-boot-clean-architecture)

---

### Baeldung: REST with Spring Boot — The Complete Guide

A comprehensive guide to building REST APIs with Spring Boot, covering controller design, HTTP method semantics, status codes, content negotiation, and HATEOAS. One of the most referenced freely available treatments of Spring REST development.

[baeldung.com/rest-with-spring-series](https://www.baeldung.com/rest-with-spring-series)

---

### Baeldung: Spring Boot DTO Validation

Covers using `@Valid` and `@Validated` to enforce constraints on request DTOs, writing custom constraint annotations, returning structured validation error responses, and unit testing validation logic in isolation. Directly maps to the DTO validation topics covered in this module.

[baeldung.com/spring-boot-bean-validation](https://www.baeldung.com/spring-boot-bean-validation)

---

### Baeldung: Exception Handling for REST with Spring Boot

A thorough walkthrough of `@ExceptionHandler`, `@ControllerAdvice`, `ResponseEntityExceptionHandler`, and custom error response bodies. Covers the progression from controller-local handling to application-wide strategies, which is the approach used in production Spring Boot services.

[baeldung.com/exception-handling-for-rest-with-spring](https://www.baeldung.com/exception-handling-for-rest-with-spring)

---

### Baeldung: REST API Versioning with Spring

A practical guide to the four main REST API versioning strategies — URI path, request parameter, custom header, and media type versioning — implemented in Spring Boot, with a clear discussion of the trade-offs of each approach. Understanding these trade-offs is essential for making defensible versioning decisions in enterprise API design.

[baeldung.com/rest-versioning](https://www.baeldung.com/rest-versioning)

---

### Baeldung: Idempotency in REST APIs

Covers what idempotency means in the context of HTTP, which methods are idempotent by specification, and patterns for implementing idempotent POST operations using idempotency keys — a common requirement in financial and transactional systems such as the kind built at Bank of America.

[baeldung.com/rest-api-idempotence](https://www.baeldung.com/rest-api-idempotence)

---

### RFC 9457 — Problem Details for HTTP APIs

The IETF specification that defines the standard JSON error response format (`application/problem+json`) supported natively in Spring Framework 6 and Spring Boot 3. Reading the specification directly is worthwhile: it is short, readable, and explains the rationale behind the `type`, `title`, `status`, `detail`, and `instance` fields that should appear in every well-formed API error response.

[datatracker.ietf.org/doc/html/rfc9457](https://datatracker.ietf.org/doc/html/rfc9457)

---

## Additional Readings and References for Deeper Study

The resources below go beyond the module material and are recommended for students who want a deeper understanding of REST API design principles and the architectural choices that underpin production Spring Boot services.

---

### Spring Blog

The official Spring team blog, covering new releases, feature announcements, best practices, and architectural guidance. Posts by the Spring engineers carry significant weight when making architectural decisions because they reflect the intended use of the framework rather than community interpretation.

[spring.io/blog](https://spring.io/blog)

---

### Spring Guides

A curated collection of task-focused tutorials maintained by the Spring team, each targeting a specific integration or pattern. The guides for "Building a RESTful Web Service," "Validating Form Input," and "Handling Form Submission" are particularly relevant to this module.

[spring.io/guides](https://spring.io/guides)

---

### "RESTful Web Services" by Leonard Richardson and Sam Ruby *(Book)*

The book that first articulated the Richardson Maturity Model and gave the developer community a shared vocabulary for REST API design. Although published before Spring Boot, the design principles — resource identification, uniform interface, statelessness, and hypermedia — are timeless and directly relevant to the REST resource design topics in this module.

---

### "REST API Design Rulebook" by Mark Masse *(Book)*

A concise, opinionated guide to making consistent design decisions across URI structure, HTTP methods, response codes, metadata, and representation design. Enterprise teams consistently reach for this book when establishing API design standards, and its rules translate directly into Spring Boot controller design decisions.

---

### Zalando RESTful API and Event Guidelines

Zalando's publicly available API design guidelines, used internally across a large engineering organization and widely referenced in the industry. Covers resource naming, versioning, error format (which aligns with RFC 9457), pagination, and idempotency. A well-maintained and practical reference for establishing consistent standards on a development team.

[opensource.zalando.com/restful-api-guidelines](https://opensource.zalando.com/restful-api-guidelines/)

---

### Microsoft REST API Guidelines

Microsoft's internal API design guidelines, published openly on GitHub. Particularly useful for students coming from a .NET and Microsoft background, as it bridges familiar territory with REST design best practices. Covers versioning, error responses, collections, and long-running operations in detail.

[github.com/microsoft/api-guidelines](https://github.com/microsoft/api-guidelines)

---

