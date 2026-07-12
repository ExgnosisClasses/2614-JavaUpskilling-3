# SLab 5-4 Banking Sonarqube

## Answer Key


> **For instructors.** This document lists every violation deliberately planted in this project, organized by file. Each finding includes the SonarQube rule ID where one exists, the severity SonarQube assigns by default, and the category (Vulnerability / Security Hotspot / Bug / Code Smell). Use this to verify students' scans and to support discussion.

## Notes on rule IDs and versions

SonarQube rule IDs evolve. The IDs shown here are the standard Java rule IDs current as of SonarQube 10.x with the SonarJava plugin. The display prefix you see in your dashboard may be `java:S2076` or `squid:S2076` depending on your scanner version - the numeric portion is stable.

Some findings depend on the SonarQube edition:

- **Community Edition** (free, what we use in class) reports all the rules listed below except where noted as "Developer+"
- **Developer Edition or higher** adds taint-analysis findings (deep data-flow tracing for injection vulnerabilities) and full SAST coverage
- **No edition of SonarQube** reports third-party dependency CVEs out of the box. Those come from a separate scan (OWASP Dependency-Check, Snyk, etc.)

If a planted violation does not appear in a student's report, possibilities are: (1) the rule is in a higher edition than you are running; (2) the scan did not have access to the bytecode (`mvn clean verify` must finish before `sonar:sonar` runs); (3) the scanner version is older than the rule. The student's scan should report at minimum 30+ findings even in Community Edition.

---

## pom.xml

| Finding | Rule | Severity | Category | Detected by |
|---|---|---|---|---|
| `commons-collections 3.2.1` has known deserialization CVEs (CVE-2015-7501, CVE-2015-6420) | n/a | n/a | n/a | NOT SonarQube. Surfaces in dependency scanners (OWASP Dependency-Check, Snyk, Dependabot). Mention this distinction to students - SonarQube checks code, not dependency CVEs. |

---

## src/main/resources/application.properties

| Line | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `spring.datasource.password=admin123` | Hardcoded credential | S2068 | Blocker | Vulnerability |
| `banking.external.api.key=sk_live_...` | Hardcoded API key | S6437 | Blocker | Vulnerability |
| `banking.signing.secret=hardcoded-signing-secret-do-not-do-this` | Hardcoded secret | S6437 | Blocker | Vulnerability |
| `spring.h2.console.settings.web-allow-others=true` | Exposes H2 console to network | S6437 / S5604 | Critical | Security Hotspot |
| `debug=true` | Debug mode in production-style config | S4507 | Critical | Security Hotspot |
| `management.endpoints.web.exposure.include=*` | All actuator endpoints exposed | S6437 | Critical | Security Hotspot |
| `management.endpoint.env.show-values=always` | Exposes environment values | S6437 | Critical | Security Hotspot |

---

## src/main/java/com/example/banking/repository/AccountRepository.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| Class | Hardcoded JDBC username/password in source | S2068 | Blocker | Vulnerability |
| `findById` query | SQL injection via string concatenation in `executeQuery` | S2077 | Critical | Vulnerability (Developer+ for full taint analysis; basic pattern caught by Community) |
| `findById` body | Resource leak: `Connection`, `Statement`, `ResultSet` not closed (no try-with-resources) | S2095 | Major | Bug |
| `findById` catch block | `e.printStackTrace()` instead of logger | S1148 | Major | Code Smell |
| `findByCustomer` query | SQL injection via string concatenation | S2077 | Critical | Vulnerability |
| `findByCustomer` body | Resource leak: `Connection`, `Statement`, `ResultSet` not closed | S2095 | Major | Bug |
| `findByCustomer` catch | Swallowed exception (catch with no handling, no rethrow, no log) | S108 / S1166 | Critical | Code Smell |
| `updateBalance` body | Resource leak: `Connection` and `PreparedStatement` not closed | S2095 | Major | Bug |
| `updateBalance` catch | `e.printStackTrace()` | S1148 | Major | Code Smell |
| `exists` query | SQL injection via string concatenation | S2077 | Critical | Vulnerability |
| `exists` catch | Swallowed exception | S1166 | Critical | Code Smell |

