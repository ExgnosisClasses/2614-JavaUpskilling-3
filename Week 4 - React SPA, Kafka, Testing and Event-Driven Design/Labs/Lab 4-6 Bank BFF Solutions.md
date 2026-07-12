## Lab 4.6  -- Solutions and Checkpoint Answers

This document contains the completed code for every TODO in the v2 BFF lab, along with explanations of why the code is the way it is.

---

## How to Use This File

For each TODO in the lab, the matching solution shows the completed code plus a short explanation. The explanations matter more than the code: the code is mechanical, but knowing **why** is what lets you write your own next time.

If you copy a solution without reading the explanation, you have understood nothing. Spend a moment with each "why".

---

## Exercise 1 -- Register the BFF as an OAuth Client

Exercise 1 has no fill-in TODOs - the code is given. The point of the exercise is for you to:

- Open the auth server project (Lab 2-1's `authserver`)
- Locate the `RegisteredClientRepository` bean
- Paste the `bankClientBff` registration after the `bankService` registration
- Update the return statement to include `bankClientBff`
- Restart the auth server

The result is a third registered client alongside `bank-spa` and `bank-service`:

| Client | Type | Grant | Used by |
|---|---|---|---|
| `bank-spa` | Public | Authorization Code + PKCE | The React SPA (no client secret) |
| `bank-service` | Confidential | Client Credentials | Backend services, no user |
| `bank-client-bff` | Confidential | Authorization Code + Refresh | The BFF (this lab) |

### Why a separate registration?

The BFF could in theory share the `bank-spa` registration, but doing so would force the BFF to behave like a public client - PKCE only, no client secret. Confidential clients are stronger because they prove their identity with a secret in addition to the redirect URI match. The BFF is a backend that can keep a secret, so it benefits from the stronger profile.

The BFF also could not use `bank-service`'s Client Credentials grant, because Client Credentials does not involve a user. The whole point of the BFF is to act on behalf of a user (alice, edward, audit), which requires Authorization Code.

### Why the refresh token grant?

Adding `AuthorizationGrantType.REFRESH_TOKEN` does two things: it tells the auth server to issue a refresh token alongside the access token, and it tells the auth server to accept refresh-token grants from this client. Without it, the BFF would need the user to log in again every time the access token expired - even though the user has an active session with the BFF. The refresh token lets the BFF renew the access token silently.

### Why register all bank scopes?

The Lab 2-1 token customizer narrows scopes per user at issue time:

- alice (account_holder) gets the account_holder subset
- edward (teller) gets the teller subset
- audit (auditor) gets the auditor subset

Registering the client with the union of all scopes means any user can log in via the BFF and receive a token appropriate to their role. If the BFF were registered only with `account.read`, then edward would get only `account.read` even though edward's role normally includes `account.write`, `account.create`, and others. Always register the client with the maximum scope set; let the token customizer narrow per user.

---

## Exercise 2 -- Extend the bankapi Resource Server

Exercise 2 has no fill-in TODOs either. The work is mechanical:

- Change `application.yml` `server.port` from 8080 to 8081
- Change `issuer-uri` (and `jwks-uri` host) from `localhost:9000` to `127.0.0.1:9000`
- Add the four new classes (`TransferRequest`, `TransferResponse`, `TransactionStatus`, `TransferService`, `TransferController`)
- Add the new scope rule for `POST /api/v1/transfers`

### Why 127.0.0.1 and not localhost in the issuer URI?

Lab 2-1's auth server uses `127.0.0.1:9000` as the issuer URL. Tokens it issues carry `iss=http://127.0.0.1:9000` in the JWT payload. Spring Security on the resource server compares the incoming token's `iss` claim against the configured `issuer-uri`. If they do not match exactly (string equality), the token is rejected with 401.

So bankapi's `issuer-uri` *must* match what the auth server actually puts in tokens. Lab 2-2's original `localhost:9000` was a hidden bug that did not surface because students obtained tokens through the auth server's web UI, which silently kept everything on `127.0.0.1` (the redirect URI). The BFF lab makes the mismatch easy to hit because both the BFF's OAuth client config and bankapi's resource server config need to agree on the host.

### Why `SCOPE_transaction.create` and not `SCOPE_account.write`?

A transfer creates a transaction record (the movement of money is a transaction). Granting `account.write` would imply broader powers - editing account metadata, changing status, etc. - that the transfer endpoint does not need. The principle of least privilege applies.

Looking at Lab 2-1's role-to-scope mapping:

- account_holder has `transaction.create` (alice, bob, carla can transfer)
- teller has `transaction.create` (edward can transfer)
- auditor does NOT have `transaction.create` (audit cannot transfer)

This is exactly the right scope for the transfer endpoint. An auditor should be able to read everything but not move money.

---

## Exercise 3 -- Configure the OAuth Client

### TODO 3.1 -- client-id

```yaml
client-id: bank-client-bff
```

Must match the `clientId(...)` value registered in Exercise 1.

### TODO 3.2 -- client-secret

```yaml
client-secret: bank-client-bff-secret
```

Must match the `clientSecret(...)` value registered in Exercise 1, **without** the `{noop}` prefix. The `{noop}` is a Spring password-encoder marker that lives only on the auth server side; the BFF sends the raw value.

### TODO 3.3 -- authorization-grant-type

```yaml
authorization-grant-type: authorization_code
```

The string value matches the OAuth2 specification's grant-type identifier. Spring Security maps this to `AuthorizationGrantType.AUTHORIZATION_CODE` internally.

### TODO 3.4 -- redirect-uri

```yaml
redirect-uri: "{baseUrl}/login/oauth2/code/{registrationId}"
```

The placeholders are filled in by Spring at runtime: `{baseUrl}` becomes `http://localhost:8080` and `{registrationId}` becomes `bank-auth`. The resolved URL is `http://localhost:8080/login/oauth2/code/bank-auth`, which must match exactly what Exercise 1 registered.

### TODO 3.5 -- scope

```yaml
scope:
  - openid
  - profile
  - account.read
  - account.write
  - account.create
  - transaction.read
  - transaction.create
  - customer.read
  - customer.write
```

These are the scopes the BFF *requests*. The auth server's token customizer narrows them per user. alice will get a token with the account_holder subset; the requested scope list is just the upper bound.

`openid` and `profile` are the two OIDC scopes that give the BFF an ID token with `preferred_username`, `name`, and so on - the data needed by `/api/me`.

### TODO 3.6 -- issuer-uri

```yaml
issuer-uri: http://127.0.0.1:9000
```

`127.0.0.1`, not `localhost`. See Exercise 2's notes on why this matters. The auth server publishes its discovery document at `http://127.0.0.1:9000/.well-known/openid-configuration`; from there Spring reads the authorization, token, and JWKS endpoints automatically.

### Complete `application.yml`

```yaml
server:
  port: 8080
  servlet:
    session:
      cookie:
        name: BFF_SESSION

spring:
  application:
    name: bankbff

  security:
    oauth2:
      client:
        registration:
          bank-auth:
            client-id: bank-client-bff
            client-secret: bank-client-bff-secret
            authorization-grant-type: authorization_code
            redirect-uri: "{baseUrl}/login/oauth2/code/{registrationId}"
            scope:
              - openid
              - profile
              - account.read
              - account.write
              - account.create
              - transaction.read
              - transaction.create
              - customer.read
              - customer.write

        provider:
          bank-auth:
            issuer-uri: http://127.0.0.1:9000

banking:
  resource-server:
    base-url: http://localhost:8081

logging:
  level:
    org.springframework.security: INFO
    org.springframework.security.oauth2: DEBUG
    com.example.bankbff: DEBUG
```

### Why the custom session cookie name matters

The `server.servlet.session.cookie.name: BFF_SESSION` setting at the top of the file is the easiest line in the configuration to skip past, but skipping it produces one of the most confusing bugs in this lab.

By default, every Spring Boot application names its session cookie `JSESSIONID`. The auth server uses `JSESSIONID`. The resource server uses `JSESSIONID`. The BFF, without this setting, would also use `JSESSIONID`. In production this is fine because the three services live on different hostnames and the browser keeps their cookies separate. In local development, all three run on `localhost`, and browsers scope cookies by hostname alone - the port number is not part of the cookie identity. The browser sees three apps trying to set a cookie called `JSESSIONID` on the same host, and each new value overwrites the previous one.

The symptom is non-deterministic 401 errors. A student logs in successfully, gets bounced back to the BFF, sees their session work for a moment, then fails authentication on the next request because the resource server's response just overwrote the BFF's session cookie with its own. Reloading sometimes works because the BFF reissues its cookie, and the order of overwrites depends on timing.

Giving the BFF a unique cookie name (`BFF_SESSION`) eliminates the collision. The browser stores `BFF_SESSION` and `JSESSIONID` as separate cookies and sends both with every request to `localhost`, but each app only reads the cookie name it knows about. The BFF reads `BFF_SESSION` and ignores `JSESSIONID`. The auth server and resource server read `JSESSIONID` and ignore `BFF_SESSION`. There is no fundamental fix needed on the auth server or resource server - changing only the BFF is sufficient because the BFF is the only app that needs to maintain a session with the browser long enough for the overwrites to matter.

The general lesson: if you are running multiple Spring Boot apps that maintain HTTP sessions on the same host, give each one a unique session cookie name. The default of `JSESSIONID` is fine when each app has its own hostname, but breaks the moment two of them share `localhost`.

---

## Exercise 4 -- Configure Spring Security in the BFF

### Complete SecurityConfig.java

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

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/oauth2/**", "/login/**").permitAll()
                        .requestMatchers("/api/**").authenticated()
                        .anyRequest().authenticated())

                .exceptionHandling(ex -> ex
                        .defaultAuthenticationEntryPointFor(
                                new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED),
                                new MediaTypeRequestMatcher(MediaType.APPLICATION_JSON))
                        .authenticationEntryPoint(
                                new LoginUrlAuthenticationEntryPoint(
                                        "/oauth2/authorization/bank-auth")))

                .oauth2Login(Customizer.withDefaults())

                .logout(logout -> logout
                        .logoutUrl("/logout")
                        .logoutSuccessUrl("/")
                        .invalidateHttpSession(true)
                        .clearAuthentication(true))

                .csrf(AbstractHttpConfigurer::disable);

        return http.build();
    }
}
```

### Why `@EnableWebSecurity` is on the class

In recent Spring Boot versions, `@EnableWebSecurity` is officially "optional" - the framework is supposed to auto-detect any `SecurityFilterChain` bean you provide and use it instead of the default chain. The Spring Security docs even say so.

In practice, the auto-detection is fragile. Depending on bean processing order, Spring Boot version, and what other configurations are present, your custom `SecurityFilterChain` can be silently overlooked. When this happens, the symptoms are confusing:

- Your `@Configuration` class is loaded (you can prove this with a `@PostConstruct` log line)
- Your `@Bean` method is called (you can prove this with a log line at the top of the method)
- But the request lifecycle uses the default filter chain anyway - your custom rules never fire

The fix is to add `@EnableWebSecurity` explicitly. This tells Spring Security "I'm taking control of the chain configuration; use mine, not yours." The contract is unambiguous and the behavior is deterministic.

The general lesson: when an "optional" annotation is documented as "the framework will figure it out for you," and you find yourself debugging weird auto-detection failures, the explicit form is almost always the safer choice. The cost of adding `@EnableWebSecurity` is one line; the cost of not adding it is potentially hours of debugging.

### Why TODO 4.2 matters: the dual-audience problem

A BFF is hit by two kinds of caller:

- **Browser navigation.** alice types `http://localhost:8080/api/me` into the address bar (or follows a link). She is not authenticated. The correct response is to redirect her to the login page. The browser follows the redirect; alice sees a login form.
- **JavaScript fetch / `.http` file / curl.** A programmatic client calls `/api/me` with `Accept: application/json`. It is not authenticated. The correct response is **401 Unauthorized** - a status code, not a redirect. The client code can branch on the 401 and show a "please log in" message of its own.

Without TODO 4.2, Spring Security defaults to the browser behaviour for everyone. A fetch call to `/api/me` returns a 302 redirect to the login page, followed by the HTML of the login page itself. The fetch caller sees HTML where it expected JSON, and chaos ensues.

The fix is `defaultAuthenticationEntryPointFor` paired with a `MediaTypeRequestMatcher`. If the request says `Accept: application/json`, return a 401. Otherwise, fall through to the default entry point, which redirects to the login URL. The `MediaTypeRequestMatcher(MediaType.APPLICATION_JSON)` is the discriminator.

### Why TODO 4.1 permits both `/oauth2/**` and `/login/**`

The OAuth flow has two checkpoints inside the BFF:

- `/oauth2/authorization/bank-auth` is where the SPA (or a browser address bar) initiates the flow. Spring Security generates this endpoint automatically for each registered client.
- `/login/oauth2/code/bank-auth` is the callback the auth server redirects to. Spring Security receives the authorization code here, exchanges it for tokens, and creates the session.

Both URLs are hit by an *unauthenticated* user - that is the whole point of the OAuth flow. If you require authentication on them, the OAuth flow cannot start. Hence `permitAll()` on `/oauth2/**` (the initiation side) and `/login/**` (the callback side).

After the callback completes, the user has a session cookie. From that point on, `/api/**` calls are authenticated.

---

## Exercise 5 -- Build the WebClient with OAuth Filter

### Complete WebClientConfig.java

```java
package com.example.bankbff.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.web.reactive.function.client.ServletOAuth2AuthorizedClientExchangeFilterFunction;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
public class WebClientConfig {

    @Bean
    public WebClient bankApiWebClient(
            OAuth2AuthorizedClientManager authorizedClientManager,
            @Value("${banking.resource-server.base-url}") String baseUrl) {

        var oauth2Filter = new ServletOAuth2AuthorizedClientExchangeFilterFunction(
                authorizedClientManager);
        oauth2Filter.setDefaultClientRegistrationId("bank-auth");

        return WebClient.builder()
                .baseUrl(baseUrl)
                .apply(oauth2Filter.oauth2Configuration())
                .build();
    }
}
```

### Why `setDefaultClientRegistrationId("bank-auth")`?

The BFF only has one OAuth client registered (`bank-auth`), so it might seem unnecessary to name it. But the filter is built to support multiple registrations in the same application. Without the default, every WebClient call would need to specify which registration to use via an attribute on the request. Setting the default registration once makes the call sites clean: `webClient.get().uri(...).retrieve()` just works, and the filter picks `bank-auth` automatically.

### Why `apply(oauth2Filter.oauth2Configuration())` rather than `filter(oauth2Filter)`?

`oauth2Configuration()` returns a `Consumer<WebClient.Builder>` that does more than just add the filter - it also configures default request attributes and other plumbing the filter relies on. Using `apply(...)` is the correct full setup. Using `filter(...)` alone would attach the filter but skip the setup, and you would get cryptic runtime errors about missing attributes.

---

## Exercise 6 -- Build the Resource Server Client

### Complete BankingApiClient.java

```java
package com.example.bankbff.client;

import com.example.bankbff.dto.AccountDto;
import com.example.bankbff.dto.TransferRequestDto;
import com.example.bankbff.dto.TransferResponseDto;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import java.util.List;

@Component
public class BankingApiClient {

    private final WebClient bankApiWebClient;

    public BankingApiClient(WebClient bankApiWebClient) {
        this.bankApiWebClient = bankApiWebClient;
    }

    public List<AccountDto> getAccounts() {
        return bankApiWebClient.get()
                .uri("/api/v1/accounts")
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<List<AccountDto>>() {})
                .block();
    }

    public TransferResponseDto postTransfer(TransferRequestDto request) {
        return bankApiWebClient.post()
                .uri("/api/v1/transfers")
                .bodyValue(request)
                .retrieve()
                .bodyToMono(TransferResponseDto.class)
                .block();
    }
}
```

### Why `ParameterizedTypeReference` for `List<AccountDto>`?

Java erases generic type parameters at runtime. `List<AccountDto>.class` does not compile. `ParameterizedTypeReference<List<AccountDto>>() {}` (note the trailing `{}` creating an anonymous subclass) preserves the generic type information in a way Spring can read at runtime. Without it, Spring would deserialize the JSON array into a raw `List<Object>` with no idea what the elements should be.

### Why `.block()`?

WebClient is reactive (non-blocking) by default - calls return a `Mono` rather than a value. The BFF runs on Spring MVC, which is a blocking model: a controller method must return a real value, not a Mono. `.block()` blocks the current thread until the Mono completes and returns the value. This is the simplest correct pattern when bridging from WebClient to MVC.

In a WebFlux application you would not call `.block()` - you would let the Mono flow through the controller and the entire chain stays reactive. But this lab uses MVC.

---

## Exercise 7 -- Build the User and Account Controllers

### Complete UserController.java (TODO 7.1)

```java
package com.example.bankbff.controller;

import com.example.bankbff.dto.UserInfoDto;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api")
public class UserController {

    @GetMapping("/me")
    public UserInfoDto me(@AuthenticationPrincipal OidcUser principal) {
        List<String> roles = principal.getClaimAsStringList("roles");
        if (roles == null) {
            roles = List.of();
        }
        return new UserInfoDto(
                principal.getSubject(),
                principal.getPreferredUsername(),
                principal.getFullName(),
                roles);
    }
}
```

### Why null-check `roles`?

If the user logs in with only `openid` scope (no `profile`, no bank scopes), the `roles` claim may not be present in the ID token. `getClaimAsStringList("roles")` returns `null` in that case. Returning a JSON null is awkward for the SPA; returning an empty list is the cleaner contract. The check converts `null` to `List.of()` so the SPA always sees an array, possibly empty.

### Why `OidcUser` and not `Authentication` directly?

`OidcUser` is a richer principal type that exposes ID-token claims as named getters: `getSubject()`, `getPreferredUsername()`, `getFullName()`, etc. Using it makes the code more readable than calling `auth.getAttributes().get("preferred_username")` repeatedly. Spring populates the `Authentication.principal` with an `OidcUser` automatically when the OAuth client is configured for OIDC (`openid` scope is requested).

### Complete AccountController.java (TODO 7.2 and 7.3)

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

@RestController
@RequestMapping("/api")
public class AccountController {

    private final BankingApiClient bankingApiClient;

    public AccountController(BankingApiClient bankingApiClient) {
        this.bankingApiClient = bankingApiClient;
    }

    @GetMapping("/accounts")
    public List<AccountDto> accounts() {
        return bankingApiClient.getAccounts();
    }

    @PostMapping("/transfers")
    public TransferResponseDto transfer(@RequestBody TransferRequestDto request) {
        return bankingApiClient.postTransfer(request);
    }
}
```

The controllers are deliberately thin proxies. They do not transform the data; they just hand the request to the client and return the response. This is the simplest BFF pattern - a real BFF would often aggregate multiple downstream calls, transform shapes for the SPA, or apply caching. For this lab the pass-through is enough.

---

## Exercise 8 -- Test with bank-requests.http

Exercise 8 has no fill-in TODOs; the `.http` file is copy-paste. The expected results are:

| Step | Expected response |
|---|---|
| Unauthenticated `/api/me` | 401 |
| Unauthenticated `/api/accounts` | 401 |
| Authenticated `/api/me` (as alice) | 200 with `{subject: "C001", preferredUsername: "alice", fullName: "Alice Nguyen", roles: ["account_holder"]}` |
| Authenticated `/api/accounts` | 200 with five accounts (A001 to A005) |
| Authenticated `/api/transfers` (A001 to A002, 100.00) | 200 with `transactionId` and `status: COMPLETE` |
| Re-fetch `/api/accounts` | 200; A001 balance 1150.00, A002 balance 8500.00 |
| `POST /logout` | 200 (or 302 redirect to `/`) |
| `/api/me` after logout | 401 |

If any step fails, check the BFF logs first. Common issues:

- Wrong `BFF_SESSION` value pasted in the `.http` file. Re-copy from DevTools.
- Browser was logged out (closed tab, session expired). Re-log in via the browser.
- bankapi is not running or returning errors. Check port 8081 logs.
- Auth server is not running. Check port 9000 logs.
- bankapi's `issuer-uri` is still `localhost:9000` instead of `127.0.0.1:9000`. The JWT validation will reject every token with 401. See Exercise 2's note.

### Testing role-based behaviour

The lab suggests trying `edward` (teller) and `audit` (auditor) as well as alice. The expected differences:

| User | `/api/me` `subject` | `/api/me` `roles` | `/api/accounts` | `/api/transfers` |
|---|---|---|---|---|
| alice | C001 | [account_holder] | 5 accounts | 200 COMPLETE |
| edward | EM01 | [teller] | 5 accounts | 200 COMPLETE |
| audit | AUD01 | [auditor] | 5 accounts | 403 from bankapi |

The audit user's transfer failure is the educational moment. The BFF holds a perfectly valid access token for audit. The token even reaches bankapi unchanged. But the token's `scope` claim does not include `transaction.create` (the token customizer narrowed scopes per role), and bankapi's `SecurityConfig` requires `SCOPE_transaction.create` for `POST /api/v1/transfers`. The 403 is correct enforcement, and it happens at the resource server, not at the BFF. The BFF itself has no idea what the rules are; it just forwards. This is the value of putting authorization in the resource server.

---

## Diagnostics Deep Dive

The main lab includes a Troubleshooting section that walks through the common failures. This section explains **why** those failures happen and the diagnostic techniques that localize them quickly. The goal is to teach the diagnostic methodology, not just give you a checklist. The next time something in a distributed system fails for non-obvious reasons, the same approach applies.

### The fundamental problem: a 401 from anywhere looks identical

When you make a request to the BFF and get back `HTTP/1.1 401`, that 401 could be coming from any of three places:

1. The BFF, because it has no session for you
2. The BFF, because it had a session but its WebClient could not get an access token to call bankapi
3. Bankapi, because the access token attached by the BFF was rejected

All three produce a 401 with similar `WWW-Authenticate: Bearer` headers. The error code does not tell you which layer is failing. You have to *infer* the layer from secondary signals.

This is true of any layered system. The closer you can get to the layer that actually generated the failure, the faster you diagnose. Most beginners stay at the outer layer, look at the 401, and start guessing. The fastest debuggers learn to read secondary signals and walk to the layer that matters.

### The three diagnostic signals in this lab

Each of these tells you something the others do not.

**Signal 1: The redirect chain in the `.http` response**

IntelliJ's HTTP client follows redirects and prints them under `Redirections:` in the response. The number of redirects encodes which layer rejected your request:

- **Zero redirects, just 401:** You are getting an "honest" 401 from somewhere - usually because the BFF's `SecurityConfig` (with the `defaultAuthenticationEntryPointFor` configured for JSON) ran correctly and decided you are not authenticated.

- **One redirect (`/api/x` -> auth server):** The BFF accepted your session as authenticated (it skipped its own login-redirect step). It then tried to do the downstream work, and *that* failed, so Spring Security treated it as a re-authentication request. The actual error is in the downstream call.

- **Two redirects (`/api/x` -> BFF's `/oauth2/authorization/bank-auth` -> auth server):** The BFF saw an unauthenticated request and started the OAuth login flow from scratch. Your session cookie was not recognized.

The pedagogical point: count the redirects before guessing. They tell you which layer to look at.

**Signal 2: Does `/api/me` work?**

`/api/me` is the simplest authenticated endpoint in the BFF. It reads the OIDC principal out of the session and returns it. It does NOT touch the WebClient, the OAuth token, or bankapi.

This makes it a perfect bisection point:

- `/api/me` works AND `/api/accounts` works -> entire system is healthy
- `/api/me` works BUT `/api/accounts` fails -> BFF session is fine; problem is in the WebClient call or downstream at bankapi
- `/api/me` fails -> BFF does not recognize your session at all; problem is your cookie or session

In any layered system, look for the cheapest endpoint that exercises only the lower layers. It's your bisection oracle.

**Signal 3: Does bankapi log anything?**

If your call fails with a 401 and you watch bankapi's console during the request, one of two things happens:

- **Bankapi logs something.** The request reached bankapi. The log message tells you why bankapi rejected the token (issuer mismatch, signature failure, expired, missing scope).

- **Bankapi logs nothing.** The request never reached bankapi. The BFF's WebClient filter could not get a token to attach, so it never made the outbound HTTP call. The 401 you see was generated by the BFF itself in response to the failed token lookup.

The pedagogical point: silence is a signal too. A system that is failing but generating no logs at the layer you expected is telling you the failure is upstream of that layer.

### The cookie-after-restart trap

This is the most common cause of "it worked before lunch but does not work now" in this lab.

The BFF's session is **server-side**. The `BFF_SESSION` cookie is only a key that points to a session object stored in the BFF's memory. The session object contains the OAuth2 authenticated client, the access token, the refresh token, and the user's principal.

When you restart the BFF, all in-memory sessions are destroyed. The `BFF_SESSION` cookie in your browser and the `@sessionCookie` value in your `.http` file still exist - they just point to nothing now. The BFF, seeing a cookie that does not match any session it knows about, treats the request as unauthenticated and initiates a fresh OAuth flow.

The fix is mechanical but easy to forget: after every BFF restart, log in fresh in the browser, copy the new cookie value, and update your `.http` file. The lab's after-restart checklist makes this routine.

In production this is less of a concern because session storage is typically externalized (Redis, a database) and survives application restarts. For local development with default in-memory sessions, restart and re-login go together.

### The cookie format trap

This trap is subtle because the cookie value alone *looks* correct. If you set:

```
@sessionCookie = 953989EFEBAA02781FB53A5C7ABD5EEA
```

then your request sends `Cookie: 953989EFEBAA02781FB53A5C7ABD5EEA`. This is not a valid `Cookie:` header - it has no cookie name. The server reads the header, fails to parse a name=value pair, and silently ignores the cookie. You get treated as unauthenticated even though the cookie value itself is right.

The correct format is:

```
@sessionCookie = BFF_SESSION=953989EFEBAA02781FB53A5C7ABD5EEA
```

The `BFF_SESSION=` prefix is part of the value, not a comment. The lab's `.http` template includes it for you - the most common mistake is replacing the whole right-hand side of the `=` (including the `BFF_SESSION=`) when pasting the cookie value, instead of replacing only `PASTE_THE_COOKIE_VALUE_HERE`.

### The hot-reload trap

Spring Boot DevTools restarts the application context when source code changes, without restarting the JVM. This is fast and useful most of the time, but it has edge cases:

- Newly added `@Configuration` classes sometimes do not get picked up correctly
- Modified `@Bean` methods sometimes get the old definition cached
- Adding annotations to existing classes sometimes does not register them

The fingerprint of a hot reload: startup time well under a second, and "process running for" time much larger than the startup time. A genuine cold restart shows startup time of 1+ seconds, and "process running for" within a second of the startup time.

If your code change does not seem to take effect, do not trust the hot reload. Click the red Stop square in IntelliJ's Run panel, wait for the process to exit, then click the green Run button. This is a true cold start. If the change still does not take effect, the build itself is the issue (run Build -> Rebuild Project).

### The `localhost` vs `127.0.0.1` trap

JWT validation in Spring is strict about string equality. If a token's `iss` claim is `http://localhost:9000` and bankapi is configured with `issuer-uri: http://127.0.0.1:9000`, the token is rejected. The two hostnames resolve to the same IP, but Spring compares strings.

The auth server in Lab 2-1 uses `127.0.0.1` (this is documented in Lab 2-1's notes - browsers treat the two as different origins for cookie scope, which would break the OAuth redirect flow). Everything that talks to the auth server must therefore also use `127.0.0.1`:

- bankapi's `issuer-uri`
- bankapi's `jwks-uri`
- bankapi's `token-uri` (if it has a downstream OAuth client block)
- The BFF's `provider.bank-auth.issuer-uri`

The BFF runs on `localhost:8080` because that's its own URL. The redirect URI registered with the auth server is `http://localhost:8080/login/oauth2/code/bank-auth` because that's where the auth server sends the browser back to. The two hosts are different services on different ports, so the browser keeps their cookies separate and no conflict arises.

The general lesson: when configuring distributed systems, pick one host convention and apply it consistently to everything in the same security domain. Mixing conventions causes "tokens that look valid but get rejected" failures.

### Pulling it together: what to do when a 401 happens

The diagnostic flow, in order:

1. Try `/api/me` in the browser using the same session. If it fails, focus on the session and cookie. If it works, focus on the WebClient or bankapi.
2. Count the redirects in the `.http` response. One redirect means downstream; two redirects mean session.
3. Watch bankapi's console during the failing request. No log means the request never reached bankapi (BFF-side problem). A log message tells you specifically what bankapi rejected.
4. If you recently restarted the BFF, refresh the `BFF_SESSION` cookie before anything else. This single step fixes most "it stopped working" reports.
5. If the discovery document at `http://127.0.0.1:9000/.well-known/openid-configuration` shows an unexpected `issuer`, the auth server's published issuer disagrees with what other services expect. Verify Lab 2-1's `application.yml` and `AuthorizationServerSettings` configuration.

---

## Reflection Questions (lab-b-notes.md answers)

### Question 1: The BFF uses the `authorization_code` grant. The other bank clients in Lab 2-1 use `client_credentials` (`bank-service`) or `authorization_code + PKCE` without a secret (`bank-spa`). What is the practical difference between these three grants? When would you use each?

The three grants represent three different scenarios:

**Authorization Code + Client Secret** (the BFF's grant) is for a confidential web application that authenticates a human user. The user is redirected to the auth server, logs in there, and is redirected back with an authorization code. The web app exchanges the code for tokens using its client secret. The resulting access token represents the user's identity, narrowed by the user's role.

**Authorization Code + PKCE** (`bank-spa`'s grant) is for a public client - typically a SPA running in a browser, or a mobile app - that cannot keep a client secret. PKCE (Proof Key for Code Exchange) replaces the secret with a cryptographic challenge generated per-request: the client generates a random verifier, sends a hash of it (the challenge) during the authorization request, and proves possession of the verifier when exchanging the code for tokens. An attacker who intercepts the code cannot exchange it because they do not have the verifier.

**Client Credentials** (`bank-service`'s grant) is for one service authenticating to another with no user involved. The client sends its client ID and client secret directly to the token endpoint and receives a token representing the service's own identity. This is for backend jobs, scheduled tasks, and service-to-service calls.

The practical difference shows up in the `sub` claim of the resulting token. Authorization Code (with or without PKCE) produces tokens whose `sub` is the user's identifier (C001, EM01, AUD01 in Lab 2-1). Client Credentials produces tokens whose `sub` is the client ID (bank-service). The resource server reads `sub` to decide what data the caller is allowed to see, and the difference between "alice" and "bank-service" is the difference between a personal API and a background job.

Use Authorization Code when there is a real user. Use PKCE when the user is on a SPA or mobile app. Use Client Credentials when there is no user, only a service. They are not interchangeable: an attempt to use Client Credentials for a user-facing flow loses the user's identity entirely.

### Question 2: After logging in, the browser holds only a `BFF_SESSION` cookie. What threats does this protect against compared to storing the access token in browser JavaScript?

The big one is XSS-based token theft.

If the access token were stored in browser JavaScript (in `localStorage`, `sessionStorage`, or even just an in-memory variable), any JavaScript code running on the same origin could read it. That includes attacker-injected JavaScript via XSS. With the token in hand, the attacker can:

- Send the token to their own server and impersonate the user from anywhere
- Make API calls as the user from any tab, any browser, any machine
- Continue using the token until it expires (potentially hours)

With the BFF pattern, the browser holds only an `HttpOnly` session cookie. JavaScript cannot read it. An XSS attack can still make calls to the API while the page is open (the cookie is sent automatically), but it cannot exfiltrate the credential to use elsewhere. When the user closes the tab or the session expires, the attack stops.

Other threats the BFF reduces:

- **Token leakage through logging**: tokens never appear in browser history, console logs, or analytics events because they are never in browser code.
- **Token persistence on disk**: `localStorage` is written to disk and survives browser restarts; a session cookie generally does not.
- **Cross-device leakage**: browser sync features may replicate `localStorage` to the user's other devices; session cookies are not synced.

### Question 3: The `WebClient` has the OAuth2 filter applied. What would happen if you used a different `WebClient` (for example, the default `WebClient.builder().build()`) to call the resource server? Why?

A WebClient without the OAuth2 filter sends requests without an `Authorization` header.

The resource server (bankapi) validates JWT bearer tokens on every request via `oauth2ResourceServer.jwt(...)`. A request with no token is rejected with `401 Unauthorized` before it ever reaches the controller method. The BFF would then propagate that 401 (or fail to parse the unexpected response) to the browser.

The OAuth2 filter is what makes the difference. It looks up the current authenticated user's `OAuth2AuthorizedClient`, extracts the access token, attaches it as `Authorization: Bearer <token>`, and handles refresh if the token has expired. None of this happens without the filter. The fix is always: use the bean wired with the filter, never `WebClient.builder().build()` directly for downstream calls.

### Question 4: If the access token expires during a long user session, what does the BFF do? What does the user see?

The `OAuth2AuthorizedClientManager` handles token expiry transparently:

1. When the BFF's WebClient filter goes to attach the access token, it first checks whether the token is expired (or close to expiring).
2. If expired, the manager exchanges the refresh token for a new access token by calling the auth server's token endpoint.
3. The new access token is stored in the session.
4. The original outgoing request continues with the new token attached.

The user sees nothing. There is no redirect, no flicker, no re-prompt. The whole exchange happens server-side in the BFF.

If the refresh token has also expired (which happens after the refresh token's lifetime - 1 day in this lab's configuration), the manager cannot refresh. The next call to a `/api/**` endpoint fails authentication and the user is redirected back to the auth server's login page (for browser navigation) or sees a 401 (for JSON requests).

### Question 5: CSRF protection is disabled in this lab. What kind of attack does CSRF protect against, and why is it more relevant for cookie-authenticated APIs than for bearer-token APIs? You will turn CSRF on in Lab 4.7; what changes?

CSRF (Cross-Site Request Forgery) attacks rely on browsers automatically sending cookies. The classic scenario:

1. alice logs into bank.com and gets a session cookie.
2. While still logged in (cookie still valid), alice visits evil.com.
3. evil.com's page contains JavaScript or a form that submits a POST request to `bank.com/transfer?to=attacker&amount=10000`.
4. Because alice's browser holds a session cookie for bank.com, the browser automatically attaches the cookie to the request. The bank's server cannot tell the request was triggered by evil.com rather than by alice.

CSRF is more relevant for cookie-authenticated APIs because cookies are attached *automatically by the browser* to any request matching the cookie's scope. Bearer tokens require JavaScript to explicitly add the `Authorization` header, which JavaScript on evil.com cannot do across origins (the browser's same-origin policy blocks it).

In Lab 4.7 you will turn CSRF protection back on using the `CookieCsrfTokenRepository.withHttpOnlyFalse()` strategy. That puts the CSRF token in a cookie called `XSRF-TOKEN` that JavaScript can read. The SPA reads the cookie and includes the token in an `X-XSRF-TOKEN` header on every state-changing request. Spring Security validates that the header matches the cookie before allowing the request through.

This is the "double-submit cookie" pattern. It works because evil.com cannot read the XSRF-TOKEN cookie value; the same-origin policy prevents that. So evil.com cannot include the correct token in the forged request, and Spring rejects it.

### Question 6: The BFF lab uses dotted scope names (`account.read`, `transaction.create`) inherited from Lab 2-1. The original module slides mentioned colon-separated scopes (`read:accounts`) as an alternative. What does the BFF actually care about - the scope name itself, or just that the auth server and resource server agree?

The BFF itself does not care about scope names at all. The BFF just requests whatever scopes it is configured to request and forwards whatever token the auth server hands back.

The auth server cares about scope names because it has to know which scopes are valid to issue.

The resource server cares about scope names because its `@PreAuthorize` annotations and `authorizeHttpRequests` rules reference specific scopes (`SCOPE_account.read`, etc.).

The *only* hard constraint is that all three parties use the same names. Whether they are `account.read` or `read:accounts` or even `BANK_READ_ACCOUNTS` is a stylistic choice that should be made once and applied consistently. Mixed conventions (one app using `account.read` and another using `read:accounts`) produce 403 errors that are easy to misdiagnose as token corruption or misconfiguration.

Lab 2-1 chose the dotted form. The BFF and bankapi inherit it. A different organization might prefer the colon form (it is somewhat common in JWT-issuing systems like Auth0). The choice itself is less important than the consistency.
