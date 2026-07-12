# Lab 1-1: IntelliJ and Copilot Checkpoint Answer Key

> **How to use this document:** The checkpoint questions are intended to give you a chance to apply the module content to practical development issues and situations.
>
>The answers provided here are not "the" correct answers, but they  model answers that demonstrate one way to think through the question and arrive at a well-reasoned conclusion. Use these answers to check your own reasoning, identify any gaps in your understanding, and refine your approach to similar questions in the future.

---

## Exercise 1:  Project Setup and IDE Orientation

**1. What is the difference between a source root and a test source root? What goes wrong if test sources are marked as production sources?**

A **source root** (`src/main/java`) is the root of the production classpath. Everything inside it is compiled into the final packaged artifact (the JAR).

A **test source root** (`src/test/java`) is compiled and available only during the test phase. Its contents are never included in the shipped artifact.

If test sources are incorrectly marked as a production source root, two things go wrong:

First, test dependencies, like JUnit, that are declared with `scope=test` in Maven will not be on the compilation classpath when IntelliJ compiles what it thinks is production code, so the build fails with missing class errors.

Second, and more seriously, if the build does succeed, test classes and test frameworks will be bundled into the production JAR. This inflates its size and potentially exposes test infrastructure or test data in a deployed environment.

---

**2. Why is reformatting code (`Ctrl+Alt+L`) preferable to manually adjusting spacing?**

Manual spacing is inconsistent; different developers have different habits, and even the same developer will format code differently depending on context or how much time they have. `Ctrl+Alt+L` applies the project's configured Code Style rules uniformly every time, regardless of who runs it or when.

Consistent formatting eliminates noise in code reviews. When every file follows the same style, a diff shows only meaningful changes (logic, structure, naming), not whether someone used two spaces or four, or whether there is a blank line before a closing brace. This makes reviews faster and more focused on what actually matters.


---

**3. The Maven tool window shows dependency scope. Why does it matter that JUnit is `test` scope rather than `compile` scope?**

Two reasons

First, correctness: JUnit should never be available to production code. If a developer accidentally imports a JUnit class (say, `Assert` or `Assumptions`) in a production class, a `test`-scoped dependency causes a compile error that catches the mistake. With `compile` scope, the import succeeds silently and JUnit ends up on the production runtime classpath.

Second, artifact size and security posture: `test`-scoped dependencies are excluded from the final packaged JAR. Including test frameworks in a production artifact unnecessarily increases the attack surface and the size of the deployable.

---

### Exercise 2: Navigation in a Codebase

**1. You are asked to rename the `calculateTotal` method. Before pressing `Shift+F6`, what shortcut do you run first and why?**

`Alt+F7` (Find Usages). Before any rename, refactor, or deletion, you need to understand the impact: how many call sites exist, which classes depend on this method, whether it is referenced in test code, and whether it appears in any configuration. Find Usages gives you this map before you make any change, so there are no surprises. For a method that has been in a codebase for a while, you may discover callers in modules or packages you were not aware of.

---

**2. What is the difference between `Ctrl+B` (Go to Declaration) and `Ctrl+Alt+B` (Go to Implementation)?**

`Ctrl+B` always jumps to the **declaration**, which the place where the symbol is defined. On a method call, this is the method signature in the class or interface that declares it. On a type reference, this is the class or interface definition.

`Ctrl+Alt+B` jumps to the **concrete implementation**. This distinction matters when you are working with interfaces or abstract classes. If you press `Ctrl+B` on a call to an interface method, you land on the abstract method declaration in the interface, which tells you the contract but not the behavior. Pressing `Ctrl+Alt+B` on the same call takes you to the class that actually runs when that line executes. If multiple implementations exist, IntelliJ presents a list, and you choose which one to navigate to.


---

**3. You type `OrdItm` in the Go to Class dialog and no results appear. What might be wrong, and how would you adjust your search?**

