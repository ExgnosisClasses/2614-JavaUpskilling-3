# Lab 2-3: Reference Solutions

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 4 - Secure External API Consumption

This file contains completed code for every `TODO` in Lab 2-3, organized by exercise and TODO number. Each entry shows the completed code and a short note on why it works the way it does.

**How to use this file:**
- Work through the lab first. Reach for solutions only after a genuine attempt.
- The completed code shown here is one correct answer; alternatives exist for several TODOs and are noted where relevant.
- Copy with understanding, not by rote. Every HTTP client bug in production starts as a line that "looked right."

---

## Exercise 1 - RestTemplate

### TODO 1 - `RestTemplateConfig` bean

Replace the body of `restTemplate(...)`:

```java
@Bean
public RestTemplate restTemplate(RestTemplateBuilder builder) {
    return builder
            .rootUri("http://localhost:8081")
            .connectTimeout(Duration.ofSeconds(3))
            .readTimeout(Duration.ofSeconds(5))
            .build();
}
```

`rootUri` lets every call site supply only the path segment, not the full URL. The two timeouts cover the two phases of an HTTP call: `connectTimeout` is how long to wait for the TCP connection to establish; `readTimeout` is how long to wait for response data once connected. A hung upstream that accepts the connection but never responds is the case `readTimeout` exists to catch.

### TODO 2 - `fetchAll()` with `getForObject`

```java
public List<Account> fetchAll() {
    Account[] response = restTemplate.getForObject("/api/accounts", Account[].class);
    return response != null ? Arrays.asList(response) : List.of();
}
```

`getForObject` returns the body directly with the type erased to whatever you ask for. `Account[].class` works because arrays carry their component type at runtime (unlike generic types). The null guard handles the corner case where the upstream returns an empty body with 200.

### TODO 3 - `fetchById()` with `getForEntity`

```java
public Account fetchById(String id) {
    ResponseEntity<Account> response =
            restTemplate.getForEntity("/api/accounts/{id}", Account.class, id);
    return response.getStatusCode().is2xxSuccessful() ? response.getBody() : null;
}
```

`getForEntity` returns the full HTTP response. The `is2xxSuccessful()` check is technically belt-and-suspenders for `RestTemplate`'s default behavior (it throws on 4xx/5xx so we'd never reach this code path), but it documents intent and survives any future change to the error handler.

The `{id}` placeholder is automatically percent-encoded by `RestTemplate`. Passing the path as a string with `id` concatenated would skip that encoding and expose path-traversal risk.

### TODO 4 - `fetchAllWithExchange()` with `ParameterizedTypeReference`

```java
public List<Account> fetchAllWithExchange() {
    var typeRef = new ParameterizedTypeReference<List<Account>>() {};
    ResponseEntity<List<Account>> response = restTemplate.exchange(
            "/api/accounts", HttpMethod.GET, HttpEntity.EMPTY, typeRef);
    return response.getBody();
}
```

The `new ParameterizedTypeReference<List<Account>>() {}` is the magic. The trailing `{}` creates an anonymous subclass; Java's type system retains that subclass's generic type information even though `List<Account>` itself is erased. This is the standard idiom for telling Spring "deserialize into this exact generic shape."

`HttpEntity.EMPTY` is used because GET requests don't carry a body. For POST/PUT, you'd pass `new HttpEntity<>(body)` or `new HttpEntity<>(body, headers)`.

### TODO 5 - `createAccount()` with `postForEntity`

```java
public String createAccount(Account account) {
    ResponseEntity<Account> response =
            restTemplate.postForEntity("/api/accounts", account, Account.class);
    var location = response.getHeaders().getLocation();
    return location != null ? location.toString() : null;
}
```

`postForEntity` accepts the request body as a plain object; the underlying message converters (Jackson by default) serialize it to JSON. The `Location` header is the standard way an upstream tells you the URL of the newly created resource.

