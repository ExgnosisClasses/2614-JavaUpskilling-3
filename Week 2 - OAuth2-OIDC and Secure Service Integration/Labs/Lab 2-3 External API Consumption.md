# Lab 2-3: Secure External API Consumption
## Hands-On Exercises

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 4 - Secure External API Consumption
> **Estimated time per exercise:** 30-60 minutes

---

## How to Use These Exercises

Each exercise is self-contained and builds directly on the concepts introduced in the module lectures. They are designed to be completed in IntelliJ IDEA using a Spring Boot project generated from Spring Initializr.

- **Context:** why this concept matters and what problem it solves
- **Setup:** how to structure the project and files before you start
- **Tasks:** step-by-step work to complete, including starter code with `TODO` markers
- **Checkpoints:** questions that test conceptual understanding, not just code completion


> **Tip:** Work through the exercises in order. Each one builds on the project structure established in the first. If you get stuck on a `TODO`, re-read the relevant section of the lecture slides before looking at the solution file.

> **Relationship to Lab 2-2:** This lab is a self-contained project that will eventually be merged into the `bankapi` application from Lab 2-2 to act as a backend-for-frontend (BFF) for the React client. For now, it stands alone and uses a WireMock stub server in place of any real upstream service. The banking domain (accounts, customers, transactions) carries forward so the code you write here will be recognizable when you do integrate it later.

---

## Before You Start: The Upstream Stub

These exercises call a local stub API that simulates an upstream banking service. The stub server runs inside the same Spring Boot application you are building, so there is nothing external to install or start.

The stub is powered by **WireMock**, a widely used HTTP mocking library. It starts on port `8081` automatically when you run the application and registers all the stub responses your exercises need. You do not need to configure anything separately, just start the application and the stubs are ready.

To verify the stub server is running after you complete the setup below, open this URL in your browser:

```
http://localhost:8081/__admin/mappings
```

You should see a JSON list of registered stubs. If you see a connection error, check that the application started without errors before proceeding.

**Stub API reference:**

| Stub URL | Method | Behaviour |
|---|---|---|
| `http://localhost:8081/api/accounts` | GET | Returns a list of three accounts |
| `http://localhost:8081/api/accounts/A001` | GET | Returns a single account |
| `http://localhost:8081/api/accounts/A999` | GET | Returns 404 |
| `http://localhost:8081/api/accounts` | POST | Returns 201 Created with Location header |
| `http://localhost:8081/api/customers/C001` | GET | Returns customer C001 |
| `http://localhost:8081/api/slow` | GET | Delays 5 seconds then responds |
| `http://localhost:8081/api/flaky` | GET | Returns 503 (Exercise 3 changes this to 200) |
| `http://localhost:8081/api/auth-required` | GET | Returns 200 only when Authorization header contains "Bearer" |
| `http://localhost:8081/external/credit-score/C001` | GET | Simulates an external credit bureau (variable latency) |

The first set of endpoints mirror what `bankapi` exposes in Lab 2-2 - this is deliberate, so the code you write here will be recognizable when these labs are eventually merged. The `external/credit-score/{customerId}` endpoint simulates an external partner API (a credit bureau), which is the kind of integration this lab is preparing you for.

---

## How the Pieces Fit Together

Before you start coding, it is worth understanding the architecture you are about to build. This lab produces a single Spring Boot application that runs **two HTTP servers on two ports** with **three categories of endpoints** with very different roles. Students who skip this section end up confused about what is calling what.

### Two servers in one application

When you run the project, two HTTP servers start up in the same JVM:

- **Spring Boot's embedded Tomcat on port `8080`** runs your controllers (everything under `/rt`, `/wc`, `/resilient`, `/auth`, `/stubs`). This is the application you are building.
- **WireMock on port `8081`** acts as the upstream that your application calls (`/api/accounts`, `/api/customers`, `/external/credit-score`, `/api/flaky`, etc.). It exists only because this lab is standalone; in a real deployment, port 8081 would be a separate banking service somewhere else on the network.

You will call `http://localhost:8080/...` from your `.http` files. Your controllers running on 8080 will then make their own HTTP calls to `http://localhost:8081/...` to get the data they need.

### Three categories of endpoints

The endpoints you will build (and the WireMock stubs that back them) fall into three categories. Each plays a different role.

| Prefix | Port | Who runs it | Role |
|---|---|---|---|
| `/api/...` | 8081 | WireMock stub | **The upstream you are calling.** Simulates a banking service. You do not write this code, WireMock serves it. |
| `/rt/...` | 8080 | Your application | **RestTemplate client.** Exercise 1. Demonstrates the classic synchronous client. |
| `/wc/...` | 8080 | Your application | **WebClient client.** Exercise 2. Demonstrates the fluent reactive client. The production target. |

There are two additional prefixes that join the picture later:

| Prefix | Port | Who runs it | Role |
|---|---|---|---|
| `/resilient/...` | 8080 | Your application | **WebClient + Resilience4j.** Exercise 3. Same client as `/wc`, with retry and circuit breaker layered on. |
| `/auth/...` | 8080 | Your application | **WebClient + bearer-token filter.** Exercise 4. Same client as `/wc`, with authentication added. |
| `/stubs/...` | 8080 | Your application | **Stub management.** Exercise 3. Changes WireMock's behavior at runtime to simulate upstreams going up and down. |

### What a single request flow actually looks like

When you call `GET http://localhost:8080/wc/accounts/A001` from your `.http` file, this is what happens:

1. The request hits your `AccountWebClientController` on port 8080.
2. The controller calls `service.fetchById("A001")` in `AccountWebClientService`.
3. The service uses `WebClient` to make an HTTP call to `http://localhost:8081/api/accounts/A001`.
4. WireMock on port 8081 matches the URL against its registered stubs and returns the pre-configured JSON.
5. The JSON flows back through the service, gets deserialized into an `Account`, returned to the controller, and serialized back out as the HTTP response on port 8080.

Two HTTP requests happened: one from your IntelliJ HTTP client to port 8080, and one from your application to port 8081. The second one is the only one that matters for these exercises - the upstream call. The first one is just how you trigger it.

### Why the parallel /rt and /wc URLs

`GET /rt/accounts/A001` and `GET /wc/accounts/A001` both make the same upstream call to `GET /api/accounts/A001` and return the same JSON. The only difference is which HTTP client did the work between your controller and WireMock. That deliberate parallelism is the comparison this lab is built around. Once you have both endpoints working, opening `AccountRestTemplateService` and `AccountWebClientService` side-by-side is the exercise: same task, two clients, see how they differ.

### Where /resilient and /auth fit

`/resilient` and `/auth` both use WebClient too. They demonstrate that WebClient is a foundation other concerns layer on top of:

- `/resilient/accounts` uses the same WebClient but adds retry and circuit-breaker decoration via Resilience4j annotations.
- `/auth/ping` uses a second WebClient bean that has a bearer-token filter wired into it.

Neither of these has a RestTemplate equivalent in this lab, because the production target is WebClient and the resilience/auth patterns are where its real advantages over RestTemplate show up.

### Looking ahead: when this becomes a BFF

