# Capstone Supplement: Testing and Validation Guidance

#### Version 1.0

This supplement guides you through **how** to prove your capstone works through automated
tests, and how to use GitHub Copilot to help you write them. It assumes the two
lectures you have had on JUnit, Mockito, and Spring integration testing, and it
does not re-teach those from scratch. Instead, it shows you where each kind of
test belongs in this specific system and walks three of them end to end.

It pairs with the Business Rules supplement, the API Contract, the Data Model,
and the JPA Persistence supplement. Keep those open while you write tests: they
are the specification your tests are checking.

If you have already started testing, use this document to confirm or help correct what you have been doing.

Since most of you have not had a background in testing, this is provided as guidance.

That means that this document is **not** a requirement or something that you have to follow, but more suggestions that might help you out as you go through the testing challenges you might face in the capstone.

---

## 1. What "proving it works" means here

Testing on this capstone has three jobs, and the rubric rewards all three:

1. **Confidence during build days.** A test suite you can run in seconds tells
   you whether the change you just made broke something you already had working.
   This is the everyday value, and it is the reason to write tests early rather
   than the night before the presentation.
2. **Evidence for the rubric.** The grading looks for service-layer unit tests
   with mocked repositories, integration tests that reach the database including
   a failure case, and a clean SonarQube scan. Your suite is the artifact that
   demonstrates this.
3. **A story for the presentation.** You must show one transaction end to end,
   including a failure path. A test that walks that exact path is the most
   reliable way to rehearse and demonstrate it.

You are not expected to become testing experts in a week. You are expected to
cover the graded paths competently. The good news is that most of the "what to
test" work is already done for you: the Business Rules **outcome matrix** and the
**six worked examples** in that supplement are effectively a ready-made list of
test cases. This document teaches the mechanics of turning them into code.

---

## 2. The testing strategy (the map)

Think in three tiers. Each tier proves something the others cannot, and each
runs at a different cost.

| Tier | What it is | What it proves | What it cannot prove | Speed |
|------|-----------|----------------|----------------------|-------|
| 1. Service unit tests | The service class with its repositories, Kafka publisher, and payment client **mocked** | Business rules: which status, which rows, which side effects, in isolation | That your JPA mapping, SQL, trigger, or security wiring is correct | Milliseconds |
| 2. Web and security slice | The controller and filter chain via `@WebMvcTest`, service **mocked** | HTTP concerns: routing, status mapping, the 401 path, the public health route, error-body shape | Anything below the controller (rules, persistence) | Fast |
| 3. Integration tests | The real service against **Testcontainers-Oracle**, **WireMock**, and **Testcontainers-Kafka** | Mapping, the audit trigger, transfer atomicity, the payment failure mapping, real publishing | Nothing more than it exercises; slow, so keep it targeted | Seconds each |

Most of your test **value** is in Tier 1, because that is where the business
rules live (see the JPA supplement: a rule that cannot be tested with the
repository mocked has probably leaked into the entity or the database). Most of
your **evidence for correctness of wiring** is in Tier 3.

### Two-tier or three-tier: pick what your schedule allows

Tier 2 (the `@WebMvcTest` slice) is the cleanest way to test the graded 401
behavior and the public health route in isolation, but it is one more concept.
If your team is short on time across July 2 and July 6, you may **fold Tier 2
into Tier 3**: stand up the full application with `@SpringBootTest` plus
`MockMvc` and assert the HTTP status codes there against a real security filter
chain. You lose isolation and speed, you keep the coverage. Both framings are
acceptable. The three-tier split is recommended if you have the time, because a
failing slice test points at the web layer directly, while a failing full-stack
test makes you hunt.

The minimum bar, regardless of framing: Tier 1 unit tests covering the outcome
matrix rows, and at least a handful of Tier 3 integration tests including the
audit trigger and one failure path.

---

## 3. Setting up the test environment

### 3.1 Dependencies

`spring-boot-starter-test` (test scope) already brings JUnit 5, Mockito,
AssertJ, MockMvc, and JSONassert. Add the pieces this capstone needs on top:

```xml
<dependency>
  <groupId>org.springframework.security</groupId>
  <artifactId>spring-security-test</artifactId>
  <scope>test</scope>
</dependency>

<dependency>
  <groupId>org.springframework.kafka</groupId>
  <artifactId>spring-kafka-test</artifactId>
  <scope>test</scope>
</dependency>

<!-- Testcontainers, managed by the BOM -->
<dependency>
  <groupId>org.testcontainers</groupId>
  <artifactId>junit-jupiter</artifactId>
  <scope>test</scope>
</dependency>
<dependency>
  <groupId>org.testcontainers</groupId>
  <artifactId>oracle-xe</artifactId>
  <scope>test</scope>
</dependency>
<dependency>
  <groupId>org.testcontainers</groupId>
  <artifactId>kafka</artifactId>
  <scope>test</scope>
</dependency>

<!-- WireMock: use the standalone artifact, per the known lab gotcha -->
<dependency>
  <groupId>org.wiremock</groupId>
  <artifactId>wiremock-standalone</artifactId>
  <version>3.9.1</version>
  <scope>test</scope>
</dependency>
```

Add the Testcontainers BOM to `dependencyManagement` so the module versions
stay aligned. Use `wiremock-standalone:3.9.1`, not the plain `wiremock`
artifact, which fails without a bundled Jetty.

> **Why Testcontainers-Kafka and not an embedded broker.** `spring-kafka-test`
> ships an `@EmbeddedKafka` broker that is lighter, and you may see it in
> tutorials. We use Testcontainers-Kafka here to stay consistent with the
> environment runbook, which runs Kafka as a Docker container. Your integration
> tests then exercise the same broker technology as your running system.

### 3.2 Loading the schema into Testcontainers Oracle

The container needs the schema and seed loaded before your integration tests
run. There is a gotcha here that will cost you an afternoon if you miss it:

> **The compose init scripts do not work unchanged in Testcontainers.** The
> Docker Compose init scripts begin with `ALTER SESSION SET CONTAINER = XEPDB1`
> and `CONNECT labuser/labpass123@localhost/XEPDB1`. Those are **SQL\*Plus
> directives**. Testcontainers `withInitScript(...)` and Spring's SQL init both
> execute statements over **JDBC**, which does not understand `CONNECT` or
> `ALTER SESSION SET CONTAINER`. Give your tests a **plain-SQL** copy of the DDL
> and seed (only `CREATE TABLE`, `CREATE TRIGGER`, `INSERT`, and so on) with no
> SQL\*Plus commands, and point the container at that.

A minimal container definition, reused by every integration test through a base
class:

```java
@Testcontainers
public abstract class OracleIntegrationTestBase {

    @Container
    static final OracleContainer ORACLE =
        new OracleContainer("gvenzl/oracle-xe:21-slim")
            .withUsername("labuser")
            .withPassword("labpass123")
            .withInitScript("db/schema-and-seed-test.sql"); // plain SQL, no SQL*Plus

    @DynamicPropertySource
    static void oracleProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", ORACLE::getJdbcUrl);
        registry.add("spring.datasource.username", ORACLE::getUsername);
        registry.add("spring.datasource.password", ORACLE::getPassword);
    }
}
```

Verify the JDBC URL the container hands you points at your pluggable database in
your environment; adjust if your local Oracle image differs from the runbook's.

### 3.3 The test profile

Keep a `application-test.yml` on the test classpath that keeps Hibernate off the
schema (the DDL owns it) and sets the Oracle dialect:

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: none
    open-in-view: false
    properties:
      hibernate.dialect: org.hibernate.dialect.OracleDialect
```

Activate it with `@ActiveProfiles("test")` on integration tests.

### 3.4 Running tests

From IntelliJ, run a single test with the gutter arrow, or a whole class from
its tab. From the command line, `mvn test` runs the unit tier;
`mvn verify` runs integration tests too if you bind them to the failsafe
plugin (name integration tests `*IT.java`). When a test fails, read the assertion
message first and the stack trace second: AssertJ messages tell you the expected
and the actual value directly.

---

## 4. Tier 1: unit testing the service layer

This is the core of your suite. Here you prove the business rules with the
database, Kafka, and the payment client all mocked, so the test runs in
milliseconds and fails for exactly one reason: a rule is wrong.

### Assumed API for the worked examples

The reference entities and service are built by your team, so method and class
names will differ. The three worked examples below all use one consistent,
hypothetical API so they read coherently. **Map these to your real code.**

- `BankingService` with `deposit`, `withdraw`, `transfer`, `pay`, and read
  methods.
- Spring Data repositories: `AccountRepository`, `TransactionRepository`,
  `CustomerRepository`, `TransferRepository`.
- `TransactionStatsPublisher` with a `publish(...)` method (the Kafka producer).
- Domain exceptions mapped by a `@RestControllerAdvice`:
  `InsufficientFundsException` and `InactiveAccountException` to 422,
  `AccountNotFoundException` to 404, `NotAccountOwnerException` to 403,
  `PaymentGatewayException` to 502.
- Enums `TransactionType`, `TransactionStatus`, `AccountStatus`, `AccountType`.

### Anatomy of a test: Arrange, Act, Assert

Every test has three parts. Arrange the inputs and stub the mocks. Act by
calling the one method under test. Assert the outcome. Name the test so the name
is the specification: `method_condition_expectedResult`.

### Worked example 1: insufficient funds (BR-F1)

This is the highest-value single test to understand, because it exercises the
whole shape of the FAILED policy: the right exception (mapping to 422), a FAILED
row written, no balance change, and nothing published to Kafka.

```java
@ExtendWith(MockitoExtension.class)
class WithdrawalRulesTest {