`OrdItm` is a valid camelCase abbreviation for `OrderItem`
- `Ord` matches `Order`
- `It` matches `Item`
- and `m` matches the trailing `m` 

I IntelliJ *should* find it. If it does not, the abbreviation itself is not the problem.

The most likely cause is that the source root is not configured correctly. The file exists on disk but IntelliJ has not indexed it as part of the project source. This typically happens when `src/main/java` is not marked as a source root, or when the Maven project has not been imported or reloaded after the file was created. Check **File → Project Structure → Modules** and confirm the folder containing the class has the blue source root icon. In a Maven project, triggering a **Reload Project** in the Maven tool window usually resolves the indexing issue immediately.

---

**4. In a production codebase, `Alt+F7` on a commonly-used method shows 87 usages. The Usages in test code group shows 0. What does this tell you about the test coverage of that method?**

It tells you that the method is called directly from production code in 87 places but is never called from any test class. This does not necessarily mean the method is never exercised by tests. it may be reached indirectly through higher-level integration tests that call other methods which eventually call this one. But it does mean there are no unit tests that target this method specifically.

In practice this is a significant gap: if the method's behavior changes or breaks, no test will catch the regression directly. You will only discover the problem if an integration test happens to exercise the affected path, or worse, in production. This is exactly the kind of gap that coverage analysis is designed to surface.

---

## Exercise 3: Code Inspections, Intentions, and Refactoring

**1. What is the difference between an inspection and an intention? Give an example of each.**

An **inspection** is a continuous background analysis that IntelliJ runs against your code, flagging potential problems with colored highlights: yellow for warnings, red for errors. Inspections detect issues proactively, before you do anything. Example: highlighting `if (isPremiumCustomer == true)` because comparing a boolean to a literal `true` is redundant.

An **intention** is a context-sensitive action that IntelliJ offers when you press `Alt+Enter` on highlighted code. Intentions are how you *act* on what an inspection (or the compiler) has detected. Example: after IntelliJ flags the redundant comparison, pressing `Alt+Enter` offers "Simplify to 'isPremiumCustomer'" As a one-key fix. Intentions also appear in non-error contexts, offering useful transformations even on code that is technically correct (for example, converting a traditional `for` loop to a Stream).

The relationship: inspections *identify*, intentions *resolve*.

---

**2. Why is IntelliJ's Rename (`Shift+F6`) safer than a global Find-and-Replace for renaming a method?**

Find-and-Replace operates on text. It does not understand scope, types, or overloading. If you rename `calculateTotal` with Find-and-Replace, it will also rename any unrelated method in a different class that happens to share the same name, any variable named `calculateTotal`, any comment or Javadoc that contains the string, and any string literal that happens to contain those characters.

`Shift+F6` operates on the **semantic model**. IntelliJ knows the exact symbol being renamed, including its type, its class, its scope. It updates only the references that resolve to that specific symbol. A different class with a method also called `calculateTotal` is left untouched. Overloaded variants are handled correctly. Imports, Javadoc `@see` references, and Spring XML configuration that refers to the class by name are all updated. The result is guaranteed to compile.

---

**3. After the Extract Method refactoring, `calculateTotal` delegates to three private methods. How has this changed the testability of the class?**

Before the refactoring, the only way to test the validation logic, the subtotal calculation, or the shipping fee calculation was to go through `calculateTotal` with a complete list of items, the entire method had to run. Any assertion about one piece of the logic was entangled with all the other pieces. This led to tests that were either too broad (asserting the final total without isolating which part was wrong) or too narrow (setting up a specific scenario that only tests one path through the method, which can lead to a combinatorial explosion of test cases).

After extraction, each piece of logic has a name and a boundary. While the extracted methods are `private` and not directly testable from outside the class, the more important benefit is **clarity of intent**: each method does one thing, which makes it straightforward to write focused tests against `calculateTotal` that isolate one behavior at a time. Additionally, if the private methods were made package-private or protected for testing purposes, they could each be tested independently. The overall reduction in method length also reduces the cyclomatic complexity, which directly reduces the number of test cases needed to achieve full branch coverage.

