# Capstone How-To: Standalone Payment Mock (WireMock)

#### Version 1.0  June 29

This walks you through recreating the WireMock server from Lab 2-3 as its **own**
Spring Boot project, serving the external payment processor the BankService calls.
It is the same embedded-WireMock pattern you wrote in `StubServerConfig`, extracted
into a standalone app and trimmed to a single endpoint.

## What you are building

A small Spring Boot application whose only job is to run a WireMock server on port
**8090** exposing one endpoint:

| Property | Value |
|----------|-------|
| Endpoint | `POST http://localhost:8090/payments` |
| Auth | none (unauthenticated mock) |
| Request body | `{ "amount": <number>, "reference": "<string>" }` |
| Success | `201 Created`, body `{ "status": "ACCEPTED", "confirmation": "PMT-1001" }` |
| Failure trigger | an `amount` of `999.99` returns `503 Service Unavailable`, body `{ "status": "UNAVAILABLE" }` |

The failure trigger exists so you can demonstrate the BankService handling a
downstream failure: on 201 it debits the account and records a `COMPLETED`
`PAYMENT`; on 503 it records a `FAILED` `PAYMENT`, does not debit, and returns 502
to the SPA. The exact amount `999.99` is just a convenient switch; what matters is
that the failure path is exercised.

---

## Step 1: Create the project with Spring Initializr

Open [https://start.spring.io](https://start.spring.io) and configure:

| Setting | Value |
|---------|-------|
| Project | Maven |
| Language | Java |
| Spring Boot | 3.4.5 |
| Group | `com.example` |
| Artifact | `paymentmock` |
| Name | `paymentmock` |
| Package name | `com.example.paymentmock` |
| Packaging | Jar |
| Java | 21 |
| Dependencies | none (leave it empty; we add WireMock by hand) |

Generate, unzip, and open in IntelliJ.

---

## Step 2: Add the dependencies

Because we selected no dependencies, add both of these inside the `<dependencies>`
block of `pom.xml`. The first is Spring Boot's core starter (the empty Initializr
project only ships the test starter); the second is WireMock 3.x.

Use the **`wiremock-standalone`** artifact, not the plain `wiremock` one. The
standalone artifact bundles its own (shaded) Jetty server, so it runs in a minimal
app like this. The plain `wiremock` artifact expects a compatible Jetty already on
the classpath, which this stripped-down project does not have, and it fails at
startup with a `Jetty 11 is not present` error.

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter</artifactId>
</dependency>

<dependency>
    <groupId>org.wiremock</groupId>
    <artifactId>wiremock-standalone</artifactId>
    <version>3.9.1</version>
</dependency>
```

Reload Maven so the dependencies download. The package names are identical between
`wiremock` and `wiremock-standalone` (`com.github.tomakehurst.wiremock`), so the
configuration code below does not change regardless of which you have seen before.

---

## Step 3: Disable the web server

This app does not need Spring's own Tomcat; WireMock provides the HTTP server.
Delete the generated `src/main/resources/application.properties` and create
`src/main/resources/application.yaml` in its place:

```yaml
spring:
  application:
    name: paymentmock
  main:
    web-application-type: none
```

`web-application-type: none` stops Spring from starting Tomcat (which would otherwise
try to bind port 8080 and collide with the BFF). The process stays alive because
WireMock's own HTTP server threads keep the JVM running.

(Spring Boot accepts either `application.yaml` or `application.yml`; use whichever
extension your team prefers, but keep only one file.)

---

## Step 4: The WireMock configuration

Create `PaymentStubConfig.java` in a `config` package
(`com.example.paymentmock.config`). This is the Lab 2-3 `StubServerConfig` pattern,
narrowed to the one payment stub plus its failure variant.

```java
package com.example.paymentmock.config;

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
public class PaymentStubConfig {

    private static final Logger log = LoggerFactory.getLogger(PaymentStubConfig.class);
    private static final int PORT = 8090;

    private WireMockServer wireMockServer;

    @EventListener(ContextRefreshedEvent.class)
    public void start() {
        if (wireMockServer != null && wireMockServer.isRunning()) {
            return;
        }
        wireMockServer = new WireMockServer(
                WireMockConfiguration.wireMockConfig().port(PORT));
        wireMockServer.start();
        WireMock.configureFor("localhost", PORT);
        registerStubs();
        log.info("Payment mock started on port {}. Admin: http://localhost:{}/__admin/mappings",
                PORT, PORT);
    }

    @PreDestroy
    public void stop() {
        if (wireMockServer != null && wireMockServer.isRunning()) {
            wireMockServer.stop();
            log.info("Payment mock stopped.");
        }
    }