    @Mock AccountRepository accountRepository;
    @Mock TransactionRepository transactionRepository;
    @Mock TransactionStatsPublisher statsPublisher;

    @InjectMocks BankingService bankingService;

    @Test
    void withdraw_whenBalanceTooLow_writesFailedRowAndDoesNotMoveMoney() {
        // Arrange: an ACTIVE account holding 50.00
        Account account = TestAccounts.active(1L, new BigDecimal("50.00"));
        when(accountRepository.findById(1L)).thenReturn(Optional.of(account));

        BigDecimal amount = new BigDecimal("75.00");

        // Act + Assert: the rule rejects with the 422-mapped exception
        assertThatThrownBy(() -> bankingService.withdraw(1L, amount))
            .isInstanceOf(InsufficientFundsException.class);

        // A FAILED WITHDRAWAL row is recorded
        ArgumentCaptor<Transaction> captor = ArgumentCaptor.forClass(Transaction.class);
        verify(transactionRepository).save(captor.capture());
        Transaction saved = captor.getValue();
        assertThat(saved.getType()).isEqualTo(TransactionType.WITHDRAWAL);
        assertThat(saved.getStatus()).isEqualTo(TransactionStatus.FAILED);

        // No balance change is persisted
        verify(accountRepository, never()).save(any(Account.class));

        // FAILED transactions are never published (BR-K1)
        verifyNoInteractions(statsPublisher);
    }
}
```

Four assertions, four rules, in one test. The `ArgumentCaptor` lets you inspect
the row the service tried to save without a database. `verifyNoInteractions`
proves the negative side of BR-K1: a failure publishes nothing.

> **Beginner gotcha: `@PreAuthorize` does not run here.** Withdrawal is
> teller-only (BR-A2), but in a plain Mockito unit test there is no Spring
> security context and no proxy, so the annotation is inert. This test proves
> the funds rule, not the role check. The role check is a security concern and
> is tested in Tier 2 and Tier 3. Do not try to assert 403 from a pure unit
> test; it will never fire.

### Parameterized tests from the outcome matrix

Several rows of the outcome matrix differ only in inputs. A parameterized test
covers them without copy-paste:

```java
@ParameterizedTest
@CsvSource({
    "DEPOSIT,    100.00, COMPLETED",
    "WITHDRAWAL,  40.00, COMPLETED",
    "WITHDRAWAL, 999.00, FAILED"
})
void cashOperationOutcomes(String type, BigDecimal amount, String expectedStatus) {
    // Arrange, Act, Assert against the matrix row
}
```

Reserve parameterized tests for genuinely uniform cases. When the side effects
differ (a transfer writes two rows and publishes twice), a dedicated test reads
more clearly than a clever parameterization.

### What to cover in Tier 1

Walk the Business Rules catalog and write one test per rule that the service
owns: ownership (BR-A4, BR-A5), inactive account (BR-S1), insufficient funds
(BR-F1), the transfer two-leg success and failure (BR-T1, BR-T3), the payment
precheck order (BR-P2), and the publish rules (BR-K1). Section 7 gives you a
coverage table to track this.

---

## 5. Tier 2: the web and security slice

Here you test HTTP behavior with the service mocked, using `@WebMvcTest`. This
tier owns the two facts about the filter chain that the rubric checks directly:
the public health route, and the 401 path for an unauthenticated caller.

### Worked example 2: the health route and the 401 path

```java
@WebMvcTest(controllers = HealthController.class)
@Import(SecurityConfig.class)   // bring in the real filter chain
class PublicAndProtectedRoutesTest {

    @Autowired MockMvc mvc;

