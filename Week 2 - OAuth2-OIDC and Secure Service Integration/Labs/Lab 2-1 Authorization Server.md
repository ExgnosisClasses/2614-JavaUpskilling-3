# Lab 2-1: Authorization Server
## Hands-On Setup Exercise

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 3 - OAuth2 / OIDC Foundations and Spring Security
> **Estimated time:** 30 to 45 minutes

---

## How to Use This Exercise

This is a standalone setup exercise. All subsequent Module 3 exercises (Resource Server configuration, secured external API consumption, token verification) depend on the Authorization Server you build here. Complete this exercise first and keep the IntelliJ window the Authorization Server is running in open throughout the lab session.

Each section follows the same pattern as the labs you have already completed:

- **Context**: why this concept matters and what problem it solves
- **Setup**: how to structure the project and files before you start
- **Tasks**: step-by-step work, with complete code (no `TODO` markers in this lab; the goal is a working server, not an exercise in completing stubs)
- **Checkpoints**: questions that test conceptual understanding, not just code completion

> **Tip:** Read every comment in the configuration class. Each block maps directly to a concept covered in the Module 3 lectures. The Authorization Server is not large in line count but every line is doing something specific, and understanding the wiring here is what makes the rest of Module 3 tractable.

> **Capstone alignment:** The Authorization Server you build here is the same one the capstone uses to issue tokens for the banking API. The users, clients, and custom claims defined in this lab carry forward unchanged. Treat this as the security backbone of the capstone, not a throwaway exercise.

---

## Overview

When complete, you will have:

- An Authorization Server running on port 9000
- Two registered clients: one for interactive user login (Authorization Code with PKCE) and one for service-to-service calls (Client Credentials)
- Five test users covering three roles: three account holders, one teller, one auditor
- A JWKS endpoint that Resource Servers use to verify token signatures
- Custom claims (`preferred_username`, `name`, `roles`) added to user tokens, with `sub` set to a stable domain identifier (customer ID / employee ID) rather than the login name

> **Important:** The Module 3 exercises and this Authorization Server must both use **Spring Boot 3.2.x**. This is not an option in the initializr so we will download it with 3.5 and modify it in one of the lab steps.

---

## Starter Project

### Step 1: Create the Project with Spring Initializr

