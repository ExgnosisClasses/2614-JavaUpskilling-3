# Lab 2-2: Resource Server, Claims, and Method Security
## Hands-On Exercises

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 3 - OAuth2 / OIDC Foundations and Spring Security
> **Estimated time per exercise:** 30–60 minutes

---

## How to Use These Exercises

Each exercise is self-contained and builds directly on the concepts introduced in the module lectures. They are designed to be completed in IntelliJ IDEA using a Spring Boot project generated from Spring Initializr.

- **Context:** why this concept matters and what problem it solves
- **Setup:** how to structure the project and files before you start
- **Tasks:** step-by-step work to complete, including starter code with `TODO` markers
- **Checkpoints:** questions that test conceptual understanding, not just code completion

> **Optional extension exercises** for faster learners are provided in a separate file, `Lab_2-2_Extension.md`. They are not required to complete the module but offer deeper challenges that may need additional research or experimentation. Suggested solutions are provided at the end of the module.

> **Tip:** Work through the exercises in order. Each one builds on the project structure established in the first. If you get stuck on a `TODO`, re-read the relevant section of the lecture slides before looking at the solution file.

---

## Before You Start: The Authorization Server

These exercises require the Authorization Server you built in **Lab 2-1** to be running. If it is not currently running, start it now before continuing.

Confirm it is ready by opening this URL in your browser:

```
http://localhost:9000/oauth2/jwks
```

You should see a JSON response containing an RSA public key. If you see an error, start the `authserver` project and wait for it to finish starting before proceeding.

### Required patch to the Authorization Server before Exercise 1

Before going further, apply a one-line fix to the Lab 2-1 Authorization Server. Without it, every client-credentials request in this lab will fail with `401 invalid_client` and you will not be able to obtain a service token.

**What the problem is.** The Lab 2-1 `passwordEncoder` bean is a plain `BCryptPasswordEncoder`, which works for user logins (the user passwords are BCrypt-hashed at startup and verified the same way). The same bean is also used by Spring Authorization Server to verify **client** secrets. The `bank-service` client's secret is stored as `{noop}bank-service-secret`, meaning "stored as plain text, do not hash." A pure BCrypt encoder does not understand the `{noop}` prefix - it tries to BCrypt-verify the literal string, fails, and logs a warning like:

```
WARN  o.s.s.c.bcrypt.BCryptPasswordEncoder : Encoded password does not look like BCrypt
DEBUG ClientSecretAuthenticationProvider : Invalid request: client_secret does not match for registered client '<uuid>'
```

The fix is to replace the encoder with `DelegatingPasswordEncoder`, which reads the `{prefix}` on each stored value and routes to the matching encoder (`{noop}` → plain text, `{bcrypt}` → BCrypt, etc.). Spring ships a factory that builds one preconfigured with every standard prefix.

**Apply the fix.** In the Lab 2-1 project, open `AuthorizationServerConfig.java`. Find the `passwordEncoder` bean and replace it:

```java
import org.springframework.security.crypto.factory.PasswordEncoderFactories;

@Bean
public PasswordEncoder passwordEncoder() {
    return PasswordEncoderFactories.createDelegatingPasswordEncoder();
}
```

Remove the now-unused `BCryptPasswordEncoder` import if your IDE doesn't strip it automatically.

**Restart the Authorization Server.** User login continues to work unchanged - `encoder.encode("password")` now produces a `{bcrypt}$2a$10$...` prefixed hash instead of a raw BCrypt hash, but it is still BCrypt, so verification still succeeds. Client-credentials requests with the `{noop}`-prefixed secret now succeed because the delegating encoder routes them through the noop path.

**Verify the fix.** From a terminal:

```bash
curl -u "bank-service:bank-service-secret" \
     -d "grant_type=client_credentials&scope=account.read transaction.read" \
     http://localhost:9000/oauth2/token
```

You should receive a JSON response containing an `access_token`. If you still get `invalid_client`, the Authorization Server has not been restarted since the edit.

---

**Authorization Server reference - values you will use throughout these exercises:**

| Item | Value |
|---|---|
| JWKS endpoint | `http://localhost:9000/oauth2/jwks` |
| Issuer URI | `http://localhost:9000` |
| Token endpoint | `http://localhost:9000/oauth2/token` |
| Service client ID | `bank-service` |
| Service client secret | `bank-service-secret` |
| User: `alice` (password `password`) | `sub`=C001, role `account_holder`, owns accounts A001 and A002 |
| User: `bob` (password `password`) | `sub`=C002, role `account_holder`, owns account A003 |
| User: `carla` (password `password`) | `sub`=C003, role `account_holder`, owns accounts A004 and A005 |
| User: `edward` (password `password`) | `sub`=EM01, role `teller` |
| User: `audit` (password `password`) | `sub`=AUD01, role `auditor` |

> **The key design decision carried forward from Lab 2-1:** the `sub` claim is the *stable domain identifier* (customer ID `C001`, employee ID `EM01`, auditor ID `AUD01`), not the login name. This is what makes ownership checks in these exercises a one-line `account.customerId().equals(authentication.getName())` - no translation step required.

---

## Tools Used in These Exercises

