## Lab 4.6  -- Building a Spring Boot BFF with OAuth2

**Estimated time:** 2.5-3.5 hours
**Topics covered:** OAuth client registration, Authorization Code grant with refresh, Spring Security in a confidential web client, session-based authentication, WebClient with OAuth filters, backend-for-frontend pattern, downstream service composition

---

## Overview

In this lab you will build a Banking BFF (backend-for-frontend) - a Spring Boot application that sits between a browser-based SPA and a protected REST API. The BFF holds the OAuth tokens, talks to the auth server, and exposes a session-cookie API to the browser. The browser never sees a bearer token.

This lab integrates directly with two projects you have already built:

- **The Authorization Server from Lab 2-1.** Runs on port 9000. You will add a single new client registration to it in Exercise 1.
- **The bankapi resource server from Lab 2-2.** Currently runs on port 8080. You will change its port to 8081 and add one new endpoint to it in Exercise 2. The BFF will then proxy calls to it.

The BFF itself is built across Exercises 3-7, then tested in Exercise 8.

By the end of the lab you will have a working three-service system in which alice logs in once via the auth server's browser flow, the BFF holds her tokens server-side, and her browser makes session-cookie API calls that the BFF translates into bearer-token calls against bankapi.

---

## Before You Start

Two projects from earlier labs must be available and running.

### Prerequisite 1 - The Authorization Server (Lab 2-1)

The auth server must be running on port 9000. Confirm by visiting:

```
http://127.0.0.1:9000/.well-known/openid-configuration
```

You should see a JSON document describing the auth server's OAuth and OIDC endpoints. If you see an error, open the `authserver` project in IntelliJ and run it. Wait for it to finish initializing.

### Prerequisite 2 - The bankapi Resource Server (Lab 2-2)

The bankapi project from Lab 2-2 must be on your machine. Open it in IntelliJ but **do not start it yet** - you will reconfigure its port in Exercise 2 before running it.

If you skipped Lab 2-2 or do not have the project handy, you can either go back and complete Lab 2-2 first, or clone a clean starter from the course repository. The BFF lab assumes Exercises 1 through 4 of Lab 2-2 are done (the account endpoints exist and require valid JWTs with the appropriate scopes).

### Reference values for this lab

| Item | Value |
|---|---|
| Authorization Server issuer URI | `http://127.0.0.1:9000` |
| Discovery endpoint | `http://127.0.0.1:9000/.well-known/openid-configuration` |
| bankapi resource server URL (after Exercise 2) | `http://localhost:8081` |
| Banking BFF URL (built in this lab) | `http://localhost:8080` |
| BFF OAuth client ID (added in Exercise 1) | `bank-client-bff` |
| BFF OAuth client secret | `bank-client-bff-secret` |
| Test users from Lab 2-1 | `alice` / `password` (account_holder, C001), `bob` / `password` (account_holder, C002), `carla` / `password` (account_holder, C003), `edward` / `password` (teller, EM01), `audit` / `password` (auditor, AUD01) |

> **A note on host names.** Lab 2-1 deliberately uses `127.0.0.1:9000` (not `localhost:9000`) for the auth server. The reason is documented in Lab 2-1: browsers treat `localhost` and `127.0.0.1` as different cookie origins, so mixing them in a single OAuth flow causes session cookies to be lost on the redirect. The BFF uses `localhost:8080` for itself (it is a different host:port from the auth server, so the cookie issue does not arise between them), but its OAuth client configuration points at `127.0.0.1:9000` for the auth server. Keep this distinction in mind when you fill in URLs later.

---

## Architecture

You will be running three services side by side during this lab:

```
   ┌─────────────────────┐         ┌─────────────────────┐         ┌──────────────────┐
   │   Browser / .http   │         │   Banking BFF       │         │  bankapi         │
   │                     │◄───────►│   (Spring Boot)     │◄───────►│  Resource Server │
   │   (You, testing)    │ session │   Port 8080         │ bearer  │  Port 8081       │
   └─────────────────────┘  cookie │                     │ token   │                  │
                                   │   Built in          │         │   From Lab 2-2,  │
                                   │   Exercises 3-7.    │         │   extended in    │
                                   └──────────┬──────────┘         │   Exercise 2.    │
                                              │                    └──────────────────┘
                                              │ OAuth flow
                                              ▼
                                   ┌─────────────────────┐
                                   │  Authorization      │
                                   │  Server             │
                                   │  Port 9000          │
                                   │                     │
                                   │  From Lab 2-1,      │
                                   │  client added in    │
                                   │  Exercise 1.        │
                                   └─────────────────────┘
```

- **Authorization Server (port 9000):** Issues tokens after authenticating users. From Lab 2-1. You will register a new OAuth client (`bank-client-bff`) for the BFF in Exercise 1.
- **bankapi Resource Server (port 8081):** Exposes the banking API behind OAuth2. From Lab 2-2. You will move it to port 8081 and add a transfer endpoint in Exercise 2.
- **Banking BFF (port 8080):** The main work of this lab. Built across Exercises 3 through 7.

The BFF's job is to **translate between two security models**: session cookies for the browser, OAuth2 bearer tokens for the resource server. Doing this in the backend keeps tokens out of JavaScript - the SPA never holds a credential it could leak through XSS.

---

## Exercise 1 -- Register the BFF as an OAuth Client

**Estimated time:** 10-15 minutes
**Topics covered:** OAuth client registration, Authorization Code grant with refresh tokens, confidential clients

### Context

The auth server from Lab 2-1 already has two registered clients:

- **`bank-spa`** - a public client using Authorization Code + PKCE. Represents the React SPA. No client secret.
- **`bank-service`** - a confidential client using Client Credentials. Represents a backend service identity. No user involved.

Neither one fits what the BFF needs. The BFF is a **confidential web application** that acts on behalf of a user: it holds a client secret (unlike `bank-spa`) and uses the Authorization Code flow (unlike `bank-service`). It needs a registration of its own.

This first exercise adds that registration.

> **Why not reuse `bank-spa`?** `bank-spa` is registered as a public client with no client secret - it relies on PKCE for security because a SPA cannot keep a secret. The BFF is a backend that *can* keep a secret, so it benefits from the stronger security profile of a confidential client. Mixing the two would force the public-client constraints (no secret, PKCE-only) onto a backend that does not need them.

### Task 1.1 -- Add the BFF client registration

Open the Authorization Server project (`authserver` from Lab 2-1). Locate the `RegisteredClientRepository` bean in `AuthorizationServerConfig.java`. Find the existing `bank-service` registration and the `return new InMemoryRegisteredClientRepository(bankSpa, bankService);` statement at the end of the method.

Add a new `bank-client-bff` registration **between** the `bank-service` builder and the return statement:

```java
RegisteredClient bankClientBff = RegisteredClient
        .withId(UUID.randomUUID().toString())
        .clientId("bank-client-bff")
        // {noop} tells Spring not to hash this value.
        // Development only; never use {noop} in production.
        .clientSecret("{noop}bank-client-bff-secret")
        .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
        // Authorization Code flow for user-facing login,
        // plus refresh tokens so the BFF can refresh access tokens silently.
        .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
        .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
        // Where the auth server is allowed to redirect the user after login.
        // Spring Security on the BFF auto-exposes this URL pattern.
        .redirectUri("http://localhost:8080/login/oauth2/code/bank-auth")
        .scope(OidcScopes.OPENID)
        .scope(OidcScopes.PROFILE)
        // The full set of bank scopes. The token customizer in Lab 2-1
        // narrows these per user at issue time: alice (account_holder) gets
        // the account_holder subset; edward (teller) gets the teller subset;
        // audit (auditor) gets the auditor subset. Registering with the
        // superset lets any user log in via the BFF and receive a token
        // appropriate to their role.
        .scope("account.read")
        .scope("account.write")
        .scope("account.create")
        .scope("transaction.read")
        .scope("transaction.create")
        .scope("customer.read")
        .scope("customer.write")
        .clientSettings(ClientSettings.builder()
                // Skip the consent screen for this lab to keep the
                // login flow short. In a real customer-facing app
                // you would typically require consent.
                .requireAuthorizationConsent(false)
                .build())
        .tokenSettings(TokenSettings.builder()
                // Longer-lived than bank-spa's 5-minute token because the
                // BFF holds the token server-side; XSS cannot steal it,
                // so a longer lifetime is acceptable.
                .accessTokenTimeToLive(Duration.ofMinutes(60))
                .refreshTokenTimeToLive(Duration.ofDays(1))
                .build())
        .build();
```

Update the `return` statement to include the new client:

```java
return new InMemoryRegisteredClientRepository(bankSpa, bankService, bankClientBff);
```

Restart the Authorization Server. In IntelliJ, click the **Stop** button in the Run panel, then click the green **Run** button to start it again. Wait for the application to finish starting up.

### Task 1.2 -- Verify the registration

Visit `http://127.0.0.1:9000/.well-known/openid-configuration` in a browser. You should see a JSON document describing the auth server's endpoints.

**Critical check:** Look at the `issuer` field at the top of the JSON. It must read `"http://127.0.0.1:9000"`. If it reads `"http://localhost:9000"` instead, the auth server is publishing the wrong issuer URI and the BFF will fail to start later in this lab with an error like *"The Issuer ... did not match the requested issuer"*. Lab 2-1's Task 1.1 sets the issuer explicitly in `application.yml`; if your discovery document shows the wrong value, return to Lab 2-1 and confirm the `spring.security.oauth2.authorizationserver.issuer` property is present and that no Java code is calling `.issuer(...)` on the `AuthorizationServerSettings` builder.

The new `bank-client-bff` registration is now active in memory; you cannot directly inspect it without writing code, but you will exercise it through the BFF later in this lab.

---

## Exercise 2 -- Extend the bankapi Resource Server

**Estimated time:** 15-20 minutes
**Topics covered:** Port reassignment, adding a state-changing endpoint, scope-protected POST endpoints

### Context

The bankapi project from Lab 2-2 already does most of what the BFF needs: it exposes account endpoints that require `SCOPE_account.read`, it validates JWTs against the auth server's JWKS, and it has `/me` and `/mine` endpoints that demonstrate the `sub`-as-customer-ID pattern.

Two changes are needed before the BFF can use it:

1. **Move bankapi to port 8081.** The BFF needs port 8080 because its registered redirect URI is `http://localhost:8080/login/oauth2/code/bank-auth`. Two Spring Boot apps cannot share a port.

2. **Add a transfer endpoint.** Lab 2-2 has account read endpoints but no transfer endpoint. The BFF lab demonstrates the full proxy pattern - reads *and* writes - and the cleanest write to demonstrate is a money transfer between accounts.

### Task 2.1 -- Change the bankapi port to 8081

Open the bankapi project in IntelliJ. Find `src/main/resources/application.yml` and change the server port:

```yaml
server:
  port: 8081

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jwks-uri: http://127.0.0.1:9000/oauth2/jwks
          issuer-uri: http://127.0.0.1:9000
```

> **A note on the issuer URI.** Lab 2-2's original `application.yml` used `localhost:9000`. Switch it to `127.0.0.1:9000` so the JWT validation matches the `iss` claim in tokens issued by Lab 2-1 (which uses `127.0.0.1`). Mismatched issuer URIs are the most common cause of "401 Unauthorized" responses from a resource server that otherwise looks correctly configured.

If bankapi has additional `application.yml` entries from Lab 2-2's Exercise 5 (the `spring.security.oauth2.client.registration` and `provider` blocks for the downstream API client), also change the `token-uri` in that block from `localhost:9000` to `127.0.0.1:9000`. Anything in bankapi that talks to the auth server must use the same host.

### Task 2.2 -- Add a transfer endpoint

The transfer endpoint moves money between two accounts. It requires `SCOPE_transaction.create` (a write scope that account holders, tellers, and auditors all have except auditors - which is what we want).

Create `TransferRequest.java` in the `model` package:

```java
package com.example.bankapi.model;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import java.math.BigDecimal;

public record TransferRequest(
        @NotBlank String fromAccountId,
        @NotBlank String toAccountId,
        @Positive BigDecimal amount
) {}
```

Create `TransferResponse.java` in the `model` package:

```java
package com.example.bankapi.model;

public record TransferResponse(
        String transactionId,
        TransactionStatus status
) {}
```

Create `TransactionStatus.java` in the `model` package:

```java
package com.example.bankapi.model;

public enum TransactionStatus {
    COMPLETE,
    FAILED
}
```

Create `TransferService.java` in the `service` package:

```java
package com.example.bankapi.service;

import com.example.bankapi.model.Account;
import com.example.bankapi.model.TransactionStatus;
import com.example.bankapi.model.TransferRequest;
import com.example.bankapi.model.TransferResponse;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Transfer service.
 *
 * Holds the mutable account state and processes transfers atomically.
 * In a production application this state would live in a database with
 * proper transactional guarantees; an in-memory list with a ReentrantLock
 * is enough for the lab.
 */
@Service
public class TransferService {

    // Same account IDs as AccountController's static list, but kept here
    // mutably so transfers can change balances. The two lists drift; in
    // a real app there would be a single source of truth (the database).
    private final List<Account> accounts = new ArrayList<>(List.of(
            new Account("A001", "C001", "CHECKING", new BigDecimal("1250.00")),
            new Account("A002", "C001", "SAVINGS",  new BigDecimal("8400.00")),
            new Account("A003", "C002", "CHECKING", new BigDecimal("300.50")),
            new Account("A004", "C003", "CHECKING", new BigDecimal("2100.75")),
            new Account("A005", "C003", "SAVINGS",  new BigDecimal("15000.00"))
    ));

    private final ReentrantLock lock = new ReentrantLock();

    public List<Account> listAccounts() {
        lock.lock();
        try {
            return List.copyOf(accounts);
        } finally {
            lock.unlock();
        }
    }

    public TransferResponse transfer(TransferRequest request) {
        lock.lock();
        try {
            int fromIndex = indexOf(request.fromAccountId());
            int toIndex   = indexOf(request.toAccountId());

            if (fromIndex == -1 || toIndex == -1) {
                return new TransferResponse(null, TransactionStatus.FAILED);
            }

            Account from = accounts.get(fromIndex);
            Account to   = accounts.get(toIndex);

            if (request.amount().compareTo(from.balance()) > 0) {
                return new TransferResponse(null, TransactionStatus.FAILED);
            }

            accounts.set(fromIndex, new Account(
                    from.id(), from.customerId(), from.accountType(),
                    from.balance().subtract(request.amount())));
            accounts.set(toIndex, new Account(
                    to.id(), to.customerId(), to.accountType(),
                    to.balance().add(request.amount())));

            String txnId = "T-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
            return new TransferResponse(txnId, TransactionStatus.COMPLETE);
        } finally {
            lock.unlock();
        }
    }

    private int indexOf(String accountId) {
        for (int i = 0; i < accounts.size(); i++) {
            if (accounts.get(i).id().equals(accountId)) {
                return i;
            }
        }
        return -1;
    }
}
```

