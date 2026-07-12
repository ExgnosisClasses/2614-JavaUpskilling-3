#  Lab 5.1 -- Solutions and Checkpoint Answers

> **Course:** MD282 - Java Full-Stack Development
> **Purpose:** This file contains complete code for every test you wrote in Lab 5.1
> and written answers to every Reflection question. Use it to verify your work
> after attempting each task yourself. Reading the solution before attempting
> the task defeats the purpose of the exercise.

---

## How to Use This File

Each section below corresponds to a task in the lab. The complete final
contents of each test method are shown so you can confirm your version
matches. The reflection-question answers serve as discussion prompts for the
class debrief.

The complete solution project is also provided as `banking-tests-lab-solution.zip`
if you want to import it into IntelliJ and run all tests at once.

### Files modified in this lab

| File | Tests | Part |
|---|---|---|
| `src/test/java/com/example/banking/TransferServiceTest.java` | 5 tests | Part 1 |
| `src/test/java/com/example/banking/TransferProcessorTest.java` | 4 tests | Part 2 |

---

## Part 1 -- Complete TransferServiceTest.java

```java
package com.example.banking;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@DisplayName("Transfer service")
class TransferServiceTest {

    private TransferService transferService;

    @BeforeEach
    void setUp() {
        transferService = new TransferService();
    }

    @Test
    @DisplayName("transfer reduces the source account's balance")
    void transferReducesSourceBalance() {
        Account source = new Account("ACC-001", new BigDecimal("100.00"));
        Account destination = new Account("ACC-002", new BigDecimal("0.00"));

        transferService.transfer(source, destination, new BigDecimal("30.00"));

        assertThat(source.getBalance()).isEqualByComparingTo("70.00");
    }

    @Test
    @DisplayName("transfer increases the destination account's balance")
    void transferIncreasesDestinationBalance() {
        Account source = new Account("ACC-001", new BigDecimal("100.00"));
        Account destination = new Account("ACC-002", new BigDecimal("0.00"));

        transferService.transfer(source, destination, new BigDecimal("30.00"));

        assertThat(destination.getBalance()).isEqualByComparingTo("30.00");
    }

    @Test
    @DisplayName("transfer rejects amounts greater than the source balance")
    void transferRejectsAmountGreaterThanSourceBalance() {
        Account source = new Account("ACC-001", new BigDecimal("50.00"));
        Account destination = new Account("ACC-002", new BigDecimal("0.00"));

        assertThatThrownBy(
                () -> transferService.transfer(source, destination, new BigDecimal("100.00")))
            .isInstanceOf(InsufficientFundsException.class)
            .hasMessageContaining("ACC-001");
    }

    @Test
    @DisplayName("transfer rejects when the source account is frozen")
    void transferRejectsWhenSourceIsFrozen() {
        Account source = new Account("ACC-001", new BigDecimal("100.00"), AccountStatus.FROZEN);
        Account destination = new Account("ACC-002", new BigDecimal("0.00"));

        assertThatThrownBy(
                () -> transferService.transfer(source, destination, new BigDecimal("30.00")))
            .isInstanceOf(AccountFrozenException.class)
            .hasMessageContaining("source")
            .hasMessageContaining("FROZEN");
    }

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
}
```

### Notes on Part 1 solutions

**Why `isEqualByComparingTo` instead of `isEqualTo` for BigDecimal.**
`new BigDecimal("70.00")` and `new BigDecimal("70")` are NOT equal under
`equals()` because the scale differs (2 decimal places vs. 0). They ARE equal
under `compareTo()`. AssertJ's `isEqualByComparingTo` uses `compareTo`, which
is the right semantics for monetary comparisons. Using `isEqualTo` here would
cause confusing failures whenever `subtract`, `add`, or `multiply` produced
a value with a different scale than the literal we were comparing against.

**Why the lambda in `assertThatThrownBy`.**
The lambda `() -> transferService.transfer(...)` defers execution. Without it,
the exception would be thrown when the line of code ran, before AssertJ had a
chance to capture it. The lambda lets AssertJ wrap the call in a try/catch and
inspect what was thrown.