---

**4. When would you use Extract Method vs Extract Variable? What problem does each one solve?**

**Extract Variable** (`Ctrl+Alt+V`) solves a *readability* problem at the expression level. When a complex expression appears inline; for example, `item.getQuantity() * item.getUnitPrice() * (1 - discountRate)` , then extracting it into a named variable like `discountedLineTotal` makes the surrounding code immediately readable. The logic stays in the same method; you are just giving a sub-expression a name.

**Extract Method** (`Ctrl+Alt+M`) solves a *structure* problem at the method level. When a block of code inside a method represents a distinct step or concern (like a validation, calculation, or formatting issue), extracting it into its own named method makes the calling method shorter, gives the block a name that communicates its purpose This makes the extracted logic independently testable and reusable. It also reduces the number of things any one method is responsible for.

More formally, this is an expression of the Single Responsibility Principle: a method should have one reason to change. If you find yourself writing a method that does multiple things, or if you have a long method where different sections do different things, Extract Method is the tool to use. If you have a single line with a complex expression that is hard to understand at a glance, Extract Variable is the tool to use.

Rule of thumb: if the problem is "this expression is hard to read," use Extract Variable. If the problem is "this method is too long or does too many things," use Extract Method.

---

## Exercise 4: Run Configurations and Debugging

**1. What are the three lifecycle states of a Run Configuration? Which one should be used for team projects, and why?**

- **Temporary:** auto-created when you click a run gutter icon for the first time. Not saved to any persistent location. These are eventually discarded when IntelliJ cleans up.
- **Permanent:** saved to local IDE settings. Survives IDE restarts but lives only on your machine. A teammate cloning the repository does not get it.
- **Shared:** committed to `.idea/runConfigurations/` as an XML file and tracked in version control. Every developer who clones the repository gets the same launch configuration automatically.

**Shared** configurations should be the standard on any team project. They encode the correct active profile, environment variable names, JVM arguments, and working directory, as well as the full set of context needed to run the application correctly. Without them, each developer recreates this configuration from memory, which leads to "works on my machine" situations where one developer's environment differs subtly from another's.

---

**2. What is the difference between Step Over (`F8`) and Step Into (`F7`)? Give a scenario where you would deliberately choose each one.**

**Step Over (`F8`)** executes the current line and moves to the next line in the same method. If the current line contains a method call, that method runs entirely without the debugger entering it.

**Step Into (`F7`)** enters the method being called on the current line, pausing at its first executable statement. You are now inside the called method.

Scenario for **Step Over**: you are in `calculateTotal` and you have already verified that `subtotal()` works correctly. You Step Over it to observe what `total` is after it returns, without re-tracing code you already understand.

Scenario for **Step Into**: you are in `calculateTotal` and the `total` value after calling `subtotal()` is wrong. You Step Into `subtotal()` to trace its execution and find where the incorrect value originates.

---

**3. You are debugging a loop that processes 500 items. The bug only affects items with a negative `quantity`. How would you configure a breakpoint to pause only on those items?**

Set a **conditional breakpoint**. Right-click the breakpoint dot on the line inside the loop → enter the condition `item.getQuantity() < 0` (or `quantity < 0` if that is the local variable name at that point). The debugger evaluates this boolean expression on every iteration and only suspends execution when it evaluates to `true`. The 499 items with valid quantities pass through without interrupting the session.

---

**4. How is a logging breakpoint different from adding `System.out.println` directly in the code? When is the logging breakpoint approach preferable?**

A `System.out.println` modifies the source file. You have to add it, recompile, run, read the output, then remove it and recompile again. If you forget to remove it, it ships to production. It also appears in code review diffs as noise.

