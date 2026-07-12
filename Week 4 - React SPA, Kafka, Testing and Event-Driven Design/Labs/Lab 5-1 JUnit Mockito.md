#  Lab 5.1 -- Unit Testing with JUnit 5 and Mockito

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 10 - Testing, SAST, and Security Hardening
> **Estimated time:** 75-90 minutes

---

## Overview

In this lab you will write unit tests for two Java classes: a self-contained `TransferService` that has no external dependencies, and a `TransferProcessor` that depends on an `AccountRepository`. The first part exercises JUnit 5 and AssertJ on pure logic. The second part adds Mockito to handle the collaborator.

The lab is split deliberately. Most students reading about JUnit and Mockito at the same time end up confused about which framework is doing what. Doing JUnit alone first, then adding Mockito, makes the boundary between the two crystal clear: JUnit runs the tests, AssertJ does the assertions, Mockito stands in for collaborators we don't want to use directly.

The starter project is a small standalone Maven project, separate from the bankbff/bankserver projects from Module 8. There is no Spring, no controllers, no HTTP. This lab is exclusively about the unit-test mechanics.

By the end of this lab you will be able to:

- Write JUnit 5 test methods following the Arrange-Act-Assert pattern
- Use AssertJ's fluent assertions and `assertThatThrownBy` for exception testing
- Apply `@DisplayName` for human-readable test reports
- Write parameterized tests with `@CsvSource`
- Use Mockito's `@Mock`, `@InjectMocks`, `when().thenReturn()`, and `verify()`
- Capture method arguments with `ArgumentCaptor` for richer assertions
- Recognize when to use a mocked collaborator vs. a real collaborator in a test

---

## Before You Start

You will need:

- **IntelliJ IDEA** (Community or Ultimate)
- **JDK 17 or 21** -- the project is configured for Java 17
- **Maven** -- bundled with IntelliJ; no separate installation needed
- The `banking-tests-lab-starter.zip` file provided with this lab

The lab does NOT require:

- The Module 8 projects (bankbff, bankserver, auth-server)
- Docker
- Any running server or database

### Importing the starter project

1. Unzip `banking-tests-lab-starter.zip` to a working directory of your choice
2. In IntelliJ, choose **File** -> **Open**, then select the unzipped `banking-tests-lab` folder
3. IntelliJ detects the `pom.xml` and offers to import as a Maven project. Accept.
4. Wait for IntelliJ to download dependencies and index the project. The first time this can take a minute or two.
5. Once indexing finishes, open `src/test/java/com/example/banking/TransferServiceTest.java`. You should see the test class skeleton with `@BeforeEach`, `@Test` annotations available, and no compile errors.

If you see compile errors after import, force a Maven reload: right-click `pom.xml` -> **Maven** -> **Reload Project**. If errors persist, ask the instructor.

### Files you will modify in this lab

| File | Purpose | Part |
|---|---|---|
| `src/test/java/com/example/banking/TransferServiceTest.java` | JUnit + AssertJ tests | Part 1 |
| `src/test/java/com/example/banking/TransferProcessorTest.java` | JUnit + AssertJ + Mockito tests | Part 2 |

Both files are skeletons: imports are in place, the class is declared, and TODO comments mark where each test goes. You will write the test method bodies.

---

## What's in the Starter Project

Before writing tests, take five minutes to read through the production code. There are seven Java files under `src/main/java/com/example/banking`. The most important ones:

**`TransferService`** -- pure-logic service. Two public methods:

- `transfer(source, destination, amount)`: validates the request, then mutates the two accounts in place to apply the transfer
- `calculateFee(amount)`: returns the fee for a transfer of the given amount, with a tiered fee structure

This class has no external dependencies. It is the unit under test for Part 1.

**`TransferProcessor`** -- orchestration class that uses an `AccountRepository`. One public method:

- `processTransfer(sourceAccountNumber, destinationAccountNumber, amount)`: fetches both accounts from the repository, delegates to `TransferService.transfer(...)` to perform the actual transfer logic, then saves both accounts back

This class is the unit under test for Part 2. Because it depends on `AccountRepository`, testing it in isolation requires mocking the repository.

**`AccountRepository`** -- interface for fetching and saving accounts. In a real application this would be a Spring Data JPA repository talking to a database. For this lab it is just an interface that we mock.

**`Account`, `AccountStatus`, `AccountFrozenException`, `InsufficientFundsException`, `AccountNotFoundException`** -- supporting domain classes. Read these briefly so you know what's available.

