# Lab 5-4 Banking Sonarqube

A deliberately flawed Spring Boot project for practicing how to read SonarQube reports.

**This project is not meant to run.** It is meant to be scanned. The code compiles cleanly so SonarQube can perform deep analysis, but several classes will throw exceptions or behave incorrectly if you actually start the application. The exercise is to scan it, then read the SonarQube dashboard.

## Prerequisites

- Java 21 installed and on your PATH
- Maven 3.8 or newer
- A running SonarQube server (in this course, we run it in Docker on `http://localhost:9000`)
- A SonarQube authentication token from your account page in the SonarQube UI

## How to scan

From the project root:

```bash
# Compile, run tests, and produce JaCoCo coverage report
mvn clean verify

# Send the analysis to SonarQube
mvn sonar:sonar \
    -Dsonar.host.url=http://localhost:9000 \
    -Dsonar.token=YOUR_TOKEN_HERE \
    -Dsonar.projectKey=banking-tests-lab-sonar-demo
```

The first command compiles, runs the one set of tests we ship (`AuditServiceTest`), and writes a coverage report under `target/site/jacoco/`. The second command sends everything (source, bytecode, coverage report, dependency info) to your SonarQube server.

When the scan completes, open `http://localhost:9000` and find the `banking-tests-lab-sonar-demo` project. The dashboard is your exercise.

## What you should see

A lot.

- Roughly 5-10 **Vulnerabilities** (blocker/critical security findings)
- Roughly 10-15 **Security Hotspots** (review-required findings)
- A handful of **Bugs**
- 20+ **Code Smells**
- A **Coverage** number well below 10% - only one class has tests

Your job is not to fix anything. Your job is to navigate the dashboard, drill into the findings, and learn how SonarQube categorizes and explains them.

## Suggested exercises

1. Open the **Vulnerabilities** tab. Pick three findings of different rule types. For each one, click into the issue, read SonarQube's explanation, and write a one-sentence summary of what the issue is and how you would fix it.

2. Open the **Security Hotspots** tab. For each hotspot, decide whether you would mark it "to review" or "safe" if you were the security reviewer. Justify each decision in one sentence.

3. Find the highest-severity **Bug** in the report. Trace it to the line of code. What sequence of events would have to happen at runtime for this bug to manifest?

4. Open the **Coverage** view. Identify the class with 100% coverage and the classes with 0% coverage. Why is partial coverage often more dangerous than zero coverage?

5. Open **Code Smells** and look at the cognitive complexity finding(s). Find the method SonarQube flagged as the most complex. Sketch how you would refactor it into smaller pieces.

If you get stuck on a finding, your instructor has the answer key with every planted violation and its expected SonarQube rule ID.

## Files of note

- `src/main/java/com/example/banking/service/AuditService.java` is the **clean reference**. Everything else has issues. Compare the others against this one.
- `src/main/java/com/example/banking/service/AuditServiceTest.java` is the only test in the project. It exists so the coverage metric is partial (a few classes covered) rather than zero.

If the SonarQube version you run is Developer Edition or higher, you may see additional findings beyond what the Community Edition reports. The answer key flags which findings depend on Community vs higher editions.