**Discussion teaching point:** the `exists` method has a `finally` block that closes `Connection` but still leaks `Statement` and `ResultSet`. A partial-cleanup pattern is sometimes worse than no cleanup because it can mask the real problem. Try-with-resources is the right answer.

---

## src/main/java/com/example/banking/service/AuthService.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `ADMIN_PASSWORD = "admin123"` constant | Hardcoded credential | S2068 | Blocker | Vulnerability |
| `SALT = "static-salt-1234"` constant | Hardcoded cryptographic salt (predictable per-application) | S2068 / S6437 | Critical | Security Hotspot |
| `authenticate`: `username == ADMIN_USERNAME` | String compared with `==` instead of `.equals()` | S4973 | Critical | Bug |
| `authenticate`: `user.getPasswordHash() == hashed` | String compared with `==` | S4973 | Critical | Bug |
| `hashPassword` body | Weak hashing algorithm MD5 | S4790 | Critical | Security Hotspot (often reported as Vulnerability with deeper analysis) |
| `tokenGenerator = new Random()` | Insecure pseudorandom for security-sensitive value | S2245 | Critical | Security Hotspot |
| `generateSessionToken` | Uses `Random` (already flagged) - produces predictable tokens | S2245 | Critical | Security Hotspot |
| `generatePasswordResetToken` | Uses `Random` for security-sensitive token | S2245 | Critical | Security Hotspot |
| `hashPassword` catch | `throw new RuntimeException(e)` wraps without context | S00112 | Major | Code Smell |
| `registerUser` catch | Catch of generic `Exception` | S2221 | Major | Code Smell |
| `registerUser` catch | `System.out.println` for error reporting | S106 | Major | Code Smell |

---

## src/main/java/com/example/banking/service/TransferService.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `executeTransfer` method | Cognitive complexity exceeds threshold (deeply nested `if` chain) | S3776 | Critical | Code Smell |
| `executeTransfer` | Multiple magic numbers (1000000, 10000, 5000) | S109 | Minor | Code Smell |
| `executeTransfer`: `userRole == "ADMIN"` | String compared with `==` | S4973 | Critical | Bug |
| `calculateFee` `switch` | `case "CHECKING"` falls through to `case "SAVINGS"` (no `break`) | S128 | Critical | Bug |
| `calculateFee` body | Magic numbers (`0.01`, `0.005`, `0.015`, `0.02`, `5`, `2.50`) | S109 | Minor | Code Smell |
| `formatTransferReceipt` and `formatRejectionReceipt` | Duplicated code blocks | S4144 / S1192 | Major | Code Smell |
| `formatTransferReceipt` and `formatRejectionReceipt` | String literals `"----------------------------------------"`, `"TRANSFER RECEIPT"` duplicated | S1192 | Critical | Code Smell |
| `isWeekend` method | Always returns the same value (`return false`) followed by unreachable comment-only code | S3923 | Major | Bug |
| `isWeekend` method | Unused private method | S1144 | Major | Code Smell |

---

## src/main/java/com/example/banking/service/FileExportService.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `exportToFile` body | Path traversal: user-controlled `filename` concatenated into file path without sanitization | S2083 | Blocker | Vulnerability (Developer+ for full taint analysis) |
| `exportToFile` body | Resource leak: `FileWriter` / `BufferedWriter` not closed in try-with-resources | S2095 | Major | Bug |
| `readExportFile` body | Path traversal in `new File(EXPORT_ROOT + filename)` | S2083 | Blocker | Vulnerability |
| `readExportFile` body | Resource leak: `FileInputStream` not closed | S2095 | Major | Bug |
| `readExportFile` body | `fis.read(data)` return value ignored | S2674 | Major | Bug |
| `archiveExport` | OS command injection via `Runtime.exec(String)` with user-controlled filename | S2076 | Blocker | Vulnerability |
| `archiveExport` | `Runtime.exec(String)` uses string-form command (parsing pitfalls) | S4036 | Critical | Security Hotspot |
| `cleanupExports` | OS command injection through `sh -c` with concatenated user input | S2076 | Blocker | Vulnerability |
| `cleanupExports` | `Runtime.exec(String)` form | S4036 | Critical | Security Hotspot |
| `parseImportXml` | XXE: `DocumentBuilderFactory` used without disabling external entities | S2755 | Critical | Vulnerability |
| `writeReport` | Path traversal: user-controlled `customerId` in file path | S2083 | Blocker | Vulnerability |
| `writeReport` | Resource leak: `FileWriter` not closed in try-with-resources | S2095 | Major | Bug |