### TODO 6 - `LoggingInterceptor.intercept()`

```java
@Override
public ClientHttpResponse intercept(
        HttpRequest request,
        byte[] body,
        ClientHttpRequestExecution execution) throws IOException {

    log.info(">>> {} {}", request.getMethod(), request.getURI());
    ClientHttpResponse response = execution.execute(request, body);
    log.info("<<< {}", response.getStatusCode());
    return response;
}
```

The interceptor sees the request before it goes out and the response after it comes back. The `execution.execute(...)` call is the boundary between "before" and "after." This is the correct place for any cross-cutting concern: logging, correlation IDs, authentication headers, request metrics.

### TODO 7 - Register the interceptor

Update `RestTemplateConfig`:

```java
@Bean
public RestTemplate restTemplate(RestTemplateBuilder builder) {
    return builder
            .rootUri("http://localhost:8081")
            .connectTimeout(Duration.ofSeconds(3))
            .readTimeout(Duration.ofSeconds(5))
            .additionalInterceptors(new LoggingInterceptor())
            .build();
}
```

`additionalInterceptors` appends to whatever interceptors the builder already has (currently none, but future Spring Boot defaults may add some). Use this method rather than `interceptors(...)` which would replace the entire list.

---

## Exercise 2 - WebClient

### TODO 8 - `accountWebClient` bean

```java
@Bean
@Primary
public WebClient accountWebClient() {
    HttpClient httpClient = HttpClient.create()
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 3000)
            .responseTimeout(Duration.ofSeconds(5))
            .doOnConnected(conn ->
                    conn.addHandlerLast(new ReadTimeoutHandler(5, TimeUnit.SECONDS)));

    return WebClient.builder()
            .baseUrl("http://localhost:8081")
            .clientConnector(new ReactorClientHttpConnector(httpClient))
            .build();
}
```

Three different "timeouts" appear here because they catch different failures:

- `CONNECT_TIMEOUT_MILLIS` - how long to wait for the TCP handshake.
- `responseTimeout` - how long the HTTP response status line takes to arrive after the request is sent.
- `ReadTimeoutHandler` - how long the connection can sit idle between bytes of the response body.

A real upstream can fail any of these ways and the symptoms look different. In Exercise 3 you'll see a fourth, reactive-level timeout layered on top.

### TODO 9 - `fetchAll()` with WebClient

```java
public List<Account> fetchAll() {
    return accountWebClient.get()
            .uri("/api/accounts")
            .retrieve()
            .bodyToFlux(Account.class)
            .collectList()
            .block();
}
```

The fluent chain reads roughly as you'd say it: "GET /api/accounts, retrieve the response, decode the body as a flux of Account, collect into a list, block until done." Each operator returns a new pipeline node; nothing executes until `block()`.

### TODO 10 - `fetchById()` with URI template

```java
public Account fetchById(String id) {
    return accountWebClient.get()
            .uri("/api/accounts/{id}", id)
            .retrieve()
            .bodyToMono(Account.class)
            .block();
}
```

`.uri("/api/accounts/{id}", id)` is the safe form. WebClient percent-encodes the `id` value, so a malicious caller passing `../admin` would not escape the intended path. Concatenating the value into the path string with `+` would skip that protection.

### TODO 11 - `createAccount()` with WebClient

```java
public String createAccount(Account account) {
    ResponseEntity<Void> response = accountWebClient.post()
            .uri("/api/accounts")
            .bodyValue(account)
            .retrieve()
            .toBodilessEntity()
            .block();
    return response != null && response.getHeaders().getLocation() != null
            ? response.getHeaders().getLocation().toString()
            : null;
}
```

`toBodilessEntity()` is the right choice when you don't need the response body but you do need the headers (status, Location, anything else). The alternative `toEntity(Account.class)` would deserialize the body too; `bodyToMono(...)` would deserialize the body and discard the headers entirely.

### TODO 12 - `fetchById()` with 404 mapping