---

## Part 1 -- JUnit and AssertJ

**Estimated time:** 35-40 minutes
**Topics covered:** test method anatomy, Arrange-Act-Assert, AssertJ basic and exception assertions, `@DisplayName`, parameterized tests
**File modified:** `src/test/java/com/example/banking/TransferServiceTest.java`

### Context

The starter `TransferServiceTest` has the class skeleton, the imports, and a `@BeforeEach` method that constructs a fresh `TransferService` before each test. Inside the class are five TODO comments. Each TODO describes one test you will write. Take them in order.

A reminder on the structure every test will follow:

```java
@Test
@DisplayName("a sentence describing the behavior under test")
void methodNameDescribingTheBehavior() {
    // Arrange: set up the input state
    Account source = ...;
    Account destination = ...;

    // Act: call the one method under test
    transferService.transfer(source, destination, ...);

    // Assert: verify the outcome
    assertThat(...).isEqualTo(...);
}
```

For exception-throwing tests, the Act and Assert combine into a single AssertJ chain:

```java
assertThatThrownBy(() -> someCallThatShouldThrow())
    .isInstanceOf(SomeException.class)
    .hasMessageContaining("expected substring");
```

### Task 1.1 -- transfer reduces the source account's balance

Find TODO 1.1 in `TransferServiceTest.java` and replace it with a test method.

The test should:

1. Create an active source account with account number "ACC-001" and balance $100.00
2. Create an active destination account with account number "ACC-002" and balance $0.00
3. Call `transferService.transfer(source, destination, new BigDecimal("30.00"))`
4. Assert that `source.getBalance()` is now $70.00

Here is a complete template you can adapt:

```java
@Test
@DisplayName("transfer reduces the source account's balance")
void transferReducesSourceBalance() {
    Account source = new Account("ACC-001", new BigDecimal("100.00"));
    Account destination = new Account("ACC-002", new BigDecimal("0.00"));

    transferService.transfer(source, destination, new BigDecimal("30.00"));

    assertThat(source.getBalance()).isEqualByComparingTo("70.00");
}
```

Note the use of `isEqualByComparingTo("70.00")` rather than `isEqualTo(new BigDecimal("70.00"))`. The two BigDecimal values `70.00` and `70` are not equal under `equals()` because of scale differences, but they ARE equal under `compareTo()`. Use `isEqualByComparingTo` for BigDecimal comparisons; it's the safer default.

Run the test by clicking the green play button in the gutter next to the method name. The test should pass.

### Task 1.2 -- transfer increases the destination account's balance

Find TODO 1.2 and add a similar test that asserts on the destination's balance instead. Same setup, same act, different assertion target.

This test gives you practice with the structure. The assertion is:

```java
assertThat(destination.getBalance()).isEqualByComparingTo("30.00");
```

Notice that we wrote a separate test for the destination balance rather than asserting both source and destination in the same test. This is the "one logical assertion per test" pattern from Unit 2 -- each test verifies one specific behavior.

### Task 1.3 -- transfer rejects amounts greater than the source balance

Find TODO 1.3 and add a test for an error case.

The setup: an active source account with $50.00, an active destination with $0.00. The act: call `transfer` with an amount of $100.00. The assertion: this should throw `InsufficientFundsException` with a message containing the source account number.

Use `assertThatThrownBy`:

```java
assertThatThrownBy(
        () -> transferService.transfer(source, destination, new BigDecimal("100.00")))
    .isInstanceOf(InsufficientFundsException.class)
    .hasMessageContaining("ACC-001");
```

The lambda `() -> ...` defers the call until AssertJ is ready to capture the exception. Without the lambda, the exception would be thrown immediately when the line executed and the test would fail before reaching the assertion.

### Task 1.4 -- transfer rejects when the source account is frozen

Find TODO 1.4 and add a test for the frozen-account case.

The setup: a source account constructed with status `AccountStatus.FROZEN`:

```java
Account source = new Account("ACC-001", new BigDecimal("100.00"), AccountStatus.FROZEN);
```

The act + assert: any transfer call should throw `AccountFrozenException`. The message should contain both "source" (the role of the offending account) and "FROZEN" (the status).

```java
assertThatThrownBy(...)
    .isInstanceOf(AccountFrozenException.class)
    .hasMessageContaining("source")
    .hasMessageContaining("FROZEN");
```

Multiple `.hasMessageContaining(...)` chained on the same assertion all have to pass. If any substring is missing, the test fails.