    @Test
    void health_isPublic_returns200WithoutToken() throws Exception {
        mvc.perform(get("/api/health"))
           .andExpect(status().isOk())
           .andExpect(jsonPath("$.status").value("up"));
    }

    @Test
    void accounts_withoutToken_returns401() throws Exception {
        mvc.perform(get("/api/accounts"))
           .andExpect(status().isUnauthorized());
    }
}
```

The first test proves `permitAll()` on the one public path. The second proves
"we do not know who you are" maps to 401, not 403. You must `@Import` your real
`SecurityConfig`, otherwise `@WebMvcTest` applies Spring Boot's default security
and you are testing the wrong filter chain.

### Where the 403 (wrong role) test lives, and why

The contract puts the deposit and withdrawal **role checks at the service
layer** with `@PreAuthorize`, not in the URL rules. That has a direct
consequence for testing: in a `@WebMvcTest` with the service **mocked**, the
mock has no `@PreAuthorize`, so a wrong-role call will not produce 403 there. To
test the 403 wrong-role decision you need the **real service** with method
security active. Do that with a focused method-security test:

```java
@SpringBootTest(classes = { BankingService.class, MethodSecurityConfig.class })
@Import(MockRepositoryConfig.class)   // repositories provided as mocks
class DepositAuthorizationTest {

    @Autowired BankingService bankingService;

    @Test
    @WithMockUser(roles = "account_holder")
    void deposit_asAccountHolder_isDenied() {
        assertThatThrownBy(() ->
            bankingService.deposit(1L, new BigDecimal("10.00")))
            .isInstanceOf(AccessDeniedException.class);
    }

    @Test
    @WithMockUser(roles = "teller")
    void deposit_asTeller_isAllowedThrough() {
        // repositories are mocked, so this asserts the rule allowed the call
        // through, not the persistence result
    }
}
```

`@WithMockUser(roles = "teller")` grants the `ROLE_teller` authority that
`hasRole('teller')` requires. Adjust the authority naming if your `@PreAuthorize`
expressions use scopes or a different convention. The 401 lives in the filter
chain (Tier 2); the 403 role decision lives on the service method
(method security). Testing each where it actually runs is the point.

### The error-body shape

The contract requires one error model (timestamp, status, error, message, path)
and forbids leaking internals. Assert its shape once, in a slice test, by
provoking a mapped exception from the mocked service and checking the JSON
fields with `jsonPath`. Confirm no stack trace or SQL appears in `message`.

---

## 6. Tier 3: integration tests against real infrastructure

These are slow, so keep them few and targeted. Each one proves something no
mock can: the mapping is real, the trigger fires, the transaction commits or
rolls back as a unit, the external failure maps correctly, the message is
actually published.

### Worked example 3: the audit trigger fires (Testcontainers-Oracle)

The JPA supplement calls the appearance of an `account_audit` row "the proof
that the trigger and the managed-entity update are wired correctly." This is the
single most important integration test to get working.

```java
@SpringBootTest
@ActiveProfiles("test")
class AuditTriggerIT extends OracleIntegrationTestBase {

    @Autowired BankingService bankingService;
    @Autowired JdbcTemplate jdbc;

    // Keep Kafka out of this test; the publisher is exercised separately.
    @MockBean TransactionStatsPublisher statsPublisher;

    @Test
    @WithMockUser(roles = "teller")
    void committedBalanceChange_writesOneAuditRow() {
        Long accountId = 1L;   // an ACTIVE seeded account
        Integer before = jdbc.queryForObject(
            "SELECT COUNT(*) FROM account_audit WHERE account_id = ?",
            Integer.class, accountId);

        bankingService.deposit(accountId, new BigDecimal("100.00"));

        Integer after = jdbc.queryForObject(
            "SELECT COUNT(*) FROM account_audit WHERE account_id = ?",
            Integer.class, accountId);
        assertThat(after).isEqualTo(before + 1);
    }
}
```

Three things to notice, each a gotcha in its own right:

> **Do not annotate this test `@Transactional`.** A test-managed transaction
> rolls back at the end, which undoes both the balance change and the audit row,
> so you could never observe the row. The trigger fires inside a transaction
> that must **commit**. Let the service commit; do not wrap the test.

> **Authenticate as a teller.** `deposit` is teller-only. Without a security
> context the `@PreAuthorize` throws `AccessDeniedException` and you never reach
> the trigger. `@WithMockUser(roles = "teller")` supplies the authority.

> **Mock the Kafka publisher here.** A successful deposit publishes to Kafka
> (BR-K1). Mocking the publisher keeps this test about the trigger and frees it
> from needing a broker. The publish itself is proven in its own test below.

### The remaining integration tests (patterns)

Build these the same way. They are complete in the held-back reference; the
shape is given here so you can write them yourself first.

**Transfer atomicity (BR-T1).** Call `transfer` for two of one customer's active
accounts, then assert two COMPLETED transactions, one `transfers` row, and both
balances updated. Then force a failure mid-transfer and assert nothing
persisted: all-or-nothing.

**Payment failure maps to 502 (BR-P3, BR-P4), with WireMock.** Start WireMock
with the JUnit 5 extension and point the payment client at it:

```java
@RegisterExtension
static WireMockExtension mock = WireMockExtension.newInstance()
    .options(wireMockConfig().dynamicPort())
    .build();