    private void registerStubs() {

        // Catch-all success: every payment is accepted with 201.
        // Registered FIRST so the failure stub below takes priority. WireMock
        // evaluates stubs in reverse registration order (last registered wins),
        // the same ordering rule as the auth-required stubs in Lab 2-3.
        stubFor(post(urlEqualTo("/payments"))
                .willReturn(aResponse()
                        .withStatus(201)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"status\":\"ACCEPTED\",\"confirmation\":\"PMT-1001\"}")));

        // Failure trigger: amount == 999.99 returns 503.
        // Registered AFTER the catch-all so WireMock checks it first.
        // The JSONPath filter matches the amount numerically, so it is not
        // sensitive to how the number is formatted on the wire.
        stubFor(post(urlEqualTo("/payments"))
                .withRequestBody(matchingJsonPath("$[?(@.amount == 999.99)]"))
                .willReturn(aResponse()
                        .withStatus(503)
                        .withHeader("Content-Type", "application/json")
                        .withBody("{\"status\":\"UNAVAILABLE\"}")));
    }
}
```

The main application class is the standard one Initializr generated; nothing to
change there.

---

## Step 5: Run it

Run the application. Near the end of the startup log you should see:

```
Payment mock started on port 8090. Admin: http://localhost:8090/__admin/mappings
```

Open that admin URL in a browser to confirm both stubs are registered. If you see
the JSON list of mappings, the mock is live.

---

## Step 6: Smoke test with an `.http` file

Create `payment-mock.http` in the project root and run each request from IntelliJ.
The assertions make it a self-checking smoke test.

```http
### Successful payment - expect 201 ACCEPTED
POST http://localhost:8090/payments
Content-Type: application/json

{
  "amount": 50.00,
  "reference": "UTIL-12345"
}

> {%
client.test("status is 201", function () {
    client.assert(response.status === 201, "Expected 201, got " + response.status);
});
client.test("body is ACCEPTED", function () {
    client.assert(response.body.status === "ACCEPTED", "Expected ACCEPTED");
});
%}

### Failure trigger - amount 999.99 - expect 503 UNAVAILABLE
POST http://localhost:8090/payments
Content-Type: application/json

{
  "amount": 999.99,
  "reference": "UTIL-99999"
}

> {%
client.test("status is 503", function () {
    client.assert(response.status === 503, "Expected 503, got " + response.status);
});
%}

### Another normal amount - expect 201
POST http://localhost:8090/payments
Content-Type: application/json

{
  "amount": 1000.00,
  "reference": "RENT-2026-07"
}

> {%
client.test("status is 201", function () {
    client.assert(response.status === 201, "Expected 201, got " + response.status);
});
%}

### Admin - list registered stubs - expect 200
GET http://localhost:8090/__admin/mappings

> {%
client.test("admin reachable", function () {
    client.assert(response.status === 200, "Expected 200, got " + response.status);
});
%}
```

All four should pass: two 201s, one 503, and the admin check. That confirms the
mock is running, the success path works, and the 999.99 failure path triggers.

---

## How the BankService uses this

The BankService payment flow (per the API contract and business rules) is:

1. Check the account is active and has sufficient funds. If not, 422 and a
   `FAILED` row, with no call made here.
2. POST to `http://localhost:8090/payments` with the amount and reference.
3. On `201`, debit the account and record a `COMPLETED` `PAYMENT`, return 201.
4. On `503`, record a `FAILED` `PAYMENT`, do not debit, and return `502` to the SPA.

So this mock's 503 is what your BankService translates into the 502 the SPA sees.
The payment base URL (`http://localhost:8090`) is the `app.payment.base-url`
property in the BankService configuration.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| App starts then exits immediately | The WireMock server did not start (check the log for an exception) or the port was already taken. Confirm `web-application-type: none` is set in `application.yaml` and port 8090 is free. |
| `999.99` returns 201 instead of 503 | The failure stub must be registered **after** the catch-all (last registered wins). Confirm the order in `registerStubs()`. |
| Every request returns 404 | The path is `/payments` and the method is POST. A GET or a different path will not match any stub. |
| Port 8090 already in use | Another process (or a second copy of this app) holds it. Stop it, or change `PORT` and the BankService `app.payment.base-url` together. |
| `FatalStartupException: Jetty 11 is not present` at startup | You are using the plain `wiremock` artifact on a minimal classpath. Switch the dependency to `org.wiremock:wiremock-standalone`, which bundles its own server. |
| Import errors on `com.github.tomakehurst...` | The package name is the same for `wiremock-standalone`. Confirm the dependency resolved and Maven reloaded. |

---

## Notes for the instructor

- This document effectively defines the external payment service contract
  (endpoint, request and response shapes, failure trigger). The dedicated
  external-service supplement can reference it rather than restating it.
- Securing this call with a client-credentials token is the documented stretch; if
  pursued, the mock would add a stub variant requiring an `Authorization: Bearer`
  header, mirroring the auth-required stub from Lab 2-3.