Create `TransferController.java` in the `controller` package:

```java
package com.example.bankapi.controller;

import com.example.bankapi.model.TransferRequest;
import com.example.bankapi.model.TransferResponse;
import com.example.bankapi.service.TransferService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/transfers")
public class TransferController {

    private final TransferService transferService;

    public TransferController(TransferService transferService) {
        this.transferService = transferService;
    }

    @PostMapping
    public TransferResponse transfer(@Valid @RequestBody TransferRequest request) {
        return transferService.transfer(request);
    }
}
```

Add a scope rule for the new endpoint in `SecurityConfig.java`. Find the `.authorizeHttpRequests(...)` block and add the transfer rule before `.anyRequest().authenticated()`:

```java
.authorizeHttpRequests(auth -> auth
        .requestMatchers(HttpMethod.GET, "/health").permitAll()
        .requestMatchers(HttpMethod.GET, "/api/v1/accounts/**").hasAuthority("SCOPE_account.read")
        .requestMatchers(HttpMethod.POST, "/api/v1/accounts").hasAuthority("SCOPE_account.create")
        .requestMatchers(HttpMethod.POST, "/api/v1/transfers").hasAuthority("SCOPE_transaction.create")
        .anyRequest().authenticated()
)
```

### Task 2.3 -- Start bankapi and verify

In IntelliJ, run the bankapi application. It should start on port 8081 now.

Test that the resource server is rejecting unauthenticated requests:

```http
### Unauthenticated request -- expect 401
GET http://localhost:8081/api/v1/accounts
```

You should see `HTTP/1.1 401 Unauthorized`. The resource server is correctly enforcing token validation. You will not be able to test the success path until the BFF is built.

Leave the bankapi running for the rest of the lab.

---

## Exercise 3 -- Create the BFF Project and Configure OAuth Client

**Estimated time:** 15-20 minutes
**Topics covered:** Spring Initializr, OAuth client configuration, session cookie naming

### Context

The BFF is a Spring Boot web application that:

1. Acts as an OAuth client (initiates the login flow to the auth server)
2. Maintains an HTTP session for the browser
3. Calls the bankapi resource server using the access token from the OAuth flow

This exercise creates the project and configures the OAuth client metadata.

### Task 3.1 -- Create the BFF project with Spring Initializr