A logging breakpoint is attached to the running process by the debugger — no source change, no recompilation. You right-click an existing breakpoint, uncheck Suspend, and enable Evaluate and Log with an expression. The program must still be launched in **debug mode** (`Shift+F9`), but when the line is hit, the expression is evaluated and printed to the Debug Console without halting execution. When you close the debug session, the breakpoint is gone. No files were modified.

This is preferable in several situations: when recompiling is slow, when the code you want to instrument is in a library you cannot modify, when you want to add and remove logging rapidly across many locations without leaving traces, or when working in a production-like environment where stopping execution is not acceptable but observing values is necessary.

---

## Exercise 5: Running and Managing Tests

**1. IntelliJ reports that `src/test/java` does not have the green test source icon. It shows a blue source icon instead. What does this mean and how would you fix it?**

It means IntelliJ's project model has classified the test source folder as a production source root. The practical consequences are that test-scoped dependencies (like JUnit) are not available to code in that folder, and if a build succeeds, test classes would be included in the production artifact.

The fix: open **File → Project Structure** (`Ctrl+Alt+Shift+S`) → Modules → select the module → find `src/test/java` in the source folders list → change its type from **Sources** to **Tests**. In a Maven project the faster fix is to right-click the project root in the Maven tool window and choose **Reload Project**. Maven's standard directory conventions will re-mark the folder correctly.

---

**2. You run all tests and one turns red. The failure message says `expected: <59.99> but was: <50.0>`. Describe the debugging steps you would take to find the root cause.**

First, read the assertion that failed. The test name and the assertion line tell you exactly which scenario is broken and what value was expected. In this case the test is `standardCustomerTotalWithShipping`, which expects `59.99` (a `50.00` subtotal plus `9.99` shipping). The actual value is `50.00`, which is the subtotal with no shipping added — so the shipping logic did not execute.

Next, set a breakpoint in `calculateTotal` at the shipping fee calculation and re-run that single test in debug mode (right-click the test method → Debug). Step through and observe: does execution enter the `shippingFee` method? Does the condition that determines whether shipping applies evaluate correctly? Is `FREE_SHIPPING_THRESHOLD` set to the right value? Inspect the `total` variable at each step to identify exactly where it stops matching the expected value.

The likely cause in this specific case is that the condition was accidentally inverted during the inspection fix in Exercise 3 (`>= 100` vs `< 100`), or the constant value was changed. The debugger will pinpoint it in seconds.

---

**3. What is the difference between IntelliJ's built-in coverage and JaCoCo coverage? Which one matches what a CI pipeline typically reports?**

IntelliJ's **built-in coverage** uses its own instrumentation agent. It is fast, integrates seamlessly into the IDE, and updates the editor gutter in real time. It is the best tool for interactive use during development.

**JaCoCo** is a separate open-source coverage library that integrates with Maven's Surefire and Failsafe plugins. It runs as part of `mvn test` or `mvn verify` and produces reports that can be published by CI tools (Jenkins, GitHub Actions, SonarQube). JaCoCo is the standard in CI pipelines because it is build-tool-neutral and produces machine-readable reports.

**JaCoCo** is what your CI pipeline reports. If your team's quality gate says "80% line coverage," that threshold is measured by JaCoCo during the Maven build, not by IntelliJ's coverage. The numbers are usually very close but can differ slightly due to instrumentation differences. When there is a discrepancy, trust JaCoCo for CI purposes.

---

## Exercise 6: GitHub Copilot Integration

**1. Copilot suggests a method implementation that compiles and the tests pass. Is that sufficient to accept it? What else would you check?**

Compiling and passing tests is the minimum bar, not the full bar. Additional things to verify:

- **Correctness against the specification:** Do the tests actually cover all the cases described in the comment or ticket? Copilot writes code that satisfies the tests as written, if a test is missing a boundary case, the code may be wrong for that case and the tests will still pass.
- **API currency:** Is Copilot using a current API, or a deprecated one (e.g., `java.util.Date` instead of `java.time`, `RestTemplate` instead of `WebClient`)? Copilot's training data includes old code.
- **Style and conventions:** Does the code follow the team's naming conventions, formatting rules, and structural patterns? Copilot does not know your team's standards unless they are evident in the surrounding code.
- **Security:** Does the code introduce any obvious vulnerabilities? For example, does it concatenate user input into a query string instead of using a parameterized query? Does it log sensitive values?
- **Readability:** Is the generated code as clear as code a thoughtful engineer would write? Copilot optimizes for plausibility, not clarity.

---

**2. What is the relationship between the quality of your comments and the quality of Copilot's suggestions?**

Copilot uses the surrounding source code, including comments, method signatures, field names, and the broader class context, as its prompt. The comment immediately preceding a method is the strongest signal it has about what you want.

A vague comment like `// calculate price` produces a plausible but generic implementation. A precise comment that specifies the business rule (`// volume discount of 8% applies when quantity >= 10; discounts are additive, not compounded; result rounded to 2 decimal places`) gives Copilot the specific constraints it needs to generate code that is correct by design rather than correct by accident.

This is why prompt engineering matters even for inline code generation: the discipline of writing a precise comment before the method is also the discipline of thinking clearly about the requirement. If you cannot write a precise comment, you do not yet understand the requirement well enough to implement it, regardless of whether Copilot is involved.

---

**3. Name two scenarios where using Copilot is clearly beneficial, and one scenario where you would be more cautious about accepting its output.**

**Beneficial:**

- **Boilerplate generation:** Copilot excels at generating repetitive, well-understood code; getters, constructors, standard exception handling, test method stubs, common stream pipelines. The risk of error is low and the time saving is high.
- **Unfamiliar APIs:** When you know what you want to do but are not familiar with the specific library, Copilot can generate a syntactically correct starting point using the API, which you then verify against the documentation. This is faster than reading through API docs blind.

**More cautious:**

- **Security-sensitive code:** Authentication logic, input validation, SQL query construction, cryptography, secret handling, and permission checks are all areas where a plausible-looking but subtly wrong implementation can introduce a serious vulnerability. Copilot is trained on a large corpus of public code, some of which contains known vulnerabilities. Always review security-sensitive suggestions line by line against authoritative documentation and your security team's standards rather than accepting them based on appearance.

---

**4. A Copilot suggestion uses `java.util.Date` to handle a timestamp. You know `Date` is deprecated in favor of `java.time.LocalDateTime`. What does this tell you about Copilot's knowledge, and how do you handle it?**

It tells you that Copilot's training data includes a large volume of code that predates the `java.time` API (introduced in Java 8), and that older patterns are well-represented in its training corpus. Copilot does not intrinsically know that `Date` is now considered legacy — it knows that `Date` is commonly used for timestamps because a lot of the code it was trained on uses it that way.

Handle it by rejecting the suggestion and prompting more specifically. Either retype the method signature using `LocalDateTime` as the parameter or return type — Copilot will adapt its suggestion to match — or use the Copilot Chat to ask it to rewrite the method using `java.time`. Then verify the result. This is a general pattern: when Copilot uses a legacy API, correct the type signature or add a comment specifying the required API, and regenerate. Never accept a suggestion that uses a deprecated API simply because it compiles.

---

## Final Reflection Questions

**1. You are joining a new team's Java project. What is the first thing you do in IntelliJ to orient yourself in the codebase, and why?**

Open the **Maven tool window** and reload the project to ensure IntelliJ's project model is fully synchronized with the POM. Then use `Ctrl+N` to find the application's entry point (typically a class annotated `@SpringBootApplication` or with a `main` method) and press `Ctrl+Alt+B` or `Ctrl+H` on any key interface to build a mental map of the type hierarchy. From the entry point, use `Ctrl+Alt+H` (Call Hierarchy) on the main method to trace the startup path, and `Alt+F7` (Find Usages) on key service interfaces to understand which classes are actively in use.