### Task 1.5 -- parameterized test for the fee tiers

Find TODO 1.5 and add a parameterized test for `calculateFee`.

A parameterized test runs the same test method multiple times with different inputs. The annotation pair is `@ParameterizedTest` (instead of `@Test`) and a source annotation that supplies the inputs (we'll use `@CsvSource`).

The fee tiers in `TransferService.calculateFee` are:

- amount up to $100 -> fee $0.50
- amount up to $1000 -> fee $1.50
- amount up to $5000 -> fee $5.00
- amount above $5000 -> 0.1% of amount

Test these four representative inputs:

| Input amount | Expected fee |
|---|---|
| 50 | 0.50 |
| 500 | 1.50 |
| 2500 | 5.00 |
| 10000 | 10.00 (which is 10000 * 0.001 = 10.00) |

The test method:

```java
@ParameterizedTest
@CsvSource({
    "50,    0.50",
    "500,   1.50",
    "2500,  5.00",
    "10000, 10.00"
})
@DisplayName("calculateFee returns the right fee for each tier")
void calculateFeeReturnsCorrectFeeForEachTier(BigDecimal amount, BigDecimal expectedFee) {
    BigDecimal fee = transferService.calculateFee(amount);

    assertThat(fee).isEqualByComparingTo(expectedFee);
}
```

You'll need two new imports:

```java
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
```

IntelliJ should auto-import them once you reference the annotations. If not, position the cursor on the red annotation name and press Alt+Enter.

When you run this test, IntelliJ shows it as one parent test with four child invocations. Each row of the CSV becomes one invocation. If three pass and one fails, you see exactly which inputs caused the failure -- which is dramatically more useful than wrapping a loop inside a single test method.

### Verify Part 1

Run the entire `TransferServiceTest` class by right-clicking the class name in the editor and choosing **Run 'TransferServiceTest'**. All five tests (eight invocations including the parameterized cases) should pass. The IntelliJ test runner shows each test by its `@DisplayName`, producing a readable tree.

If any test fails, read the AssertJ error message carefully. AssertJ's failure messages are designed to diagnose -- they include the expected and actual values, the call site, and often a hint at what went wrong. Most failures students hit at this stage are typos in account numbers or amounts.

---

## Part 2 -- Adding Mockito

**Estimated time:** 40-50 minutes
**Topics covered:** Mockito setup with `@ExtendWith` and `@Mock`, `@InjectMocks`, stubbing with `when().thenReturn()`, verifying with `verify()`, capturing arguments with `ArgumentCaptor`
**File modified:** `src/test/java/com/example/banking/TransferProcessorTest.java`

### Context

`TransferProcessor` depends on two collaborators: an `AccountRepository` (an interface representing some kind of persistence) and a `TransferService` (the same class you tested in Part 1). To test `TransferProcessor` in isolation, both collaborators get mocked.

The starter `TransferProcessorTest` class has all the Mockito-related declarations already in place:

```java
@ExtendWith(MockitoExtension.class)
@DisplayName("Transfer processor")
class TransferProcessorTest {

    @Mock
    private AccountRepository accountRepository;

    @Mock
    private TransferService transferService;

    @InjectMocks
    private TransferProcessor transferProcessor;
```

What each line does:

- `@ExtendWith(MockitoExtension.class)` activates Mockito's JUnit 5 integration. Without it, `@Mock` and `@InjectMocks` do nothing.
- `@Mock` on a field tells Mockito to create a fresh mock object before each test. The mock is a stand-in for the real type with all methods returning their type's default value (null for objects, false for booleans, empty Optional for Optional, etc.).
- `@InjectMocks` constructs the unit under test and injects the matching mocks into its constructor parameters. `TransferProcessor`'s constructor takes `AccountRepository` and `TransferService`; Mockito wires in the two `@Mock`-annotated fields automatically.

You don't need a `@BeforeEach` setup method. Mockito does the wiring before each test runs.

### Task 2.1 -- processTransfer fetches both accounts from the repository

Find TODO 2.1 and add a test that verifies `processTransfer` calls `findById` for both account numbers.

The pattern for Mockito-based tests:

1. **Stub** the mock's behavior with `when(...).thenReturn(...)` to control what the mock returns when called
2. **Act** by calling the method under test
3. **Verify** with `verify(mock).someMethod(args)` that the expected interactions happened

For this test:

```java
@Test
@DisplayName("processTransfer fetches both accounts from the repository")
void processTransferFetchesBothAccountsFromRepository() {
    Account source = new Account("ACC-001", new BigDecimal("100.00"));
    Account destination = new Account("ACC-002", new BigDecimal("0.00"));
    when(accountRepository.findById("ACC-001")).thenReturn(Optional.of(source));
    when(accountRepository.findById("ACC-002")).thenReturn(Optional.of(destination));

    transferProcessor.processTransfer("ACC-001", "ACC-002", new BigDecimal("30.00"));

    verify(accountRepository).findById("ACC-001");
    verify(accountRepository).findById("ACC-002");
}
```

A few details worth noting:

- The two `when(...).thenReturn(...)` calls program the mock to return real `Account` objects when those specific account numbers are looked up. Without these stubs, the mock would return `Optional.empty()` (the default for Optional), and `processTransfer` would throw `AccountNotFoundException`.

- We don't stub `transferService.transfer(...)` because it's a void method AND because we don't care about its return value here. The mock's default is to do nothing for void methods, which is fine for this test.

- `verify(accountRepository).findById("ACC-001")` asserts that the method was called exactly once with that argument. If `findById` was never called with "ACC-001", or was called multiple times, the verification fails.

Run the test. It should pass.

### Task 2.2 -- processTransfer saves both accounts after a successful transfer

Find TODO 2.2 and add a test that asserts `save` was called twice.

The setup is similar to Task 2.1:

```java
@Test
@DisplayName("processTransfer saves both accounts after a successful transfer")
void processTransferSavesBothAccounts() {
    Account source = new Account("ACC-001", new BigDecimal("100.00"));
    Account destination = new Account("ACC-002", new BigDecimal("0.00"));
    when(accountRepository.findById("ACC-001")).thenReturn(Optional.of(source));
    when(accountRepository.findById("ACC-002")).thenReturn(Optional.of(destination));

    transferProcessor.processTransfer("ACC-001", "ACC-002", new BigDecimal("30.00"));

    verify(accountRepository, times(2)).save(any(Account.class));
}
```

Three new pieces:

- `times(2)` modifies the verification to "expected exactly 2 calls" instead of the default 1
- `any(Account.class)` is an argument matcher that matches any Account argument; we don't care which specific accounts at this point in the test
- The static import for `times` is `org.mockito.Mockito.times`; for `any` it's `org.mockito.ArgumentMatchers.any`. Both are already imported in the starter.

The test verifies `save` was called twice (once per account) without inspecting which specific accounts were saved. Test 2.4 will use ArgumentCaptor for that finer-grained inspection.

### Task 2.3 -- processTransfer throws AccountNotFoundException when source is missing

Find TODO 2.3 and add a test for the unhappy path where the source account does not exist.

```java
@Test
@DisplayName("processTransfer throws AccountNotFoundException when source is missing")
void processTransferThrowsWhenSourceIsMissing() {
    when(accountRepository.findById("ACC-MISSING")).thenReturn(Optional.empty());

    assertThatThrownBy(
            () -> transferProcessor.processTransfer(
                    "ACC-MISSING", "ACC-002", new BigDecimal("30.00")))
        .isInstanceOf(AccountNotFoundException.class)
        .hasMessageContaining("ACC-MISSING");

    verify(accountRepository, never()).save(any(Account.class));
}
```

Two things to note:

- We only stub `findById("ACC-MISSING")` to return `Optional.empty()`. We do NOT need to stub `findById("ACC-002")` because the code throws before ever reaching that lookup.
- After the assertion, we add `verify(accountRepository, never()).save(any(Account.class))`. This asserts that `save` was never called. Since the method threw before reaching the save step, no save should have happened. This is the kind of "make sure nothing bad got persisted" check that's often overlooked but matters in error-path testing.

The static import for `never` is `org.mockito.Mockito.never`. Already in the starter imports.

### Task 2.4 -- processTransfer saves the source account with the updated balance

Find TODO 2.4 and add a test that uses `ArgumentCaptor` to verify what was actually passed to `save`.

This test is more involved than the others because we want to verify the **state** of the saved Account, not just that some save call happened. There's also a wrinkle worth understanding: in tests 2.1-2.3 we mocked `TransferService`, which means the transfer logic doesn't actually run -- the accounts' balances never change. For this test we want the real `TransferService` to do its work, so we replace the mock with a real instance.

```java
@Test
@DisplayName("processTransfer saves the source account with the updated balance")
void processTransferSavesSourceWithUpdatedBalance() {
    // Build a processor with a REAL TransferService so balances actually update
    TransferService realTransferService = new TransferService();
    TransferProcessor processor = new TransferProcessor(accountRepository, realTransferService);

    Account source = new Account("ACC-001", new BigDecimal("100.00"));
    Account destination = new Account("ACC-002", new BigDecimal("0.00"));
    when(accountRepository.findById("ACC-001")).thenReturn(Optional.of(source));
    when(accountRepository.findById("ACC-002")).thenReturn(Optional.of(destination));

    processor.processTransfer("ACC-001", "ACC-002", new BigDecimal("30.00"));

    ArgumentCaptor<Account> captor = ArgumentCaptor.forClass(Account.class);
    verify(accountRepository, times(2)).save(captor.capture());

    List<Account> saved = captor.getAllValues();
    Account savedSource = saved.stream()
            .filter(a -> a.getAccountNumber().equals("ACC-001"))
            .findFirst()
            .orElseThrow();
    assertThat(savedSource.getBalance()).isEqualByComparingTo("70.00");
}
```

Walk through what's happening:

- We construct a separate `TransferProcessor` (called `processor`) using a real `TransferService` and the still-mocked `accountRepository`. The `transferProcessor` field on the test class is unused for this test.

- The `ArgumentCaptor<Account>` is set up to capture every `Account` passed to `save()`.

- `verify(accountRepository, times(2)).save(captor.capture())` does the verification AND captures both Account arguments.

- `captor.getAllValues()` returns a `List<Account>` containing every captured argument in call order. `getValue()` returns only the most recent capture; for this test we want all of them.

- We use a stream to find the saved Account whose account number is "ACC-001". This is more robust than relying on call order, which could change if the implementation switches the order of saves.

- The final assertion confirms that the source account was saved with a balance of $70.00 ($100 - $30).

A new import is needed:

```java
import java.util.List;
```

### Verify Part 2

Run the entire `TransferProcessorTest` class. All four tests should pass. Combined with Part 1, you should have nine green tests across the two files.

---

## Reflection Questions

In a new file `lab-5.1-notes.md` in the project root, answer these questions:

1. In Test 1.5 (the parameterized fee test), each row of the `@CsvSource` becomes one test invocation in the test report. What is the advantage of this over wrapping a loop inside one regular `@Test` method that iterates the same inputs?

2. In Test 2.4 you constructed a `TransferProcessor` manually with a real `TransferService`, instead of using the `@InjectMocks`-constructed processor. Why was this necessary for that specific test? What would have happened if you had used the `@InjectMocks` processor with the mocked `TransferService`?

3. In Test 2.3, after asserting the exception is thrown, the test also asserts `verify(accountRepository, never()).save(any(Account.class))`. Why is this second assertion important? What kind of bug would only the second assertion catch?

4. Look at the four Mockito tests you wrote. Three of them use `times(...)`, `never()`, or the default verify-once. Test 2.4 uses `times(2)`. Could Test 2.4 have used `atLeastOnce()` instead? What would change about what the test guarantees?

5. The `TransferService` from Part 1 has no external collaborators, so we tested it with plain JUnit + AssertJ. The `TransferProcessor` from Part 2 has collaborators, so we needed Mockito. In your own words, what is the rule of thumb for deciding whether a class needs Mockito to test?

---

## What You Have Built

You now have nine working unit tests across two test classes, exercising both styles of unit testing you'll see in real code:

- **Pure unit tests** (Part 1): the unit under test has no collaborators. Tests are simple Arrange-Act-Assert; the only frameworks involved are JUnit (the runner) and AssertJ (the assertions).

- **Mock-collaborator tests** (Part 2): the unit under test has collaborators that we don't want to use directly in tests. Mockito stands in for the collaborators, letting us control their behavior and verify how the unit interacts with them.

The same patterns apply when you write tests for Spring Boot service classes. Service classes that are pure logic look like Part 1. Service classes that depend on repositories, downstream HTTP clients, or other beans look like Part 2.

For your capstone, expect to write both kinds of tests. Pure logic should be tested with plain JUnit + AssertJ. Service classes with collaborators should be tested with Mockito.

---

## What's Next

- **Lab 5.2:** Spring Boot integration testing -- testing controllers with `@WebMvcTest`, including OAuth-authenticated cases
- **Unit 4 already covered the concepts;** Lab 5.2 applies them
- **Capstone reminder:** unit tests with both styles (pure and mocked) are expected on the capstone. The skills from this lab are direct preparation.
