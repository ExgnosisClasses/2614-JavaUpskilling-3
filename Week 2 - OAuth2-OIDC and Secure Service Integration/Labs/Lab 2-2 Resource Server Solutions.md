# Lab 2-2: Reference Solutions

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 3 - OAuth2 / OIDC Foundations and Spring Security

This file contains completed code for every `TODO` in Lab 2-2, organized by exercise and TODO number. Each entry shows the completed code and a short note on why it works the way it does.

**How to use this file:**
- Work through the lab first. Reach for solutions only after a genuine attempt.
- The completed code shown here is one correct answer; alternatives exist for several TODOs and are noted where relevant.
- Copy with understanding, not by rote - every Spring Security misconfiguration in production starts as a line that "looked right."

---

## Exercise 2 - Configuring Spring Security as a Resource Server

### TODO 1 - POST endpoint on `AccountController`

Add to `AccountController.java`:

```java
@PostMapping
public ResponseEntity<Account> create(@RequestBody Account account) {
    // Stub: no persistence in this exercise. We just echo the account back
    // to demonstrate the 201 Created response and confirm the security rule
    // (account.create scope) is enforced before this method is reached.
    return ResponseEntity.status(HttpStatus.CREATED).body(account);
}
```

The body never runs without an `account.create` scope because the URL-level rule in `SecurityConfig` (TODO 2) rejects unauthorized callers before the request reaches the controller.

### TODO 2 - URL-level authorization rules

Replace the `.authorizeHttpRequests(...)` block in `SecurityConfig.java`:

```java
.authorizeHttpRequests(auth -> auth
        .requestMatchers(HttpMethod.GET,  "/health").permitAll()
        .requestMatchers(HttpMethod.GET,  "/api/v1/accounts/**").hasAuthority("SCOPE_account.read")
        .requestMatchers(HttpMethod.POST, "/api/v1/accounts").hasAuthority("SCOPE_account.create")
        .anyRequest().authenticated()
)
```

Order matters: the GET rule for `/api/v1/accounts/**` is listed before `anyRequest().authenticated()` because rules are evaluated top-to-bottom and the first match wins. If you reversed them, every GET would be accepted as long as the caller had *any* valid token.

### TODO 3 - Enable JWT resource-server processing

Add this method call to the `SecurityConfig` chain:

```java
.oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
```

This single line activates the entire JWT pipeline: the `BearerTokenAuthenticationFilter` extracts the token, the `JwtDecoder` (auto-configured from `jwks-uri` in `application.yml`) verifies the signature, and the `JwtAuthenticationConverter` turns each scope into a `SCOPE_<name>` authority.

### TODO 4 - Stateless session management

```java
.sessionManagement(session -> session
        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
```

`STATELESS` tells Spring Security never to create or look up an `HttpSession`. Each request stands alone: the Bearer token is the entire identity. If you omit this, Spring creates a session per request as a side effect of evaluating the security context, which wastes memory and creates a foothold for session-fixation attacks.

### TODO 5 - Disable CSRF

```java
.csrf(csrf -> csrf.disable())
```

CSRF defends against the browser auto-sending session cookies to a malicious site. Bearer tokens travel in the `Authorization` header, which browsers never auto-send cross-origin, so CSRF doesn't apply. Disabling it removes a check that would only generate noise for a stateless API.