**Why we wrote separate tests for source balance and destination balance.**
Each test verifies one logical outcome. A test that asserts both balances
mixes two concerns; if the source assertion fails, you don't see whether the
destination assertion would have passed. Splitting them gives you precise
failure information.

**Why we used `@CsvSource` for the fee test and not `@ValueSource`.**
`@ValueSource` supports only one parameter per invocation. The fee test needs
two parameters (amount and expected fee), so `@CsvSource` is the right choice.
For more complex inputs (custom objects, computed values), `@MethodSource` is
the next step up.

---

## Part 2 -- Complete TransferProcessorTest.java

```java
package com.example.banking;

import com.example.banking.repository.AccountRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("Transfer processor")
class TransferProcessorTest {

    @Mock
    private AccountRepository accountRepository;

    @Mock
    private TransferService transferService;

    @InjectMocks
    private TransferProcessor transferProcessor;

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

    @Test
    @DisplayName("processTransfer saves the source account with the updated balance")
    void processTransferSavesSourceWithUpdatedBalance() {
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
}
```

### Notes on Part 2 solutions

**Why `@ExtendWith(MockitoExtension.class)`.**
This annotation activates Mockito's JUnit 5 integration. Without it, `@Mock`
and `@InjectMocks` produce null fields and your test fails immediately with a
NullPointerException. The extension wires up Mockito's lifecycle: create
mocks before each test, reset between tests, validate stubbing strictness.

**Why `@InjectMocks` is convenient but not magic.**
`@InjectMocks` instructs Mockito to construct the unit under test using the
test's other mocks. For TransferProcessor, the constructor takes
`AccountRepository` and `TransferService`, both of which are `@Mock` fields.
Mockito picks the matching constructor, supplies the mocks, and stores the
result in the `@InjectMocks` field. If a constructor parameter has no
matching mock, Mockito leaves it null without warning, which can produce
confusing NullPointerException at test time. Always make sure every
constructor parameter has a matching mock.

**Why Test 2.3 doesn't stub `findById("ACC-002")`.**
The test exercises the path where the source account is missing. `findById`
for "ACC-MISSING" returns empty, the orElseThrow fires, and the method
throws before reaching the second `findById` call. Stubbing the second call
would be wasted setup. Mockito tolerates unstubbed methods (they return
defaults), so leaving them out is fine and signals intent: "I expect the
code path NOT to reach here."

In stricter Mockito modes (`Mockito.STRICT_STUBS`), unused stubs throw an
error at the end of the test. The default mode used by `MockitoExtension`
is moderately strict and warns about unused stubs, which is why we don't
stub things we don't need.

**Why Test 2.4 builds the processor manually.**
Tests 2.1-2.3 use the `@InjectMocks` processor with a mocked TransferService.
The mocked TransferService does nothing on its `transfer` method (the default
for void methods). That's fine for those tests because they don't depend on
the balances actually changing.

Test 2.4 needs the balances to change so the `save` calls receive accounts
with the updated balances. With a mocked TransferService, the accounts would
still have their original balances when saved, and the assertion on $70.00
would fail.

The fix is to bypass `@InjectMocks` for this one test and construct the
processor with a real TransferService. The mocked AccountRepository is still
used. This is a deliberate mix of mock and real collaborators -- a "London
school" test that's leaning slightly toward "Detroit school" for one specific
collaborator.

**Why `getAllValues()` instead of `getValue()`.**
`getValue()` returns only the most recent captured argument. With two save
calls, that would give us either the source or the destination depending on
implementation order -- and we don't want our test to be order-dependent.
`getAllValues()` returns the full list, and we use a stream to find the
specific account we care about by its account number. This is robust to
implementation changes that reorder the saves.

---

## Reflection Questions (lab-5.1-notes.md answers)

### Question 1: In Test 1.5 (the parameterized fee test), each row of the `@CsvSource` becomes one test invocation in the test report. What is the advantage of this over wrapping a loop inside one regular `@Test` method that iterates the same inputs?

The most concrete advantage is **failure visibility**. With a parameterized
test, each input is reported separately in the test runner. If the input
"2500, 5.00" causes a failure, the test report shows specifically:

```
calculateFee returns the right fee for each tier(2500, 5.00) FAILED
```

You see exactly which inputs failed. The other three pass quietly.

With a loop inside a single `@Test` method, the first failed assertion stops
the test. You see "calculateFeeForEachTier FAILED" with details about the
specific iteration where it failed, but you don't know whether subsequent
iterations would have failed too. To find out, you'd have to fix the first
failure and re-run.

Other advantages:

- **Parallelization.** Test runners can run different parameterized
  invocations in parallel, while a loop inside one test runs serially.
- **Documentation.** Reading `@CsvSource` shows you the test cases at a
  glance. Reading a loop body requires mentally executing the loop.
- **Debuggability.** You can rerun a single failing parameterized invocation
  in IntelliJ without rerunning the whole test method.

The pattern is broadly applicable. Anywhere you find yourself writing
"for (input : inputs) { ... assertions ... }" in a test, consider whether
parameterization would be a better fit.

### Question 2: In Test 2.4 you constructed a `TransferProcessor` manually with a real `TransferService`, instead of using the `@InjectMocks`-constructed processor. Why was this necessary for that specific test? What would have happened if you had used the `@InjectMocks` processor with the mocked `TransferService`?

The `@InjectMocks` processor was constructed with the mocked TransferService.
A mocked TransferService's `transfer` method does nothing -- the default
behavior for void methods on Mockito mocks is to not run the real
implementation.

This means: the source account's balance would remain at $100, and the
destination's balance would remain at $0. The processor would still call
`save(source)` and `save(destination)`, but the saved accounts would have
their **original** balances, not the updated ones.

The assertion in the test asserts that the saved source has a balance of
$70.00. With a mocked TransferService, the saved source still has $100.00.
The test would fail with an assertion error like "expected: 70.00, actual:
100.00".

To make the test work, the real TransferService logic has to run so that
the balances actually change. We achieve this by constructing a separate
processor with a real TransferService. The mocked AccountRepository is still
used (we want to capture the save calls), but the TransferService is real.

This pattern -- mocking some collaborators while using real instances of
others -- is common in real codebases. It works well when one collaborator's
behavior is fundamentally part of the test (we want to verify the real
balance arithmetic) and another's is incidental (we just want to capture
what got persisted).

### Question 3: In Test 2.3, after asserting the exception is thrown, the test also asserts `verify(accountRepository, never()).save(any(Account.class))`. Why is this second assertion important? What kind of bug would only the second assertion catch?

The exception assertion confirms that the right thing was thrown. It does
NOT confirm that nothing else happened before the exception was thrown.

The `verify(...never()).save(...)` assertion confirms that save was never
called. This catches a specific class of bug:

**Bug scenario:** imagine a future developer changes `processTransfer` to
save the source account FIRST, then look up the destination. The flow
becomes:

```java
Account source = accountRepository.findById(sourceAccountNumber).orElseThrow(...);
accountRepository.save(source);  // saves with original balance
Account destination = accountRepository.findById(destinationAccountNumber).orElseThrow(...);
accountRepository.save(destination);
transferService.transfer(source, destination, amount);  // never reached if dest is missing
```

This is a buggy refactor that creates inconsistent state on the destination-
missing path: the source got saved but the transfer never happened.

The exception assertion alone would still pass (the destination is missing,
the orElseThrow fires, the right exception is thrown). But the
`verify(...never())...save(...)` assertion fails, because save WAS called
once (with the source) before the failure.

This is the kind of subtle bug that can escape unit tests if you only assert
on the happy-path outcome. By asserting both "the right exception happened"
AND "no unwanted side effects happened", the test covers both halves of
correct error-path behavior.

The general principle: error-path tests should verify what DIDN'T happen as
well as what did. Did the system roll back? Did nothing get persisted? Did
no notification get sent? These are all `verify(...never()...)` assertions
that catch bugs in error handling.

### Question 4: Look at the four Mockito tests you wrote. Three of them use `times(...)`, `never()`, or the default verify-once. Test 2.4 uses `times(2)`. Could Test 2.4 have used `atLeastOnce()` instead? What would change about what the test guarantees?