Visit [https://start.spring.io](https://start.spring.io) and configure:

- **Project:** Maven
- **Language:** Java
- **Spring Boot:** 3.3.x or later (current stable; if 3.5+ is offered, use that)
- **Group:** `com.example`
- **Artifact:** `bankbff`
- **Name:** `bankbff`
- **Package name:** `com.example.bankbff`
- **Packaging:** Jar
- **Java:** 17 or 21

Add these dependencies:

- **Spring Web**
- **Spring Reactive Web** (for WebClient)
- **OAuth2 Client**
- **Spring Boot DevTools** (optional but recommended)

Click **Generate**, unzip the project, and open it in IntelliJ.

### Task 3.2 -- Create the package structure

Inside `src/main/java/com/example/bankbff`, create the following packages:

```
com.example.bankbff
├── config
├── controller
├── dto
└── client
```

### Task 3.3 -- Configure the OAuth client

Delete `src/main/resources/application.properties` and create `application.yml` in the same location with this content. The `# TODO` comments mark places where you must fill in values.

```yaml
# Banking BFF configuration.
#
# Most of the OAuth client behavior is configured here rather than in code.
# Spring Security reads this configuration on startup and wires up the
# OAuth flow, token storage, and refresh logic automatically.

server:
  port: 8080
  servlet:
    session:
      cookie:
        # Use a unique cookie name for the BFF's session.
        # The default name is JSESSIONID, which is also the default name
        # used by the auth server and the resource server. Because all three
        # apps run on localhost, the browser sends the same JSESSIONID cookie
        # to all of them, and each app overwrites the others' sessions. The
        # result is non-deterministic 401 errors. Giving the BFF its own
        # cookie name avoids the collision entirely.
        name: BFF_SESSION

spring:
  application:
    name: bankbff

  security:
    oauth2:
      client:
        registration:
          # The 'bank-auth' name is a local label; you reference it in URLs
          # like /oauth2/authorization/bank-auth.
          bank-auth:
            # TODO 3.1: Set the client-id to match the registration in the
            # auth server (Exercise 1).
            client-id:

            # TODO 3.2: Set the client-secret to match the auth server.
            client-secret:

            # TODO 3.3: Set the grant type. The BFF is a confidential client
            # acting on behalf of a user, so use authorization_code.
            authorization-grant-type:

            # TODO 3.4: Set the redirect-uri using Spring's placeholder syntax.
            # The pattern is: "{baseUrl}/login/oauth2/code/{registrationId}".
            # Spring fills in the placeholders at runtime.
            redirect-uri:

            # TODO 3.5: Request these scopes:
            #   openid, profile, account.read, account.write, account.create,
            #   transaction.read, transaction.create, customer.read, customer.write
            scope:

        provider:
          bank-auth:
            # TODO 3.6: Set the issuer-uri. Spring will discover the rest of
            # the OAuth endpoints from the standard well-known location
            # (issuer-uri + /.well-known/openid-configuration).
            # IMPORTANT: use 127.0.0.1, not localhost, to match Lab 2-1.
            issuer-uri:

# Banking resource server (downstream API the BFF proxies to).
banking:
  resource-server:
    base-url: http://localhost:8081

logging:
  level:
    org.springframework.security: INFO
    org.springframework.security.oauth2: DEBUG
    com.example.bankbff: DEBUG
```

Fill in each TODO. The values you need are in the **Before You Start** reference table and in Exercise 1.

> **A note on the custom session cookie name.** The `server.servlet.session.cookie.name` setting at the top of the file is filled in for you - it is not a TODO. The reason it matters: this lab runs three Spring Boot apps on localhost (the auth server on 9000, the resource server on 8081, the BFF on 8080). All three default to a session cookie named `JSESSIONID`. The browser scopes cookies by hostname, not by port, so it sends the same `JSESSIONID` cookie to all three apps. Each app overwrites the others' sessions, which produces non-deterministic 401 errors when the wrong app reads the cookie. Giving the BFF a unique cookie name (`BFF_SESSION`) keeps it isolated. In production this is not usually an issue because services live on different hostnames, but for any local-development setup with multiple Spring Boot apps on `localhost`, you need to set this explicitly.

> **A note on placeholders.** `{baseUrl}` becomes `http://localhost:8080` at runtime. `{registrationId}` becomes `bank-auth`. The resulting URL is `http://localhost:8080/login/oauth2/code/bank-auth`, which must match the redirect URI you registered with the auth server in Exercise 1. Mismatch is the most common cause of OAuth login failures.

### Verify Exercise 3

Try to start the BFF. In IntelliJ, locate `BankbffApplication` in `src/main/java/com/example/bankbff/`, right-click it, and select **Run 'BankbffApplication.main()'** (or use the green **Run** button if a run configuration already exists).

The application should start cleanly. If you see a startup error mentioning OAuth client configuration, re-check the TODOs - the most common mistake is leaving one blank.

You cannot test the OAuth flow yet because there is no security configuration. Exercise 4 adds that.

---

## Exercise 4 -- Configure Spring Security in the BFF

**Estimated time:** 25-30 minutes
**Topics covered:** `SecurityFilterChain`, `oauth2Login`, dual-audience routing (browser vs API), CSRF disable for lab purposes

### Context

Adding `spring-boot-starter-oauth2-client` to the dependencies activates a lot of default behaviour. Spring Security:

- Generates a login URL at `/oauth2/authorization/{registrationId}` that initiates the OAuth flow.
- Exposes a callback URL at `/login/oauth2/code/{registrationId}` that receives the authorization code.
- Stores the resulting access token, refresh token, and authenticated user in a server-side session, keyed by the session cookie.
- Forces authentication on every request (by default).

You will configure a `SecurityFilterChain` that:

1. Requires authentication for `/api/**` endpoints
2. Redirects browser navigation to the login page when unauthenticated
3. Returns 401 (not a redirect) for JSON API requests when unauthenticated
4. Allows the OAuth callback URLs without authentication
5. Disables CSRF (this lab does not need it; Lab 4.7 turns it back on)

The dual-audience routing in points 2 and 3 is the most subtle piece. A browser navigating to `/api/me` expects to be sent to a login page. An XHR or fetch call to `/api/me` expects a 401 status, not an HTML redirect.

### Task 4.1 -- Create SecurityConfig

Create `SecurityConfig.java` in the `config` package:

```java
package com.example.bankbff.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;

/**
 * BFF security configuration.
 *
 *  - Require authentication for /api/** endpoints.
 *  - Allow /oauth2/** and /login/** unauthenticated so the OAuth flow can complete.
 *  - Return 401 for JSON requests, redirect to login for browser navigation.
 *  - CSRF disabled in this lab. Lab 4.7 will turn it on with a cookie-based token repository.
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                // TODO 4.1: Configure authorizeHttpRequests so that:
                //   - "/oauth2/**" and "/login/**" are permitted without auth
                //     (the OAuth flow needs to be able to reach these endpoints
                //     while the user is still anonymous)
                //   - "/api/**" requires authentication
                //   - any other request requires authentication
                //
                // Example structure:
                // .authorizeHttpRequests(auth -> auth
                //         .requestMatchers("/oauth2/**", "/login/**").permitAll()
                //         .requestMatchers("/api/**").authenticated()
                //         .anyRequest().authenticated())

                // TODO 4.2: Configure exceptionHandling so that the BFF responds
                // differently depending on whether the caller is a browser or a JSON client.
                //
                // Use defaultAuthenticationEntryPointFor with a MediaTypeRequestMatcher
                // for MediaType.APPLICATION_JSON. The entry point for JSON requests is
                // new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED). The default entry
                // point (used for non-JSON requests) is a LoginUrlAuthenticationEntryPoint
                // pointed at "/oauth2/authorization/bank-auth".
                //
                // Example structure:
                // .exceptionHandling(ex -> ex
                //         .defaultAuthenticationEntryPointFor(
                //                 new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED),
                //                 new MediaTypeRequestMatcher(MediaType.APPLICATION_JSON))
                //         .authenticationEntryPoint(
                //                 new LoginUrlAuthenticationEntryPoint(
                //                         "/oauth2/authorization/bank-auth")))

                // Activate the OAuth2 login flow.
                // This is what makes /oauth2/authorization/{regId} actually do the redirect.
                .oauth2Login(Customizer.withDefaults())

                // Logout configuration. Sending POST /logout invalidates the session.
                .logout(logout -> logout
                        .logoutUrl("/logout")
                        .logoutSuccessUrl("/")
                        .invalidateHttpSession(true)
                        .clearAuthentication(true))

                // Disable CSRF for this lab only. Lab 4.7 will turn it back on
                // with a cookie-based token repository.
                .csrf(AbstractHttpConfigurer::disable);

        return http.build();
    }
}
```

Fill in TODO 4.1 and TODO 4.2. The hint blocks above are nearly complete - your job is to read them, understand why each line is there, and type them out (or copy them, with intent).

> **About the `@EnableWebSecurity` annotation:** Spring Boot is documented to auto-detect a custom `SecurityFilterChain` bean and use it in place of the default chain. In practice, this auto-detection is not always reliable - depending on the Spring Boot version and the order in which beans are processed, your custom `SecurityFilterChain` can be silently ignored in favour of the default. The result is confusing: your code compiles, your bean appears to be created, but the actual filter chain at runtime does not include your rules. Adding `@EnableWebSecurity` explicitly forces Spring Security to use your configuration. It is the safer, recommended form even when auto-detection would "probably" work.

### Verify Exercise 4

Restart the BFF. In a browser, visit `http://localhost:8080/api/me`. You should be redirected to the auth server's login page. **Do not log in yet** - the rest of the BFF is not built. Just confirm the redirect happens. Then close the browser tab.

If you stay on `http://localhost:8080/api/me` and see an error instead of a redirect, double-check TODO 4.1 and TODO 4.2.

---

## Exercise 5 -- Build the WebClient with OAuth Filter

**Estimated time:** 15-20 minutes
**Topics covered:** WebClient, ExchangeFilterFunction, ServletOAuth2AuthorizedClientExchangeFilterFunction

### Context

The BFF holds OAuth tokens server-side. When it needs to call bankapi, it must attach the access token as a Bearer token in the `Authorization` header. Spring Security provides a built-in WebClient filter that:

1. Reads the access token from the current authenticated user's `OAuth2AuthorizedClient`
2. Attaches it to outgoing requests automatically
3. Refreshes the token transparently when it expires (using the refresh token)

Your job is to construct a WebClient with that filter applied.

### Task 5.1 -- Create WebClientConfig

Create `WebClientConfig.java` in the `config` package:

```java
package com.example.bankbff.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.web.reactive.function.client.ServletOAuth2AuthorizedClientExchangeFilterFunction;
import org.springframework.web.reactive.function.client.WebClient;

/**
 * Configures the WebClient used to call the bankapi resource server.
 *
 * The WebClient is wired with the Spring Security OAuth2 filter, which:
 *   - looks up the current authenticated user's OAuth2AuthorizedClient
 *   - extracts the access token
 *   - attaches it as a Bearer token on every outgoing request
 *   - refreshes the token if it has expired
 *
 * Calling code does not need to know any of this. From its perspective,
 * webClient.get().uri("/api/v1/accounts").retrieve()... is all you write.
 */
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient bankApiWebClient(
            OAuth2AuthorizedClientManager authorizedClientManager,
            @Value("${banking.resource-server.base-url}") String baseUrl) {

        // TODO 5.1: Create a ServletOAuth2AuthorizedClientExchangeFilterFunction
        // using the supplied authorizedClientManager. Call its
        // setDefaultClientRegistrationId("bank-auth") method so it uses the
        // BFF's client registration (the one configured in application.yml).
        //
        //   var oauth2Filter = new ServletOAuth2AuthorizedClientExchangeFilterFunction(
        //           authorizedClientManager);
        //   oauth2Filter.setDefaultClientRegistrationId("bank-auth");

        // TODO 5.2: Build the WebClient. Set the base URL and apply the filter.
        //
        //   return WebClient.builder()
        //           .baseUrl(baseUrl)
        //           .apply(oauth2Filter.oauth2Configuration())
        //           .build();

        return null; // Replace this line with your implementation.
    }
}
```

Fill in both TODOs.

> **Why use `OAuth2AuthorizedClientManager`?** Spring auto-configures this bean once you have an OAuth client. It knows how to retrieve the current user's authorized client (with token), how to refresh tokens, and how to handle the case where a client is missing. You should not construct one manually unless you have a specific reason.

### Verify Exercise 5

Restart the BFF. It should start cleanly. The WebClient is built but not yet called from anywhere - the next exercise wires it up.

---

## Exercise 6 -- Build the Resource Server Client

**Estimated time:** 15-20 minutes
**Topics covered:** WebClient calls, DTO mapping, downstream proxy pattern

### Context

Now you can write the code that actually calls bankapi. You will create:

- DTOs that mirror bankapi's request/response shapes
- A client class that wraps the WebClient calls

The DTOs are kept separate from bankapi's domain classes so the BFF can shape the data independently. In a real BFF you would often transform or aggregate the responses; in this lab the BFF just passes data through, but the DTOs are still in their own classes so the option is preserved.

### Task 6.1 -- Create the DTO classes

Create the following records in the `dto` package.

`AccountDto.java`:

```java
package com.example.bankbff.dto;

import java.math.BigDecimal;

/**
 * Account as returned from bankapi.
 *
 * Field names match the JSON exactly: id, customerId, accountType, balance.
 */
public record AccountDto(
        String id,
        String customerId,
        String accountType,
        BigDecimal balance
) {}
```

`TransferRequestDto.java`:

```java
package com.example.bankbff.dto;

import java.math.BigDecimal;

public record TransferRequestDto(
        String fromAccountId,
        String toAccountId,
        BigDecimal amount
) {}
```

`TransferResponseDto.java`:

```java
package com.example.bankbff.dto;

public record TransferResponseDto(
        String transactionId,
        String status
) {}
```

`UserInfoDto.java`:

```java
package com.example.bankbff.dto;

import java.util.List;

/**
 * Information about the authenticated user, exposed via /api/me.
 *
 * The SPA calls /api/me on load to determine whether the user is logged in
 * and to display the user's name and role. The fields come from the OAuth2
 * authenticated principal and the access token claims.
 *
 *   subject:          the JWT's sub claim. From Lab 2-1 this is the
 *                     customer ID (C001), employee ID (EM01), or auditor ID.
 *   preferredUsername: the login name (alice, edward, audit).
 *   fullName:         the user's display name from the token.
 *   roles:            the user's roles (account_holder, teller, auditor).
 */
public record UserInfoDto(
        String subject,
        String preferredUsername,
        String fullName,
        List<String> roles
) {}
```

### Task 6.2 -- Create BankingApiClient

Create `BankingApiClient.java` in the `client` package:

```java
package com.example.bankbff.client;

import com.example.bankbff.dto.AccountDto;
import com.example.bankbff.dto.TransferRequestDto;
import com.example.bankbff.dto.TransferResponseDto;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import java.util.List;

/**
 * Client for the bankapi resource server.
 *
 * Uses the OAuth-configured WebClient. The access token is attached
 * automatically by the ServletOAuth2AuthorizedClientExchangeFilterFunction
 * configured in WebClientConfig.
 */
@Component
public class BankingApiClient {

    private final WebClient bankApiWebClient;

    public BankingApiClient(WebClient bankApiWebClient) {
        this.bankApiWebClient = bankApiWebClient;
    }

    public List<AccountDto> getAccounts() {
        // TODO 6.1: GET /api/v1/accounts and deserialize to List<AccountDto>.
        // Use ParameterizedTypeReference<List<AccountDto>>() {} for the body type.
        //
        //   return bankApiWebClient.get()
        //           .uri("/api/v1/accounts")
        //           .retrieve()
        //           .bodyToMono(new ParameterizedTypeReference<List<AccountDto>>() {})
        //           .block();
        return List.of();
    }

    public TransferResponseDto postTransfer(TransferRequestDto request) {
        // TODO 6.2: POST /api/v1/transfers with the given request body and
        // return the response as a TransferResponseDto.
        //
        //   return bankApiWebClient.post()
        //           .uri("/api/v1/transfers")
        //           .bodyValue(request)
        //           .retrieve()
        //           .bodyToMono(TransferResponseDto.class)
        //           .block();
        return null;
    }
}
```

Fill in both TODOs.

> **Why `.block()`?** WebClient is reactive by default, but the BFF runs on the servlet stack (Spring MVC). Calling `.block()` converts a Mono into a synchronous result on the current servlet thread. This is the simplest correct pattern when the BFF is built on Spring MVC.

### Verify Exercise 6

Restart the BFF. It should start cleanly. The client is built but not yet called - the next exercise wires it up to the controllers.

---

## Exercise 7 -- Build the User and Account Controllers

**Estimated time:** 25-30 minutes
**Topics covered:** Controllers as proxies, reading the authenticated principal, browser-friendly REST APIs

### Context

The BFF exposes two kinds of endpoints to the browser:

1. **`/api/me`** - "who am I?" Returns the authenticated user's info, or 401 if not logged in.
2. **`/api/accounts` and `/api/transfers`** - the proxied banking endpoints.

`/api/me` is the one the SPA calls on load to decide whether to show the login button or the dashboard. The other endpoints look exactly like the bankapi endpoints but are reached via the BFF's session cookie instead of a bearer token.

### Task 7.1 -- Create UserController

Create `UserController.java` in the `controller` package:

```java
package com.example.bankbff.controller;

import com.example.bankbff.dto.UserInfoDto;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * User-info controller.
 *
 * The SPA calls /api/me on load to determine whether the user is logged in
 * and to display name and role. Returns 401 (handled by the security filter
 * chain) if the user is not authenticated.
 */
@RestController
@RequestMapping("/api")
public class UserController {

    @GetMapping("/me")
    public UserInfoDto me(@AuthenticationPrincipal OidcUser principal) {
        // TODO 7.1: Build a UserInfoDto from the OidcUser principal.
        //
        // OidcUser exposes the claims from the ID token. Use:
        //   principal.getSubject()                                   - the sub claim
        //   principal.getPreferredUsername()                         - login name
        //   principal.getFullName()                                  - the "name" claim
        //   principal.getClaimAsStringList("roles")                  - the roles claim
        //
        // If "roles" is missing, default to an empty list.
        //
        //   List<String> roles = principal.getClaimAsStringList("roles");
        //   if (roles == null) roles = List.of();
        //   return new UserInfoDto(
        //           principal.getSubject(),
        //           principal.getPreferredUsername(),
        //           principal.getFullName(),
        //           roles);

        return null;
    }
}
```

Fill in TODO 7.1.

> **Why `OidcUser`?** Because the BFF is registered with the `openid` scope, the auth server issues both an access token and an ID token. Spring populates the `Authentication` with an `OidcUser` principal that exposes the ID token claims directly. If you used the `profile` scope but not `openid`, you would get a plain `OAuth2User` instead and would need to call `.getAttributes()` for everything.

### Task 7.2 -- Create AccountController

Create `AccountController.java` in the `controller` package:

```java
package com.example.bankbff.controller;

import com.example.bankbff.client.BankingApiClient;
import com.example.bankbff.dto.AccountDto;
import com.example.bankbff.dto.TransferRequestDto;
import com.example.bankbff.dto.TransferResponseDto;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Account-proxy controller.
 *
 * Forwards browser requests to bankapi. The access token is attached
 * automatically by the WebClient filter.
 */
@RestController
@RequestMapping("/api")
public class AccountController {

    private final BankingApiClient bankingApiClient;

    public AccountController(BankingApiClient bankingApiClient) {
        this.bankingApiClient = bankingApiClient;
    }

    @GetMapping("/accounts")
    public List<AccountDto> accounts() {
        // TODO 7.2: Return bankingApiClient.getAccounts().
        return List.of();
    }

    @PostMapping("/transfers")
    public TransferResponseDto transfer(@RequestBody TransferRequestDto request) {
        // TODO 7.3: Return bankingApiClient.postTransfer(request).
        return null;
    }
}
```

Fill in TODOs 7.2 and 7.3.

### Verify Exercise 7

**Do a full cold restart of the BFF** before testing. Click the red **Stop** square in IntelliJ's Run panel and wait until the console says the process has exited. Then click the green **Run** button. Do not rely on Spring Boot DevTools to pick up the new controller and config beans - DevTools is unreliable for that on the first run and using a hot reload here is the most common cause of "my code looks right but doesn't seem to be loaded."

All three services should now be running:

- Authorization server on port 9000
- bankapi resource server on port 8081
- BFF on port 8080

Test the full flow in a browser:

1. Open `http://localhost:8080/oauth2/authorization/bank-auth`.
2. The auth server's login page appears.
3. Log in as `alice` / `password`.
4. The browser is redirected back to `http://localhost:8080/`. You may see a 404 page since we have not built a root page; that is fine. The session cookie is set.
5. Open DevTools (F12), go to the Application tab, find the cookies for `localhost`, and confirm there is a `BFF_SESSION` cookie. Note its `HttpOnly` flag.
6. In a new browser tab, visit `http://localhost:8080/api/me`. You should see a JSON response with alice's information: `subject=C001`, `preferredUsername=alice`, `fullName=Alice Nguyen`, `roles=[account_holder]`.
7. In the same tab, visit `http://localhost:8080/api/accounts`. You should see the five bank accounts (A001 through A005).

If all of these work, you have built a fully functional BFF.

If any step returns a redirect to the login page or a 401, jump to the **Troubleshooting** section at the end of this lab. Do not proceed to Exercise 8 with a broken setup - the `.http` tests there will appear to fail for what looks like cookie reasons but is really an upstream problem from this exercise.

---

## Exercise 8 -- Test with bank-requests.http

**Estimated time:** 10-15 minutes
**Topics covered:** Cookie-based session testing, the IntelliJ HTTP client, role-based behaviour

### Context

A complete BFF deserves a test file. IntelliJ's HTTP client (or the VS Code REST Client extension) lets you script HTTP requests in plain text and run them with one click. Most of this lab's HTTP testing has involved redirects through a browser, but once the session cookie is established you can exercise the API endpoints from a `.http` file.

### Task 8.1 -- Create bank-requests.http

In the `bankbff` project root, create `bank-requests.http`. Notice that every request includes an `Accept: application/json` header. This is what tells the BFF to treat the request as a programmatic API call. Without this header, the BFF assumes the request is browser navigation and may redirect to the login page (returning HTML) instead of returning a clean 401.

```http
### Banking BFF -- request examples

@bff = http://localhost:8080
@authServer = http://127.0.0.1:9000

###############################################################################
### 1. Verify the BFF is running and rejecting unauthenticated calls.
### Should return 401 Unauthorized.
###############################################################################

### Unauthenticated /api/me -- expect 401
GET {{bff}}/api/me
Accept: application/json

### Unauthenticated /api/accounts -- expect 401
GET {{bff}}/api/accounts
Accept: application/json


###############################################################################
### 2. Log in via a browser, then paste the BFF_SESSION cookie value below.
###
### To get the cookie:
###   - Open http://localhost:8080/oauth2/authorization/bank-auth in a browser.
###   - Log in as alice / password.
###   - Open DevTools, go to Application > Cookies > localhost.
###   - Copy ONLY the value of the BFF_SESSION cookie, NOT the name.
###
### IMPORTANT: keep the "BFF_SESSION=" prefix on the line below and replace
### only "PASTE_THE_COOKIE_VALUE_HERE" with the value you copied. A Cookie
### header without a name (e.g. "Cookie: 953989EFE...") is invalid and the
### server will treat the request as unauthenticated.
###
### Every time you restart the BFF, the old cookie value becomes stale and
### you must log in again to get a fresh one. Sessions are server-side; they
### do not survive a restart.
###############################################################################

@sessionCookie = BFF_SESSION=PASTE_THE_COOKIE_VALUE_HERE


###############################################################################
### 3. Authenticated requests
###############################################################################

### /api/me -- expect 200 with user info
GET {{bff}}/api/me
Accept: application/json
Cookie: {{sessionCookie}}

### /api/accounts -- expect 200 with the account list
GET {{bff}}/api/accounts
Accept: application/json
Cookie: {{sessionCookie}}

### /api/transfers -- expect 200 with a transaction ID
POST {{bff}}/api/transfers
Accept: application/json
Cookie: {{sessionCookie}}
Content-Type: application/json

{
  "fromAccountId": "A001",
  "toAccountId": "A002",
  "amount": 100.00
}

### /api/accounts again -- A001 balance should be lower, A002 should be higher
GET {{bff}}/api/accounts
Accept: application/json
Cookie: {{sessionCookie}}


###############################################################################
### 4. Logout and verify the session is gone.
###############################################################################

### POST /logout -- expect 200 (or 204 No Content)
POST {{bff}}/logout
Accept: application/json
Cookie: {{sessionCookie}}

### /api/me after logout -- expect 401
GET {{bff}}/api/me
Accept: application/json
Cookie: {{sessionCookie}}
```

### Task 8.2 -- Run the requests in order

**Before running anything, confirm all three services are running:**

- Auth server on port 9000 (browser test: open `http://127.0.0.1:9000/.well-known/openid-configuration` and confirm `"issuer": "http://127.0.0.1:9000"` appears in the JSON)
- bankapi on port 8081 (browser test: open `http://localhost:8081/api/v1/accounts` and confirm you get `401 Unauthorized` - that proves it is running and enforcing tokens)
- BFF on port 8080 (will be tested by step 1 below)

Run the requests in order:

1. Run the unauthenticated requests. Both should return 401.
2. In a browser, log in via `http://localhost:8080/oauth2/authorization/bank-auth` as `alice` / `password`.
3. Copy the `BFF_SESSION` cookie value from DevTools and paste it in place of `PASTE_THE_COOKIE_VALUE_HERE`. Keep the `BFF_SESSION=` prefix in your `@sessionCookie` line.
4. Run the authenticated requests. They should all succeed.
5. Run the transfer request. The response should contain a `transactionId` and `status: COMPLETE`.
6. Re-run `GET /api/accounts`. The balance of `A001` should be 100 less than before (initial 1250.00 - 100 = 1150.00), and the balance of `A002` should be 100 more than before (initial 8400.00 + 100 = 8500.00).
7. Run `POST /logout`.
8. Run `GET /api/me` again. It should now return 401.

If all of these work, the BFF is complete.

> **If anything fails along the way:** jump to the **Troubleshooting** section at the end of this lab. The most common cause is a stale `BFF_SESSION` value after restarting the BFF.

### Optional - try other users

Repeat steps 2-6 logging in as a different user. The BFF's behaviour changes based on whose token it holds:

- **`edward` / `password`** (teller, EM01) - sees all accounts. Can transfer.
- **`audit` / `password`** (auditor, AUD01) - sees all accounts. **Cannot transfer**, because the auditor role does not include `transaction.create`. Try the transfer call; it should return 403 from bankapi.

This is the role-based behaviour from Lab 2-1 finally paying off at the BFF layer. The BFF itself enforces nothing about roles - it just forwards the request with the user's token. The resource server checks the scope, and the token customizer narrowed the scopes based on the user's role at issue time.

---

## Troubleshooting

This lab has three Spring Boot apps, a browser-issued session cookie, an OAuth token flow, and a `.http` file all interacting. When something fails, the error message often points at the wrong layer. This section walks through the common failures and how to localize the actual problem.

### Step 1: Diagnose where the failure is

When you get a 401 or a redirect from one of your `.http` requests, the first job is to figure out *which* service is rejecting you. Use this decision tree.

**Question 1: Does `GET /api/me` work?**

Visit `http://localhost:8080/api/me` in your browser with the same session you are testing with. Open it in the SAME browser session where you logged in.

- **You see alice's JSON info → the BFF session is fine.** The problem is in the BFF -> bankapi call. Skip to Step 3 below.
- **You are redirected to the auth server login page → the BFF does not recognize your session.** Skip to Step 2 below.

`/api/me` is a useful diagnostic because it does not touch the WebClient. It just reads the OIDC principal out of the session and returns it. If it works, your authentication is fine; if it fails, your session is gone.

**Question 2: Count the redirects in your `.http` response chain**

When IntelliJ's HTTP client follows redirects, it prints them in the response panel under `Redirections:`. Count them:

- **One redirect** (`/api/x` -> `127.0.0.1:9000/oauth2/authorize`): The BFF accepted your session but the downstream call to bankapi failed. The BFF interpreted the failure as "my OAuth token is no good" and re-initiated the login flow. The actual error is at bankapi.

- **Two redirects** (`/api/x` -> `localhost:8080/oauth2/authorization/bank-auth` -> `127.0.0.1:9000/oauth2/authorize`): The BFF did not see a valid session at all. Your cookie is missing, malformed, or stale.

The redirect count is the single fastest way to tell apart "the BFF did not recognize me" from "the BFF tried to call bankapi and bankapi said no."

**Question 3: Does bankapi log anything?**

Watch the bankapi console at the moment you make the failing request.

- **Bankapi logs a JWT validation message** (something like `JWT validation failed: ...`): Skip to Step 4 below.
- **Bankapi logs nothing**: The request never reached bankapi. The 401 you see is coming from the BFF itself, not bankapi. The BFF's WebClient filter could not get an access token to attach, so the call was abandoned. Most likely your BFF session is stale and the manager could not find an authorized client for the current user.

### Step 2: BFF does not recognize my session

**Likely cause: stale `BFF_SESSION` cookie**

Server-side sessions die when the BFF restarts. The cookie value in your `.http` file refers to a session that no longer exists. Every time you restart the BFF, you must:

1. Log in again in the browser at `http://localhost:8080/oauth2/authorization/bank-auth`
2. Open DevTools (F12) -> Application -> Cookies -> `localhost`
3. Copy the new `BFF_SESSION` value
4. Paste it into your `.http` file's `@sessionCookie` line, keeping the `BFF_SESSION=` prefix

**Other possible causes:**

- The cookie variable in your `.http` file is missing the `BFF_SESSION=` prefix. A line that reads `@sessionCookie = 953989EFE...` produces a malformed `Cookie:` header that the server ignores. The correct form is `@sessionCookie = BFF_SESSION=953989EFE...`.
- The cookie was set on `127.0.0.1` but your request goes to `localhost` (or vice versa). The browser scopes cookies by hostname. Confirm both your login URL (`localhost:8080`) and your test requests use `localhost`, not `127.0.0.1`. The auth server is the only thing on `127.0.0.1` in this lab.
- The `Accept: application/json` header is missing from your request. Without it, the BFF treats the request as browser navigation and may redirect to login differently. All authenticated `.http` requests in this lab include `Accept: application/json`.
- The `.http` file is sending a non-`BFF_SESSION` cookie left over from earlier sessions. Inspect the actual `Cookie:` header IntelliJ is sending. The IntelliJ HTTP client preserves cookies across requests in `.idea/httpRequests/http-client.cookies` - this can confuse tests. If in doubt, clear that file and rely only on `@sessionCookie`.

### Step 3: BFF -> bankapi call fails

You established that `/api/me` works but `/api/accounts` does not. This means the BFF's call to bankapi is failing.

Watch the bankapi console at the moment of the failure.

**If bankapi logs nothing, the request never reached it.** The BFF's `OAuth2AuthorizedClientManager` could not produce a token. Most likely you have a stale BFF session and need to log in again (the `OAuth2AuthorizedClient` lives in the session). Re-log-in and refresh the `@sessionCookie` value.

**If bankapi logs an issuer-mismatch error** like *"The iss claim is not equal to the configured issuer"*: The auth server is issuing tokens with one issuer but bankapi is configured to expect a different one. Check that bankapi's `application.yml` has `issuer-uri: http://127.0.0.1:9000` (not `localhost`). Also confirm the auth server's discovery document at `http://127.0.0.1:9000/.well-known/openid-configuration` shows `"issuer": "http://127.0.0.1:9000"`. All three (token, bankapi config, discovery doc) must use the same host.

**If bankapi logs a signature error** like *"Signed JWT rejected"* or *"Unable to find a signing key for kid"*: bankapi cached an old JWKS from before the auth server restarted. Restart bankapi to clear its JWKS cache, then log in again to get a fresh token.

**If bankapi logs an expired-token error**: your access token's 5-minute lifetime ran out. Log in again to get a fresh one. The BFF will refresh tokens automatically when the refresh token is still valid, but if the BFF session was created over an hour ago (the access token + refresh token lifetimes), you need a fresh login.

**If bankapi logs a 403 (not 401)**: the token is valid but the user lacks the required scope. The audit user, for example, lacks `transaction.create` and will get 403 on `POST /api/transfers`. This is correct enforcement, not a bug.

### Step 4: My code looks right but does not seem to be loaded

This is rare but worth knowing about. Symptoms include:

- The startup log shows `Will secure any request with filters: ...` without the filters you configured
- A `@Bean` you defined does not seem to take effect
- A `@PostConstruct` log statement you added never prints
- The behavior is exactly the same as the Spring Boot default, even after editing your code

**Cause:** Spring Boot DevTools or IntelliJ's hot-reload missed your change. The class file in `target/classes` is stale, or DevTools restart applied to the wrong classloader.

**Fix:**

1. In the IntelliJ Run panel, click the red **Stop** square. Wait for the process to fully exit.
2. **Build -> Rebuild Project** to force a full recompile.
3. Click the green **Run** button (this is a cold start, not a hot reload).
4. Watch the startup banner appear (the Spring Boot ASCII art). A cold start prints this; a hot reload does not.
5. Note the "Started ... in X.XX seconds (process running for Y.YY)" line at the end. For a true cold start, X.XX and Y.YY are about the same (within a second of each other). If "process running for" is many seconds longer than the startup time, you got a hot reload, not a cold start.

If even a cold rebuild does not pick up your change, the issue is something more unusual:

- **Missing `@EnableWebSecurity`** on `SecurityConfig`. Spring Boot is documented to auto-detect `SecurityFilterChain` beans without this annotation, but auto-detection is fragile - your bean can be silently overridden by the default chain. The fix is always to add `@EnableWebSecurity` explicitly alongside `@Configuration`. This is the form used throughout this lab.
- **File in the wrong package**, outside the component-scan path of `BankbffApplication` (which is in `com.example.bankbff` and scans that and all sub-packages).
- **Conflicting bean from another `@Configuration` class** declaring its own `SecurityFilterChain`. Search the project: `find src -name "*.java" -exec grep -l "SecurityFilterChain" {} \;`. There should be exactly one match.
- **Missing `@Configuration` annotation** entirely. Use `javap -v` on the compiled class file (in `target/classes/...`) to confirm the annotations are present in the bytecode.

### After-restart checklist

Every time you restart the BFF, follow this sequence before running any `.http` tests:

1. Confirm the BFF has finished starting (look for `Started BankbffApplication in ...` in the console).
2. Confirm the auth server and bankapi are still running.
3. Log in fresh in the browser at `http://localhost:8080/oauth2/authorization/bank-auth`.
4. Copy the new `BFF_SESSION` value from DevTools.
5. Update `@sessionCookie` in your `.http` file.
6. Run the tests.

Skipping any of these steps tends to produce the symptom "it worked yesterday but does not work now."

---

## What You Have Built

The BFF you have built does several things at once:

- **Acts as an OAuth client.** Initiates the Authorization Code flow against the auth server when a user is not yet logged in. The OAuth client metadata is in `application.yml`; Spring Security wires up everything else from that configuration.
- **Holds the OAuth tokens server-side.** The access token and refresh token live in the BFF's session storage, keyed by the session cookie. The browser never sees them.
- **Issues an HttpOnly session cookie.** This is the only credential the browser ever sees. Tokens never reach JavaScript. An XSS vulnerability in the SPA cannot exfiltrate the tokens because they are not in the browser.
- **Translates session cookies into bearer tokens.** When the browser calls `/api/accounts` with a session cookie, the BFF reads the cookie, looks up the access token, attaches it to a call to bankapi, and returns the result.
- **Refreshes tokens transparently.** The `OAuth2AuthorizedClientManager` refreshes the access token using the refresh token whenever the access token expires, without the user noticing.
- **Exposes a clean session-cookie API for the SPA.** From the SPA's perspective, `/api/me` and `/api/accounts` are just normal endpoints. No OAuth complexity reaches the browser.

This is the architectural pattern that the next lab (Lab 4.7) will rely on. The React app you built in Lab 4.5 will be wired up to call this BFF, replacing the mock service worker. The fetch calls in the React code will not need to change.

---

## Reflection Questions

In a new file `lab-b-notes.md` in the `bankbff` project root, answer these:

1. The BFF uses the `authorization_code` grant. The other bank clients in Lab 2-1 use `client_credentials` (`bank-service`) or `authorization_code + PKCE` without a secret (`bank-spa`). What is the practical difference between these three grants? When would you use each?

2. After logging in, the browser holds only a `BFF_SESSION` cookie. What threats does this protect against compared to storing the access token in browser JavaScript?

3. The `WebClient` has the OAuth2 filter applied. What would happen if you used a different `WebClient` (for example, the default `WebClient.builder().build()`) to call the resource server? Why?

4. If the access token expires during a long user session, what does the BFF do? What does the user see?

5. CSRF protection is disabled in this lab. What kind of attack does CSRF protect against, and why is it more relevant for cookie-authenticated APIs than for bearer-token APIs? You will turn CSRF on in Lab 4.7; what changes?

6. The BFF lab uses dotted scope names (`account.read`, `transaction.create`) inherited from Lab 2-1. The original module slides mentioned colon-separated scopes (`read:accounts`) as an alternative. What does the BFF actually care about - the scope name itself, or just that the auth server and resource server agree?

---