**Final `SecurityConfig.java` for Exercise 2:**

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                    .requestMatchers(HttpMethod.GET,  "/health").permitAll()
                    .requestMatchers(HttpMethod.GET,  "/api/v1/accounts/**").hasAuthority("SCOPE_account.read")
                    .requestMatchers(HttpMethod.POST, "/api/v1/accounts").hasAuthority("SCOPE_account.create")
                    .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .sessionManagement(session -> session
                    .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .csrf(csrf -> csrf.disable());

        return http.build();
    }
}
```

---

## Exercise 3 - Accessing JWT Claims in Application Code

### TODO 6 & 7 - `/me` endpoint reading claims

Full method body for `AccountController`:

```java
@GetMapping("/me")
public Map<String, Object> getCurrentUser(@AuthenticationPrincipal Jwt jwt) {
    Map<String, Object> result = new HashMap<>();
    result.put("subject",     jwt.getSubject());
    result.put("issuer",      jwt.getIssuer().toString());
    result.put("scopes",      jwt.getClaimAsString("scope"));
    result.put("tokenExpiry", jwt.getExpiresAt().toString());

    var roles = jwt.getClaimAsStringList("roles");
    result.put("roles", roles != null ? roles : List.of());

    var pref = jwt.getClaimAsString("preferred_username");
    result.put("preferredUsername", pref != null ? pref : "not present");

    var name = jwt.getClaimAsString("name");
    result.put("fullName", name != null ? name : "not present");

    return result;
}
```

The `HashMap` (rather than `Map.of(...)`) is necessary because `Map.of` rejects null values, and `jwt.getClaimAsStringList` returns null for absent claims. The defensive null checks make the contract clear: a service token simply doesn't have these claims, and "not present" is informative rather than an error.

### TODO 8 & 9 - Reading the subject in `AuditService`

```java
public void logEvent(String action, String resourceId) {
    Authentication auth = SecurityContextHolder.getContext().getAuthentication();
    String subject = "anonymous";

    if (auth != null && auth.getPrincipal() instanceof Jwt jwt) {
        subject = jwt.getSubject();   // C001, EM01, AUD01, or a service client ID
    }

    System.out.printf("[AUDIT] %s | action=%s | resource=%s | caller=%s%n",
            Instant.now(), action, resourceId, subject);
}
```

The pattern-matching `instanceof` both checks the type and assigns the variable in one step. The `"anonymous"` default handles the case where this service is called from a non-secured context (e.g., a startup task or a unit test without `@WithMockUser`).

Wire it into `AccountController.getById`:

```java
@RestController
@RequestMapping("/api/v1/accounts")
public class AccountController {

    private final AuditService auditService;

    public AccountController(AuditService auditService) {
        this.auditService = auditService;
    }