`atLeastOnce()` is more permissive than `times(2)`. It accepts ANY number of
calls greater than zero -- 1, 2, 3, 100, all pass.

If Test 2.4 used `atLeastOnce()`, the test would still pass when save is
called twice (once per account). It would ALSO pass if save were called
once (only the source, missed the destination), three times (the destination
got saved twice for some reason), or twenty times (a runaway loop in a
buggy refactor).

The test would fail to detect the "save called fewer times than expected"
class of bugs. If a future refactor accidentally removed the
`accountRepository.save(destination)` line, the test would still pass --
because save was called at least once, satisfying the looser assertion.

`times(2)` is stricter and catches that bug. It specifies the exact expected
call count, so any deviation -- too few OR too many -- fails the test.

The general principle: use the strictest verification that's correct for
your test. `times(N)` is most strict. `atLeast`, `atMost` are looser. 
`atLeastOnce` is even looser. `verify(mock, atLeastOnce()).method(...)` is
appropriate when the production code legitimately may call the mock more
than once and you don't want to over-specify the count.

For Test 2.4 specifically, the contract of `processTransfer` is "save both
accounts." The exact count is 2, no more, no less. `times(2)` is the right
strictness. The looser version would be sloppy.

### Question 5: The `TransferService` from Part 1 has no external collaborators, so we tested it with plain JUnit + AssertJ. The `TransferProcessor` from Part 2 has collaborators, so we needed Mockito. In your own words, what is the rule of thumb for deciding whether a class needs Mockito to test?

A class needs Mockito to test (in isolation) when it depends on other
classes whose behavior is **inconvenient or impossible** to use directly in
tests. Specifically:

- The collaborator does I/O (database, network, file system) that we don't
  want to perform in unit tests
- The collaborator depends on external resources (a third-party API, a
  message broker, an LDAP server) that aren't available in test environments
- The collaborator has non-deterministic behavior (random numbers, current
  time, network latency) that produces flaky tests if used directly
- The collaborator has expensive setup (large object graphs, complex
  configuration) that would dominate test runtime
- The collaborator is hard to drive into specific states (testing a "what
  if the database connection drops mid-transaction" path is much easier with
  a mock that just throws)

Conversely, a class does NOT need Mockito when:

- It has no collaborators (it's pure logic)
- Its collaborators are simple, deterministic, and cheap to construct (value
  objects like BigDecimal, Account, simple data records)
- Its collaborators are themselves easy to test alongside the unit under
  test, and the team prefers "Detroit school" tests that exercise real
  objects

The boundary is judgment, not rule. Some questions to ask:

- Could I construct this collaborator in a test in two lines or less?
- Would the test be deterministic with the real collaborator?
- Does the collaborator do anything I don't want my test to do?

If the answer to all three is "yes, just use the real thing," do that.
Skip Mockito. If any of the answers is no, mock the collaborator.

For Spring Boot specifically: any class that depends on a `@Repository` or
a downstream HTTP client (`RestTemplate`, `WebClient`) almost always wants
Mockito for those collaborators. Any class that depends only on value
objects, simple data structures, or other pure-logic services doesn't need
Mockito.

---

## What You Have Learned

By completing this lab you have practiced:

- The structure of a JUnit 5 test (annotation, method, AAA body)
- AssertJ's fluent assertion API including `assertThatThrownBy`
- Parameterized tests with `@CsvSource`
- The `@DisplayName` annotation for human-readable test reports
- The Mockito annotation pattern (`@ExtendWith`, `@Mock`, `@InjectMocks`)
- Stubbing behavior with `when(...).thenReturn(...)`
- Verifying interactions with `verify(...)`, including `times()`, `never()`,
  and the default
- Capturing arguments with `ArgumentCaptor` for richer assertions
- The judgment call about when to use mocks vs. real collaborators

These are the fundamental unit-testing skills you'll apply throughout your
career as a Spring Boot developer. The next lab (5.2) extends this to
integration testing, where Spring's framework infrastructure is loaded
alongside your code so you can test controllers, security configuration,
and other framework-level behavior.
