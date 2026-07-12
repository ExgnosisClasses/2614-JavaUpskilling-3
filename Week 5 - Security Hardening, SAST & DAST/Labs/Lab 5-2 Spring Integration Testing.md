# Lab 5.2 -- Spring Boot Integration Testing

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 10 - Testing, SAST, and Security Hardening
> **Estimated time:** 45-60 minutes

---

## Overview

In this lab you will write integration tests for a Spring Boot REST controller. Where Lab 5.1 tested pure logic and Mockito-based service classes, this lab exercises the **Spring framework infrastructure**: request mapping, JSON serialization, security filters, and the response pipeline.

The starter project is a small standalone Spring Boot application separate from the bankbff/bankserver projects from Module 8. It has one controller (`AccountController`), one service interface (`AccountService`), security configuration that requires OAuth authentication on `/api/**`, and almost nothing else. The smaller surface area lets you focus on integration test mechanics without the noise of a larger application.

Three exercises, three tests. By the end of this lab you will be able to:

- Use `@WebMvcTest` to load a controller and the MVC infrastructure without the full Spring context
- Use `@Import` to bring custom security configuration into the test context
- Provide a mock service collaborator with `@MockBean`
- Build HTTP requests with `MockMvc` and assert on status code and JSON response
- Test both unauthenticated (401) and authenticated paths
- Use Spring Security's `oauth2Login()` post-processor to simulate authentication without a real OAuth flow

---

## Before You Start

You will need:

- **IntelliJ IDEA** (Community or Ultimate)
- **JDK 17 or newer** -- the project is configured for Java 17
- **Maven** -- bundled with IntelliJ; no separate installation needed
- The `banking-integration-lab-starter.zip` file provided with this lab

The lab does NOT require:

- The Module 8 projects (bankbff, bankserver, auth-server)
- A running auth server or any other service
- Docker
- A database

### Importing the starter project

1. Unzip `banking-integration-lab-starter.zip` to a working directory of your choice
2. In IntelliJ, choose **File** -> **Open**, then select the unzipped `banking-integration-lab` folder
3. IntelliJ detects the `pom.xml` and offers to import as a Maven project. Accept.
4. Wait for IntelliJ to download dependencies and index the project. Spring Boot pulls a lot of dependencies on first import; this can take a few minutes.
5. Once indexing finishes, open `src/test/java/com/example/banking/controller/AccountControllerTest.java`. You should see the test class skeleton with `@WebMvcTest`, `@Import(SecurityConfig.class)`, `@Autowired MockMvc`, and `@MockBean AccountService` already in place. There should be no compile errors.

If you see compile errors after import, force a Maven reload: right-click `pom.xml` -> **Maven** -> **Reload Project**. If errors persist, ask the instructor.

### Files you will modify in this lab

| File | Purpose |
|---|---|
| `src/test/java/com/example/banking/controller/AccountControllerTest.java` | Integration tests for AccountController |

The other files in the project (the controller, service, security config, application class) are read-only references. You will look at them but not change them.

---

## What's in the Starter Project

Before writing tests, take a few minutes to read through the production code. Five Java files plus one configuration file:

**`AccountController`** (`controller/AccountController.java`) -- exposes one endpoint:

- `GET /api/accounts` -- returns a JSON array of accounts

The controller depends on `AccountService`. Spring injects the implementation at runtime; in tests we substitute a mock.

**`AccountService`** (`service/AccountService.java`) -- interface with one method `findAll()` returning a list of accounts. The integration test does not need the real implementation.

**`InMemoryAccountService`** (`service/InMemoryAccountService.java`) -- the `@Service`-annotated implementation Spring loads at runtime. Returns two hardcoded accounts. **Not used in this lab's tests** because `@MockBean` replaces it with a mock.

**`SecurityConfig`** (`config/SecurityConfig.java`) -- configures Spring Security:

- `/api/**` requires authentication
- Unauthenticated requests to `/api/**` receive 401 Unauthorized (rather than a redirect to a login page)
- OAuth2 login is the authentication mechanism for any non-API requests

**`Account`** (`domain/Account.java`) -- a Java record with four fields: accountNumber, accountType, balance, status. Used as the response body type.