The goal at this stage is not to read every class, it is to understand the shape of the system: how many layers it has, where the boundaries between them are, and which classes are central (many usages) vs peripheral (few usages). This takes 20–30 minutes and prevents days of working with a wrong mental model.

---

**2. A colleague says "I don't need the debugger, I just add `System.out.println` everywhere." What would you say to them, and what specific debugger capabilities would you demonstrate?**

Acknowledge that `println` works for simple, well-understood cases, but demonstrate three capabilities it cannot match:

First, the **call stack**: the debugger shows the full chain of method calls that led to the current line. `println` can only tell you what a value is at a specific point; the debugger tells you *how execution arrived* at that point, which is usually the more important question.

Second, **Evaluate Expression** (`Alt+F8`): you can execute arbitrary Java expressions against the live runtime state without modifying any source file or recompiling. `println` requires a source edit, a recompile, a re-run, and then cleanup.

Third, **conditional breakpoints**: when a bug only occurs for specific data in a loop processing thousands of items, a conditional breakpoint pauses only on the affected iteration. The `println` equivalent, wrapping the print in an `if`,still requires a source edit, recompile, and cleanup, and produces thousands of lines of output for all the passing iterations.

The underlying point is that `println` debugging has a fixed cost per investigation: edit, compile, run, read, remove, compile again. The debugger's cost decreases with familiarity and eventually becomes faster than any `println`-based approach for any non-trivial problem.

---

**3. Your team lead asks you to rename a public interface method that has been in production for two years. Walk through the exact steps you would take in IntelliJ to do this safely.**

1. **`Alt+F7` on the method** and read the full Find Usages report. How many call sites are there? Are any in external modules you did not know about? Are there usages in Spring XML configuration or annotation-based configuration? Are there usages in test code? This step is non-negotiable before touching any widely-used symbol.

2. **Check for external consumers** If this is a public interface in a library consumed by other teams or systems, a rename is a breaking change that cannot be handled by IntelliJ alone. That conversation needs to happen before any refactoring.

3. **`Shift+F6` on the method name** and type the new name. IntelliJ previews all the changes it will make. Review the preview list: does it include all the call sites you identified in step 1? Are there any unexpected inclusions?

4. **Click Refactor** and IntelliJ applies all changes atomically.

5. **Run the full test suite** using `Ctrl+Shift+F10` on the test root or trigger via Maven. All tests should pass. If any fail, the Find Usages step missed a call site that was reached indirectly (for example, through reflection or a string-based configuration), which the tests will now expose.

6. **Review the diff before committing** to confirm that only the intended symbol and its references changed. No unrelated files should be touched.

---

**4. You ask Copilot to generate a method that processes sensitive data. The generated code is functional. What specific concerns would you review before accepting it?**

- **Logging:** Does the method log any of the sensitive values, even at DEBUG level? Log aggregators collect everything, and sensitive data in logs is a common source of exposure. Remove or mask any logging of sensitive fields.
- **Exception messages:** Does the method include sensitive data in exception messages? Exceptions propagate up the stack and may be serialized into HTTP responses or audit logs.
- **Input validation:** Does the method validate and sanitize its inputs before processing them? Copilot often generates the happy path without defensive checks.
- **Unnecessary retention:** Does the method store sensitive data in a field, a cache, or a collection longer than necessary? Data that is not retained cannot be leaked.
- **Dependency on insecure APIs:** Does the method use any cryptographic operations? If so, are they using current algorithms and secure defaults (for example, AES-GCM rather than AES-ECB), or did Copilot default to something that appears in older code?
- **Test data:** Do the tests Copilot generated (if any) use real-looking sensitive data — names, identifiers, account numbers — that should not appear in source code? Replace any such values with clearly synthetic test data.

---

*End of Module 0 Answer Key*