When this code is eventually merged into the `bankapi` application from Lab 2-2 as a backend-for-frontend (BFF) for the React banking UI, the picture changes in one important way: WireMock disappears (port 8081 becomes a real backend banking service), and the `/wc` and `/auth` endpoints become the BFF endpoints the React app calls. The structure of the code stays the same; only the upstream changes from a stub to a real service.

---

## Starter Project

All exercises share a single Spring Boot project. Follow these steps exactly, there are a few specific choices you need to make to ensure the project is configured correctly.

### Create the project with Spring Initializr

1. Open [https://start.spring.io](https://start.spring.io) in a browser

2. Configure the left-hand panel as follows:

| Setting | Value |
|---|---|
| Project | Maven |
| Language | Java |
| Spring Boot | **3.4.5** (see note below) |
| Group | `com.example` |
| Artifact | `bankclient` |
| Name | `bankclient` |
| Packaging | Jar |
| Java | 17 |

   > **Spring Boot version:** Spring Initializr defaults to the latest available version, which may be 4.x. These exercises require **3.4.5**. Click the Spring Boot version dropdown and select `3.4.5`. If 3.4.5 is not listed, select the highest available `3.x` version. Do not use a 4.x version, it is not yet compatible with the dependencies used in these exercises.

3. Click **ADD DEPENDENCIES** and add the following. Search for each by name:

   - **Spring Web** provides `RestTemplate`, `RestTemplateBuilder`, and the Spring MVC controller layer
   - **Spring Reactive Web** provides `WebClient`, `Mono`, and `Flux`
   - **Spring Boot DevTools**
   - **Validation**

   > **Both Spring Web and Spring Reactive Web are required.** They serve different purposes and are not alternatives to each other. After adding dependencies, confirm that both appear in the dependency list on the right side of the Initializr page before generating.

4. Click **GENERATE**, unzip the downloaded file, and open the project in IntelliJ using **File -> Open -> New Window**

5. Wait for Maven to finish downloading dependencies. Watch the progress bar at the bottom of IntelliJ and confirm there are no red error lines in the Maven tool window before continuing.

### Verify and fix pom.xml

Before writing any code, open `pom.xml` and replace its entire contents with the following. This ensures the correct Spring Boot version and dependency artifact IDs are in place, regardless of what Initializr generated.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>
	<parent>
		<groupId>org.springframework.boot</groupId>
		<artifactId>spring-boot-starter-parent</artifactId>
		<version>3.4.5</version>
		<relativePath/>
	</parent>
	<groupId>com.example</groupId>
	<artifactId>bankclient</artifactId>
	<version>0.0.1-SNAPSHOT</version>

	<properties>
		<java.version>17</java.version>
	</properties>

	<dependencies>
		<!-- Spring MVC: RestTemplateBuilder, @RestController, embedded Tomcat -->
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-web</artifactId>
		</dependency>

		<!-- WebFlux: WebClient, Mono, Flux -->
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-webflux</artifactId>
		</dependency>

		<!-- Bean validation (@Valid, @NotNull, etc.) -->
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-validation</artifactId>
		</dependency>

		<!-- Hot reload during development -->
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-devtools</artifactId>
			<scope>runtime</scope>
			<optional>true</optional>
		</dependency>

		<!-- Embedded stub server for exercises -->
		<dependency>
			<groupId>org.wiremock</groupId>
			<artifactId>wiremock-standalone</artifactId>
			<version>3.6.0</version>
		</dependency>

		<!-- Standard Spring Boot test support (JUnit 5, MockMvc, WebTestClient) -->
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-test</artifactId>
			<scope>test</scope>
		</dependency>
	</dependencies>

	<build>
		<plugins>
			<plugin>
				<groupId>org.springframework.boot</groupId>
				<artifactId>spring-boot-maven-plugin</artifactId>
			</plugin>
		</plugins>
	</build>

</project>
```

After saving, reload Maven using the popup prompt that appears in IntelliJ, or by clicking the reload icon in the Maven tool window. Wait for the download to complete before continuing.

### Package structure to create before Exercise 1

Right-click `src/main/java/com/example/bankclient` and create the following sub-packages:

```
com.example.bankclient
├── config
├── controller
├── exception
├── model
└── service
```

### Shared model classes

Create three records in the `model` package. All exercises share these.

`Account.java`:

```java
package com.example.bankclient.model;

import java.math.BigDecimal;

public record Account(
        String id,
        String customerId,
        String accountType,
        BigDecimal balance
) {}
```

`Customer.java`:

```java
package com.example.bankclient.model;

public record Customer(
        String id,
        String fullName,
        String email
) {}
```

`CreditScore.java`:

```java
package com.example.bankclient.model;

public record CreditScore(
        String customerId,
        int score,
        String rating
) {}
```

These mirror the shape of the corresponding records in the `bankapi` application from Lab 2-2, which makes the eventual merge straightforward. The `CreditScore` record represents data from the external credit bureau partner.

### Embedded stub server setup

Create `StubServerConfig.java` in the `config` package. This class starts a WireMock server on port `8081` when the Spring application starts and registers all the stubs used across every exercise. Read through every stub registration, each one corresponds directly to a behaviour in the upstream API reference table above.

```java
package com.example.bankclient.config;

import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.client.WireMock;
import com.github.tomakehurst.wiremock.core.WireMockConfiguration;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.ContextRefreshedEvent;
import org.springframework.context.event.EventListener;

import static com.github.tomakehurst.wiremock.client.WireMock.*;

@Configuration
public class StubServerConfig {

    private static final Logger log = LoggerFactory.getLogger(StubServerConfig.class);
    private static final int STUB_PORT = 8081;

    private WireMockServer wireMockServer;

    @EventListener(ContextRefreshedEvent.class)
    public void start() {
        if (wireMockServer != null && wireMockServer.isRunning()) {
            return;
        }

        wireMockServer = new WireMockServer(
                WireMockConfiguration.wireMockConfig().port(STUB_PORT)
        );
        wireMockServer.start();

        // Point the WireMock static DSL at our server instance
        WireMock.configureFor("localhost", STUB_PORT);

        registerStubs();
        log.info("Stub server started on port {}. Admin UI: http://localhost:{}/__admin/mappings",
                STUB_PORT, STUB_PORT);
    }

    @PreDestroy
    public void stop() {
        if (wireMockServer != null && wireMockServer.isRunning()) {
            wireMockServer.stop();
            log.info("Stub server stopped.");
        }
    }

    // Exposed so StubManagementController can update stubs at runtime
    public WireMockServer getServer() {
        return wireMockServer;
    }

    private void registerStubs() {

        // --- Account list ---
        stubFor(get(urlEqualTo("/api/accounts"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("[" +
                                "{\"id\":\"A001\",\"customerId\":\"C001\",\"accountType\":\"CHECKING\",\"balance\":1250.00}," +
                                "{\"id\":\"A002\",\"customerId\":\"C001\",\"accountType\":\"SAVINGS\",\"balance\":8400.00}," +
                                "{\"id\":\"A003\",\"customerId\":\"C002\",\"accountType\":\"CHECKING\",\"balance\":300.50}" +
                                "]")));

        // --- Single account ---
        stubFor(get(urlEqualTo("/api/accounts/A001"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"id\":\"A001\",\"customerId\":\"C001\",\"accountType\":\"CHECKING\",\"balance\":1250.00}")));

        // --- Missing account (404) ---
        stubFor(get(urlEqualTo("/api/accounts/A999"))
                .willReturn(aResponse()
                        .withStatus(404)
                        .withBody("Not found")));

        // --- Create account (201 with Location header) ---
        stubFor(post(urlEqualTo("/api/accounts"))
                .willReturn(aResponse()
                        .withStatus(201)
                        .withHeader("Content-Type", "application/json")
                        .withHeader("Location", "http://localhost:8081/api/accounts/A004")
                        .withBody("{\"id\":\"A004\",\"customerId\":\"C003\",\"accountType\":\"SAVINGS\",\"balance\":0.00}")));

        // --- Single customer ---
        stubFor(get(urlEqualTo("/api/customers/C001"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"id\":\"C001\",\"fullName\":\"Alice Nguyen\",\"email\":\"alice@example.com\"}")));

        // --- External credit bureau partner endpoint ---
        // Realistic third-party API: different domain prefix, slightly different shape.
        stubFor(get(urlEqualTo("/external/credit-score/C001"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withFixedDelay(800)  // External partners are slower than your own services
                        .withBody("{\"customerId\":\"C001\",\"score\":742,\"rating\":\"GOOD\"}")));

        // --- Slow response (used to demonstrate timeout behaviour in Exercise 2) ---
        stubFor(get(urlEqualTo("/api/slow"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withFixedDelay(5000)
                        .withBody("finally!")));

        // --- Flaky endpoint (starts as 503; Exercise 3 updates it to 200 at runtime) ---
        stubFor(get(urlEqualTo("/api/flaky"))
                .willReturn(aResponse()
                        .withStatus(503)
                        .withBody("Service Unavailable")));

        // --- Auth-required: 401 when Authorization header is missing or wrong ---
        // WireMock matches stubs in reverse registration order (last registered wins).
        // The catch-all 401 stub must be registered FIRST so that the more specific
        // Bearer stub registered below takes priority when the header is present.
        stubFor(get(urlEqualTo("/api/auth-required"))
                .willReturn(aResponse()
                        .withStatus(401)
                        .withBody("Unauthorized")));

        // --- Auth-required: 200 when Authorization header contains "Bearer" ---
        // Registered AFTER the catch-all so WireMock evaluates this one first.
        stubFor(get(urlEqualTo("/api/auth-required"))
                .withHeader("Authorization", containing("Bearer"))
                .willReturn(aResponse()
                        .withStatus(200)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"message\":\"Authenticated successfully\"}")));
    }
}
```

> **What is WireMock?** WireMock is an HTTP server that returns pre-configured responses rather than processing real business logic. It is the standard tool for testing HTTP client code without depending on real external services.

> **WireMock stub matching order:** WireMock evaluates stubs in reverse registration order, the last registered stub is checked first. For the `/api/auth-required` stubs, the catch-all 401 is registered first and the more specific Bearer stub is registered second, so the Bearer stub takes priority when the Authorization header is present.

Start the application now. You should see this line near the end of the startup log:

```
Stub server started on port 8081. Admin UI: http://localhost:8081/__admin/mappings
```

Open that URL in your browser to confirm all stubs are registered before proceeding to Exercise 1.

---

## Exercise 1 - RestTemplate: Synchronous HTTP Calls

**Estimated time:** 30-40 minutes
**Topics covered:** RestTemplate, `getForObject`, `getForEntity`, `exchange`, `ParameterizedTypeReference`, interceptors, error handling

### Context

`RestTemplate` is the original Spring HTTP client and remains common in enterprise codebases. Even if you write new code using `WebClient`, you will encounter `RestTemplate` when maintaining or migrating existing applications. This exercise builds the muscle memory for reading and writing idiomatic `RestTemplate` code.

The lecture introduced a key distinction: `getForObject` returns the body directly and throws on any non-2xx response, while `getForEntity` returns the full HTTP response including status and headers. In production, `getForEntity` is usually the better choice because HTTP status codes carry meaning that your calling code often needs to inspect.

`RestTemplate` follows the same template-method pattern used elsewhere in Spring, such as `JdbcTemplate`: it manages the repetitive lifecycle work of an HTTP connection while you supply only the parts that vary, the URL, method, and expected response type.

### Task 1.1 - Create and configure a RestTemplate bean

Create `RestTemplateConfig.java` in the `config` package:

```java
package com.example.bankclient.config;

import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

@Configuration
public class RestTemplateConfig {

    // TODO 1: Use the RestTemplateBuilder to create a RestTemplate bean.
    // Set the root URI to "http://localhost:8081".
    // Set a connection timeout of 3 seconds.
    // Set a read timeout of 5 seconds.
    // Hint: builder.rootUri(...).connectTimeout(...).readTimeout(...)
    @Bean
    public RestTemplate restTemplate(RestTemplateBuilder builder) {
        return builder.build(); // Replace with your implementation
    }
}
```

> **Note:** In Spring Boot 3.4, the timeout methods on `RestTemplateBuilder` were renamed. Use `connectTimeout(Duration)` and `readTimeout(Duration)` rather than the older `setConnectTimeout` and `setReadTimeout` forms, which are deprecated and will produce compiler warnings.

**Why `rootUri` matters:** Setting the root URI on the builder means every call site only needs to supply the path segment (for example, `/api/accounts`), not the full URL. This eliminates duplication and makes the base URL easy to change in one place.

### Task 1.2 - Fetch accounts using RestTemplate

Create `AccountRestTemplateService.java` in the `service` package:

```java
package com.example.bankclient.service;

import com.example.bankclient.model.Account;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.Arrays;
import java.util.List;

@Service
public class AccountRestTemplateService {

    private final RestTemplate restTemplate;

    public AccountRestTemplateService(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    // TODO 2: Implement fetchAll() using getForObject.
    // The upstream URL is "/api/accounts".
    // The return type must be Account[].class (arrays are safe for getForObject).
    // Convert the array to a List before returning.
    // Hint: Arrays.asList(restTemplate.getForObject(...))
    public List<Account> fetchAll() {
        return List.of(); // Replace with your implementation
    }

    // TODO 3: Implement fetchById() using getForEntity.
    // The upstream URL uses a URI variable: "/api/accounts/{id}".
    // Return the body from the ResponseEntity.
    // Inspect the status code: if it is not 2xx, return null.
    // Hint: restTemplate.getForEntity("/api/accounts/{id}", Account.class, id)
    public Account fetchById(String id) {
        return null; // Replace with your implementation
    }

    // TODO 4: Implement fetchAllWithExchange() using exchange.
    // This method does the same job as fetchAll() but uses ParameterizedTypeReference
    // so the response is deserialized directly into List<Account> rather than Account[].
    // Hint:
    //   var typeRef = new ParameterizedTypeReference<List<Account>>() {};
    //   ResponseEntity<List<Account>> response = restTemplate.exchange(
    //       "/api/accounts", HttpMethod.GET, HttpEntity.EMPTY, typeRef);
    //   return response.getBody();
    public List<Account> fetchAllWithExchange() {
        return List.of(); // Replace with your implementation
    }

    // TODO 5: Implement createAccount() using postForEntity.
    // POST to "/api/accounts" with the account object as the request body.
    // Return the Location header from the response as a String.
    // Hint: restTemplate.postForEntity("/api/accounts", account, Account.class)
    //       response.getHeaders().getLocation().toString()
    public String createAccount(Account account) {
        return null; // Replace with your implementation
    }
}
```

> **Why `ParameterizedTypeReference`?** Java erases generic type parameters at runtime due to type erasure. The expression `List<Account>.class` does not compile. `ParameterizedTypeReference<List<Account>>() {}` creates an anonymous subclass that captures the full generic type at compile time, giving `RestTemplate` enough information to deserialize a JSON array into `List<Account>`.

### Task 1.3 - Expose the service through a controller

Create `AccountRestTemplateController.java` in the `controller` package:

```java
package com.example.bankclient.controller;

import com.example.bankclient.model.Account;
import com.example.bankclient.service.AccountRestTemplateService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/rt/accounts")
public class AccountRestTemplateController {

    private final AccountRestTemplateService service;

    public AccountRestTemplateController(AccountRestTemplateService service) {
        this.service = service;
    }

    @GetMapping
    public List<Account> getAll() {
        return service.fetchAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity<Account> getById(@PathVariable String id) {
        var account = service.fetchById(id);
        return account != null ? ResponseEntity.ok(account) : ResponseEntity.notFound().build();
    }

    @GetMapping("/exchange")
    public List<Account> getAllWithExchange() {
        return service.fetchAllWithExchange();
    }

    @PostMapping
    public ResponseEntity<String> create(@RequestBody Account account) {
        var location = service.createAccount(account);
        return ResponseEntity.ok("Created at: " + location);
    }
}
```

Create `rest-template-requests.http` in the project root to test the endpoints:

```http
### Get all accounts (getForObject)
GET http://localhost:8080/rt/accounts

###

### Get account by ID (getForEntity)
GET http://localhost:8080/rt/accounts/A001

###

### Get missing account (should return 404)
GET http://localhost:8080/rt/accounts/A999

###

### Get all accounts (exchange with ParameterizedTypeReference)
GET http://localhost:8080/rt/accounts/exchange

###

### Create a new account
POST http://localhost:8080/rt/accounts
Content-Type: application/json

{
  "customerId": "C003",
  "accountType": "SAVINGS",
  "balance": 0.00
}
```

Run each request. Confirm that the list endpoints return three accounts, the single-account endpoint returns A001, the A999 request returns 404, and the POST response includes the Location URL.

### Task 1.4 - Add a logging interceptor

The lecture explained that `ClientHttpRequestInterceptor` is the correct mechanism for cross-cutting concerns on `RestTemplate`. Authentication headers, correlation IDs, and logging all belong in an interceptor rather than scattered across call sites.

Create `LoggingInterceptor.java` in the `config` package:

```java
package com.example.bankclient.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpRequest;
import org.springframework.http.client.ClientHttpRequestExecution;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.http.client.ClientHttpResponse;

import java.io.IOException;

public class LoggingInterceptor implements ClientHttpRequestInterceptor {

    private static final Logger log = LoggerFactory.getLogger(LoggingInterceptor.class);

    @Override
    public ClientHttpResponse intercept(
            HttpRequest request,
            byte[] body,
            ClientHttpRequestExecution execution) throws IOException {

        // TODO 6: Before calling execution.execute(), log the HTTP method and URI.
        // Use: log.info(">>> {} {}", request.getMethod(), request.getURI())
        // After execution.execute() returns, log the response status code.
        // Use: log.info("<<< {}", response.getStatusCode())
        // Return the response.
        // Hint: ClientHttpResponse response = execution.execute(request, body);

        return execution.execute(request, body); // Replace with your implementation
    }
}
```

Register the interceptor in `RestTemplateConfig.java`:

```java
// TODO 7: Register the LoggingInterceptor on the RestTemplate.
// Use builder.additionalInterceptors(new LoggingInterceptor()) before calling build().
```

Run the GET all accounts request again. You should see log lines in the application console:

```
>>> GET http://localhost:8081/rt/accounts
<<< 200 OK
```

> **Finding the log output:** The log lines appear in the **Run** tool window at the bottom of IntelliJ, not in the HTTP response panel. Open it with **Alt+4** (Windows/Linux) or **Cmd+4** (Mac). After running a request, scroll to the bottom of the console or use **Ctrl+F** to search for `>>>`.

### Checkpoints

1. The lecture stated that `getForObject` is a convenience method and `getForEntity` is usually the better production choice. Looking at your `fetchById` implementation, describe a case where knowing the HTTP status code changes what your method returns to the caller.
2. `RestTemplate` is in maintenance mode as of Spring 5. Given that, when would you choose to use it rather than `WebClient` in a real project?
3. The interceptor logs the full URI including the base URL. If a colleague argued that the base URL should be stripped from the log to save space, how would you do that using `request.getURI()`?

---

## Exercise 2 - WebClient: Fluent Non-Blocking HTTP

**Estimated time:** 40-50 minutes
**Topics covered:** `WebClient`, `Mono`, `Flux`, the filter chain, `retrieve()` vs `exchangeToMono()`, URI templates, per-call timeouts, domain exception mapping

### Context

`WebClient` is Spring's current HTTP client. Where `RestTemplate` is synchronous and holds a thread for the duration of every call, `WebClient` is built on reactive streams and releases the thread the moment the request is dispatched. The thread returns to the pool and is available to handle other work while the network I/O completes.

In a Spring MVC application (which this project is), you will use `.block()` to bridge from the reactive pipeline back to an imperative return value. This is perfectly valid and widely used. The benefit of `WebClient` in Spring MVC is not reactive end-to-end pipelines but rather the fluent API, the filter chain, codec control, and access to features that `RestTemplate` will never receive.

`Mono<T>` represents a single value that will arrive asynchronously, similar in concept to a `Future` or `Promise`. `Flux<T>` represents a stream of zero or more values arriving asynchronously. Neither does anything until something subscribes to it. Calling `.block()` is the subscription mechanism used in Spring MVC, it waits synchronously for the result and returns it as a plain Java object.

> **Looking ahead:** the `WebClient` patterns you build here are the same ones the BFF (backend-for-frontend) for the React banking app will use. The eventual integration will involve aggregating account, customer, and external credit-score data into a single response shaped for the React UI. That is why the WebClient version of these exercises gets more depth than the RestTemplate version: WebClient is the production target, RestTemplate is the comparison baseline.

### Task 2.1 - Create and configure a WebClient bean

Create `WebClientConfig.java` in the `config` package:

```java
package com.example.bankclient.config;

import io.netty.channel.ChannelOption;
import io.netty.handler.timeout.ReadTimeoutHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Configuration
public class WebClientConfig {

    // TODO 8: Create a WebClient bean named "accountWebClient".
    // Configure the Reactor Netty HttpClient with:
    //   - Connection timeout: 3000 milliseconds (ChannelOption.CONNECT_TIMEOUT_MILLIS)
    //   - Read timeout: 5 seconds (ReadTimeoutHandler added via doOnConnected)
    //   - Response timeout: 5 seconds (HttpClient.responseTimeout)
    // Build a WebClient using WebClient.builder()
    //   - Set the base URL to "http://localhost:8081"
    //   - Apply the ReactorClientHttpConnector wrapping your HttpClient
    //
    // Hint - HttpClient setup:
    //   HttpClient httpClient = HttpClient.create()
    //       .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 3000)
    //       .responseTimeout(Duration.ofSeconds(5))
    //       .doOnConnected(conn ->
    //           conn.addHandlerLast(new ReadTimeoutHandler(5, TimeUnit.SECONDS)));
    @Bean
    @Primary
    public WebClient accountWebClient() {
        return WebClient.builder()
                .baseUrl("http://localhost:8081")
                .build(); // Replace with your implementation
    }
}
```

> **Why configure timeouts at the HTTP engine level?** The Netty `HttpClient` timeout is a safety net at the TCP and I/O layer. It catches cases where the connection itself hangs or where the response delivery stalls at the network level. The reactive `.timeout()` you will add in Task 2.4 operates at the business logic layer and enforces end-to-end time budgets per call. Both levels are needed in production.

> **Why `@Primary`?** Exercise 4 adds a second `WebClient` bean for authenticated calls. `@Primary` tells Spring which bean to inject by default when no `@Qualifier` is specified, preventing ambiguous dependency errors.

### Task 2.2 - Fetch accounts using WebClient

Create `AccountWebClientService.java` in the `service` package:

```java
package com.example.bankclient.service;

import com.example.bankclient.model.Account;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.util.List;

@Service
public class AccountWebClientService {

    private final WebClient accountWebClient;

    public AccountWebClientService(WebClient accountWebClient) {
        this.accountWebClient = accountWebClient;
    }

    // TODO 9: Implement fetchAll() using WebClient.
    // Chain: .get().uri("/api/accounts").retrieve()
    //        .bodyToFlux(Account.class).collectList().block()
    // bodyToFlux turns the JSON array into a reactive stream of Account objects.
    // collectList() gathers all emitted items into a single Mono<List<Account>>.
    // block() subscribes and waits synchronously (acceptable in Spring MVC).
    public List<Account> fetchAll() {
        return List.of(); // Replace with your implementation
    }

    // TODO 10: Implement fetchById() using URI template variables.
    // Chain: .get().uri("/api/accounts/{id}", id).retrieve()
    //        .bodyToMono(Account.class).block()
    // URI template variables are automatically percent-encoded.
    // They are resistant to path traversal because {id} is treated as a single segment.
    public Account fetchById(String id) {
        return null; // Replace with your implementation
    }

    // TODO 11: Implement createAccount() using POST.
    // Chain: .post().uri("/api/accounts")
    //        .bodyValue(account)
    //        .retrieve()
    //        .toBodilessEntity()     <- returns Mono<ResponseEntity<Void>>
    //        .block()
    // Extract the Location header: response.getHeaders().getLocation()
    // Return the Location URI as a String.
    public String createAccount(Account account) {
        return null; // Replace with your implementation
    }
}
```

Create `AccountWebClientController.java` in the `controller` package:

```java
package com.example.bankclient.controller;

import com.example.bankclient.model.Account;
import com.example.bankclient.service.AccountWebClientService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/wc/accounts")
public class AccountWebClientController {

    private final AccountWebClientService service;

    public AccountWebClientController(AccountWebClientService service) {
        this.service = service;
    }

    @GetMapping
    public List<Account> getAll() {
        return service.fetchAll();
    }

    @GetMapping("/{id}")
    public Account getById(@PathVariable String id) {
        return service.fetchById(id);
    }

    @PostMapping
    public ResponseEntity<String> create(@RequestBody Account account) {
        var location = service.createAccount(account);
        return ResponseEntity.ok("Created at: " + location);
    }
}
```

Create `web-client-requests.http` in the project root:

```http
### Get all accounts
GET http://localhost:8080/wc/accounts

###

### Get account by ID
GET http://localhost:8080/wc/accounts/A001

###

### Create a new account
POST http://localhost:8080/wc/accounts
Content-Type: application/json

{
  "customerId": "C003",
  "accountType": "SAVINGS",
  "balance": 0.00
}
```

Run each request and confirm the responses match what you saw from the `RestTemplate` endpoints in Exercise 1.

> **The point of the parallel structure:** the URL difference between `/rt/accounts/A001` and `/wc/accounts/A001` is the only observable change. Both endpoints call the exact same downstream service and return the exact same JSON. The contrast is purely at the client layer: the code you write to make the HTTP call. Open `AccountRestTemplateService` and `AccountWebClientService` side by side now and compare them line by line. The differences are the lesson.

### Task 2.3 - Map HTTP errors to domain exceptions

The lecture explained that your service layer should speak your domain, not HTTP. A caller should handle `AccountNotFoundException`, not `WebClientResponseException`. This keeps your service layer independent of whichever HTTP client is in use.

Create `AccountNotFoundException.java` in the `exception` package:

```java
package com.example.bankclient.exception;

public class AccountNotFoundException extends RuntimeException {
    public AccountNotFoundException(String id) {
        super("Account not found: " + id);
    }
}
```

Update `fetchById()` in `AccountWebClientService` to map the 404 response:

```java
// TODO 12: Replace the fetchById() implementation with one that maps a 404
// to AccountNotFoundException using onStatus().
//
//   return accountWebClient.get()
//       .uri("/api/accounts/{id}", id)
//       .retrieve()
//       .onStatus(
//           status -> status.value() == 404,
//           response -> Mono.error(new AccountNotFoundException(id)))
//       .bodyToMono(Account.class)
//       .block();
//
// onStatus() intercepts responses matching the predicate and substitutes
// the supplied error signal instead of attempting to deserialize the body.
// Add the required import: import reactor.core.publisher.Mono;
```

Add an `@ExceptionHandler` to `AccountWebClientController` to return a clean 404 response:

```java
// TODO 13: Add this handler inside AccountWebClientController.
@ExceptionHandler(AccountNotFoundException.class)
public ResponseEntity<String> handleNotFound(AccountNotFoundException ex) {
    return ResponseEntity.notFound().build();
}
```

Add a test request to `web-client-requests.http`:

```http
### Get missing account - should return 404, not 500
GET http://localhost:8080/wc/accounts/A999
```

Run the request. The response should be a clean 404 with no body, rather than a 500 with a stack trace.

### Task 2.4 - Add a per-call reactive timeout

Update `fetchAll()` to enforce a 2-second business-level timeout using the reactive `.timeout()` operator:

```java
// TODO 14: Add .timeout(Duration.ofSeconds(2)) between collectList() and block()
// in fetchAll(). Import java.time.Duration.
//
// This timeout is separate from the HTTP engine timeout in WebClientConfig.
// The HTTP engine timeout is the safety net at the network layer.
// This reactive timeout enforces an end-to-end time budget for this specific call.
```

To observe the timeout firing, temporarily change the URI in `fetchAll()` from `/api/accounts` to `/api/slow` and run `GET http://localhost:8080/wc/accounts`. The stub delays 5 seconds but the reactive timeout fires after 2, so you will see a `TimeoutException` in the Run console almost immediately rather than waiting. Change the URI back to `/api/accounts` when you are done.

### Checkpoints

1. The lecture described `Mono` and `Flux` as "cold publishers." What does cold mean in this context, and what happens if you build a `Mono` chain but never call `.block()` or `.subscribe()`?
2. `retrieve()` and `exchangeToMono()` are both ways to process a response. The lecture stated that if you use `exchangeToMono()` you must consume the response body in every code path. What happens to the HTTP connection pool if you do not?
3. Your `WebClientConfig` sets a 5-second read timeout at the HTTP engine level. `fetchAll()` sets a 2-second reactive timeout. If the upstream takes 3 seconds to respond, which timeout fires? Why?
4. Compare `AccountRestTemplateService.fetchById()` to `AccountWebClientService.fetchById()`. Which one is easier to extend with a 404 mapping like the one in Task 2.3? Why?

---

## Exercise 3 - Resilience Patterns: Retry, Backoff, and Circuit Breaker

**Estimated time:** 40-55 minutes
**Topics covered:** timeout, retry, exponential backoff with jitter, circuit breaker, Resilience4j, fallback methods, the resilience stack ordering

### Context

Every upstream service you consume will eventually fail. Networks drop packets, deployments restart services, and load spikes cause temporary throttling. Without resilience patterns, a single upstream failure becomes your failure: threads exhaust waiting on hung connections, your service degrades, and users see errors from transient conditions that would have resolved on their own.

This exercise adds Resilience4j to the project and applies the four essential patterns the lecture covered: timeout, retry, exponential backoff with jitter, and circuit breaker.

For a banking client this matters in concrete ways. The external credit bureau partner endpoint you stubbed earlier has variable latency. The internal account service may be temporarily overloaded during peak hours. A naive client that crashes on every transient error will produce a steady stream of false-positive alerts; a resilient one will absorb the noise and only fail loudly when something is actually wrong.

### Task 3.1 - Add Resilience4j dependencies

Add the following to `pom.xml` inside the `<dependencies>` block:

```xml
<!-- Resilience4j Spring Boot starter -->
<dependency>
    <groupId>io.github.resilience4j</groupId>
    <artifactId>resilience4j-spring-boot3</artifactId>
    <version>2.2.0</version>
</dependency>

<!-- Required for AOP-based annotations (@CircuitBreaker, @Retry) -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aop</artifactId>
</dependency>
```

Reload Maven when IntelliJ prompts you to do so.

### Task 3.2 - Configure resilience settings in application.yml

Rename `src/main/resources/application.properties` to `application.yml` and replace its contents with the following. Read through every comment before writing any code.

```yaml
spring:
  application:
    name: bankclient

logging:
  level:
    com.example.bankclient: DEBUG

resilience4j:

  # Retry: attempt failed calls up to 3 times before giving up.
  retry:
    instances:
      upstream-api:
        max-attempts: 3
        wait-duration: 500ms
        # Exponential backoff doubles the wait after each failure:
        # attempt 1 fails -> wait 500ms, attempt 2 fails -> wait 1000ms, attempt 3 fails -> propagate
        enable-exponential-backoff: true
        exponential-backoff-multiplier: 2
        exponential-max-wait-duration: 5s
        # Only retry on these exceptions.
        # 4xx client errors are not listed - retrying them will never help.
        retry-exceptions:
          - org.springframework.web.reactive.function.client.WebClientResponseException.ServiceUnavailable
          - java.util.concurrent.TimeoutException
          - java.io.IOException

  # Circuit Breaker: stop calling a failing upstream when it is clearly struggling.
  circuit-breaker:
    instances:
      upstream-api:
        # Evaluate the last 10 calls to decide whether to open the circuit.
        sliding-window-size: 10
        # Open the circuit if 50% or more of the last 10 calls fail.
        failure-rate-threshold: 50
        # Allow 2 probe requests through the half-open state to test recovery.
        permitted-number-of-calls-in-half-open-state: 2
        # Wait 30 seconds in the open state before moving to half-open.
        wait-duration-in-open-state: 30s
        # Count all exceptions as failures toward the threshold.
        record-exceptions:
          - java.lang.Exception

upstream:
  api:
    # In a real deployment this value comes from an environment variable or a secrets manager.
    # It is in application.yml here for exercise purposes only.
    # Never commit real credentials to source control.
    token: "exercise-static-bearer-token"
    base-url: "http://localhost:8081"
```

### Task 3.3 - Apply retry and circuit breaker annotations

Create `ResilientAccountService.java` in the `service` package:

```java
package com.example.bankclient.service;

import com.example.bankclient.model.Account;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.util.List;

@Service
public class ResilientAccountService {

    private static final Logger log = LoggerFactory.getLogger(ResilientAccountService.class);

    private final WebClient accountWebClient;

    public ResilientAccountService(WebClient accountWebClient) {
        this.accountWebClient = accountWebClient;
    }

    // TODO 15: Add @Retry(name = "upstream-api") to fetchAll().
    // Add @CircuitBreaker(name = "upstream-api", fallbackMethod = "fetchAllFallback") to fetchAll().
    //
    // Annotation ordering matters. CircuitBreaker wraps Retry, which means:
    //   1. The circuit breaker checks its state first.
    //      If open, it fails immediately without making a network call.
    //   2. If closed, Retry orchestrates multiple attempts with exponential backoff.
    //   3. If all retry attempts are exhausted, the exception reaches the circuit breaker,
    //      which counts it as a failure toward the threshold.
    public List<Account> fetchAll() {
        log.info("Calling upstream /api/flaky");
        return accountWebClient.get()
                .uri("/api/flaky")
                .retrieve()
                .bodyToFlux(Account.class)
                .collectList()
                .block();
    }

    // TODO 16: Implement the fallback method.
    // The fallback method must have the same return type as fetchAll() -- List<Account>.
    // It must accept a Throwable as its last (and only) parameter.
    // Log a warning that includes ex.getMessage() so the failure is observable in logs.
    // Return List.of() to serve a degraded empty response rather than propagating the error.
    public List<Account> fetchAllFallback(Throwable ex) {
        return List.of(); // Replace with your implementation
    }
}
```

Create `ResilientController.java` in the `controller` package:

```java
package com.example.bankclient.controller;

import com.example.bankclient.model.Account;
import com.example.bankclient.service.ResilientAccountService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/resilient")
public class ResilientController {

    private final ResilientAccountService service;

    public ResilientController(ResilientAccountService service) {
        this.service = service;
    }

    @GetMapping("/accounts")
    public List<Account> getAll() {
        return service.fetchAll();
    }
}
```

### Task 3.4 - Create a stub management controller

The exercises need a way to change stub behaviour at runtime to simulate an upstream recovering or going down. Create `StubManagementController.java` in the `controller` package:

```java
package com.example.bankclient.controller;

import com.example.bankclient.config.StubServerConfig;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import static com.github.tomakehurst.wiremock.client.WireMock.*;

@RestController
@RequestMapping("/stubs")
public class StubManagementController {

    private final StubServerConfig stubServerConfig;

    public StubManagementController(StubServerConfig stubServerConfig) {
        this.stubServerConfig = stubServerConfig;
    }

    // Simulates the /api/flaky upstream recovering and returning 200
    @PostMapping("/flaky/recover")
    public ResponseEntity<String> makeFlakyRecover() {
        stubServerConfig.getServer().stubFor(
                get(urlEqualTo("/api/flaky"))
                        .willReturn(aResponse()
                                .withStatus(200)
                                .withHeader("Content-Type", "application/json")
                                .withBody("[{\"id\":\"A001\",\"customerId\":\"C001\",\"accountType\":\"CHECKING\",\"balance\":1250.00}]"))
        );
        return ResponseEntity.ok("Stub updated: /api/flaky now returns 200");
    }

    // Simulates the /api/flaky upstream going back down
    @PostMapping("/flaky/fail")
    public ResponseEntity<String> makeFlakyFail() {
        stubServerConfig.getServer().stubFor(
                get(urlEqualTo("/api/flaky"))
                        .willReturn(aResponse()
                                .withStatus(503)
                                .withBody("Service Unavailable"))
        );
        return ResponseEntity.ok("Stub updated: /api/flaky now returns 503");
    }
}
```

### Task 3.5 - Observe the resilience stack in action

Add requests to `web-client-requests.http`:

```http
### Resilient endpoint - the /api/flaky stub currently returns 503.
### Watch the application console: you will see retry attempts before the fallback fires.
GET http://localhost:8080/resilient/accounts

###

### Make the flaky stub return 200 (simulates upstream recovery)
POST http://localhost:8080/stubs/flaky/recover

###

### Make the flaky stub return 503 again (simulates upstream going down)
POST http://localhost:8080/stubs/flaky/fail
```

Run `GET /resilient/accounts`. Because the `/api/flaky` stub always returns 503, the retry will exhaust all three attempts and the circuit breaker will invoke the fallback. You should see three log lines in the console:

```
INFO  Calling upstream /api/flaky
INFO  Calling upstream /api/flaky
INFO  Calling upstream /api/flaky
WARN  Fallback invoked: 503 Service Unavailable
```

The HTTP response to your client should be `200 OK` with an empty array `[]`. The fallback produced a degraded response rather than propagating the failure to the caller.

Now run `POST /stubs/flaky/recover`, then run `GET /resilient/accounts` again. The response should include accounts and no fallback warning should appear in the log. Run `POST /stubs/flaky/fail` to restore the 503 behaviour.

### Checkpoints

1. The lecture described the thundering herd problem. With 100 clients all retrying at the same interval after a shared failure, what happens when the upstream recovers? How does jitter address this?
2. The retry configuration lists `ServiceUnavailable` (503) as a retryable exception but does not include `WebClientResponseException.NotFound` (404). Explain the reason for this distinction.
3. The circuit breaker's `wait-duration-in-open-state` is set to 30 seconds. During those 30 seconds, what happens when a request arrives? Does it go to the upstream, to the fallback, or is an exception thrown?
4. The fallback returns an empty list. For a banking client showing account balances to a user, is an empty list a safe degraded response? What is a better alternative and why?

---

## Exercise 4 - Bearer Token Attachment via WebClient Filter

**Estimated time:** 30-40 minutes
**Topics covered:** bearer tokens, `ExchangeFilterFunction`, token attachment via filter vs inline, secure configuration, proactive token expiry checks

### Context

A bearer token is a credential. Anyone bearing the token can use it, there is no binding to a specific client identity. This means mishandling the token is a security failure: logging its full value, sending it over plain HTTP, or scattering token retrieval logic across call sites all create vulnerabilities.

The lecture described the correct pattern: attach tokens in a `WebClient` filter, not at call sites. The filter is a single, auditable, independently testable place where all token handling lives. Call sites express only business intent.

This exercise simulates a service-to-service call where your application must acquire a token and attach it to every outbound request. You will work with a static token for now. The OAuth2 automated flow you saw in Lab 2-2 (with `OAuth2AuthorizedClientManager`) is the production replacement for this; the filter mechanics you build here are exactly the machinery that Spring Security wires up for you in that integration. Understanding the filter pattern is the prerequisite for understanding what the framework does on your behalf.

### Task 4.1 - Confirm the token property is in application.yml

The `upstream.api.token` property should already be present in `application.yml` from Task 3.2. Confirm the following block is there:

```yaml
upstream:
  api:
    token: "exercise-static-bearer-token"
    base-url: "http://localhost:8081"
```

> **The baseline rule from the lecture:** secrets never appear in source code. In production, the token value would be injected from an environment variable using `${UPSTREAM_API_TOKEN}` as the value in `application.yml`, or sourced from a secrets manager such as AWS Secrets Manager, Azure Key Vault, or HashiCorp Vault. The `application.yml` file itself would contain only the reference, not the value.

### Task 4.2 - Create a token provider

Create `StaticTokenProvider.java` in the `config` package:

```java
package com.example.bankclient.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Provides the bearer token for outbound API calls.
 *
 * In production this would contact an OAuth2 token endpoint,
 * cache the token, and refresh it before expiry.
 * For this exercise it returns a static value injected from configuration.
 */
@Component
public class StaticTokenProvider {

    private final String token;

    // TODO 17: Inject the value of upstream.api.token using @Value.
    // @Value reads from application.yml using Spring's ${...} syntax.
    // Assign the injected value to the token field.
    public StaticTokenProvider(@Value("${upstream.api.token}") String token) {
        this.token = token;
    }

    public String getToken() {
        return token;
    }
}
```

### Task 4.3 - Create a bearer token filter

Create `BearerTokenFilter.java` in the `config` package:

```java
package com.example.bankclient.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.reactive.function.client.ClientRequest;
import org.springframework.web.reactive.function.client.ExchangeFilterFunction;
import reactor.core.publisher.Mono;

public class BearerTokenFilter {

    private static final Logger log = LoggerFactory.getLogger(BearerTokenFilter.class);

    private final StaticTokenProvider tokenProvider;

    public BearerTokenFilter(StaticTokenProvider tokenProvider) {
        this.tokenProvider = tokenProvider;
    }

    // TODO 18: Implement filter(), returning an ExchangeFilterFunction.
    //
    // Use ExchangeFilterFunction.ofRequestProcessor(request -> { ... })
    // Inside the lambda:
    //   1. Call tokenProvider.getToken() to retrieve the token value.
    //   2. Log that a token is being attached, but log only the first 8 characters
    //      followed by "..." to avoid exposing the full token value in logs.
    //      Example: log.debug("Attaching token: {}...", token.substring(0, 8))
    //   3. Build a new request with the Authorization header:
    //        ClientRequest.from(request)
    //            .header("Authorization", "Bearer " + token)
    //            .build()
    //   4. Wrap the result in Mono.just() and return it.
    //
    // Never log the full token value. This is a security requirement, not a style choice.
    public ExchangeFilterFunction filter() {
        return ExchangeFilterFunction.ofRequestProcessor(request -> {
            return Mono.just(request); // Replace with your implementation
        });
    }
}
```

> **Why log only the first 8 characters?** The lecture stated: never log the full token value. A full bearer token in a log file is a credential leak. An attacker with log access gains the same permissions as the token holder. The first 8 characters are enough to identify which token is in use for debugging purposes without exposing the credential itself.

### Task 4.4 - Register the filter on a new WebClient bean

Add a second `WebClient` bean to `WebClientConfig.java` that includes the bearer token filter. The complete updated `WebClientConfig` should look like this:

```java
package com.example.bankclient.config;

import io.netty.channel.ChannelOption;
import io.netty.handler.timeout.ReadTimeoutHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Configuration
public class WebClientConfig {

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

    // TODO 19: Complete this bean by applying the bearer token filter.
    // The BearerTokenFilter is already constructed below.
    // Add .filter(bearerTokenFilter.filter()) to the builder before .build().
    @Bean
    public WebClient authenticatedWebClient(StaticTokenProvider tokenProvider) {
        var bearerTokenFilter = new BearerTokenFilter(tokenProvider);
        return WebClient.builder()
                .baseUrl("http://localhost:8081")
                .build(); // Replace with your implementation
    }
}
```

> **Why `@Primary` on `accountWebClient`?** With two `WebClient` beans in the context, Spring does not know which one to inject when a class declares `WebClient` without a `@Qualifier`. `@Primary` designates `accountWebClient` as the default. The `authenticatedWebClient` is only injected where `@Qualifier("authenticatedWebClient")` is explicitly specified.

### Task 4.5 - Call the protected endpoint

Create `AuthenticatedAccountService.java` in the `service` package:

```java
package com.example.bankclient.service;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

@Service
public class AuthenticatedAccountService {

    private final WebClient authenticatedWebClient;

    public AuthenticatedAccountService(
            @Qualifier("authenticatedWebClient") WebClient authenticatedWebClient) {
        this.authenticatedWebClient = authenticatedWebClient;
    }

    // TODO 20: Implement ping() using the authenticatedWebClient.
    // Call GET "/api/auth-required".
    // Return the response body as a String.
    // Chain: .get().uri("/api/auth-required").retrieve().bodyToMono(String.class).block()
    public String ping() {
        return null; // Replace with your implementation
    }
}
```

Create `AuthController.java` in the `controller` package:

```java
package com.example.bankclient.controller;

import com.example.bankclient.service.AuthenticatedAccountService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/auth")
public class AuthController {

    private final AuthenticatedAccountService service;

    public AuthController(AuthenticatedAccountService service) {
        this.service = service;
    }

    @GetMapping("/ping")
    public String ping() {
        return service.ping();
    }
}
```

Add a request to `web-client-requests.http`:

```http
### Should return: {"message":"Authenticated successfully"}
GET http://localhost:8080/auth/ping
```

Run the request. You should receive `{"message":"Authenticated successfully"}`.

To confirm the filter is doing the work, temporarily comment out the `.header(...)` line inside `BearerTokenFilter.filter()` so it returns `Mono.just(request)` unchanged. Run the request again - you should receive a 401. This confirms the stub requires the `Authorization` header and the filter is what provides it. Restore the filter before continuing.

### Task 4.6 - Reflect on filter ordering

The lecture stated that filters execute in registration order and recommended: correlation ID first, token attachment before logging, error-handling filters last.

Add a second filter to `authenticatedWebClient` that logs the HTTP method and URI of every request. Register it after the bearer token filter using a second `.filter(...)` call.

Run `GET /auth/ping` again and examine the Run console. You should see:

1. The bearer token filter log line (token being attached)
2. The logging filter log line (method and URI)

Swap the registration order and run again. Both log lines still appear, but note that if the logging filter ran first it would record the request before the token was attached. A log entry without an `Authorization` header present could be misread as meaning the call was unauthenticated. Restore the original order when you are done.

### Checkpoints

1. The lecture listed three golden rules for bearer tokens. State all three from memory, then verify against the lecture notes.
2. Your `StaticTokenProvider` returns the same token on every call. In a real production system using OAuth2 Client Credentials (as you saw in Lab 2-2), what would `getToken()` need to do differently to avoid sending an expired token to the upstream?
3. The filter uses `ClientRequest.from(request).header(...).build()`. Why create a new request object rather than mutating the existing one?
4. In Lab 2-2 you used `ServletOAuth2AuthorizedClientExchangeFilterFunction` to attach tokens automatically. Looking at the `BearerTokenFilter` you just built, which parts would be replaced by the Spring Security integration, and which parts (logging, the WebClient itself) would remain your responsibility?

---

## Summary and Reflection

After completing all four exercises you have worked through the core lifecycle of secure external API consumption: making synchronous calls with `RestTemplate`, building fluent non-blocking pipelines with `WebClient`, applying resilience patterns to protect your service from upstream failures, and attaching bearer tokens securely through the filter chain.

| Exercise | Concept | Key Insight |
|---|---|---|
| 1 - RestTemplate | `getForObject`, `getForEntity`, `exchange`, interceptors | `RestTemplate` is still widely used; interceptors are the correct place for cross-cutting concerns |
| 2 - WebClient | Fluent API, `Mono`, `Flux`, domain exception mapping | WebClient is a pipeline, not a function call; nothing executes until subscribed |
| 3 - Resilience | Retry, backoff, jitter, circuit breaker, fallback | Ordering matters: circuit breaker wraps retry; jitter prevents thundering herd |
| 4 - Bearer Tokens | `ExchangeFilterFunction`, secure config, filter ordering | Tokens are credentials; attach them in a filter, never at call sites, never log the full value |

### Final Reflection Questions

Take 10 minutes to answer these before your next session:

1. The lecture's production checklist includes "safe logging filter, no Authorization header values logged." You implemented partial token logging (first 8 characters only) in Exercise 4. Describe how you would extend the logging filter to redact the `Authorization` header from request logs entirely, while still logging a flag that indicates whether the header was present.

2. In Exercise 3, the circuit breaker fallback returns an empty list. In a real banking application, describe three different fallback strategies for a circuit-broken call to a customer account balance service. Consider the trade-offs of each: what does the user experience, what is the business risk, and when would each be appropriate?

3. Exercise 4 used a static token for simplicity. Spring Security's `OAuth2AuthorizedClientManager` (covered in Lab 2-2) automates token acquisition, caching, and refresh. Looking at the filter mechanics you built manually in this exercise, identify which parts of your `BearerTokenFilter` would be replaced by the Spring Security integration, and which parts (such as logging and connection management) would remain your responsibility.

4. The end-state for this code is to be merged into the `bankapi` application as a backend-for-frontend (BFF) for the React banking UI. The WebClient patterns you built in Exercises 2 and 4 are the foundation for that integration. Describe how a BFF endpoint that returns "account summary + recent transactions + credit score" for a customer would use the WebClient code you wrote: how many downstream calls would it make, in what order, and what failure modes would it need to handle?

---

*End of Lab 2-3 Exercises*