- **jwt.io**: paste any JWT at [https://jwt.io](https://jwt.io) to decode the header and payload immediately
- **IntelliJ HTTP Client**: `.http` files work the same way as in Module 2

---

## Starter Project

All exercises share a single Spring Boot project for the Bank API (the Resource Server). Create it now.

### Create the project with Spring Initializr

1. Open [https://start.spring.io](https://start.spring.io) in a browser
2. Configure the project as follows:

| Setting | Value |
|---|---|
| Project | Maven |
| Language | Java |
| Spring Boot | 3.2.x (match Lab 2-1) |
| Group | `com.example` |
| Artifact | `bankapi` |
| Packaging | Jar |
| Java | 21 |

3. Add the following dependencies:
   - **Spring Web**
   - **Spring Security**
   - **OAuth2 Resource Server**
   - **Spring Boot DevTools**
   - **Validation**

4. Click **Generate**, unzip, and open in IntelliJ using **File → Open → New Window**

5. Confirm there are no Maven download errors in the Maven tool window

> **Spring Boot version:** as in Lab 2-1, set the `<parent>` version in `pom.xml` to `3.2.5`. Spring Initializr defaults to 3.5, but we need the same line as the Authorization Server for compatibility.

### Verify the project starts and notice what Spring Security does

Run `BankapiApplication.java`. You should see:

```
Using generated security password: 8f3a1b9c-4d2e-4f7a-9c3e-1b2d3e4f5a6b
Started BankapiApplication in X.XXX seconds
```

However, you may not depend on the logging level. If you don't see it, don't worry - you don't really need the credentials.

Open `http://localhost:8080/` in your browser. Spring Security has locked everything and redirected you to a login form. This is the **secure by default** behaviour described in the lecture. You have not written a single line of security configuration yet.

### Package structure to create before Exercise 1

Right-click `src/main/java/com/example/bankapi` and create the following sub-packages:

```
com.example.bankapi
├── config
├── controller
├── model
└── service
```

---

## Exercise 1 - Decoding JWTs and Understanding the Token Structure

**Estimated time:** 30–40 minutes
**Topics covered:** JWT structure (header, payload, signature), registered claims (`sub`, `iss`, `aud`, `exp`, `iat`), OIDC standard claims (`preferred_username`, `name`), scopes, roles, what a valid signature proves and what it does not

### Context

Before configuring Spring Security to validate tokens you need to understand what a JWT actually contains. This exercise is primarily analytical. You will obtain a real token from the Authorization Server, decode it, read the claims, and reason about the security implications.

A valid signature proves the token was issued by a trusted Authorization Server and has not been tampered with. A valid signature does not prove the token has not been stolen, and does not prove the user's permissions are still current. Understanding this distinction shapes how you design token lifetimes and scope granularity.

You will also see directly how the Authorization Server's token customizer (which you built in Lab 2-1) shapes the contents of the JWT - the `sub` rewrite, the `preferred_username` and `name` additions, and the scope-intersection step are all observable in the decoded payload.

### Task 1.1 - Obtain a service token

Create `auth-requests.http` in the **bankapi** project root. This file gives you a convenient way to obtain tokens from the Authorization Server throughout the exercises:

```http
### Client Credentials token -- service identity, no user involved.
### The Authorization header is Base64("bank-service:bank-service-secret").
POST http://localhost:9000/oauth2/token
Authorization: Basic YmFuay1zZXJ2aWNlOmJhbmstc2VydmljZS1zZWNyZXQ=
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=account.read transaction.read

###

### Authorization Code flow -- Step 1.
### Open the URL below manually in your browser (do not run it as an HTTP request).
### Log in as alice / password and approve the scopes on the consent screen.
### The browser redirects to http://127.0.0.1:9000/authorized?code=XXXX
### Copy the "code" query parameter value from the URL bar before it expires.
###
### IMPORTANT: the authorize URL host (127.0.0.1) MUST match the redirect_uri
### host (127.0.0.1). Using "localhost" for one and "127.0.0.1" for the other
### will cost you a second login -- the browser treats them as different origins.
###
### URL to open in browser:
### http://127.0.0.1:9000/oauth2/authorize?response_type=code&client_id=bank-spa&redirect_uri=http://127.0.0.1:9000/authorized&scope=openid%20profile%20account.read%20account.write%20account.create%20transaction.read%20transaction.create%20customer.read%20customer.write&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=abc123

###

### Authorization Code flow -- Step 2.
### Replace CODE_FROM_BROWSER with the value from the browser URL bar.
### The code_verifier matches the code_challenge in the URL above.
POST http://127.0.0.1:9000/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=CODE_FROM_BROWSER
&redirect_uri=http://127.0.0.1:9000/authorized
&client_id=bank-spa
&code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
```

Execute the Client Credentials request. Copy the `access_token` value from the response.

### Task 1.2 - Decode the token and answer the following questions

Navigate to [https://jwt.io](https://jwt.io) and paste the token into the **Encoded** panel. Create a file called `token-analysis.md` in the project root and write your answers there.

**Header questions:**

1. What is the value of `alg`? What does this tell the Resource Server about how to verify the signature?
2. What is the value of `kid`? Navigate to `http://localhost:9000/oauth2/jwks`. Find the key whose `kid` matches the token header. This is the specific public key the Resource Server will use to verify this token.
3. Why does the Authorization Server use RS256 rather than HS256? What problem does the asymmetric approach solve in a multi-service architecture?

**Payload questions (service token):**

4. What is the `sub` claim in this service token? How does it differ from what you would expect to see in a token issued to alice after she logs in interactively (think back to Lab 2-1's token customizer)?
5. What is the `iss` claim? Compare it to the `issuer` value in `http://localhost:9000/.well-known/oauth-authorization-server`. Where is this value configured in the Authorization Server?
6. What is the `aud` claim? Describe the attack that audience validation prevents.
7. Calculate the token lifetime by subtracting `iat` from `exp`. Both are Unix timestamps (seconds since 1 January 1970). Does this match the `accessTokenTimeToLive` configured for `bank-service` in the Authorization Server?
8. What scopes are present? Compare them to the scopes requested in the token request.
9. Are `roles`, `preferred_username`, or `name` present in this service token? Why or why not? (Re-read the `tokenCustomizer` bean in `AuthorizationServerConfig.java` from Lab 2-1 if you need a reminder.)

**Signature questions:**

10. Copy the value of `n` from `http://localhost:9000/oauth2/jwks` and paste it into the public key field at jwt.io. Does the signature now verify? What does a successful verification confirm?
11. Restart the Authorization Server. Obtain a new token. Try to verify the new token using the public key value you copied in question 10. Does it verify? Explain why not, and what this implies for production key rotation.

### Task 1.3 - Reason about the stale permissions problem

Write a short paragraph (3–5 sentences) in `token-analysis.md` describing the following scenario:

> Carla (account holder, sub=C003) authenticates at 09:00 and receives a token with a 5-minute lifetime. At 04:00 into the token's life, a fraud investigation results in her account being frozen and her role downgraded by an administrator. At 04:30 she makes a request using the token issued at 09:00.

Will the Resource Server accept or reject this request? What claim protects against this problem and what is its limitation? What is the significance of the 5-minute lifetime, and what is the trade-off of making it shorter?

### Checkpoints

1. You observed in question 11 that restarting the Authorization Server invalidates all existing tokens because a new RSA key pair is generated. In a production system, how is the key pair managed to avoid this problem?
2. The service token does not contain `roles`, `preferred_username`, or `name` claims. Looking at the `tokenCustomizer` in the Authorization Server, identify exactly which condition prevents these claims from being added to service tokens.
3. A colleague suggests caching JWTs by their `jti` value to detect replay attacks. What additional infrastructure does this require, and what availability risk does it introduce?

---

## Exercise 2 - Configuring Spring Security as a Resource Server

**Estimated time:** 40–50 minutes
**Topics covered:** `SecurityFilterChain`, `HttpSecurity` DSL, `oauth2ResourceServer` configuration, `SessionCreationPolicy.STATELESS`, CSRF, `authorizeHttpRequests`, `issuer-uri` and `jwks-uri`

### Context

In the previous exercise you analysed a JWT manually. Now you will configure Spring Security to validate JWTs automatically on every incoming request. This is the Resource Server role: your service trusts nothing except a cryptographically valid token from the Authorization Server on port 9000.

The lecture emphasised that adding `spring-boot-starter-security` locks everything down immediately. Your job is to replace that default with a configuration that matches the security contract of your API: JWT authentication, stateless sessions, and URL-level access rules tied to OAuth2 scopes.

### Task 2.1 - Create the domain models and controllers

Create the three domain models in the `model` package.

`Account.java`:

```java
package com.example.bankapi.model;

import java.math.BigDecimal;

public record Account(
        String id,           // e.g. "A001"
        String customerId,   // e.g. "C001" -- matches the customer's sub claim
        String accountType,  // "CHECKING", "SAVINGS"
        BigDecimal balance
) {}
```

`Customer.java`:

```java
package com.example.bankapi.model;

public record Customer(
        String id,           // e.g. "C001" -- matches the sub claim of the corresponding user
        String fullName,
        String email
) {}
```

`Transaction.java`:

```java
package com.example.bankapi.model;

import java.math.BigDecimal;
import java.time.Instant;

public record Transaction(
        String id,           // e.g. "T001"
        String accountId,    // FK to Account.id
        String type,         // "DEPOSIT", "WITHDRAWAL", "TRANSFER"
        BigDecimal amount,
        Instant timestamp
) {}
```

Create `AccountController.java` in the `controller` package:

```java
package com.example.bankapi.controller;

import com.example.bankapi.model.Account;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;

@RestController
@RequestMapping("/api/v1/accounts")
public class AccountController {

    private static final List<Account> ACCOUNTS = List.of(
            new Account("A001", "C001", "CHECKING", new BigDecimal("1250.00")),
            new Account("A002", "C001", "SAVINGS",  new BigDecimal("8400.00")),
            new Account("A003", "C002", "CHECKING", new BigDecimal("300.50")),
            new Account("A004", "C003", "CHECKING", new BigDecimal("2100.75")),
            new Account("A005", "C003", "SAVINGS",  new BigDecimal("15000.00"))
    );

    @GetMapping
    public List<Account> getAll() {
        return ACCOUNTS;
    }

    @GetMapping("/{id}")
    public ResponseEntity<Account> getById(@PathVariable String id) {
        return ACCOUNTS.stream()
                .filter(a -> a.id().equals(id))
                .findFirst()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    // TODO 1: Add a POST endpoint that accepts an Account in the request body
    // and returns 201 Created with the account in the response body.
    // The endpoint does not need to persist the account -- this is a stub.
    // Annotate the parameter with @RequestBody.
    // Use ResponseEntity.status(HttpStatus.CREATED).body(account) as the return value.
}
```

Create `HealthController.java` in the `controller` package:

```java
package com.example.bankapi.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;

@RestController
public class HealthController {

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
```

> **About the other two models:** `Customer` and `Transaction` will be wired in during Exercise 3 (claims in code) and Exercise 4 (method security). Creating them now lets you import them later without context-switching.

### Task 2.2 - Configure the Resource Server

Create `SecurityConfig.java` in the `config` package:

```java
package com.example.bankapi.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {

        http
            // TODO 2: Configure authorization rules using authorizeHttpRequests().
            // Rules:
            //   - GET  /health                       -- permitAll()
            //   - GET  /api/v1/accounts/**           -- hasAuthority("SCOPE_account.read")
            //   - POST /api/v1/accounts              -- hasAuthority("SCOPE_account.create")
            //   - anyRequest()                       -- authenticated()
            // Rules are evaluated in order. Specific rules must come before general ones.
            .authorizeHttpRequests(auth -> auth
                    .requestMatchers(HttpMethod.GET, "/health").permitAll()
                    // Add your rules here
                    .anyRequest().authenticated()
            )

            // TODO 3: Configure the OAuth2 Resource Server to validate JWT Bearer tokens.
            // Use: .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            // This activates JWT extraction, JWKS key fetching, signature verification,
            // and claims-to-authorities mapping. Spring Security calls the jwks-uri
            // configured in application.yml to fetch the verification keys.

            // TODO 4: Configure session management to STATELESS.
            // Use: .sessionManagement(session -> session
            //          .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            // A REST API using Bearer tokens has no need for HTTP sessions.

            // TODO 5: Disable CSRF protection.
            // Use: .csrf(csrf -> csrf.disable())
            // CSRF attacks rely on browsers automatically sending session cookies.
            // Bearer tokens are not sent automatically, so CSRF does not apply here.
            ;

        return http.build();
    }
}
```

### Task 2.3 - Point the Resource Server at the Authorization Server

Create or update `src/main/resources/application.yml` in the **bankapi** project:

```yaml
server:
  port: 8080

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          # Spring Security fetches the public keys from this endpoint on startup
          # and caches them. The key whose "kid" matches the incoming token's
          # "kid" header claim is used to verify the signature.
          jwks-uri: http://localhost:9000/oauth2/jwks

          # The expected value of the "iss" claim in every incoming token.
          # Tokens where "iss" does not equal this value are rejected with 401.
          issuer-uri: http://localhost:9000
```

### Task 2.4 - Test the security configuration

Ensure both the Authorization Server (port 9000) and the Bank API (port 8080) are running. Add the following to `auth-requests.http`:

```http
### Step 1: Obtain a service token (run this first).
POST http://localhost:9000/oauth2/token
Authorization: Basic YmFuay1zZXJ2aWNlOmJhbmstc2VydmljZS1zZWNyZXQ=
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=account.read transaction.read

###

### Step 2: Health endpoint -- no token required, should return 200.
GET http://localhost:8080/health

###

### Step 3: Accounts with no token -- should return 401.
GET http://localhost:8080/api/v1/accounts

###

### Step 4: Accounts with a valid token -- should return 200.
### Paste the access_token from Step 1.
GET http://localhost:8080/api/v1/accounts
Authorization: Bearer <paste-access-token-here>

###

### Step 5: POST with read scopes only -- should return 403.
### The service token has account.read but NOT account.create.
POST http://localhost:8080/api/v1/accounts
Authorization: Bearer <paste-access-token-here>
Content-Type: application/json

{
  "id": "A006",
  "customerId": "C002",
  "accountType": "SAVINGS",
  "balance": 500.00
}
```

Execute each request in order and record the HTTP status code for each in `token-analysis.md`. The 403 on Step 5 confirms scope-based URL authorization is working correctly.

### Checkpoints

1. You added `@EnableWebSecurity` to `SecurityConfig`. What does Spring Boot's auto-configuration do when it detects this annotation? What default behaviour does your `SecurityFilterChain` bean replace?
2. The `/health` endpoint uses `permitAll()`. Explain why `anonymous()` would be a less correct choice even though both allow unauthenticated access.
3. You disabled CSRF. Describe precisely the condition that must be true for it to be safe to disable CSRF on a REST API endpoint.
4. Your authorization rules check for `SCOPE_account.read`. The token's `scope` claim contains `account.read` without a prefix. Where does the `SCOPE_` prefix come from, and which Spring Security component adds it?

---

## Exercise 3 - Accessing JWT Claims in Application Code

**Estimated time:** 30–40 minutes
**Topics covered:** `SecurityContextHolder`, the `Authentication` object, `JwtAuthenticationToken`, extracting claims from the JWT, audit logging, ownership checks

### Context

Once Spring Security has validated a token and populated the `SecurityContext`, your application code can read the authenticated identity and its claims. This is how you implement ownership checks and audit logging.

The `Authentication` object is the central data structure that flows through both the filter chain and method security. In a JWT Resource Server application the concrete type is `JwtAuthenticationToken`, which exposes the original JWT and all its claims.

This is the exercise where the Lab 2-1 design choice (`sub` = customer ID) pays off most visibly. When alice (sub=C001) calls `GET /api/v1/accounts/A001`, `authentication.getName()` returns `"C001"` directly - the same value as `Account.customerId()`. No translation step, no extra database lookup, no helper service that maps usernames to customer IDs.

### Task 3.1 - Read the current identity in a controller

Add the following method to `AccountController`:

```java
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import java.util.HashMap;
import java.util.Map;

// TODO 6: Complete this endpoint.
// @AuthenticationPrincipal instructs Spring Security to inject the validated Jwt
// from the SecurityContext directly as a method parameter.
// This is cleaner than calling SecurityContextHolder.getContext() manually.
@GetMapping("/me")
public Map<String, Object> getCurrentUser(@AuthenticationPrincipal Jwt jwt) {
    // TODO 7: Return a Map containing:
    //   "subject"            -- jwt.getSubject()
    //   "issuer"             -- jwt.getIssuer().toString()
    //   "scopes"             -- jwt.getClaimAsString("scope")
    //   "tokenExpiry"        -- jwt.getExpiresAt().toString()
    //   "roles"              -- jwt.getClaimAsStringList("roles"), or an empty list if null
    //   "preferredUsername"  -- jwt.getClaimAsString("preferred_username"), or "not present"
    //   "fullName"           -- jwt.getClaimAsString("name"), or "not present"
    //
    // The service token will NOT have "roles", "preferred_username", or "name"
    // because the token customizer in the Authorization Server only adds those
    // for user-context tokens. This difference is the main thing to observe.
    return Map.of(); // Replace with your implementation
}
```

Add a test request to `auth-requests.http`:

```http
### Current identity -- observe which claims are present for a service token.
GET http://localhost:8080/api/v1/accounts/me
Authorization: Bearer <paste-service-token-here>
```

Execute the request. Confirm that `roles` is empty and `preferredUsername` and `fullName` show "not present". This directly demonstrates the difference between service-identity tokens and user-identity tokens.

### Task 3.2 - Access the SecurityContext in a service class

`@AuthenticationPrincipal` only works in controller methods. Inside a service class you must read from the `SecurityContextHolder` directly. Create `AuditService.java` in the `service` package:

```java
package com.example.bankapi.service;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import java.time.Instant;

@Service
public class AuditService {

    public void logEvent(String action, String resourceId) {
        // TODO 8: Retrieve the Authentication from the SecurityContextHolder.
        // Use SecurityContextHolder.getContext().getAuthentication()
        // Then use pattern matching to check if the principal is a Jwt:
        //   if (auth != null && auth.getPrincipal() instanceof Jwt jwt) { ... }

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        String subject = "anonymous";

        if (auth != null && auth.getPrincipal() instanceof Jwt jwt) {
            // TODO 9: Assign the subject from jwt.getSubject() to the subject variable.
            // Remember: this will be a customer ID (C001), employee ID (EM01),
            // or auditor ID (AUD01) -- never a login name like "alice".
        }

        System.out.printf("[AUDIT] %s | action=%s | resource=%s | caller=%s%n",
                Instant.now(), action, resourceId, subject);
    }
}
```

Inject `AuditService` into `AccountController` via constructor injection and call `auditService.logEvent("READ_ACCOUNT", id)` inside `getById`. Restart the Bank API, call `GET /api/v1/accounts/A001` with a valid token, and verify the audit line appears in the console.

### Task 3.3 - Implement an ownership check in a controller

Now we put the `sub`-as-customer-ID design to work. Add a new endpoint to `AccountController` that returns *only* the accounts owned by the caller, with a teller/auditor override that returns all accounts.

```java
// TODO 10: Add this endpoint to AccountController.
// For a regular account holder it returns only accounts whose customerId
// matches their sub. For a teller or auditor it returns all accounts.
//
// Read jwt.getSubject() and jwt.getClaimAsStringList("roles").
// Filter ACCOUNTS by customerId for account holders.
// Return the full list for tellers and auditors.
@GetMapping("/mine")
public List<Account> getMyAccounts(@AuthenticationPrincipal Jwt jwt) {
    // TODO 11: Read the caller's subject (customer ID, employee ID, or auditor ID)
    //          and roles list. If "teller" or "auditor" is in the roles, return
    //          ACCOUNTS in full. Otherwise filter to accounts where
    //          customerId equals the subject.
    return List.of(); // Replace with your implementation
}
```

### Task 3.4 - Obtain user tokens for alice, edward, and audit, and compare the responses

Complete the Authorization Code flow for each of these users in turn (open the authorization URL, log in as the user, approve the scopes, exchange the code).

For each token, call `GET /api/v1/accounts/me` and `GET /api/v1/accounts/mine`, and record the responses in `token-analysis.md`. You should see:

| Caller | `/me` shows                              | `/mine` returns                      |
|--------|------------------------------------------|--------------------------------------|
| alice  | `sub`=C001, `preferred_username`=alice   | A001 and A002 (her own accounts)     |
| edward | `sub`=EM01, `roles`=[teller]             | all five accounts                    |
| audit  | `sub`=AUD01, `roles`=[auditor]           | all five accounts                    |

Confirm that the *same endpoint code* produces these different results based purely on the claims in the token.

### Checkpoints

1. `@AuthenticationPrincipal` injects the JWT directly into controller methods. When is `SecurityContextHolder.getContext().getAuthentication()` necessary instead?
2. The `AuditService` reads from the `SecurityContext` on the calling thread. What problem would occur if the service method were executed on a different thread (for example, using `@Async`)? What does Spring Security provide to address this?
3. Imagine the Authorization Server had been built differently - `sub` was the login name (`alice`, `edward`, `audit`) and `customerId` was a separate custom claim. How would `getMyAccounts` change? What additional failure mode does that design introduce that the current one avoids?

---

## Exercise 4 - Method-Level Security with @PreAuthorize

**Estimated time:** 40–50 minutes
**Topics covered:** `@EnableMethodSecurity`, `@PreAuthorize`, `@PostAuthorize`, SpEL expressions, role-based and scope-based method authorization, the AOP proxy model, testing method security

### Context

URL-level rules in `SecurityFilterChain` provide coarse-grained access control at the HTTP boundary. Method-level security provides fine-grained control at the service layer, and enforces authorization regardless of which entry point calls the method: HTTP controller, Kafka consumer, scheduled job, or internal code.

Spring Security implements method security using AOP proxies. When Spring creates your service bean it wraps it in a proxy. Every external call goes through the proxy, which evaluates the `@PreAuthorize` expression before delegating to the real method. If the expression is false, `AccessDeniedException` is thrown and the method body never executes.

This exercise puts the three-way role distinction to use: `account_holder` (own data only), `teller` (full read/write on accounts and customers), `auditor` (full read, no write). Each `@PreAuthorize` you write will need to express which combination of these is allowed.

### Task 4.1 - Enable method security

Add `@EnableMethodSecurity` to `SecurityConfig`:

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity  // Activates @PreAuthorize, @PostAuthorize, @PreFilter, @PostFilter
public class SecurityConfig {
    // ... existing configuration unchanged
}
```

### Task 4.2 - Create a service with method-level security

Create `AccountService.java` in the `service` package:

```java
package com.example.bankapi.service;

import com.example.bankapi.model.Account;
import org.springframework.security.access.prepost.PostAuthorize;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class AccountService {

    private final Map<String, Account> store = new ConcurrentHashMap<>();

    public AccountService() {
        store.put("A001", new Account("A001", "C001", "CHECKING", new BigDecimal("1250.00")));
        store.put("A002", new Account("A002", "C001", "SAVINGS",  new BigDecimal("8400.00")));
        store.put("A003", new Account("A003", "C002", "CHECKING", new BigDecimal("300.50")));
        store.put("A004", new Account("A004", "C003", "CHECKING", new BigDecimal("2100.75")));
        store.put("A005", new Account("A005", "C003", "SAVINGS",  new BigDecimal("15000.00")));
    }

    // TODO 12: Add @PreAuthorize that restricts this to tellers and auditors only.
    //          An account holder should NEVER be able to list every account in the bank.
    //          Hint: "hasRole('TELLER') or hasRole('AUDITOR')"
    public List<Account> findAll() {
        return new ArrayList<>(store.values());
    }

    // TODO 13: Add @PreAuthorize requiring the SCOPE_account.read authority.
    //          Then add @PostAuthorize so the returned account is only visible if:
    //            - the caller is a teller or auditor, OR
    //            - the account's customerId equals authentication.name
    //          Hint: "returnObject.isEmpty() or hasRole('TELLER') or hasRole('AUDITOR')
    //                 or returnObject.get().customerId() == authentication.name"
    //          @PostAuthorize sees the method's return value via 'returnObject'.
    public Optional<Account> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }

    // TODO 14: Add @PreAuthorize that allows callers to look up their own accounts
    //          by customer ID, and allows tellers and auditors to look up any customer's:
    //            "#customerId == authentication.name
    //             or hasRole('TELLER') or hasRole('AUDITOR')"
    //          The #customerId prefix references the method parameter directly.
    public List<Account> findByCustomerId(String customerId) {
        return store.values().stream()
                .filter(a -> a.customerId().equals(customerId))
                .toList();
    }

    // TODO 15: Add @PreAuthorize requiring BOTH:
    //            hasAuthority('SCOPE_account.create') AND hasRole('TELLER')
    //          Combine them with 'and' (or '&&' -- both work in SpEL).
    //          An auditor has account.read but no create scope and no teller role,
    //          so this denies them even though they can read everything.
    public Account create(Account account) {
        store.put(account.id(), account);
        return account;
    }

    // TODO 16: Add @PreAuthorize that allows the account's owner OR a teller to
    //          update an account. Auditors are NOT allowed to update.
    //          Hint: "hasAuthority('SCOPE_account.write')
    //                 and (hasRole('TELLER')
    //                      or @accountOwnership.isOwner(#account.id(), authentication))"
    //          You will create the @accountOwnership bean in Task 4.3.
    public Account update(Account account) {
        store.put(account.id(), account);
        return account;
    }
}
```

### Task 4.3 - Create an ownership helper bean

Some authorization decisions require a database lookup, which is awkward to inline into a SpEL expression. The Spring-recommended pattern is a small `@Component` bean referenced from `@PreAuthorize` via the `@beanName.method(...)` syntax.

Create `AccountOwnership.java` in the `service` package:

```java
package com.example.bankapi.service;

import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Component;

@Component("accountOwnership")
public class AccountOwnership {

    private final AccountService accountService;

    // Constructor injection. AccountService and AccountOwnership refer to each other
    // only through this constructor -- Spring resolves the cycle at startup.
    public AccountOwnership(AccountService accountService) {
        this.accountService = accountService;
    }

    /**
     * Returns true if the given account exists and its customerId equals the
     * authenticated principal's name (which, by Lab 2-1's design, is the
     * customer ID from the sub claim).
     *
     * Called from @PreAuthorize expressions like:
     *   @PreAuthorize("@accountOwnership.isOwner(#accountId, authentication)")
     */
    public boolean isOwner(String accountId, Authentication authentication) {
        if (authentication == null || authentication.getName() == null) {
            return false;
        }
        // TODO 17: Look up the account using accountService.findById(accountId).
        //          Return true if the account exists AND its customerId
        //          equals authentication.getName().
        //          Note: calling findById here will itself trigger its own
        //          @PreAuthorize -- which requires SCOPE_account.read.
        //          Auditors and tellers and the owner all have account.read,
        //          so this works for every caller who legitimately reaches this point.
        return false; // Replace with your implementation
    }
}
```

> **About the bean name:** `@Component("accountOwnership")` registers the bean with the explicit name `accountOwnership`. This is the name used inside the SpEL expression as `@accountOwnership.isOwner(...)`. If you let Spring derive the name automatically (`AccountOwnership` → `accountOwnership`) the result is the same; we set it explicitly to make the reference unambiguous.

### Task 4.4 - Test method security without a real token

Spring Security's test support provides `@WithMockUser` to simulate an authenticated user in unit tests. This lets you test authorization logic without the Authorization Server running at all. Add the following test class to `src/test/java/com/example/bankapi/service`:

```java
package com.example.bankapi.service;

import com.example.bankapi.model.Account;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.test.context.support.WithMockUser;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class AccountServiceSecurityTest {

    @Autowired
    private AccountService accountService;

    // @WithMockUser simulates an authenticated user in the SecurityContext.
    // "SCOPE_account.read" is the authority Spring Security derives from the
    // "account.read" scope in a JWT -- the SCOPE_ prefix is added automatically.
    // The "username" attribute becomes authentication.getName().
    // For our domain that means the customer ID (e.g. "C001"), employee ID, or
    // auditor ID -- because the Authorization Server puts the customer ID into sub.

    @Test
    @WithMockUser(username = "EM01",
                  authorities = {"SCOPE_account.read", "ROLE_TELLER"})
    void findAll_asTeller_returnsAllAccounts() {
        var result = accountService.findAll();
        assertThat(result).hasSize(5);
    }

    @Test
    @WithMockUser(username = "C001",
                  authorities = {"SCOPE_account.read", "ROLE_ACCOUNT_HOLDER"})
    void findAll_asAccountHolder_throwsAccessDeniedException() {
        // TODO 18: Assert that calling accountService.findAll() throws AccessDeniedException.
        //          Account holders should never be able to list every account in the bank.
        assertThatThrownBy(() -> accountService.findAll())
                .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    @WithMockUser(username = "C001",
                  authorities = {"SCOPE_account.read", "ROLE_ACCOUNT_HOLDER"})
    void findById_asOwner_returnsAccount() {
        // alice (C001) owns A001 -- @PostAuthorize allows the return value through.
        var result = accountService.findById("A001");
        assertThat(result).isPresent();
        assertThat(result.get().customerId()).isEqualTo("C001");
    }

    @Test
    @WithMockUser(username = "C001",
                  authorities = {"SCOPE_account.read", "ROLE_ACCOUNT_HOLDER"})
    void findById_asNonOwner_throwsAccessDeniedException() {
        // alice (C001) trying to look up A003, which is owned by C002 (bob).
        // The method body runs, returns the account, then @PostAuthorize denies it.
        assertThatThrownBy(() -> accountService.findById("A003"))
                .isInstanceOf(AccessDeniedException.class);
    }

    // TODO 19: Write a test verifying create() succeeds when the caller has BOTH
    //          SCOPE_account.create AND ROLE_TELLER.
    //          @WithMockUser(username = "EM01",
    //                        authorities = {"SCOPE_account.create", "ROLE_TELLER"})
    @Test
    @WithMockUser(username = "EM01",
                  authorities = {"SCOPE_account.create", "ROLE_TELLER"})
    void create_asTellerWithCreateScope_succeeds() {
        // TODO: Build a new Account and call create(). Assert the return value is not null.
    }

    // TODO 20: Write a test verifying create() throws AccessDeniedException when the
    //          caller is an auditor (has read scopes but no create scope, no teller role).
    @Test
    @WithMockUser(username = "AUD01",
                  authorities = {"SCOPE_account.read", "ROLE_AUDITOR"})
    void create_asAuditor_throwsAccessDeniedException() {
        // TODO: Build a new Account and assert that create() throws AccessDeniedException.
    }
}
```

Run the tests. All should pass. Notice that `@WithMockUser` bypasses the Authorization Server entirely - this is the correct approach for unit testing authorization logic.

> **Note: `WebClient` not yet available.** If your tests fail at startup with
>
> > **No qualifying bean of type 'org.springframework.web.reactive.function.client.WebClient' available**
>
> it means `DownstreamAccountService` from Exercise 5 has already been created. `@SpringBootTest` loads the full application context, which tries to wire it, and that fails because the `WebClient` bean depends on OAuth2 client configuration not relevant to Exercise 4. Add a mock to the test class:
>
> ```java
> @SpringBootTest
> class AccountServiceSecurityTest {
>     @Autowired private AccountService accountService;
>     @MockitoBean private DownstreamAccountService downstreamAccountService;
>     // ... tests unchanged
> }
> ```
>
> `@MockitoBean` is available in Spring Boot 3.4+. For earlier versions use `@MockBean`.

### Task 4.5 - Observe the self-invocation limitation

Add the following method to `AccountService`:

```java
/**
 * Calls findAll() via 'this' -- which bypasses the AOP proxy.
 * The @PreAuthorize on findAll() is NOT enforced for this call.
 * This is the most common AOP proxy gotcha in Spring applications.
 */
public List<Account> findAllInternal() {
    return this.findAll(); // proxy not involved -- @PreAuthorize does not run
}
```

Add a test:

```java
// TODO 21: Write a test with NO @WithMockUser (unauthenticated context).
// Call accountService.findAllInternal() and assert that no exception is thrown
// and the result is not empty.
// Despite findAll() having @PreAuthorize requiring TELLER or AUDITOR,
// the annotation is not enforced because the call bypasses the proxy via self-invocation.
// Add a comment explaining: why this happens, what the correct solutions are,
// and what the production security risk is.
@Test
void findAllInternal_bypassesMethodSecurity() {
    // TODO: Assert the result is not empty and no exception is thrown.
}
```

### Checkpoints

1. The `@PreAuthorize` on `create()` combines a scope check (`SCOPE_account.create`) and a role check (`ROLE_TELLER`) with `and`. Explain why this combination is stronger than either alone. What kind of attack or misconfiguration does each check independently catch?
2. `@PostAuthorize` on `findById()` runs *after* the method executes, meaning the account is always loaded from the store regardless of the authorization outcome. In what scenario would you accept this trade-off rather than rewriting the query to enforce ownership at the data layer?
3. The tests use `@WithMockUser(username = "C001", ...)`. Why does setting `username` to the customer ID - rather than a login name like `alice` - produce a test that mirrors production behaviour? What would break if you set `username = "alice"` instead?
4. What are the two correct solutions to the self-invocation problem, and what are the trade-offs of each?

---

## Exercise 5 - Understanding the Client Credentials Flow

**Estimated time:** 30–45 minutes
**Topics covered:** Client Credentials grant type, service-to-service authentication, the distinction between user-delegated tokens and service identity tokens, `spring-boot-starter-oauth2-client`, `WebClient` with OAuth2 token attachment

### Context

The previous exercises configured your Bank API as a Resource Server: it receives and validates tokens. Services also act as clients: they obtain tokens and present them to downstream services.

The Client Credentials flow is for service-to-service communication where no user is present. The calling service authenticates using its own identity (client ID and secret) and receives a token representing the service itself. In this exercise the Bank API calls itself as a downstream service - a deliberate simplification that lets you observe the full flow without needing a second service.

### Setup

Add the following dependencies to `pom.xml`:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-oauth2-client</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webflux</artifactId>
</dependency>
```

Reload Maven after saving.

### Task 5.1 - Configure the OAuth2 client registration

Update `application.yml` so the resource-server config and the client config sit side by side:

```yaml
server:
  port: 8080

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jwks-uri: http://localhost:9000/oauth2/jwks
          issuer-uri: http://localhost:9000
      client:
        registration:
          downstream-api:
            client-id: bank-service
            # Matches the {noop}bank-service-secret configured in the
            # Authorization Server. In production this comes from an
            # environment variable or secrets manager.
            client-secret: bank-service-secret
            authorization-grant-type: client_credentials
            scope: account.read
        provider:
          downstream-api:
            token-uri: http://localhost:9000/oauth2/token
```

### Task 5.2 - Configure a WebClient with automatic token attachment

Create `DownstreamClientConfig.java` in the `config` package:

```java
package com.example.bankapi.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.web.reactive.function.client.ServletOAuth2AuthorizedClientExchangeFilterFunction;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
public class DownstreamClientConfig {

    @Value("${downstream.api.base-url:http://localhost:8080}")
    private String downstreamBaseUrl;

    /**
     * Creates a WebClient that automatically acquires and attaches a Bearer token
     * using Client Credentials before every outbound request.
     *
     * The OAuth2AuthorizedClientManager is auto-configured by Spring Boot
     * from the spring.security.oauth2.client.* properties above.
     * It handles token acquisition, caching, and refresh automatically.
     */
    @Bean
    public WebClient downstreamApiClient(OAuth2AuthorizedClientManager authorizedClientManager) {

        // TODO 22: Create a ServletOAuth2AuthorizedClientExchangeFilterFunction,
        // passing the authorizedClientManager to its constructor.
        // Call setDefaultClientRegistrationId("downstream-api") on the filter.
        // Build and return a WebClient using WebClient.builder()
        // with the baseUrl set to downstreamBaseUrl
        // and the filter applied with .apply(oauth2Filter.oauth2Configuration()).

        var oauth2Filter = new ServletOAuth2AuthorizedClientExchangeFilterFunction(authorizedClientManager);
        oauth2Filter.setDefaultClientRegistrationId("downstream-api");

        return WebClient.builder()
                .baseUrl(downstreamBaseUrl)
                .apply(oauth2Filter.oauth2Configuration())
                .build();
    }
}
```

### Task 5.3 - Call a downstream service using the service token

Create `DownstreamAccountService.java` in the `service` package:

```java
package com.example.bankapi.service;

import com.example.bankapi.model.Account;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import java.util.List;

@Service
public class DownstreamAccountService {

    private final WebClient downstreamApiClient;

    public DownstreamAccountService(WebClient downstreamApiClient) {
        this.downstreamApiClient = downstreamApiClient;
    }

    /**
     * Calls the account API using a Client Credentials token.
     * Spring Security acquires the token from the Authorization Server automatically.
     * The token represents this service's identity -- no user token is forwarded.
     */
    public List<Account> fetchAllFromDownstream() {
        // TODO 23: Use the WebClient to call GET /api/v1/accounts.
        // Chain: .get().uri("/api/v1/accounts").retrieve()
        //        .bodyToFlux(Account.class).collectList().block()
        // The OAuth2 filter calls the Authorization Server's token endpoint,
        // caches the token, and adds it to the Authorization header automatically.
        return List.of(); // Replace with your implementation
    }
}
```

Add an endpoint to `AccountController`. Inject `DownstreamAccountService` via the constructor alongside `AuditService`:

```java
// TODO 24: Add this endpoint to AccountController.
// It is protected and requires an authenticated caller.
// The inbound request uses the caller's token.
// The outbound call to the downstream service uses the service's own token.
@GetMapping("/downstream")
public List<Account> getFromDownstream() {
    // TODO: call downstreamAccountService.fetchAllFromDownstream() and return the result
    return List.of();
}
```

Add a test request to `auth-requests.http`:

```http
### The downstream endpoint.
### Inbound: the caller's token authenticates this request.
### Outbound: the Bank API obtains its own service token automatically.
### Watch the Authorization Server console when this executes -- you will see a
### POST /oauth2/token request arrive from bank-service.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer <paste-any-valid-token-here>
```

#### What this endpoint actually does, step by step

The `/downstream` endpoint is the most important pedagogical artifact in Module 3, so it is worth tracing exactly what happens when you call it. It demonstrates two identities flowing through the same request: the *caller's* identity on the way in, and the *service's* identity on the way out.

When you send `GET /api/v1/accounts/downstream` with a Bearer token in the header, the sequence is:

1. The Bank API's `SecurityFilterChain` extracts the Bearer token, verifies its signature against the Authorization Server's JWKS, and populates the `SecurityContext` with a `JwtAuthenticationToken` representing the caller. If the token is missing or invalid, the request is rejected with 401 here, and nothing else runs.

2. The URL-level rule `anyRequest().authenticated()` passes (any valid token satisfies it), so the request reaches `AccountController.getFromDownstream()`.

3. The controller calls `downstreamAccountService.fetchAllFromDownstream()`. This is where the second identity enters the picture. The `DownstreamAccountService` uses a `WebClient` configured with `ServletOAuth2AuthorizedClientExchangeFilterFunction`. That filter intercepts the outbound HTTP call and asks `OAuth2AuthorizedClientManager` for a token for the `downstream-api` client registration.

4. `OAuth2AuthorizedClientManager` checks its cache. If no cached token exists (or the cached one is near expiry), it performs a Client Credentials grant against the Authorization Server: `POST /oauth2/token` with HTTP Basic auth as `bank-service:bank-service-secret`. The Authorization Server validates the client credentials, runs the `tokenCustomizer` (which does *nothing* for client-credentials tokens because there is no user principal), and returns an access token with `sub=bank-service` and `scope=account.read`. The manager caches it.

5. The filter attaches this *service* token to the outbound request as `Authorization: Bearer <service-token>`, then makes the actual `GET http://localhost:8080/api/v1/accounts` call.

6. That call lands back on this same Bank API. The `SecurityFilterChain` validates the *service* token (not the caller's token), the URL rule `hasAuthority("SCOPE_account.read")` passes, and the controller returns all 5 accounts.

7. The `WebClient` deserializes the response into `List<Account>`, hands it back to `DownstreamAccountService`, which returns it to the controller, which returns it as the HTTP response to the original caller.

The caller's token authenticated step 1. The service's token authenticated step 6. **The caller's identity is not forwarded to the downstream call.** This is the entire point of the Client Credentials grant: services act under their own identity for service-to-service communication, not by impersonating the user who triggered the work.

#### What this means observationally

This has two consequences that the tests below will let you verify directly:

- **Any valid token works as the inbound credential.** A service token, alice's user token, edward's teller token, the auditor's token, all of them. Whoever authenticates the inbound request, the *outbound* call is always made as `bank-service` and always sees all 5 accounts.

- **The first call after server startup triggers a token request to the Authorization Server. Subsequent calls within the next hour do not.** The token is cached and reused until shortly before expiry, at which point a new one is automatically fetched. You can watch this directly in the Authorization Server console: the first call produces a `POST /oauth2/token` log entry, the second call produces nothing token-related.

#### Tests to run

Replace (or add to) the `auth-requests.http` snippet above with the following set of tests. Run them top-to-bottom and observe both the HTTP responses and the Authorization Server console output as instructed.

```http
###############################################################################
# Downstream endpoint tests
#
# The /downstream endpoint demonstrates the Client Credentials flow in action:
# the inbound request authenticates the caller (any valid token works), and
# then the controller calls fetchAllFromDownstream(), which uses the
# bank-service's own token to call GET /api/v1/accounts on this same server.
#
# Watch the Authorization Server's console as these run. The first call after
# Bank API startup produces a "POST /oauth2/token" from bank-service;
# subsequent calls within the token's 1-hour lifetime skip that step
# (the token is cached by OAuth2AuthorizedClientManager).
###############################################################################

### Step A: Get a service token so you have a valid token to use as the
###         inbound credential for the downstream tests below. Copy the
###         access_token from the response.
POST http://localhost:9000/oauth2/token
Authorization: Basic YmFuay1zZXJ2aWNlOmJhbmstc2VydmljZS1zZWNyZXQ=
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=account.read transaction.read

###

### Test D1: Downstream call with a service token as the inbound credential.
###          Expected: 200 with all 5 accounts.
###          Watch the auth server console: the FIRST time this runs after
###          starting the Bank API, you will see an outbound POST /oauth2/token
###          from bank-service. That is the Bank API acquiring its own service
###          token to make the downstream call.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer <paste-service-token-from-Step-A>

###

### Test D2: Run the same call again immediately.
###          Expected: 200 with all 5 accounts, but this time NO new
###          POST /oauth2/token appears in the auth server console. The
###          cached service token is reused. This is the cache behavior
###          that Exercise 5 Checkpoint 1 asks about.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer <paste-service-token-from-Step-A>

###

### Test D3: Downstream call with NO Authorization header.
###          Expected: 401 Unauthorized. Inbound authentication fails at the
###          SecurityFilterChain before the controller is even reached, so
###          no downstream call happens. The auth server console stays silent.
GET http://localhost:8080/api/v1/accounts/downstream

###

### Test D4: Downstream call with an obviously invalid token.
###          Expected: 401 Unauthorized with a WWW-Authenticate: Bearer header
###          containing error="invalid_token" in the response. The token
###          could not be verified against the JWKS, so the inbound check
###          fails. Again, no downstream call happens.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer not-a-real-token

###

### Test D5: Downstream call with alice's user token. Complete the Authorization
###          Code flow for alice first (see Exercise 1), then paste her
###          access_token below.
###          Expected: 200 with all 5 accounts. The outbound call uses the
###          bank-service service token, NOT alice's user token, so it sees
###          everything. Alice's identity is not forwarded.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer <paste-alice-user-token-here>

###

### Test D6: Downstream call with edward's (teller) token.
###          Expected: 200 with all 5 accounts. Same reason as D5: the inbound
###          token is just a credential for the request, the outbound call
###          uses the service token regardless of who the caller is.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer <paste-edward-teller-token-here>

###

### Test D7: Downstream call with the auditor's token.
###          Expected: 200 with all 5 accounts. Even though the auditor has
###          read-only permissions and could see all accounts directly via
###          GET /api/v1/accounts, the downstream call still flows through
###          the same service-token path -- the auditor's identity is not
###          forwarded either.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer <paste-auditor-token-here>

###

### Test D8: The contrast that makes the Client Credentials flow click.
###          Run these two requests back-to-back as alice. They go to the
###          same controller, with the same authenticated user, but answer
###          fundamentally different questions.

### D8a: alice asks "what are MY accounts?" -- the inbound token's sub claim
###      drives the answer. Expected: 200 with only A001 and A002 (alice's).
GET http://localhost:8080/api/v1/accounts/mine
Authorization: Bearer <paste-alice-user-token-here>

### D8b: alice triggers a downstream call. The outbound call uses the
###      service identity, not alice's identity. Expected: 200 with all 5
###      accounts, including accounts owned by bob and carla.
GET http://localhost:8080/api/v1/accounts/downstream
Authorization: Bearer <paste-alice-user-token-here>
```

#### What to observe

Run D1 first, with the Bank API freshly started. In the **Authorization Server** terminal you should see a burst that includes something like:

```
DEBUG o.s.security.web.FilterChainProxy : Securing POST /oauth2/token
TRACE o.s.s.a.ProviderManager : Authenticating request with ClientSecretAuthenticationProvider
TRACE s.a.a.ClientSecretAuthenticationProvider : Retrieved registered client
```

That is the Bank API acquiring the service token. Now run D2 immediately. You should see the HTTP response (200 with the accounts) but **no new POST /oauth2/token entries in the Authorization Server console**. The token from D1 was cached and reused. If you wait long enough (close to an hour) the cache will expire and the next call will trigger a fresh acquisition.

D8a versus D8b is the moment the whole concept of "service identity" becomes concrete. Same controller, same caller, two different endpoints, two different answers, because two different identities authenticated the *data access* call: alice's identity for `/mine`, bank-service's identity for `/downstream`. That difference is exactly what the Final Reflection question 3 asks you to think about: when is this the right design, and when should you forward the user's identity instead?

### Task 5.4 - Compare user tokens and service tokens

Decode both alice's user token (from Exercise 3) and the service token (from Exercise 1) at jwt.io. Complete the comparison table in `token-analysis.md`:

| Claim                              | User Token (alice) | Service Token (bank-service) |
|------------------------------------|--------------------|------------------------------|
| `sub`                              |                    |                              |
| `iss`                              |                    |                              |
| `aud`                              |                    |                              |
| `scope`                            |                    |                              |
| `roles` (if present)               |                    |                              |
| `preferred_username` (if present)  |                    |                              |
| `name` (if present)                |                    |                              |
| Lifetime in seconds (`exp - iat`)  |                    |                              |

Answer these questions in `token-analysis.md`:

1. In the user token, `sub` identifies alice as `C001`. In the service token, what does `sub` identify, and where does this value come from in the Authorization Server configuration?
2. The service token has no `roles`, `preferred_username`, or `name` claims. Looking at the `tokenCustomizer` in the Authorization Server, identify exactly which condition prevents those claims from being added.
3. The service token has a 3600-second lifetime. The user token has a 300-second lifetime. Explain the security reasoning behind the different lifetimes.

### Checkpoints

1. The `OAuth2AuthorizedClientManager` caches the service token after its first acquisition. What triggers a new token request to the Authorization Server?
2. If the Authorization Server is unavailable when the Bank API starts, the `WebClient` configuration still succeeds. The failure only occurs on the first outbound call. What resilience pattern from Module 4 would you apply to `fetchAllFromDownstream()` to handle this gracefully?
3. The client secret is in `application.yml` for this exercise. In a production deployment what mechanism would you use to supply it at runtime without committing it to source control?

---

## Summary and Reflection

After completing all five exercises you have worked through the full OAuth2 and Spring Security lifecycle: inspecting tokens, configuring a Resource Server, reading claims in application code, enforcing method-level authorization, and acting as an OAuth2 client for downstream calls.

| Exercise | Concept | Key Insight |
|---|---|---|
| 1 – JWT Structure | Header, payload, signature, registered claims, OIDC standard claims | A valid signature proves authenticity and integrity, not current permissions or legitimate possession |
| 2 – Resource Server | `SecurityFilterChain`, JWT validation, URL rules | Spring Security wraps the entire application. Your job is to declare rules, not enforce them inline. |
| 3 – Claims in Code | `SecurityContextHolder`, `@AuthenticationPrincipal`, ownership checks | Putting the stable domain ID in `sub` makes ownership a one-line comparison: no translation, no extra lookups |
| 4 – Method Security | `@PreAuthorize`, `@PostAuthorize`, AOP proxies, self-invocation limitation | Method security enforces authorization regardless of which entry point calls the method |
| 5 – Client Credentials | Service-to-service authentication, `WebClient` with OAuth2 | The Client Credentials flow authenticates the service identity. No user is involved and no user token is forwarded. |

### Final Reflection Questions

Take 10 minutes to answer these before your next session:

1. The Authorization Server generates a new RSA key pair on every startup, immediately invalidating all previously issued tokens. You observed this in Exercise 1. Describe the production solution: where should the key pair be stored, and what does a deliberate key rotation process look like from the Resource Server's perspective?

2. Exercise 4 demonstrated the self-invocation limitation of AOP proxies. `@Transactional` uses the same mechanism with the same limitation. How would you structure a service class that needs both transactional behaviour and method-level security on the same methods?

3. In Exercise 5 the Bank API used its own service token to call the downstream account endpoint, even though the incoming request carried alice's user token. Describe a scenario where you would instead forward alice's token to the downstream service rather than using a service token. What are the security trade-offs of each approach?

4. The Bank API trusts that the `sub` claim is the customer ID because the Authorization Server's `tokenCustomizer` writes it that way. What stops a different (rogue) Authorization Server from issuing a token with `sub=C001` for a completely unrelated user? Trace the specific Spring Security check that prevents this.

---

*End of Lab 2-2 Exercises*