---

## src/main/java/com/example/banking/util/CryptoUtil.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `DES_KEY` field | Hardcoded encryption key | S6418 / S2068 | Blocker | Vulnerability |
| `AES_KEY` field | Hardcoded encryption key | S6418 / S2068 | Blocker | Vulnerability |
| `encryptDes` | Use of DES algorithm (broken) | S5547 | Critical | Vulnerability |
| `encryptDes` | Use of ECB cipher mode (deterministic, leaks structure) | S5542 | Critical | Vulnerability |
| `encryptAesEcb` | Use of ECB cipher mode | S5542 | Critical | Vulnerability |
| `encryptAesEcb` | No initialization vector (no IV for AES) | S5542 / S3329 | Critical | Vulnerability |

---

## src/main/java/com/example/banking/util/LegacyUserUtil.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `public static Map<String, String> CACHE` | Public static mutable field | S1444 | Major | Code Smell |
| `public static List<String> RECENT_USERS` | Public static mutable field | S1444 | Major | Code Smell |
| `private static int unusedCounter` | Unused private static field | S1068 | Major | Code Smell |
| `createdAt` of type `java.util.Date` | Use of legacy `Date` API instead of `java.time` | S6829 (Java 8+ time API preferred) | Minor | Code Smell |
| Override of `hashCode` without `equals` | Equals/hashCode contract violation | S1206 | Critical | Bug |
| `formatLegacyId` method | Unused private method | S1144 | Major | Code Smell |
| `incrementUnused` method | Unused private method | S1144 | Major | Code Smell |

**Discussion teaching point:** S1206 is one of the most important "subtle" findings in Java. A class with `hashCode` but no `equals` (or vice versa) breaks hash-based collections in ways that are very hard to debug at runtime. Always implement both or neither.

---

## src/main/java/com/example/banking/filter/LoggingFilter.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| Throughout | `System.out.println` instead of logger | S106 | Major | Code Smell (multiple occurrences) |
| `Authorization` header logging | Logging sensitive data (bearer tokens) | S5145 / S2629 | Critical | Security Hotspot |
| `Cookie` header logging | Logging sensitive data (session cookies) | S5145 | Critical | Security Hotspot |
| Loop over all headers | Logs entire request headers (may include sensitive values) | S5145 | Critical | Security Hotspot |
| Catch of generic `Exception` | Catch of generic exception | S2221 | Major | Code Smell |

---

## src/main/java/com/example/banking/controller/UserController.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `DEFAULT_API_KEY` constant | Hardcoded API key | S2068 / S6437 | Blocker | Vulnerability |
| `log.info("Login attempt for user: " + username)` | Log injection (user-controlled input in log message via concatenation) | S5145 | Critical | Vulnerability |
| `log.info("Looking up accounts for customer " + customerId)` | Log injection via concatenation | S5145 | Critical | Vulnerability |
| `login` catch | Catch of generic `Exception` | S2221 | Major | Code Smell |
| `register` catch | Catch of generic `Exception` | S2221 | Major | Code Smell |
| `getApiKey` endpoint | Exposes API key via unauthenticated endpoint | S6437 (and any custom rule for endpoint exposure) | Blocker | Vulnerability |
| `echo` endpoint | XSS: user input reflected into HTML without escaping | S5131 | Critical | Vulnerability (Developer+ for full taint analysis) |

---

## src/main/java/com/example/banking/controller/ConfigController.java