    @GetMapping("/{id}")
    public ResponseEntity<Account> getById(@PathVariable String id) {
        auditService.logEvent("READ_ACCOUNT", id);
        return ACCOUNTS.stream()
                .filter(a -> a.id().equals(id))
                .findFirst()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
    // ... rest unchanged
}
```

### TODO 10 & 11 - `/mine` endpoint with ownership filter

Add to `AccountController`:

```java
@GetMapping("/mine")
public List<Account> getMyAccounts(@AuthenticationPrincipal Jwt jwt) {
    String subject = jwt.getSubject();
    List<String> roles = jwt.getClaimAsStringList("roles");
    if (roles == null) roles = List.of();

    boolean isStaff = roles.contains("teller") || roles.contains("auditor");
    if (isStaff) {
        return ACCOUNTS;
    }
    return ACCOUNTS.stream()
            .filter(a -> a.customerId().equals(subject))
            .toList();
}
```

The comparison `a.customerId().equals(subject)` is the entire ownership check. There's no helper, no DAO call, no username-to-customer-ID lookup. That's the payoff of putting the customer ID in `sub`.

Alternative: a service-token caller has no `roles` claim. The defensive `if (roles == null) roles = List.of();` ensures `contains(...)` doesn't NPE on those callers - they fall through to the filter branch with `subject = "bank-service"`, which matches no account's customer ID, so they get an empty list. That's the right behavior: a service token isn't a user and shouldn't claim ownership of anything.

---

## Exercise 4 - Method-Level Security with @PreAuthorize

### TODO 12 - `@PreAuthorize` on `findAll()`

```java
@PreAuthorize("hasRole('TELLER') or hasRole('AUDITOR')")
public List<Account> findAll() {
    return new ArrayList<>(store.values());
}
```

Note that this is *only* a role check; there's no scope check. Both tellers and auditors have `account.read` in their scope set, so a scope check here would be redundant - but adding `hasAuthority('SCOPE_account.read') and (hasRole('TELLER') or hasRole('AUDITOR'))` would be defense-in-depth and equally correct.

### TODO 13 - `@PreAuthorize` + `@PostAuthorize` on `findById()`

```java
@PreAuthorize("hasAuthority('SCOPE_account.read')")
@PostAuthorize(
    "returnObject.isEmpty() or hasRole('TELLER') or hasRole('AUDITOR') "
    + "or returnObject.get().customerId() == authentication.name"
)
public Optional<Account> findById(String id) {
    return Optional.ofNullable(store.get(id));
}
```

`@PreAuthorize` runs *before* the method, so it can only check things that don't require the result - here, the scope. `@PostAuthorize` runs *after*, so it can inspect the returned `Optional<Account>` via `returnObject`. The `returnObject.isEmpty()` clause is essential - without it, a 404 (account doesn't exist) would throw `AccessDeniedException` instead of returning `Optional.empty()`, which would leak that the account *would have been* visible to a more privileged user.

### TODO 14 - `@PreAuthorize` on `findByCustomerId()`

```java
@PreAuthorize(
    "#customerId == authentication.name "
    + "or hasRole('TELLER') or hasRole('AUDITOR')"
)
public List<Account> findByCustomerId(String customerId) {
    return store.values().stream()
            .filter(a -> a.customerId().equals(customerId))
            .toList();
}
```

The `#customerId` references the method parameter. The check works because `authentication.name` returns `sub`, which for account holders *is* their customer ID. Carla (sub=C003) can call `findByCustomerId("C003")` but not `findByCustomerId("C001")`.

### TODO 15 - `@PreAuthorize` on `create()`

```java
@PreAuthorize("hasAuthority('SCOPE_account.create') and hasRole('TELLER')")
public Account create(Account account) {
    store.put(account.id(), account);
    return account;
}
```

The `and` combination explicitly requires both. An auditor has broad reads but no create scope and no teller role - denied. A teller without the `account.create` scope in their *current* token (because the scope set requested at login didn't include it) - also denied, even though the role check passes. This is the per-token scope check catching a stale or scope-narrowed token.

### TODO 16 - `@PreAuthorize` on `update()`

```java
@PreAuthorize(
    "hasAuthority('SCOPE_account.write') "
    + "and (hasRole('TELLER') "
    + "     or @accountOwnership.isOwner(#account.id(), authentication))"
)
public Account update(Account account) {
    store.put(account.id(), account);
    return account;
}
```

The `@accountOwnership.isOwner(...)` syntax invokes a Spring bean named `accountOwnership`. `#account.id()` calls the `id()` accessor on the `Account` parameter. Auditors fall through both branches (no teller role, not the owner) so they're denied even though they have `account.write` would - actually they don't have `account.write` in our scope set; the scope check alone denies them. The role/ownership branch is the second layer for tellers vs. account holders.

### TODO 17 - `AccountOwnership.isOwner` body

```java
public boolean isOwner(String accountId, Authentication authentication) {
    if (authentication == null || authentication.getName() == null) {
        return false;
    }
    return accountService.findById(accountId)
            .map(a -> a.customerId().equals(authentication.getName()))
            .orElse(false);
}
```

`Optional.map(...).orElse(false)` is the idiomatic way to express "if present, test the condition; if absent, return false." Equivalent to `findById(accountId).isPresent() && findById(...).get().customerId().equals(...)` but cleaner and only calls `findById` once.

One subtlety worth understanding: calling `accountService.findById(accountId)` inside this helper triggers `findById`'s own `@PreAuthorize` (which requires `SCOPE_account.read`). Every caller who legitimately reaches `isOwner` already has that scope - account holders, tellers, and auditors all carry `account.read`. If they didn't, the chain would fail with an `AccessDeniedException` at the `findById` call rather than returning `false`, which would surface as a 403 to the user. That's acceptable behavior but worth knowing.

### TODO 18 - Account holder cannot call `findAll()`

```java
@Test
@WithMockUser(username = "C001",
              authorities = {"SCOPE_account.read", "ROLE_ACCOUNT_HOLDER"})
void findAll_asAccountHolder_throwsAccessDeniedException() {
    assertThatThrownBy(() -> accountService.findAll())
            .isInstanceOf(AccessDeniedException.class);
}
```

(This is shown in the lab already; included here for completeness.)

### TODO 19 - Teller with create scope succeeds

```java
@Test
@WithMockUser(username = "EM01",
              authorities = {"SCOPE_account.create", "ROLE_TELLER"})
void create_asTellerWithCreateScope_succeeds() {
    var account = new Account("A999", "C002", "CHECKING", new BigDecimal("0.00"));
    var result = accountService.create(account);
    assertThat(result).isNotNull();
    assertThat(result.id()).isEqualTo("A999");
}
```

### TODO 20 - Auditor denied on `create()`

```java
@Test
@WithMockUser(username = "AUD01",
              authorities = {"SCOPE_account.read", "ROLE_AUDITOR"})
void create_asAuditor_throwsAccessDeniedException() {
    var account = new Account("A999", "C002", "CHECKING", new BigDecimal("0.00"));
    assertThatThrownBy(() -> accountService.create(account))
            .isInstanceOf(AccessDeniedException.class);
}
```

The auditor's authorities lack both `SCOPE_account.create` and `ROLE_TELLER`, so the `and` expression in TODO 15 short-circuits to false before the method body runs.

### TODO 21 - Self-invocation bypass demonstration

```java
@Test
void findAllInternal_bypassesMethodSecurity() {
    // No @WithMockUser -- the SecurityContext is empty (anonymous).
    // findAll() has @PreAuthorize("hasRole('TELLER') or hasRole('AUDITOR')"),
    // which would fail for an anonymous caller. But findAllInternal() calls
    // findAll() through 'this', which bypasses the AOP proxy. The annotation
    // is on the proxy, not on the real method, so it never runs.
    //
    // Two correct fixes:
    //   1. Move findAllInternal() to a different bean that injects AccountService
    //      -- the call then goes through the proxy normally.
    //   2. Use AopContext.currentProxy() to call findAll() via the proxy from
    //      within the same class. Requires <aop:aspectj-autoproxy expose-proxy="true"/>
    //      or @EnableAspectJAutoProxy(exposeProxy = true). Less common, less clean.
    //
    // Production risk: any helper method that calls a secured method via 'this'
    // is an authorization bypass. The most common form: a public 'doSomething()'
    // method that calls a private 'doSomethingSecured()' method directly.
    var result = accountService.findAllInternal();
    assertThat(result).isNotEmpty();
}
```

---

## Exercise 5 - Client Credentials Flow

### TODO 22 - `WebClient` bean with OAuth2 filter

(The lab already shows the completed code, repeated here for reference.)

```java
@Bean
public WebClient downstreamApiClient(OAuth2AuthorizedClientManager authorizedClientManager) {
    var oauth2Filter = new ServletOAuth2AuthorizedClientExchangeFilterFunction(authorizedClientManager);
    oauth2Filter.setDefaultClientRegistrationId("downstream-api");

    return WebClient.builder()
            .baseUrl(downstreamBaseUrl)
            .apply(oauth2Filter.oauth2Configuration())
            .build();
}
```

`setDefaultClientRegistrationId("downstream-api")` tells the filter which `spring.security.oauth2.client.registration.*` entry to use when fetching the token. The string must exactly match the YAML key from Task 5.1.

### TODO 23 - `fetchAllFromDownstream()`

```java
public List<Account> fetchAllFromDownstream() {
    return downstreamApiClient.get()
            .uri("/api/v1/accounts")
            .retrieve()
            .bodyToFlux(Account.class)
            .collectList()
            .block();
}
```

`.block()` makes this a synchronous call from inside an MVC controller. In a fully reactive application (`spring-boot-starter-webflux` end-to-end) you'd return the `Flux<Account>` and let the framework handle it; here we're using WebFlux only as the HTTP client, with MVC for the controller, so blocking is appropriate.

### TODO 24 - `/downstream` endpoint

Add to `AccountController`:

```java
private final DownstreamAccountService downstreamAccountService;

// Update the constructor to inject both services:
public AccountController(AuditService auditService,
                         DownstreamAccountService downstreamAccountService) {
    this.auditService = auditService;
    this.downstreamAccountService = downstreamAccountService;
}

@GetMapping("/downstream")
public List<Account> getFromDownstream() {
    return downstreamAccountService.fetchAllFromDownstream();
}
```

Watch the Authorization Server console when you call this endpoint. The first call produces a `POST /oauth2/token` from `bank-service` (acquiring the service token), followed by the `GET /api/v1/accounts` to the downstream URL. Subsequent calls within the token's lifetime skip the token request - `OAuth2AuthorizedClientManager` caches it and only renews on expiry.

---

## Notes on Common Pitfalls

**`hasRole('TELLER')` vs `hasAuthority('ROLE_TELLER')`** - They mean the same thing. `hasRole('X')` is sugar for `hasAuthority('ROLE_X')`. The `ROLE_` prefix is a Spring Security convention; the role string in the JWT's `roles` claim is unprefixed (`teller`), and the prefix is added when the role is converted into a `GrantedAuthority`.

**`hasAuthority('SCOPE_account.read')`** - Note the underscore in `SCOPE_` and the literal dot in `account.read`. The dot is part of the scope name, not a SpEL operator. If you write `hasAuthority('SCOPE_accountread')` it silently fails because that's not a real authority.

**`authentication.name` vs `authentication.principal.subject`** - Both give you `sub` for a JWT-authenticated request, because `JwtAuthenticationToken.getName()` delegates to the JWT's subject. Use `authentication.name` in SpEL for brevity.

**`@PostAuthorize` doesn't prevent side effects** - The method runs first, then the check. If the method modifies state (e.g., increments a counter, sends an email), the modification persists even if the caller is denied. Use `@PreAuthorize` for any method with side effects.

**The `@accountOwnership` SpEL reference is case-sensitive** - `@AccountOwnership` (with a capital A) does not resolve. Spring beans are by default registered with a lowercased first letter; we explicitly set `@Component("accountOwnership")` to make this unambiguous.

---

*End of Lab 2-2 Reference Solutions*