```java
public Account fetchById(String id) {
    return accountWebClient.get()
            .uri("/api/accounts/{id}", id)
            .retrieve()
            .onStatus(
                    status -> status.value() == 404,
                    response -> Mono.error(new AccountNotFoundException(id)))
            .bodyToMono(Account.class)
            .block();
}
```

Don't forget the new import: `import reactor.core.publisher.Mono;`

`onStatus` is the right place for HTTP-to-domain translation. It runs before `bodyToMono` would try to deserialize, so you don't pay the cost of parsing an error response body just to throw it away. The predicate `status -> status.value() == 404` is more explicit than `status -> status.is4xxClientError()`, which would also catch 400, 401, 403, etc. - probably not what you want here.

### TODO 13 - Exception handler in controller

Already shown inline in the lab. For reference:

```java
@ExceptionHandler(AccountNotFoundException.class)
public ResponseEntity<String> handleNotFound(AccountNotFoundException ex) {
    return ResponseEntity.notFound().build();
}
```

`ResponseEntity.notFound().build()` produces a clean 404 with no body, which is what most clients expect for a missing resource.

### TODO 14 - Reactive timeout

```java
public List<Account> fetchAll() {
    return accountWebClient.get()
            .uri("/api/accounts")
            .retrieve()
            .bodyToFlux(Account.class)
            .collectList()
            .timeout(Duration.ofSeconds(2))
            .block();
}
```

This timeout layers on top of the HTTP engine timeouts from TODO 8. The HTTP engine timeouts catch low-level network failures; this reactive timeout enforces an end-to-end business deadline. In a banking client, the business reasoning might be "the user is waiting on a UI - if we can't get an answer in 2 seconds, show a fallback rather than hang."

---

## Exercise 3 - Resilience Patterns

### TODO 15 - Annotations on `fetchAll()`

```java
@Retry(name = "upstream-api")
@CircuitBreaker(name = "upstream-api", fallbackMethod = "fetchAllFallback")
public List<Account> fetchAll() {
    log.info("Calling upstream /api/flaky");
    return accountWebClient.get()
            .uri("/api/flaky")
            .retrieve()
            .bodyToFlux(Account.class)
            .collectList()
            .block();
}
```

The order in which Resilience4j applies these annotations (when both are on the same method) is **outer-to-inner: CircuitBreaker -> Retry -> method body**. The circuit breaker checks first; if open, it short-circuits without involving retry. If closed, retry orchestrates multiple attempts. If retry exhausts, the final exception reaches the circuit breaker which counts it.

The `fallbackMethod` name must match a method in the same class with a compatible signature (same return type, parameters of the original method plus a Throwable as the last parameter). A typo here produces a runtime error, not a compile error - test the fallback path explicitly.

### TODO 16 - Fallback method

```java
public List<Account> fetchAllFallback(Throwable ex) {
    log.warn("Fallback invoked: {}", ex.getMessage());
    return List.of();
}
```

The fallback must have the same return type as the original method. The trailing `Throwable` parameter lets you inspect what went wrong without coupling to a specific exception type. Logging here is essential; otherwise the only sign that the fallback fired is that data is missing.

`List.of()` is the simplest degraded response. For a real banking UI, an empty list could be misleading ("the user has no accounts" reads very differently from "we couldn't talk to the account service"). Final Reflection Question 2 asks you to think about better strategies.

---

## Exercise 4 - Bearer Token Filter

### TODO 17 - Token property injection

Already shown in the lab. For reference:

```java
public StaticTokenProvider(@Value("${upstream.api.token}") String token) {
    this.token = token;
}
```

`@Value("${upstream.api.token}")` reads from `application.yml` at bean construction time. If the property is missing, Spring throws an exception at startup - fail-fast for configuration is the right default. To provide a default value: `@Value("${upstream.api.token:default-value}")`.

### TODO 18 - `BearerTokenFilter.filter()` body