| Line area | Finding | Rule | Severity | Category |
|---|---|---|---|---|
| `@CrossOrigin(origins = "*", allowCredentials = "true")` | Permissive CORS combined with credentials - a serious combination | S5122 | Blocker | Vulnerability |
| `systemInfo` | Exposes system properties and environment via unauthenticated endpoint | S6437 / S5547 | Critical | Vulnerability |
| `activeThreads` | Exposes internal thread information | S6437 | Major | Security Hotspot |
| `shutdown` | Unauthenticated remote shutdown endpoint | n/a (no specific rule) - flagged via combination of S5852 or custom rules; pattern is unsafe regardless | Critical | Security Hotspot (instructor: this is a great discussion point - SonarQube may not flag this directly, which teaches the lesson that SAST is not a complete substitute for code review) |
| `shutdown` `Thread.sleep(1000)` | Magic number / arbitrary sleep | S2925 | Critical | Security Hotspot |
| `shutdown` catch block | Swallowed `InterruptedException` without re-interrupting thread | S2142 | Critical | Bug |
| `exec` endpoint | OS command injection via user-controlled command | S2076 | Blocker | Vulnerability |
| `exec` `Runtime.getRuntime().exec(cmd)` | `Runtime.exec(String)` form | S4036 | Critical | Security Hotspot |

---

## src/main/java/com/example/banking/service/AuditService.java

**This class is the clean reference.** No findings expected. If SonarQube reports anything here, either the scanner has been customized with non-default rules, or there is a finding that escaped the deliberate-clean review (please file a bug report against this answer key).

---

## src/main/java/com/example/banking/model/Account.java, User.java, TransferRequest.java

Mostly clean DTOs. SonarQube may report some minor findings on `User.java`:

- `User` has setters and is mutable - some teams have rules against mutable DTOs but this is not a default SonarJava rule
- No `equals`/`hashCode` on the `User` class - not flagged by default but worth noting if any rule mandates it

---

## Coverage findings

The only test is `AuditServiceTest`, covering `AuditService` thoroughly. Every other class has 0% coverage.

| Metric | Expected value |
|---|---|
| Overall line coverage | Below 10% (just `AuditService` lines) |
| Classes with coverage | 1 (AuditService) |
| Classes without coverage | All others |

SonarQube's default Quality Gate fails any project with new code coverage below 80%, so the entire project will be flagged as failing the quality gate. This is intentional.

---

## Summary by category (expected counts in Community Edition)

| Category | Approximate count |
|---|---|
| Vulnerabilities | 12-18 |
| Security Hotspots | 12-18 |
| Bugs | 8-12 |
| Code Smells | 25-35 |
| Coverage | 1 finding (low coverage) |
| Duplications | 1-2 (TransferService receipt methods) |

Exact counts vary by scanner version. If your students see far fewer findings, double-check:

1. The project actually compiled (`mvn clean verify` succeeded before `sonar:sonar` ran)
2. Bytecode was uploaded (look for `INFO: Java Main Files AST scan` in the scanner log)
3. JaCoCo coverage was produced and uploaded (`target/site/jacoco/jacoco.xml` exists)

---

## Suggested discussion themes

After students complete the scan, these are worth covering:

1. **Severity vs reality.** SonarQube's Blocker findings should be fixed first, but the Critical-grade hardcoded JDBC password in `AccountRepository` is just as urgent as any Blocker. Don't let the severity tab be your only triage criterion.

2. **What SAST cannot find.** The `/api/admin/shutdown` endpoint is unauthenticated and shuts down the JVM. SonarQube may not flag it because the *individual lines* are not dangerous - it is the *combination* (no auth + system effect) that is dangerous. SAST is one layer in defense in depth; it is not a substitute for design review or threat modeling.

3. **Hotspots vs vulnerabilities.** A Security Hotspot is "review required" - SonarQube cannot tell whether your use of `Random` is for a security purpose or for a non-security simulation. Hotspots are an explicit invitation for a human to apply context. Teach students to triage hotspots actively rather than ignoring them.

4. **Dependency CVEs.** SonarQube Community does not report `commons-collections 3.2.1` as having CVEs even though it is a well-known issue. Show students the OWASP Dependency-Check Maven plugin output or a Snyk report so they understand the distinction.

5. **Tests as a security control.** A class with no tests can have any number of subtle bugs introduced without anyone noticing. The fact that `AuditService` has tests is part of what makes it the reference implementation.
