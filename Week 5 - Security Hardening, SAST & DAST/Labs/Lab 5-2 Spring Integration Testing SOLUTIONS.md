# Lab 5.2 -- Solutions

> **Course:** MD282 - Java Full-Stack Development
> **Purpose:** This file contains complete code for every test you wrote in Lab 5.2.
> Use it to verify your work after attempting each task yourself. Reading the
> solution before attempting the task defeats the purpose of the exercise.

---

## How to Use This File

The complete solution code for the test class is shown below.

The complete solution project is also provided as `banking-integration-lab-solution.zip` if you want to import it into IntelliJ and run all tests at once.

### Files modified in this lab

| File | Tests |
|---|---|
| `src/test/java/com/example/banking/controller/AccountControllerTest.java` | 3 tests |

---

## Complete AccountControllerTest.java

```java
package com.example.banking.controller;

import com.example.banking.config.SecurityConfig;
import com.example.banking.domain.Account;
import com.example.banking.service.AccountService;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.util.List;

import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.oauth2Login;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AccountController.class)
@Import(SecurityConfig.class)
@DisplayName("Account controller")
class AccountControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private AccountService accountService;

    @Test
    @DisplayName("unauthenticated request returns 401")
    void unauthenticatedRequestReturns401() throws Exception {
        mockMvc.perform(get("/api/accounts"))
                .andExpect(status().isUnauthorized());
    }

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

    @Test
    @DisplayName("authenticated request returns an empty list when service has no accounts")
    void authenticatedRequestReturnsEmptyListWhenServiceHasNoAccounts() throws Exception {
        when(accountService.findAll()).thenReturn(List.of());

        mockMvc.perform(get("/api/accounts").with(oauth2Login()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$.length()").value(0));
    }
}
```

---

## Notes on the Solutions

### Why `@Import(SecurityConfig.class)` is required

This is the most important detail of this entire lab.

`@WebMvcTest` is designed to load only the MVC slice. It auto-configures Spring Security, but only with **default** behavior. Custom `SecurityFilterChain` beans declared in your application's configuration classes are NOT auto-loaded.

This is a behavior change from earlier Spring Boot versions. Before Spring Boot 2.7, security configuration extended `WebSecurityConfigurerAdapter`, and `@WebMvcTest` auto-detected those classes. Spring Boot 2.7+ deprecated `WebSecurityConfigurerAdapter` and switched to declaring `SecurityFilterChain` as a bean. The trade-off: `@WebMvcTest` no longer auto-loads these beans.

Without `@Import(SecurityConfig.class)`:

- The test runs with Spring Security's default OAuth2 client configuration
- The default behavior for unauthenticated requests is to redirect to the OAuth login flow (302)
- Our custom 401 entry point is never registered
- The `unauthenticatedRequestReturns401` test fails with "Status expected:<401> but was:<302>"

With `@Import(SecurityConfig.class)`:

- The custom `SecurityFilterChain` bean is loaded into the test context
- The 401 entry point for `/api/**` is active
- Unauthenticated requests to `/api/**` return 401 as configured
- The test passes

This is one of the most common gotchas in Spring Boot integration testing. Worth memorizing: **whenever you `@WebMvcTest` a controller protected by custom security, `@Import` your security configuration**.

### Why `@WebMvcTest` rather than `@SpringBootTest`

`@WebMvcTest` loads only the MVC slice: controllers, JSON converters, filters, security configuration. It does NOT load services, repositories, or other beans. This makes the test fast (1-2 seconds vs. 5-10+ for full context) while still exercising real Spring framework behavior.

For a controller test, you almost never need the full context. The controller's collaborators are interfaces; we can replace them with `@MockBean`. The framework infrastructure we DO need (request mapping, JSON marshalling, security filters) is exactly what `@WebMvcTest` loads -- once we add `@Import` for our custom configuration.

Reach for `@SpringBootTest` only when you need something `@WebMvcTest` cannot provide: full bean wiring, integration between layers that includes real services/repositories, scheduled jobs, async execution. (As a side benefit, `@SpringBootTest` does auto-load all configuration classes including SecurityConfig, so you don't need `@Import` with it. But the price is a much slower test.)

### Why `@MockBean` instead of `@Mock`

The two annotations look similar but behave differently. `@Mock` (from Mockito) creates a plain mock object. The mock exists, but Spring doesn't know about it -- you have to wire it into the unit under test manually.

`@MockBean` (from Spring Boot Test) creates a Mockito mock AND registers it in the Spring application context. Any bean that depends on the type (in this case, `AccountController` depends on `AccountService`) gets the mock injected by Spring. The controller doesn't know it's getting a mock; from its perspective the dependency injection works exactly as it would at runtime.

For `@WebMvcTest` and `@SpringBootTest` scenarios, `@MockBean` is almost always what you want. Use plain `@Mock` only in pure unit tests with no Spring context (Lab 5.1's `TransferProcessorTest` is the canonical example).

### Why the `oauth2Login()` post-processor over a real OAuth flow

A real OAuth flow in tests would require:

- A running auth server (or a sophisticated mock of one)
- A real client registration with valid credentials
- Network calls between the test, the auth server, and the resource server
- Handling of state parameters, PKCE, redirect URIs, JWT validation

This is slow, fragile, and tests the auth server more than your application. The `oauth2Login()` post-processor sidesteps it by directly populating the security context with the simulated authenticated state. The controller sees a logged-in user; the test runs in milliseconds; no real OAuth machinery is involved.

The trade-off: a simulated-flow test does not catch bugs in the OAuth flow itself. If your auth server's redirect URI is misconfigured, the simulated test won't notice. For OAuth-flow bugs you need a different kind of test (often a manual end-to-end check in a staging environment).

### Why `throws Exception` on every test

`MockMvc.perform(...)` declares `throws Exception` because a request can fail in many ways: I/O failures during request building, unexpected exceptions in controller code, JSON serialization errors, etc. JUnit accepts `throws Exception` on test methods without ceremony; the test passes if the method completes without throwing, fails otherwise.

Some teams prefer to wrap MockMvc calls in try/catch and rethrow as RuntimeException to keep test signatures clean. Either style is fine. The starter and solution use `throws Exception` because it's the most idiomatic Spring Boot test signature.

---

## What You Have Learned

By completing this lab you have practiced:

- Loading the MVC test slice with `@WebMvcTest`
- Importing custom security configuration with `@Import`
- Substituting collaborators with `@MockBean`
- Building HTTP requests with `MockMvc`
- Asserting on response status with `status().isXxx()`
- Asserting on response JSON with JSONPath
- Simulating OAuth authentication with `oauth2Login()`
- Testing both authenticated and unauthenticated cases for protected endpoints

These patterns scale up to any Spring Boot application. The bankbff project from Module 8 has the same shape (controllers + services + OAuth security), so the same testing patterns apply directly. For your capstone, expect to write integration tests that look like the ones in this lab: `@WebMvcTest` plus `@Import(SecurityConfig.class)`, `@MockBean` for collaborators, `oauth2Login()` for authentication, JSONPath for response assertions.