```java
public ExchangeFilterFunction filter() {
    return ExchangeFilterFunction.ofRequestProcessor(request -> {
        String token = tokenProvider.getToken();
        log.debug("Attaching token: {}...", token.substring(0, Math.min(8, token.length())));
        ClientRequest authorizedRequest = ClientRequest.from(request)
                .header("Authorization", "Bearer " + token)
                .build();
        return Mono.just(authorizedRequest);
    });
}
```

The `Math.min(8, token.length())` guards against tokens shorter than 8 characters (which would throw an `IndexOutOfBoundsException` on the static token from the exercise's config because it's longer than 8, but defensive code is cheap).

`ClientRequest.from(request)` creates a builder pre-populated with the original request's data. Adding a header builds a new immutable `ClientRequest`. The original is unchanged, which is what you want in a reactive pipeline where any object you receive might be replayed or shared.

### TODO 19 - `authenticatedWebClient` with the filter applied

```java
@Bean
public WebClient authenticatedWebClient(StaticTokenProvider tokenProvider) {
    var bearerTokenFilter = new BearerTokenFilter(tokenProvider);
    return WebClient.builder()
            .baseUrl("http://localhost:8081")
            .filter(bearerTokenFilter.filter())
            .build();
}
```

For consistency with `accountWebClient`, you could also apply the same HTTP engine timeouts. Many production codebases factor the common configuration into a private method that returns a `WebClient.Builder`, and each public `@Bean` adds only the bean-specific concerns (filters, base URL).

### TODO 20 - `AuthenticatedAccountService.ping()`

```java
public String ping() {
    return authenticatedWebClient.get()
            .uri("/api/auth-required")
            .retrieve()
            .bodyToMono(String.class)
            .block();
}
```

Standard WebClient call. Notice that nothing in this method mentions tokens or authentication - the filter handles that invisibly. That is the entire point of putting token attachment in a filter: business-facing code stays clean.

---

## Notes on Common Pitfalls

**RestTemplate is in maintenance mode**, but it is not deprecated. It still receives critical bug fixes. New features go into `WebClient`. Choose `RestTemplate` when the project is already using it heavily, or when you have a hard requirement on the synchronous behavior (some legacy interceptors or test infrastructure don't play well with reactive pipelines).

**`block()` is acceptable in Spring MVC.** A common piece of folklore is "never call `.block()`." That rule applies to fully reactive applications running on WebFlux, where blocking a single thread can starve the entire event loop. In Spring MVC, every request runs on its own thread anyway, and `.block()` is the documented bridge from reactive to imperative code.

**`onStatus(predicate, function)`** runs before `bodyToMono(...)`. If you put your error handling after `bodyToMono`, the deserialization either succeeds (filling a `Mono<Account>` with garbage from the error response body) or fails with a confusing decoding exception. Always map status codes before decoding the body.

**`retry-exceptions`** in Resilience4j is a whitelist, not a blacklist. If you forget to list an exception type, it will not trigger a retry. For an outbound HTTP client, you almost always want to retry `WebClientResponseException.ServiceUnavailable` (503), `WebClientResponseException.GatewayTimeout` (504), `TimeoutException`, and `IOException`. You almost never want to retry 4xx exceptions - they indicate a problem with the request itself that the upstream cannot resolve by retry.

**The fallback method's signature** must match the original method's parameters plus a Throwable as the last parameter. `fetchAll()` takes no parameters, so the fallback is `fetchAllFallback(Throwable ex)`. If the original method took an `accountId`, the fallback would be `fetchByIdFallback(String accountId, Throwable ex)`. Resilience4j matches by parameter order, not by name.

**Never log full bearer tokens.** This is not a style preference. A token in a log file is a credential leak. An attacker with log access (which often has weaker controls than database access) gets the same permissions as the service. First-8-characters logging is enough to identify which token is in use without exposing the credential.

---

*End of Lab 2-3 Reference Solutions*