```

Stub the mock to return 503, call `pay` with `999.99` (the deterministic failure
hook, BR-P4), and assert the service raises the 502-mapped
`PaymentGatewayException`, a FAILED `PAYMENT` row exists, and the balance did not
change. Stub a 201 for the success case and assert the debit and the COMPLETED
row. Wire the mock's `baseUrl()` into the payment client with
`@DynamicPropertySource`.

**Kafka publish (BR-K1), with Testcontainers-Kafka.** Add a `KafkaContainer` to
your integration base and wire `spring.kafka.bootstrap-servers` from it. Commit a
deposit, then read the `transaction-stats` topic with a test consumer
(`KafkaTestUtils.getRecords`) and assert one record whose value is
`{"type":"DEPOSIT","amount":...}`. Assert a FAILED transaction publishes nothing,
and a transfer publishes two records (one `TRANSFER_OUT`, one `TRANSFER_IN`).

---

## 7. Turning the specs into a test plan

You already have the specification of what to test. The outcome matrix and the
six worked examples in the Business Rules supplement are your test list. Copy
this table into your repo and fill the last two columns as you go. "Enough" is
covering the rubric-relevant paths, not chasing a coverage percentage.

| Rule or case | Expected outcome | Tier | Test name | Done |
|--------------|------------------|------|-----------|------|
| BR-F1 insufficient funds | 422, FAILED row, no balance change, no Kafka | 1 | `withdraw_whenBalanceTooLow_...` | yes |
| BR-S1 inactive account | 422, no row | 1 | | |
| BR-A4 ownership | 403, nothing written | 1 | | |
| BR-A2 deposit role | 403 | 2 | | |
| BR-A1 no token | 401 | 2 | `accounts_withoutToken_returns401` | yes |
| Health public | 200, no token | 2 | `health_isPublic_...` | yes |
| BR-X1 audit trigger | audit row on commit | 3 | `committedBalanceChange_...` | yes |
| BR-T1 transfer atomicity | two legs plus transfer row, or full rollback | 3 | | |
| BR-P3 payment failure | 502, FAILED, no debit | 3 | | |
| BR-K1 publish | one message per COMPLETED, two per transfer | 3 | | |

Map worked examples 1 to 6 from the Business Rules supplement onto rows above;
each is already a concrete integration scenario.

---

## 8. Using GitHub Copilot to design and write tests

You are expected to use Copilot on the tests, and to be able to explain how your
AI-assisted code works. Use the same generate, review, refine workflow from the
Copilot lab.

### Prompt with the rule, the signature, and the expected status

Copilot writes a far better test when you give it the specification rather than a
vague ask. Paste the rule text and the method signature into a comment, then let
it draft:

```java
// BR-F1: withdrawing more than the balance must reject with a 422-mapped
// InsufficientFundsException, write one FAILED WITHDRAWAL row, change no
// balance, and publish nothing to Kafka.
// Service: BankingService.withdraw(Long accountId, BigDecimal amount)
// Write a Mockito unit test in Arrange-Act-Assert form.
```

Ask it to generate the parameterized cases straight from an outcome-matrix row
you paste in. It is good at the boilerplate: mock setup, captors, `jsonPath`
chains.

### Review critically: the test smells to catch

Copilot produces plausible tests that quietly prove nothing. Reject any test
that shows these:

- **Asserts nothing**, or only asserts the method ran without throwing.
- **Tests the mock, not the code**: stubs a repository to return a value and then
  asserts that same value, exercising no logic of yours.
- **Over-mocks**, mocking the class under test so the real rule never runs.
- **Happy path only**, skipping the failure branches that carry the rules.
- **Wrong exception or status**, for example expecting 400 where the contract
  says 422.
- **Hallucinated API**: methods on your service or repositories that do not
  exist. If it does not compile against your code, it was guessed.

### Refine so the test expresses the rule

A passing test is not the goal; a test that fails when the rule is wrong is. After
Copilot drafts a test, deliberately break the rule in the service and confirm the
test goes red. If it stays green, it was not testing the rule.

### What Copilot cannot know

It does not know your actual wiring, your trigger behavior, or your real status
mapping. It will confidently guess the container setup and the security
authorities. Treat anything touching Testcontainers, the audit trigger, or the
`@PreAuthorize` authorities as a draft you verify against a running test, not as
an answer.

### Keep a short record

The rubric asks how you used AI. Keep a few lines per component: what you asked
Copilot for, what you kept, what you rewrote and why. That record is itself a
deliverable.

---

## 9. Static analysis with SonarQube

Testing meets the security rubric here. After your tests are green, run a
SonarQube scan on the codebase and review the findings.

- Run the scan against your project and open the report.
- Triage: separate real issues (a hardcoded credential, an unhandled resource, a
  broken authorization check) from noise.
- Fix the real ones. Where you judge a finding a false positive, mark it with a
  justified suppression rather than deleting the rule, so a reviewer can see your
  reasoning.
- Your **test code is scanned too**. Do not leave secrets or dead code in tests.

Be ready to speak to what the scan found and what you did about it.

---

## 10. Preparing the testing story for the presentation

The checklist requires one transaction demonstrated end to end, from the SPA
through the BFF, BankService, database, and Kafka, including a failure path. The
most reliable way to have that ready is to already have an integration test that
walks it.

- Pick a path that touches every component: a customer transfer, or a payment
  that succeeds, plus the matching failure (insufficient funds, or the `999.99`
  payment rejection).
- A red-then-green moment can be worth showing: break a rule, show the test
  catch it, restore it.
- Every team member should be able to speak to some part of the suite. Divide
  the tiers across the team so no single person owns all of testing.

---

## 11. Quick reference

### Test dependency checklist

- [ ] `spring-boot-starter-test`
- [ ] `spring-security-test`
- [ ] `spring-kafka-test`
- [ ] Testcontainers `junit-jupiter`, `oracle-xe`, `kafka` (via the BOM)
- [ ] `wiremock-standalone:3.9.1`

### Outcome-matrix coverage checklist

- [ ] Every COMPLETED success path (deposit, withdrawal, transfer, payment)
- [ ] 401, 403 (role), 403 (ownership), 400, 404
- [ ] 422 inactive (no row) and 422 insufficient funds (FAILED row)
- [ ] 502 external payment failure (FAILED row, no debit)
- [ ] Audit row appears on a committed balance change
- [ ] Kafka: one per COMPLETED, two per transfer, none for FAILED

### Copilot review checklist

- [ ] The test asserts an outcome, not just "did not throw"
- [ ] It exercises your code, not the mock
- [ ] It fails when I break the rule
- [ ] The status code matches the contract
- [ ] It compiles against my real API

### Common failure diagnoses

| Symptom | Likely cause |
|---------|--------------|
| Testcontainers Oracle will not start | Docker not running, or first pull still downloading the image |
| Init script errors on `CONNECT` or `ALTER SESSION` | SQL\*Plus directives in a JDBC init script; use a plain-SQL DDL |
| Audit row never appears | Test is `@Transactional` and rolled back, or the balance change was a native bulk update that bypassed the persistence context |
| Deposit test fails with `AccessDeniedException` | No teller authority in the security context; add `@WithMockUser(roles = "teller")` |
| `@WebMvcTest` returns 403 everywhere unexpectedly | Real `SecurityConfig` not imported, or default security applied |
| Kafka test flakes | Consumer polled before the record arrived; use `KafkaTestUtils` with a poll timeout |

---

## Checkpoints

Answer these as a team; they map to what the presentation may ask.

1. Why can the insufficient-funds rule be tested with no database running, while
   the audit-trigger rule cannot?
2. The 401 test lives in the web slice and the 403 wrong-role test needs the real
   service. Explain, in terms of where each rule is enforced, why they cannot
   swap tiers.
3. Why must the audit-trigger integration test avoid `@Transactional`?
4. Your payment success test debits an account and your payment failure test does
   not. Which single rule (by identifier) makes the failure case leave the
   balance untouched, and where is it checked relative to the external call?
5. Your team chose at-least-once delivery for Kafka. What would a duplicate
   `(type, amount)` do to the statistics, and why is that acceptable here?

---

### End