**`application.yml`** -- the Spring configuration. Contains a stub OAuth2 client registration. The lab tests do not exercise the actual OAuth flow (we use Spring Security's test post-processors instead), but the registration must exist so Spring Security boots without error.

---

## Exercise 1 -- Three Integration Tests

**Estimated time:** 45-60 minutes
**Topics covered:** `@WebMvcTest`, `@Import`, `@MockBean`, `MockMvc` request building, `oauth2Login()` post-processor, JSONPath assertions
**File modified:** `src/test/java/com/example/banking/controller/AccountControllerTest.java`

### Context

The starter test class has the boilerplate already in place:

```java
@WebMvcTest(AccountController.class)
@Import(SecurityConfig.class)
@DisplayName("Account controller")
class AccountControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private AccountService accountService;
```

What each line does:

- `@WebMvcTest(AccountController.class)` tells Spring Boot: "load only the MVC infrastructure plus this controller. Don't load services, repositories, or other beans." This makes the test fast (about 1-2 seconds to start vs. 5-10+ seconds for `@SpringBootTest`).

- `@Import(SecurityConfig.class)` brings the application's custom security configuration into the test context. **This is required.** `@WebMvcTest` does not auto-load custom `SecurityFilterChain` beans, only Spring Security's defaults. Without this import, the unauthenticated test would return 302 (the default OAuth redirect behavior) instead of 401 (the behavior we configured in `SecurityConfig`). This is one of the most common gotchas in Spring Boot integration testing; see the box below.

- `@Autowired MockMvc mockMvc` injects Spring's MockMvc -- a tool for performing HTTP requests against the controller without starting a real server. The request goes through the dispatcher servlet, security filters, request mapping, and response serialization, just like a real request, but never hits the network.

- `@MockBean AccountService accountService` provides a Mockito mock that Spring injects into the controller. The real `InMemoryAccountService` is NOT loaded.

> **Why `@Import` is required**
>
> Before Spring Boot 2.7, the standard pattern for security configuration was to extend `WebSecurityConfigurerAdapter`. `@WebMvcTest` would auto-detect and load these classes.
>
> Spring Boot 2.7+ deprecated `WebSecurityConfigurerAdapter` in favor of declaring a `SecurityFilterChain` bean directly (which is what our `SecurityConfig` does). The trade-off is that `@WebMvcTest` no longer auto-loads these custom security configurations -- you have to import them explicitly.
>
> Without `@Import(SecurityConfig.class)`, the test runs with Spring Security's default configuration. The default for an OAuth2 client application is "redirect unauthenticated requests to the OAuth login flow" (a 302 response). The custom 401 entry point we configured in `SecurityConfig` is simply not loaded.
>
> If you ever see "Status expected:<401> but was:<302>" in a Spring Security test, missing `@Import` for the security configuration is the most likely cause.

You will fill in three test methods, marked with TODO comments inside the class.

### Task 1.1 -- Unauthenticated request returns 401

Find TODO 1.1 and replace it with a test that verifies the security configuration rejects unauthenticated requests.

```java
@Test
@DisplayName("unauthenticated request returns 401")
void unauthenticatedRequestReturns401() throws Exception {
    mockMvc.perform(get("/api/accounts"))
            .andExpect(status().isUnauthorized());
}
```

Three things worth understanding about this test:

1. **No authentication post-processor.** The `mockMvc.perform(get(...))` call has no `.with(oauth2Login())` chained on it. This produces a request that Spring Security treats as unauthenticated.

2. **No service stubbing.** We don't call `when(accountService.findAll())...` because the request never reaches the controller. Spring Security's filter chain rejects it before any controller code runs.

3. **`throws Exception`.** MockMvc's `perform` method declares `throws Exception` because of how the framework propagates errors. Test methods that use MockMvc typically declare this on the method signature.

Run the test by clicking the green play button in the gutter. The test should pass with status 401.

This test does double duty: it confirms the controller exists and is mapped to `/api/accounts`, AND it confirms that the security configuration actually requires authentication for this URL. If a future change accidentally exempts `/api/**` from authentication, this test catches the regression.

### Task 1.2 -- Authenticated request returns 200 with the account list

Find TODO 1.2 and replace it with a test that simulates authentication and asserts on the response.

```java
@Test
@DisplayName("authenticated request returns 200 with the account list")
void authenticatedRequestReturnsAccountList() throws Exception {
    when(accountService.findAll()).thenReturn(List.of(
            new Account("ACC-001", "CHECKING", new BigDecimal("1500.00"), "ACTIVE")));

    mockMvc.perform(get("/api/accounts").with(oauth2Login()))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].accountNumber").value("ACC-001"))
            .andExpect(jsonPath("$[0].balance").value(1500.00));
}
```

A few things to note:

**The `oauth2Login()` post-processor.** The `.with(oauth2Login())` chain adds simulated OAuth authentication to the request. Spring Security treats the request as if a real OAuth flow had completed and a user had been authenticated. **No real OAuth server is involved.** The post-processor builds the security context directly. This is why the lab works with a stub OAuth registration -- no real auth server needs to exist.

The static import for `oauth2Login` is `org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.oauth2Login`. It's already in the starter imports.

**JSONPath assertions.** `jsonPath("$[0].accountNumber")` extracts a value from the JSON response body. The `$` is the root, `[0]` is the first element of the array, `.accountNumber` is the field. The same syntax works for any depth of JSON structure: `$.users[2].address.city`, etc.

**JSONPath value comparison for numbers.** Notice that we're comparing balance to `1500.00` (a double literal), not `new BigDecimal("1500.00")`. JSONPath operates on the parsed JSON, where numbers are represented as JavaScript-style numbers. Be careful with this: very precise BigDecimal values can lose precision in the JSON round-trip if the controller doesn't serialize them carefully. For the values in this lab the comparison works cleanly.

Run the test. It should pass and return 200 OK with the JSON body.

### Task 1.3 -- Authenticated request returns an empty list when service has no accounts

Find TODO 1.3 and add a test for the edge case where the service returns no accounts.

```java
@Test
@DisplayName("authenticated request returns an empty list when service has no accounts")
void authenticatedRequestReturnsEmptyListWhenServiceHasNoAccounts() throws Exception {
    when(accountService.findAll()).thenReturn(List.of());

    mockMvc.perform(get("/api/accounts").with(oauth2Login()))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$").isArray())
            .andExpect(jsonPath("$.length()").value(0));
}
```

This test verifies that an empty result still produces a 200 OK with a JSON array (rather than a 404 or null body). It's the kind of edge case worth covering because some controllers accidentally treat an empty result as a 404.

`jsonPath("$").isArray()` confirms the root is an array (not null, not an object). `jsonPath("$.length()").value(0)` confirms the array has zero elements. Together they assert: empty array, not null or missing.

### Verify Exercise 1

Run the entire `AccountControllerTest` class by right-clicking the class name in the editor and choosing **Run 'AccountControllerTest'**. All three tests should pass. The IntelliJ test runner shows them by their `@DisplayName`:

```
Account controller
├── unauthenticated request returns 401
├── authenticated request returns 200 with the account list
└── authenticated request returns an empty list when service has no accounts
```

Note the startup time. The test class loads in 1-2 seconds despite involving Spring's MVC infrastructure and Spring Security. This is what `@WebMvcTest` buys you: real framework behavior, but only the slice you need. A `@SpringBootTest` annotation here would load the full application context and roughly triple the startup time without adding test value for these particular tests.

---

## What You Have Built

You have three integration tests covering the AccountController's contract:

- The endpoint exists and is correctly secured
- Authenticated requests succeed and return the expected JSON
- The empty-result case is handled correctly

Together, these tests exercise the parts of the system that unit tests cannot reach: the request-mapping configuration, the JSON serialization, the security filter chain, and the response pipeline. A bug in any of those layers would have escaped unit tests but is caught here.

The `@WebMvcTest` + `@Import(SecurityConfig.class)` + `@MockBean` + `oauth2Login()` pattern is the workhorse of Spring Boot integration testing for OAuth-protected controllers. Once you understand this pattern, the same shape applies to every OAuth-protected controller in any Spring Boot project: load just the controller and MVC, import the security configuration, mock the collaborators, simulate authentication, assert on the response.

---

## What's Next

- Day 1 of Module 10 wraps with this lab. Day 2 begins with Unit 5 (SAST Concepts) and Lab 5.4 (SonarQube triage).
- **Capstone reminder:** capstone evaluation expects both unit tests (Lab 5.1 style) AND integration tests (Lab 5.2 style). The patterns from these two labs are direct preparation.