1. Open [https://start.spring.io](https://start.spring.io) in a browser
2. Configure the project as follows:

| Setting | Value                  |
|---|------------------------|
| Project | Maven                  |
| Language | Java                   |
| Spring Boot | **3.5** Modified Later |
| Group | `com.example`          |
| Artifact | `authserver`           |
| Packaging | Jar                    |
| Java | 21                     |

3. Add the following dependencies using the search box:
   - **Spring Web**
   - **OAuth2 Authorization Server**

4. Click **Generate**, unzip the archive, and open the folder in IntelliJ IDEA using **File → Open → New Window**

5. When IntelliJ finishes indexing, open the Maven tool window (**View → Tool Windows → Maven**) and confirm there are no download errors

### Step 2: Verify and Adjust the Dependencies

Open `pom.xml` and confirm the `<dependencies>` block contains the following. If the content differs, replace it with this exactly:

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <dependency>
        <groupId>org.springframework.security</groupId>
        <artifactId>spring-security-oauth2-authorization-server</artifactId>
    </dependency>

    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>

    <dependency>
        <groupId>org.springframework.security</groupId>
        <artifactId>spring-security-test</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>
```

Change the `<parent>` block so that it specifies Spring Boot 3.2.5. Spring Initializr defaults to 3.5, which ships a version of the Authorization Server library that is not compatible with the resource servers you will build in subsequent Module 3 exercises. The correct block is:

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.5</version>
    <relativePath/>
</parent>
```

After making any changes, right-click `pom.xml` and choose **Maven → Reload Project**.

Verify the correct version resolved by running the following in the IntelliJ terminal:

```bash
mvn dependency:tree | grep authorization-server
```

You should see a version beginning with `1.2`:

```
\- org.springframework.security:spring-security-oauth2-authorization-server:jar:1.2.x
```

If you see `7.0.x` the Spring Boot version is wrong. Correct the `<parent>` version and reload again.

### Step 3: Confirm Your Package Name

Open the main application class (named `AuthserverApplication.java`) and confirm the first line is:

```java
package com.example.authserver;
```

This is the base package every class in this exercise will use. The instructions below assume `com.example.authserver` throughout. Using the artifact name `authserver` (no hyphen) keeps the package name a single legal Java identifier, which avoids the hyphen-to-separator translation Spring Initializr would otherwise apply.

---

## Exercise 1: Building the Authorization Server

**Estimated time:** 30 to 45 minutes
**Topics covered:** Authorization Server vs Resource Server vs Client, OAuth2 protocol endpoints, registered clients, public vs confidential clients, PKCE, JWT signing with RSA keys, JWKS, OIDC, custom token claims, in-memory user details, roles vs scopes, stable subject identifiers

### Context

An Authorization Server is the trust anchor of an OAuth2 system. It is the only component in the architecture that is permitted to issue access tokens, and every Resource Server in the ecosystem trusts it implicitly. When a client wants to call a protected API, it first obtains a token from the Authorization Server. When a Resource Server receives that token, it verifies the signature against the Authorization Server's public key (published at the JWKS endpoint), checks the claims, and either allows or rejects the request.

Three things make the Authorization Server worth understanding deeply rather than treating as a black box:

1. **It is the source of identity.** Every claim in a JWT (the user's roles, the client that obtained the token, the scopes that were granted, the expiry) is decided here. Understanding which claims are set and why is the difference between a security model you can reason about and one you trust by default.

2. **It enforces the client contract.** Each application that talks to the Authorization Server must be registered ahead of time, with specific grant types, redirect URIs, scopes, and authentication methods. Misconfiguration here is a frequent source of bugs that look like Resource Server failures.

3. **The flows are not interchangeable.** Authorization Code + PKCE is for users in browsers; Client Credentials is for backend services. Using one where the other is appropriate is a security failure, not a stylistic one. Building the server forces you to see why.

#### Two ideas this lab makes concrete

Before you start, two design decisions in this lab are worth flagging because they appear in every checkpoint and carry forward into the capstone.

**Subject (`sub`) is a stable domain identifier, not the login name.** OIDC requires `sub` to be stable, non-reassignable, and unique within the issuer. Login names ("alice") fail all three: they change, they can be reassigned, and they are display-oriented. In this lab, `sub` is the customer ID (`C001`) for account holders, the employee ID (`EM01`) for tellers, and the auditor ID (`AUD01`) for auditors. The login name goes into the standard OIDC `preferred_username` claim. The payoff appears in the Resource Server exercises: when your domain model keys `Account` by `customerId`, an authorization check is literally `account.customerId.equals(authentication.getName())` with no translation step.

**Roles and scopes answer different questions.** A role describes who the user *is* (`account_holder`, `teller`, `auditor`) - coarse-grained and stable across sessions. A scope describes what *this token* is allowed to do (`account.read`, `account.write`, ...) - fine-grained and per-token. In OAuth, a single user may legitimately request a token with only a subset of the scopes their role entitles them to (principle of least privilege per token). You will see both in your `@PreAuthorize` expressions in Lab 2-2: `hasRole('TELLER')` for ownership-style checks and `hasAuthority('SCOPE_account.write')` for capability checks.

#### The users and clients this lab defines

In this exercise you will build a single configuration class that defines two filter chains (protocol endpoints and login form), five users (three account holders, a teller, an auditor), two clients (a public SPA client and a confidential service client), a token customizer that adds application-specific claims and rewrites `sub`, and the RSA key pair that signs every token. The end result is a working Authorization Server you can call from the rest of Module 3.

| Login    | `sub`   | Role              | Full Name             |
|----------|---------|-------------------|-----------------------|
| `alice`  | `C001`  | `account_holder`  | Alice Nguyen          |
| `bob`    | `C002`  | `account_holder`  | Bob Patel             |
| `carla`  | `C003`  | `account_holder`  | Carla Romero          |
| `edward` | `EM01`  | `teller`          | Edward Teller         |
| `audit`  | `AUD01` | `auditor`         | Sunrise Accounting    |

All five users share the password `password`. This is acceptable for a lab environment and **only** for a lab environment. Production systems must use per-user passwords, BCrypt hashing, and an account lockout policy.

#### Scopes defined by this server

The seven scopes below are all the scopes any client in this ecosystem will request. Each role has a default scope set:

| Scope                 | Meaning                                       |
|-----------------------|-----------------------------------------------|
| `account.read`        | Read account details and balance              |
| `account.write`       | Modify account details (not balance directly) |
| `account.create`      | Open a new account                            |
| `transaction.read`    | Read transaction history                      |
| `transaction.create`  | Post a new transaction (deposit/withdraw/transfer) |
| `customer.read`       | Read customer profile data                    |
| `customer.write`      | Modify customer profile data                  |

| Role             | Default scopes                                                                                            |
|------------------|------------------------------------------------------------------------------------------------------------|
| `account_holder` | `account.read`, `account.write`, `transaction.read`, `transaction.create`, `customer.read`                |
| `teller`         | All `account_holder` scopes **plus** `account.create`, `customer.write`                                   |
| `auditor`        | `account.read`, `transaction.read`, `customer.read` (read-only across the system; no writes, no creates)  |



### Task 1.1: Configure the Server Properties

Delete `src/main/resources/application.properties` if it exists and create `src/main/resources/application.yml`:

```yaml
server:
  port: 9000

spring:
  security:
    oauth2:
      authorizationserver:
        # Pin the issuer URI explicitly. Without this setting, Spring infers
        # the issuer from the host of the first incoming request -- which
        # means it could become "http://localhost:9000" or "http://127.0.0.1:9000"
        # depending on which one happened to hit the server first. Resource
        # servers and OAuth clients in later labs match the iss claim
        # against a configured issuer-uri string exactly, so the issuer
        # must be deterministic.
        #
        # 127.0.0.1 (not localhost) is chosen because Lab 2-1's redirect URI
        # for bank-spa is http://127.0.0.1:9000/authorized. The authorize
        # URL and the redirect URI must use the same host or the browser
        # loses the session cookie on the redirect.
        issuer: http://127.0.0.1:9000

logging:
  level:
    org.springframework.security: DEBUG
```

The DEBUG logging is intentional. It lets you see every security decision the Authorization Server makes in the console, which helps you understand the OAuth2 flow as it runs. In a production deployment you would set this to INFO or WARN; for a learning environment, the verbose output is the point.

### Task 1.2: Create the BankUser Class

Standard `User.withDefaultPasswordEncoder()` only carries a username, password, and authorities. Our token customizer needs more: the customer/employee ID for `sub`, the full name for the `name` claim, and the user's allowed scopes. The cleanest way to carry these into the customizer is a custom `UserDetails` implementation.

Create the package `com.example.authserver.users` and inside it create `BankUser.java`:

```java
package com.example.authserver.users;

import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.util.Collection;
import java.util.List;
import java.util.Set;

/**
 * A UserDetails implementation that carries the domain attributes
 * this Authorization Server needs to put into the JWT:
 *
 *   subjectId      -- becomes the "sub" claim (C001, EM01, AUD01, ...)
 *   username       -- the login name (alice, edward, ...) -> "preferred_username"
 *   fullName       -- display name -> "name"
 *   role           -- single role like "account_holder", "teller", "auditor"
 *   allowedScopes  -- the maximum scope set this user is entitled to
 *
 * The token customizer pulls these directly off the principal at JWT
 * encoding time. Storing them here (rather than in a parallel map)
 * keeps the user's identity and the user's authorization data
 * in one place.
 */
public class BankUser implements UserDetails {

    private final String subjectId;
    private final String username;
    private final String password;
    private final String fullName;
    private final String role;
    private final Set<String> allowedScopes;

    public BankUser(String subjectId,
                    String username,
                    String password,
                    String fullName,
                    String role,
                    Set<String> allowedScopes) {
        this.subjectId = subjectId;
        this.username = username;
        this.password = password;
        this.fullName = fullName;
        this.role = role;
        this.allowedScopes = Set.copyOf(allowedScopes);
    }

    public String getSubjectId() {
        return subjectId;
    }

    public String getFullName() {
        return fullName;
    }

    public String getRole() {
        return role;
    }

    public Set<String> getAllowedScopes() {
        return allowedScopes;
    }

    // UserDetails contract below.
    // Spring Security uses ROLE_ as a prefix convention so that hasRole('TELLER')
    // matches an authority named ROLE_TELLER. We follow that convention here.

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + role.toUpperCase()));
    }

    @Override public String getPassword() { return password; }
    @Override public String getUsername() { return username; }
    @Override public boolean isAccountNonExpired() { return true; }
    @Override public boolean isAccountNonLocked() { return true; }
    @Override public boolean isCredentialsNonExpired() { return true; }
    @Override public boolean isEnabled() { return true; }
}
```

### Task 1.3: Create the Configuration Class

Create the package `com.example.authserver.config` (adjust for your actual package name from Step 3).

Inside it, create `AuthorizationServerConfig.java` with the following content. Read every comment. Each section maps directly to a concept covered in the Module 3 lectures:

```java
package com.example.authserver.config;

import com.example.authserver.users.BankUser;
import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.SecurityContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.core.oidc.OidcScopes;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.authorization.client.InMemoryRegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.config.annotation.web.configuration.OAuth2AuthorizationServerConfiguration;
import org.springframework.security.oauth2.server.authorization.config.annotation.web.configurers.OAuth2AuthorizationServerConfigurer;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.ClientSettings;
import org.springframework.security.oauth2.server.authorization.settings.TokenSettings;
import org.springframework.security.oauth2.server.authorization.token.JwtEncodingContext;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.time.Duration;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Configuration
@EnableWebSecurity
public class AuthorizationServerConfig {

    // -------------------------------------------------------------------------
    // Scope sets, declared once at the top so the user definitions below
    // and the client registration both reference the same constants.
    // Keeping these in one place is the difference between a typo being
    // caught at compile time and a typo being caught by a confused student
    // staring at a 403 from the Resource Server.
    // -------------------------------------------------------------------------

    private static final Set<String> ACCOUNT_HOLDER_SCOPES = Set.of(
            "account.read",
            "account.write",
            "transaction.read",
            "transaction.create",
            "customer.read"
    );

    private static final Set<String> TELLER_SCOPES = Set.of(
            "account.read",
            "account.write",
            "account.create",
            "transaction.read",
            "transaction.create",
            "customer.read",
            "customer.write"
    );

    private static final Set<String> AUDITOR_SCOPES = Set.of(
            "account.read",
            "transaction.read",
            "customer.read"
    );

    // Union of every scope any user can hold. The bank-spa client is
    // registered with this superset; the token customizer narrows the
    // scope claim per user at issue time.
    private static final Set<String> ALL_BANK_SCOPES = Set.of(
            "account.read",
            "account.write",
            "account.create",
            "transaction.read",
            "transaction.create",
            "customer.read",
            "customer.write"
    );

    // -------------------------------------------------------------------------
    // Filter Chain 1: Authorization Server protocol endpoints
    //
    // This chain handles the OAuth2 protocol endpoints:
    //   /oauth2/authorize  -- the authorization endpoint (redirects to login)
    //   /oauth2/token      -- the token endpoint (issues JWTs)
    //   /oauth2/jwks       -- the public key endpoint (Resource Servers fetch from here)
    //   /.well-known/...   -- discovery endpoints
    //
    // @Order(1) ensures this chain is evaluated before the login form chain below.
    // -------------------------------------------------------------------------
    @Bean
    @Order(1)
    public SecurityFilterChain authorizationServerSecurityFilterChain(HttpSecurity http)
            throws Exception {

        OAuth2AuthorizationServerConfiguration.applyDefaultSecurity(http);

        http.getConfigurer(OAuth2AuthorizationServerConfigurer.class)
                // Enable OpenID Connect 1.0. This adds the /userinfo endpoint
                // and id_token support alongside the standard access token.
                .oidc(Customizer.withDefaults());

        http
                // When an unauthenticated browser request arrives at the
                // authorization endpoint, redirect to the login form.
                .exceptionHandling(ex -> ex
                        .defaultAuthenticationEntryPointFor(
                                new LoginUrlAuthenticationEntryPoint("/login"),
                                new MediaTypeRequestMatcher(MediaType.TEXT_HTML)
                        )
                )
                // Accept Bearer tokens for the /userinfo endpoint.
                .oauth2ResourceServer(rs -> rs.jwt(Customizer.withDefaults()));

        return http.build();
    }

    // -------------------------------------------------------------------------
    // Filter Chain 2: Default security for the login form
    //
    // @Order(2) means this chain is checked after the Authorization Server chain.
    // It provides the login form that users see when authenticating interactively.
    // -------------------------------------------------------------------------
    @Bean
    @Order(2)
    public SecurityFilterChain defaultSecurityFilterChain(HttpSecurity http)
            throws Exception {
        http
                .authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
                .formLogin(Customizer.withDefaults());
        return http.build();
    }

    // -------------------------------------------------------------------------
    // Password Encoder
    //
    // BCrypt is the production standard for password hashing. Even in a lab,
    // hashing the password is one line of code and removes a footgun from
    // the system: nobody will see the literal "password" string in logs,
    // stack traces, or memory dumps.
    // -------------------------------------------------------------------------
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    // -------------------------------------------------------------------------
    // Users
    //
    // Five users covering the three roles in the banking scenario.
    // All share the password "password" for lab convenience only.
    //
    // The role string drives two things:
    //   1. The Spring Security authority (ROLE_ACCOUNT_HOLDER, ROLE_TELLER, ...)
    //      used by hasRole(...) in @PreAuthorize on the Resource Server.
    //   2. A "roles" claim added to the JWT by the token customizer.
    //
    // The allowedScopes field is the user's *maximum* scope set. The token
    // customizer intersects this with the scopes requested by the client at
    // authorize time, so a token never carries a scope its bearer was not
    // entitled to (principle of least privilege per token).
    //
    // IMPORTANT: we do NOT use InMemoryUserDetailsManager here, even though
    // it looks like the natural choice. InMemoryUserDetailsManager silently
    // wraps every UserDetails you give it and reconstructs a plain
    // org.springframework.security.core.userdetails.User on lookup -- your
    // BankUser subtype is stripped. The token customizer's
    // `instanceof BankUser` check would then always be false, and the JWT
    // would come out with sub="carla" (the login name), no roles, no name,
    // no preferred_username, and an unfiltered scope claim. The tiny lambda
    // UserDetailsService below hands the BankUser back unchanged.
    // -------------------------------------------------------------------------
    @Bean
    public UserDetailsService userDetailsService(PasswordEncoder encoder) {
        String pwd = encoder.encode("password");   // LAB ONLY -- same password for all users

        Map<String, BankUser> users = Map.of(
                "alice",  new BankUser("C001",  "alice",  pwd, "Alice Nguyen",
                                        "account_holder", ACCOUNT_HOLDER_SCOPES),
                "bob",    new BankUser("C002",  "bob",    pwd, "Bob Patel",
                                        "account_holder", ACCOUNT_HOLDER_SCOPES),
                "carla",  new BankUser("C003",  "carla",  pwd, "Carla Romero",
                                        "account_holder", ACCOUNT_HOLDER_SCOPES),
                "edward", new BankUser("EM01",  "edward", pwd, "Edward Teller",
                                        "teller",         TELLER_SCOPES),
                "audit",  new BankUser("AUD01", "audit",  pwd, "Sunrise Accounting",
                                        "auditor",        AUDITOR_SCOPES)
        );

        return username -> {
            BankUser user = users.get(username);
            if (user == null) {
                throw new UsernameNotFoundException("No such user: " + username);
            }
            return user;
        };
    }

    // -------------------------------------------------------------------------
    // Registered Clients
    //
    // A registered client is an application that has permission to request
    // tokens from this Authorization Server.
    //
    // bank-spa: a public client using Authorization Code + PKCE.
    //   Represents the React banking app you will build in a later lab.
    //   PKCE provides the security guarantee that a client secret would give.
    //   Registered with the union of all bank scopes; the token customizer
    //   narrows them per user.
    //
    // bank-service: a confidential client using Client Credentials.
    //   Represents a backend service (batch job, reconciliation worker)
    //   authenticating with its own identity. No user is involved; the
    //   service authenticates directly.
    // -------------------------------------------------------------------------
    @Bean
    public RegisteredClientRepository registeredClientRepository() {

        RegisteredClient.Builder spaBuilder = RegisteredClient
                .withId(UUID.randomUUID().toString())
                .clientId("bank-spa")
                // Public clients have no secret. PKCE takes its place.
                .clientAuthenticationMethod(ClientAuthenticationMethod.NONE)
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
                .redirectUri("http://127.0.0.1:9000/authorized")
                .redirectUri("http://localhost:3000/callback")  // React dev server
                .scope(OidcScopes.OPENID)
                .scope(OidcScopes.PROFILE);

        // Add every bank scope so any user can request what they're entitled to.
        ALL_BANK_SCOPES.forEach(spaBuilder::scope);

        RegisteredClient bankSpa = spaBuilder
                .clientSettings(ClientSettings.builder()
                        // Require PKCE. The Authorization Server rejects any
                        // authorization request that does not include a code_challenge.
                        .requireProofKey(true)
                        // Show the consent screen so students can see scope approval.
                        .requireAuthorizationConsent(true)
                        .build())
                .tokenSettings(TokenSettings.builder()
                        // 5-minute access token lifetime. Intentionally short so the
                        // stale permissions scenario in later exercises is observable
                        // within a single lab session.
                        .accessTokenTimeToLive(Duration.ofMinutes(5))
                        .refreshTokenTimeToLive(Duration.ofDays(1))
                        .build())
                .build();

        RegisteredClient bankService = RegisteredClient
                .withId(UUID.randomUUID().toString())
                .clientId("bank-service")
                // {noop} tells Spring not to hash this value.
                // Development only; never use {noop} in production.
                .clientSecret("{noop}bank-service-secret")
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .scope("account.read")
                .scope("transaction.read")
                .tokenSettings(TokenSettings.builder()
                        // Service tokens can have longer lifetimes because the
                        // service can re-authenticate silently at any time.
                        .accessTokenTimeToLive(Duration.ofHours(1))
                        .build())
                .build();

        return new InMemoryRegisteredClientRepository(bankSpa, bankService);
    }

    // -------------------------------------------------------------------------
    // Token Customizer
    //
    // Three jobs:
    //
    //   1. Replace "sub" with the stable domain identifier (customer or
    //      employee ID) instead of the login name. This is what the Resource
    //      Server's @PreAuthorize expressions key off via authentication.getName().
    //
    //   2. Add OIDC standard claims: "preferred_username" (login name) and
    //      "name" (full name). These are display-oriented and never used
    //      for authorization.
    //
    //   3. Add a "roles" claim derived from the user's role, and rewrite the
    //      "scope" claim to be the intersection of (requested scopes) and
    //      (user's allowedScopes). This enforces least privilege per token:
    //      a token never carries a scope its bearer is not entitled to,
    //      regardless of what the client requested.
    //
    // The customizer only runs for user-bearing tokens (Authorization Code
    // flow). Client Credentials tokens have no user principal; the condition
    // below is false and none of these claims are added. This is intentional
    // and is something later exercises ask you to observe directly.
    // -------------------------------------------------------------------------
    @Bean
    public OAuth2TokenCustomizer<JwtEncodingContext> tokenCustomizer() {
        return context -> {
            var principal = context.getPrincipal();

            if (principal != null
                    && principal.getPrincipal() instanceof BankUser user) {

                // 1. Stable subject identifier.
                context.getClaims().subject(user.getSubjectId());

                // 2. OIDC display claims.
                context.getClaims().claim("preferred_username", user.getUsername());
                context.getClaims().claim("name", user.getFullName());

                // 3a. Roles claim (single-element list so future multi-role
                //     support is a one-line change).
                context.getClaims().claim("roles", List.of(user.getRole()));

                // 3b. Narrow the scope claim to (requested ∩ allowed).
                Set<String> requested = new HashSet<>(context.getAuthorizedScopes());
                Set<String> granted = requested.stream()
                        .filter(user.getAllowedScopes()::contains)
                        .collect(Collectors.toSet());

                // OIDC scopes (openid, profile) are not in allowedScopes but
                // should pass through if the client requested them.
                if (requested.contains(OidcScopes.OPENID)) granted.add(OidcScopes.OPENID);
                if (requested.contains(OidcScopes.PROFILE)) granted.add(OidcScopes.PROFILE);

                context.getClaims().claim("scope", String.join(" ", granted));
            }
        };
    }

    // -------------------------------------------------------------------------
    // RSA Key Pair
    //
    // The Authorization Server signs JWTs with the private key.
    // Resource Servers verify JWTs using the public key, fetched from:
    //   http://127.0.0.1:9000/oauth2/jwks
    //
    // A new key pair is generated in memory on each startup. Any token issued
    // before a restart is immediately invalid because the new public key will
    // not match the old signature. This is expected in development and is
    // something the checkpoints ask you to reason about.
    //
    // In production the key pair is generated once, stored securely, and
    // rotated deliberately with advance notice to all Resource Servers.
    // -------------------------------------------------------------------------
    @Bean
    public JWKSource<SecurityContext> jwkSource() {
        KeyPair keyPair = generateRsaKey();
        RSAPublicKey publicKey = (RSAPublicKey) keyPair.getPublic();
        RSAPrivateKey privateKey = (RSAPrivateKey) keyPair.getPrivate();

        RSAKey rsaKey = new RSAKey.Builder(publicKey)
                .privateKey(privateKey)
                // The kid (Key ID) appears in every JWT header.
                // Resource Servers use it to select the correct verification
                // key from the JWKS when multiple keys are present.
                .keyID(UUID.randomUUID().toString())
                .build();

        return new ImmutableJWKSet<>(new JWKSet(rsaKey));
    }

    private static KeyPair generateRsaKey() {
        try {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(2048);
            return generator.generateKeyPair();
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to generate RSA key pair", ex);
        }
    }

    @Bean
    public JwtDecoder jwtDecoder(JWKSource<SecurityContext> jwkSource) {
        return OAuth2AuthorizationServerConfiguration.jwtDecoder(jwkSource);
    }

    // -------------------------------------------------------------------------
    // Authorization Server Settings
    //
    // The issuer URI is embedded in the "iss" claim of every token this
    // server issues. Resource Servers are configured with this URI and reject
    // any token where "iss" does not match. This prevents a token issued for
    // one system from being replayed against a different system.
    //
    // We use the default builder here. The issuer is configured in
    // application.yml via spring.security.oauth2.authorizationserver.issuer.
    // Putting it there (rather than hardcoding it in Java) means it is set
    // in one place, can be overridden per environment without recompiling,
    // and cannot accidentally diverge from the property file.
    // -------------------------------------------------------------------------
    @Bean
    public AuthorizationServerSettings authorizationServerSettings() {
        return AuthorizationServerSettings.builder().build();
    }
}
```

### Task 1.4: Start the Server

> **Why not `InMemoryUserDetailsManager`?** It is the obvious choice and most Spring Security tutorials use it. We do not, because it silently strips custom `UserDetails` subtypes. Internally it wraps every `UserDetails` you pass it and, on lookup, hands back a plain `org.springframework.security.core.userdetails.User` rebuilt from the wrapped fields. Our token customizer's `instanceof BankUser` check would then always be false, the entire customizer body would be skipped, and the JWT would come out with `sub` set to the login name, no `roles`, no `name`, no `preferred_username`, and an unfiltered `scope` claim. The lambda `UserDetailsService` in this task returns the `BankUser` instance unchanged, which is what the customizer needs.

Run the main application class. You should see it start on port 9000. The DEBUG logging will produce a large amount of filter chain output. This is normal.

Look for this line near the end of the startup output:

```
Started AuthserverApplication in X.XXX seconds
```

### Task 1.5: Verify the Key Endpoints

Open the following URLs in your browser to confirm the server is running and exposing the right endpoints.

**JWKS endpoint**, the public keys Resource Servers use to verify signatures:

```
http://127.0.0.1:9000/oauth2/jwks
```

Expected response:

```json
{
  "keys": [{
    "kty": "RSA",
    "e": "AQAB",
    "kid": "some-generated-uuid",
    "n": "a-very-long-base64url-encoded-number..."
  }]
}
```

**Discovery endpoint**, the document that clients and Resource Servers use to auto-configure:

```
http://127.0.0.1:9000/.well-known/oauth-authorization-server
```

Note the `issuer`, `token_endpoint`, and `jwks_uri` fields in the response. They should all use `http://127.0.0.1:9000` -- if any of them reads `http://localhost:9000` instead, the issuer setting in `application.yml` is not taking effect. Stop the application fully (red square in IntelliJ, not just DevTools reload), restart it, and check again. These are the values you will configure in the resource servers during the rest of Module 3.

### Task 1.6: Obtain Your First Tokens

Create `auth-requests.http` in the project root:

```http
### Client Credentials token. Service identity, no user involved.
### The Authorization header is Base64("bank-service:bank-service-secret").
POST http://127.0.0.1:9000/oauth2/token
Authorization: Basic YmFuay1zZXJ2aWNlOmJhbmstc2VydmljZS1zZWNyZXQ=
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=account.read transaction.read

###

### Authorization Code flow, Step 1.
### Open the URL below manually in your browser (do not run it as an HTTP request).
### Log in as alice / password (or bob, carla, edward, audit) and approve the
### scopes on the consent screen.
### The browser redirects to http://127.0.0.1:9000/authorized?code=XXXX
### Copy the "code" query parameter value from the URL bar before it expires.
###
### IMPORTANT: the authorize URL host (127.0.0.1) MUST match the redirect_uri
### host (127.0.0.1). The browser treats "localhost" and "127.0.0.1" as
### different origins -- if the authorize URL uses one and the redirect_uri
### uses the other, the session cookie is lost on the redirect and you will
### be asked to log in a second time.
###
### URL to open in browser (request the full set of bank scopes; the customizer
### will narrow them to what the logged-in user is entitled to):
###
### http://127.0.0.1:9000/oauth2/authorize?response_type=code&client_id=bank-spa&redirect_uri=http://127.0.0.1:9000/authorized&scope=openid%20profile%20account.read%20account.write%20account.create%20transaction.read%20transaction.create%20customer.read%20customer.write&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=abc123

###

### Authorization Code flow, Step 2.
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

Execute the Client Credentials request first. You should receive:

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6Ii4uLiJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "account.read transaction.read"
}
```

Copy the `access_token` value and paste it into the decoder at [https://jwt.io](https://jwt.io). Note that the payload contains `iss`, `sub` (which is `bank-service`, the client ID), `aud`, `exp`, `iat`, and `scope` - but no `roles`, `preferred_username`, or `name`. That is the expected behaviour for a client-credentials token; no user is present.

Now run the Authorization Code flow as **alice**. Decode the resulting token and confirm:

- `sub` is `C001` (not `alice`)
- `preferred_username` is `alice`
- `name` is `Alice Nguyen`
- `roles` is `["account_holder"]`
- `scope` is `openid profile account.read account.write transaction.read transaction.create customer.read` - `account.create` and `customer.write` are absent because alice is not entitled to them, even though the client requested them.

Repeat as **edward** and confirm `scope` now includes `account.create` and `customer.write`. Repeat as **audit** and confirm `scope` is reduced to read-only.

### Checkpoints

1. The Authorization Server defines two filter chains, both annotated with `@Order`. What goes wrong if the order is reversed or if neither chain is given an explicit order?

2. The `bank-spa` client requires PKCE (`requireProofKey(true)`) and has `ClientAuthenticationMethod.NONE`. The `bank-service` client uses `CLIENT_SECRET_BASIC` and has no PKCE requirement. Why are these settings appropriate for each client type, and what specifically would go wrong if they were swapped?

3. The token customizer adds `roles`, `preferred_username`, and `name` only when the principal is a `BankUser`. A token obtained via Client Credentials therefore contains none of these. From the Resource Server's perspective, what does this imply about how `@PreAuthorize("hasRole('TELLER')")` will behave on a service-to-service call?

4. The customizer overrides `sub` to be the customer or employee ID (`C001`, `EM01`, `AUD01`) instead of the login name (`alice`, `edward`, `audit`). Explain *why* in terms of what the Resource Server has to do in a method like `@PreAuthorize("@accountSecurity.isOwner(#accountId, authentication)")`. What would the implementation of `isOwner` look like if `sub` were `alice` and accounts were keyed by `customerId`?

5. The customizer narrows the `scope` claim to `(requested ∩ allowed)` rather than just trusting the client's request. What attack or misconfiguration does this defend against? If `audit` logs in via `bank-spa` and the client requests `account.write` in addition to read scopes, what does `audit`'s token end up with, and why?

6. The RSA key pair is generated fresh on every server restart. Why is this acceptable in development and unacceptable in production? What specific behaviour would a deployed Resource Server exhibit on the morning after an unannounced Authorization Server restart in production?

7. Each `BankUser` currently has a single `role` field. If a teller could also be an account holder (i.e. a teller with their own personal account at the bank), what would change in `BankUser`, in the token customizer, and in a `@PreAuthorize("hasRole('TELLER') or @accountSecurity.isOwner(...)")` expression?

---

## Reference: What This Server Provides

| Item | Value |
|---|---|
| Authorization Server URL | `http://127.0.0.1:9000` |
| JWKS endpoint | `http://127.0.0.1:9000/oauth2/jwks` |
| Issuer URI | `http://127.0.0.1:9000` |
| Token endpoint | `http://127.0.0.1:9000/oauth2/token` |
| Public client ID | `bank-spa` |
| Service client ID | `bank-service` |
| Service client secret | `bank-service-secret` |
| User token lifetime | 300 seconds (5 minutes) |
| Service token lifetime | 3600 seconds (1 hour) |

### Users

| Login    | Password   | `sub`   | Role             | Full Name           |
|----------|------------|---------|------------------|---------------------|
| `alice`  | `password` | `C001`  | `account_holder` | Alice Nguyen        |
| `bob`    | `password` | `C002`  | `account_holder` | Bob Patel           |
| `carla`  | `password` | `C003`  | `account_holder` | Carla Romero        |
| `edward` | `password` | `EM01`  | `teller`         | Edward Teller       |
| `audit`  | `password` | `AUD01` | `auditor`        | Sunrise Accounting  |

### Default scope sets per role

| Role             | Scopes                                                                                                |
|------------------|-------------------------------------------------------------------------------------------------------|
| `account_holder` | `account.read`, `account.write`, `transaction.read`, `transaction.create`, `customer.read`            |
| `teller`         | All `account_holder` scopes plus `account.create`, `customer.write`                                   |
| `auditor`        | `account.read`, `transaction.read`, `customer.read`                                                   |

---

## Troubleshooting

**Port 9000 is already in use**

Change `server.port` in `application.yml` to another port. Also update `spring.security.oauth2.authorizationserver.issuer` in `application.yml` to match the new port (for example, `http://127.0.0.1:9001`). Use the same port everywhere when configuring the resource servers in Module 3.

**The application fails to start with a `NoSuchBeanDefinitionException`**

The most common cause is a missing `@EnableWebSecurity` annotation on `AuthorizationServerConfig`. Verify it is present.

**Login fails with "Bad credentials"**

The lab uses BCrypt to hash passwords. Confirm the `PasswordEncoder` bean is defined and that the `UserDetailsService` calls `encoder.encode("password")` rather than passing the literal string.

**Token is issued but `sub` is the login name (e.g. `carla`) instead of the customer ID, and `roles`/`name`/`preferred_username` are all missing**

The `instanceof BankUser` check in the token customizer is returning false, so the customizer's body is being skipped entirely. The most common cause is using `InMemoryUserDetailsManager` to hold the users: it silently wraps each `UserDetails` and returns a plain `User` from `loadUserByUsername`, stripping the `BankUser` subtype. Confirm the `userDetailsService` bean uses the lambda form shown in Task 1.3, not `new InMemoryUserDetailsManager(...)`. If you have already switched to the lambda form and still see this symptom, also check that the import in `AuthorizationServerConfig` resolves to *your* `BankUser` (`com.example.authserver.users.BankUser`), not a Spring class with the same simple name.

**Token contains scopes the user shouldn't have**

The token customizer's intersection step is not running. If the `scope` claim in the decoded token is a JSON *array* rather than a space-separated *string*, the customizer didn't write it at all - see the troubleshooting entry above (the `instanceof BankUser` check is failing). If `scope` is a string but contains the wrong scopes, the user's `allowedScopes` constant is wrong; verify the `ACCOUNT_HOLDER_SCOPES`, `TELLER_SCOPES`, and `AUDITOR_SCOPES` constants at the top of `AuthorizationServerConfig` match the lab spec.

**The flow asks me to log in twice - once before consent, once after**

This is a session cookie issue, not a security misconfiguration. The browser treats `localhost` and `127.0.0.1` as different origins, so a session cookie set during login on `localhost:9000` is not sent on the redirect to `127.0.0.1:9000`. Use the same host throughout: the authorize URL in `auth-requests.http` uses `http://127.0.0.1:9000` to match the registered redirect URI `http://127.0.0.1:9000/authorized`. If you copy-pasted the URL but changed the host to `localhost`, change it back to `127.0.0.1`.

**A downstream Resource Server or OAuth client fails to start with `The Issuer "http://localhost:9000" provided in the configuration metadata did not match the requested issuer "http://127.0.0.1:9000"` (or vice versa)**

This appears later in the lab series, not in Lab 2-1 itself, but the fix lives here.

The downstream service is requesting the discovery document at one host (say `127.0.0.1`) and the Auth Server is publishing endpoints under the other host (say `localhost`). Spring's strict matching rejects the mismatch.

Verify what the Auth Server is actually publishing by opening the discovery document in a browser:

```
http://127.0.0.1:9000/.well-known/oauth-authorization-server
```

The `issuer` field at the top of the JSON should be `"http://127.0.0.1:9000"`. If it says `"http://localhost:9000"`, the `spring.security.oauth2.authorizationserver.issuer` setting in `application.yml` is not being applied. Stop the Auth Server fully (red square in IntelliJ, not just DevTools reload), confirm the setting is present in `application.yml`, and restart. If a Java config bean is also calling `.issuer(...)` on the `AuthorizationServerSettings` builder, it will override the yaml - remove that call. Lab 2-1's reference Task 1.3 deliberately uses `AuthorizationServerSettings.builder().build()` with no `.issuer(...)` so the yaml is the only source of truth.

**Tokens become invalid after restarting the server**

This is expected. A new RSA key pair is generated on each startup. Re-execute the Client Credentials request in `auth-requests.http` or repeat the Authorization Code flow to get a fresh token.

**Authorization code exchange fails with `invalid_grant`**

Authorization codes expire in approximately 5 minutes and are single-use. Open the browser URL again to get a fresh code and exchange it immediately.

**The `mvn dependency:tree` output shows `7.0.x` for the authorization server**

The `<parent>` block in `pom.xml` is still set to Spring Boot 3.5 or higher. Change it to `3.2.5` as shown in Step 2 and reload the Maven project.

---

*Once the JWKS endpoint responds correctly and you have decoded tokens for at least one account holder, the teller, and the auditor, proceed to Lab 2-2 where you will build the Resource Server that consumes these tokens.*
