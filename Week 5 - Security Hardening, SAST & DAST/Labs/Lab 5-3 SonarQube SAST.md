# # Lab 5.3 -- SonarQube SAST Triage

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 10 - Testing, SAST, and Security Hardening
> **Estimated time:** 60-75 minutes

---

## Overview

In this lab you will run SonarQube against a deliberately-vulnerable Spring Boot application, triage the security findings, and remediate one of them. The skills you practice here transfer directly to Checkmarx, Snyk, and other commercial SAST tools your team uses at the bank.

The starter project (`banking-vulnerable-lab`) is a small Spring Boot application with several deliberately-introduced security issues: hardcoded credentials, weak cryptography, weak random number generation, and others. These are realistic, real-world vulnerability patterns. SonarQube will detect most of them; one is a deliberate "false positive bait" so you can practice classifying.

By the end of this lab you will be able to:

- Run SonarQube Community Edition locally in Docker
- Configure a SonarQube authentication token and use it from a Maven scan
- Read SonarQube findings and connect them to the underlying code
- Apply the four-category triage workflow (true positive fix-now, true positive accepted risk, false positive, out of scope)
- Remediate a true positive and verify the fix by re-scanning
- Mark a finding as a false positive in SonarQube with an audit-quality justification

---

## Before You Start

You will need:

- **IntelliJ IDEA** (Community or Ultimate)
- **JDK 17 or newer**
- **Maven** -- bundled with IntelliJ
- **Docker** -- already installed on your lab VM
- A modern browser (Chrome, Firefox, Edge)
- The `banking-vulnerable-lab.zip` file provided with this lab

The lab does NOT require:

- The Module 8 projects, the Lab 5.1 project, or the Lab 5.2 project
- A Checkmarx license
- An internet connection during the triage portion (only during initial Docker image pull and Maven dependency download)

### A note on the tool we are using

The bank's CI pipeline uses Checkmarx as its SAST tool. This lab uses SonarQube Community Edition because it is free, runs locally, and does not require a license. **The triage workflow is identical between the two tools.** Once you can read a SonarQube finding, classify it, and write a justification, you can do the same in Checkmarx with minimal ramp-up. The vocabulary differs (SonarQube says "False Positive" where Checkmarx says "Not Exploitable") but the meaning is the same. SonarQube and Checkmarx both use CWE numbers, so the vulnerability vocabulary itself is portable.

### A note on what SonarQube Community detects

SonarQube Community Edition catches **pattern-based** security issues: hardcoded credentials, weak crypto algorithms, weak random number generation, insecure cipher modes, and similar.

What it does NOT catch in the Community Edition: **injection vulnerabilities** that require taint analysis (SQL injection, command injection, path traversal, XSS). These rules are paywalled to SonarQube's commercial editions. Checkmarx, in contrast, includes taint analysis as part of its base offering.

This means the findings you see in this lab are a subset of what Checkmarx would flag for the same code. That subset is still valuable for the triage exercise, and the workflow you learn here works exactly the same way for the larger set of findings you'll see at the bank.

---

## Exercise 1 -- Start SonarQube

**Estimated time:** 5-10 minutes

### Task 1.1 -- Pull and run the SonarQube container

Open a terminal on your lab VM. Run this command:

```bash
docker run -d --name sonarqube -p 9000:9000 sonarqube:community
```

What this does:

- `-d` runs the container in detached mode (in the background)
- `--name sonarqube` gives it a friendly name so you can reference it later
- `-p 9000:9000` maps the container's port 9000 to your VM's port 9000
- `sonarqube:community` is the image name and tag (the free Community Edition)

The first time you run this, Docker downloads the SonarQube image. This is about 700 MB and takes a few minutes depending on your network speed. Subsequent runs use the cached image and start in under a minute.

While Docker is downloading, you can move on to importing the project (Exercise 2's first step) in parallel.

### Task 1.2 -- Wait for SonarQube to start

SonarQube takes 1-2 minutes to start up after the container is running. Check progress with:

```bash
docker logs sonarqube --tail 20
```

You'll know it is ready when you see a line like:

```
SonarQube is operational
```

If you don't see this yet, wait 30 seconds and check again.

### Task 1.3 -- Log in for the first time

In your browser, go to `http://localhost:9000`.

Log in with the default credentials:

- Username: `admin`
- Password: `admin`

SonarQube will immediately ask you to change the password. Set it to something simple but memorable (this is a local-only instance, so the password is not security-critical). For example: `Lab5.3Pass!`. Write it down so you don't forget.

After changing the password you'll see SonarQube's main dashboard. There are no projects yet.

### Task 1.4 -- Generate a token

SonarQube uses tokens (not passwords) for the Maven scan to authenticate. Generate one now.

1. Click your profile avatar in the top-right corner
2. Choose **My Account**
3. Go to the **Security** tab
4. Under "Generate Tokens":
   - Name: `lab-scan-token`
   - Type: leave as "User Token" (the default)
   - Expires in: leave as default
5. Click **Generate**

A token string appears (something like `squ_abc123...`). **Copy this immediately and save it somewhere you can paste from in the next exercise.** SonarQube only shows it once. If you lose it you'll need to generate a new one.

---

## Exercise 2 -- Run the First Scan

**Estimated time:** 10-15 minutes

### Task 2.1 -- Import the project

1. Unzip `banking-vulnerable-lab.zip` to a working directory
2. In IntelliJ, choose **File** -> **Open**, then select the unzipped `banking-vulnerable-lab` folder
3. IntelliJ detects the `pom.xml` and offers to import as a Maven project. Accept.
4. Wait for IntelliJ to download dependencies and index the project. This can take 1-2 minutes the first time.

While indexing, take a few minutes to read through the production code. Pay particular attention to:

- `AdminService.java` -- look at how the admin password is declared and how the catch block is written
- `CryptoUtil.java` -- look at the password hashing, the token generation, the encryption method, and the `TEST_FIXTURE_KEY` constant near the top
- `AccountRepository.java` -- look at how queries are constructed (the patterns here are interesting but SonarQube Community will not flag them)

You don't need to find the bugs yet. Just notice how the code is structured.

### Task 2.2 -- Run the SonarQube scan

Open the Terminal tab in IntelliJ (View -> Tool Windows -> Terminal). You should be in the project root directory.

Run the scan:

```bash
mvn clean verify sonar:sonar \
    -Dsonar.host.url=http://localhost:9000 \
    -Dsonar.token=PASTE_YOUR_TOKEN_HERE \
    -Dsonar.projectKey=banking-vulnerable-lab \
    -Dsonar.projectName="Banking Vulnerable Lab"
```

Replace `PASTE_YOUR_TOKEN_HERE` with the token you generated in Task 1.4.

> **On Windows**, the backslash line continuations don't work. Either put the whole command on one line, or use the caret (`^`) for line continuation:
>
> ```
> mvn clean verify sonar:sonar ^
>     -Dsonar.host.url=http://localhost:9000 ^
>     -Dsonar.token=PASTE_YOUR_TOKEN_HERE ^
>     -Dsonar.projectKey=banking-vulnerable-lab ^
>     -Dsonar.projectName="Banking Vulnerable Lab"
> ```

What happens:

1. Maven compiles the code (`clean verify`)
2. The Sonar Maven plugin (`sonar:sonar`) sends the source code and compiled classes to your local SonarQube instance
3. SonarQube analyzes the code, applies its rules, and stores findings in its database
4. The Maven build prints a URL to view the results

This takes 1-2 minutes. Watch the output. The end of the output should look something like:

```
[INFO] ANALYSIS SUCCESSFUL, you can find the results at: http://localhost:9000/dashboard?id=banking-vulnerable-lab
[INFO] Note that you will be able to access the updated dashboard once the server has processed the submitted analysis report
[INFO] More about the report processing at http://localhost:9000/api/ce/task?id=...
[INFO] BUILD SUCCESS
```

Open the dashboard URL in your browser. SonarQube needs another 30-60 seconds to "process" the report after the Maven scan finishes; if the dashboard is still empty, wait and refresh.

### Task 2.3 -- Survey the findings

You should now see the project on the SonarQube dashboard with a summary of findings.

The dashboard categorizes findings into:

- **Bugs** -- code that is likely incorrect (logic errors, null pointer issues, etc.)
- **Vulnerabilities** -- security issues
- **Security Hotspots** -- code that needs human review for potential security implications
- **Code Smells** -- maintainability issues (not security per se, but worth attention)

For this lab, focus on the Vulnerabilities and Security Hotspots tabs. Click into the **Issues** tab and use the left sidebar to filter by **Type**.

You should see findings spread across `AdminService.java` and `CryptoUtil.java`, plus possibly one or two code-smell findings in other files.

Take 5 minutes to scroll through the findings. For each one, note:

- The rule that fired (the rule name and its description)
- What CWE it maps to (shown in the rule details when you click into a finding)
- Which file and line the finding points at

Expected security findings (rule names may vary slightly between SonarQube versions):

| File | Finding |
|---|---|
| `AdminService.java` | Hardcoded credential (`ADMIN_PASSWORD`) |
| `CryptoUtil.java` | Weak hash algorithm (MD5) in `hashPassword` |
| `CryptoUtil.java` | Insecure cipher mode in `encryptSensitiveData` |
| `CryptoUtil.java` | Insecure source of randomness in `generateSessionToken` |
| `CryptoUtil.java` | Possibly: hardcoded credential warning on `TEST_FIXTURE_KEY` |

Plus one or more code smell findings such as the empty catch block in `AdminService.generateHealthReport`.

The exact count varies by SonarQube version. If you see 4-6 security findings and a couple of code-smell findings, you're in the expected range.

---

## Exercise 3 -- Triage Five Findings

**Estimated time:** 25-30 minutes

### Context

For each of five findings, you will apply the triage workflow from Unit 5:

1. **Confirm** -- read the finding and the code; does the alleged vulnerability exist?
2. **Classify** -- pick one of the four categories:
   - True positive, fix now
   - True positive, accepted risk
   - False positive
   - Out of scope
3. **Act** -- update the finding in SonarQube with the classification and a comment

You do NOT need to actually fix the code in this exercise (that's Exercise 4). The triage exercise is just about the analysis.

### Task 3.1 -- Triage Finding A: Hardcoded Credential (ADMIN_PASSWORD)

In the SonarQube Issues view, find the finding for `AdminService.java`. The rule is something like "Credentials should not be hard-coded" with severity Blocker or Critical.

Click the finding to expand it. You'll see:

- The line of code that triggered the finding
- A "Why is this an issue?" explanation
- A "How can I fix it?" section with sample fixes

Read the explanation. Then look at the actual code in `AdminService.java`:

```java
private static final String ADMIN_PASSWORD = "Admin@123!Production";

public boolean authenticateAdmin(String suppliedPassword) {
    return ADMIN_PASSWORD.equals(suppliedPassword);
}
```

The admin password is a string literal in source code.

**Triage:**

- This is a **true positive**.
- Anyone with read access to the source (or to the compiled JAR) knows the production admin password.
- Even worse: if this code has been committed to source control, the password is permanently in git history even if removed later.
- Classification: **True positive, fix now**.

**Act in SonarQube:**

1. With the finding expanded, click **Status** -> change to "Confirmed"
2. Click **Add comment** and add a brief note like:
   > Confirmed hardcoded credential. Production admin password is a string literal in source code. Will fix by reading from environment variable or secrets manager. The string itself is now compromised since it has been in source control; rotation is also required.

This is the kind of audit-trail comment that demonstrates you understood the finding and made a deliberate decision.

### Task 3.2 -- Triage Finding B: Weak Hash Algorithm (MD5)

Find the SonarQube finding pointing at `CryptoUtil.hashPassword(...)`. The rule is something like "Cryptographic algorithms should be robust" or "Weak cryptographic algorithms should not be used", citing MD5.

The code:

```java
MessageDigest digest = MessageDigest.getInstance("MD5");
byte[] hash = digest.digest(password.getBytes());
```

**Triage:**

- True positive. MD5 has been considered cryptographically broken since the early 2000s.
- Using it for password hashing is particularly bad: rainbow tables for MD5'd passwords are widely available.
- The right fix is `BCryptPasswordEncoder` from Spring Security (you'll do this in Exercise 4).
- Classification: **True positive, fix now**.

**Act in SonarQube:** Set status to Confirmed and add a comment explaining the analysis.

### Task 3.3 -- Triage Finding C: Insecure Cipher Mode

Find the SonarQube finding pointing at `CryptoUtil.encryptSensitiveData(...)`. The rule is something like "Insecure cipher mode" or "Encryption algorithms should be used with secure mode and padding scheme".

The code:

```java
Cipher cipher = Cipher.getInstance("AES");
```

**Triage:**

- True positive. `Cipher.getInstance("AES")` without specifying a mode and padding implicitly uses ECB mode (Electronic Codebook).
- ECB encrypts identical plaintext blocks to identical ciphertext blocks, which leaks information about the structure of the data.
- The fix is to specify a secure mode and padding, for example `Cipher.getInstance("AES/GCM/NoPadding")` for authenticated encryption.
- Classification: **True positive, fix now** (or **accepted risk** if there's a compelling reason the data is non-sensitive, but for a banking application this would be a hard sell).

**Act in SonarQube:** Set status to Confirmed and add a comment.

### Task 3.4 -- Triage Finding D: Insecure Random

Find the SonarQube finding pointing at `CryptoUtil.generateSessionToken(...)`. The rule is something like "Pseudorandom number generators (PRNGs) should not be used in secure contexts" or "Using pseudorandom number generators (PRNGs) is security-sensitive".

The code:

```java
public String generateSessionToken() {
    Random random = new Random();
    StringBuilder token = new StringBuilder();
    for (int i = 0; i < 32; i++) {
        token.append(Integer.toHexString(random.nextInt(16)));
    }
    return token.toString();
}
```

**Triage:**

- True positive. `java.util.Random` is a deterministic pseudo-random number generator suitable for non-security purposes.
- It is NOT suitable for security-relevant random values: tokens, session IDs, password reset codes, cryptographic nonces.
- An attacker who observes a few output values can predict subsequent ones.
- The fix is `java.security.SecureRandom`, which uses the operating system's entropy source.
- Classification: **True positive, fix now**.

**Act in SonarQube:** Set status to Confirmed and add a comment.

### Task 3.5 -- Triage Finding E: TEST_FIXTURE_KEY (False Positive Candidate)

Find the SonarQube finding pointing at `CryptoUtil.TEST_FIXTURE_KEY`. SonarQube may flag this as a hardcoded credential because the constant name contains "Key" and the value looks like a secret. Whether it is flagged depends on the rule pack and version.

Look at the code carefully:

```java
/**
 * Test fixture key used only by unit tests. NOT a real production secret.
 * The actual production key is loaded from the EncryptionConfigService at runtime
 * (see EncryptionConfigService.getProductionKey()). This constant exists solely
 * so unit tests have a deterministic key for round-trip encryption tests.
 *
 * SAST scanners may flag this as a hardcoded credential. That would be a false
 * positive: the value is not a credential and never reaches production code.
 */
public static final String TEST_FIXTURE_KEY = "TestFixtureKey16";
```

**Triage:**

- The Javadoc explicitly documents that this value is a test fixture, not a production credential.
- The string `"TestFixtureKey16"` is not a real key; it's deterministic test data so unit tests can verify round-trip encryption produces consistent output.
- The actual production key is loaded from configuration at runtime, not from this constant.
- Classification: **False positive**.

**Act in SonarQube:** If this finding exists, set its status to "Resolved as False Positive" and add a justification:

> False positive. The constant is a test fixture documented as such in Javadoc, not a production credential. Real production key material is loaded from EncryptionConfigService at runtime. The value "TestFixtureKey16" is not a credential and would never reach production code; it exists solely to give unit tests a deterministic key for round-trip encryption tests. The tool flagged on the constant name pattern ("Key" plus a string literal) without examining the documented purpose.

If SonarQube did NOT flag this constant (it may not, depending on its rules), don't worry. The exercise still works -- you've still practiced the analysis. Add a brief note in your triage comments saying SonarQube correctly did not flag this.

### Verify Exercise 3

Go back to the project's Issues view. Filter by **Status** in the sidebar. You should now have several issues marked as "Confirmed" and possibly one marked as "Resolved" (the false positive from Task 3.5). Each one has a comment explaining your triage decision.

This is the audit trail. In a real bank engagement, security auditors and your team's security engineers can read these comments to see what you decided and why.

---

## Exercise 4 -- Remediate One Finding

**Estimated time:** 15-20 minutes

### Context

Pick one of the true-positive findings you triaged in Exercise 3 and fix it. Then re-scan and verify the finding is gone.

For this exercise, fix the **MD5 weak hash in `CryptoUtil.hashPassword(...)`** (Finding B from Task 3.2). The fix replaces MD5 with Spring Security's `BCryptPasswordEncoder`, which is the standard Spring choice for password hashing.

### Task 4.1 -- Add Spring Security to the dependencies

Open `pom.xml`. Inside the `<dependencies>` block, add:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
```

Save the file. IntelliJ will detect the change and offer to reload the Maven project; accept the reload, or right-click `pom.xml` -> **Maven** -> **Reload Project** if prompted.

### Task 4.2 -- Apply the fix

Open `CryptoUtil.java`. Replace the `hashPassword` method:

**Before:**

```java
public String hashPassword(String password) {
    try {
        MessageDigest digest = MessageDigest.getInstance("MD5");
        byte[] hash = digest.digest(password.getBytes());

        StringBuilder hexString = new StringBuilder();
        for (byte b : hash) {
            hexString.append(String.format("%02x", b));
        }
        return hexString.toString();
    } catch (NoSuchAlgorithmException e) {
        throw new RuntimeException("Hash algorithm not available", e);
    }
}
```

**After:**

```java
private final org.springframework.security.crypto.password.PasswordEncoder passwordEncoder =
        new org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder();

public String hashPassword(String password) {
    return passwordEncoder.encode(password);
}
```

You can also clean up the `MessageDigest` and `NoSuchAlgorithmException` imports at the top of the file if you no longer need them.

A real production codebase would inject the `PasswordEncoder` as a `@Bean` rather than instantiating it inline. For lab simplicity, an inline instance is fine; the security improvement is the same.

Save the file.

### Task 4.3 -- Re-scan

Run the same Maven command from Task 2.2:

```bash
mvn clean verify sonar:sonar \
    -Dsonar.host.url=http://localhost:9000 \
    -Dsonar.token=PASTE_YOUR_TOKEN_HERE \
    -Dsonar.projectKey=banking-vulnerable-lab \
    -Dsonar.projectName="Banking Vulnerable Lab"
```

Wait for the build to succeed, then for SonarQube to process the new report (30-60 seconds).

### Task 4.4 -- Verify the fix

Refresh the SonarQube Issues view. You should see:

- One fewer Critical/Blocker vulnerability finding
- The MD5 finding for `hashPassword` is no longer in the list (or is marked as "Closed")
- The other findings remain (you didn't fix them)

If the finding is still showing as open, your fix may not have addressed what SonarQube was complaining about. Look at the finding details again and compare them to your fix. The most common mistake is leaving the `MessageDigest.getInstance("MD5")` call somewhere in the file.

### What this proves

The before-and-after scan demonstrates the full SAST remediation cycle:

1. The original code had a finding
2. You changed the code to use a strong password hashing algorithm
3. The new scan does not find the issue

This is exactly what a CI pipeline would do. Every commit triggers a scan; new findings block the merge; remediated findings drop off automatically. The same pattern works in Checkmarx, Snyk, and other tools.

---

## Exercise 5 -- Write a Suppression Justification

**Estimated time:** 5-10 minutes

### Context

Suppression justifications are part of the security audit trail. Future readers (security engineers, auditors, your future self) will read them to decide whether your dismissal of a finding was sound. A good justification withstands review; a bad one creates an audit problem.

You will write one justification at the "Better" level from Unit 5 Slide 5.12.

### Task 5.1 -- Pick a finding and draft the justification

Pick the false-positive finding from Task 3.5 (the `TEST_FIXTURE_KEY`). If SonarQube did not flag that one, pick any finding you triaged as either "false positive" or "accepted risk" and write the justification as if it had been flagged.

A "Better"-level justification has three parts:

1. **States the tool's allegation.** What did the tool flag?
2. **Explains the actual code behavior.** Why is the allegation wrong (false positive) or accepted (accepted risk)?
3. **Identifies WHY the tool was wrong, or what mitigates the risk.** The diagnostic insight.

### Task 5.2 -- Sample format

Below is a sample for the `TEST_FIXTURE_KEY` false positive. Yours does not need to be word-for-word identical, but it should cover the same three parts.

> False positive. The tool flagged `CryptoUtil.TEST_FIXTURE_KEY` as a hardcoded credential because the constant name contains "Key" and the value is a string literal that resembles a secret. The actual purpose of the constant is to provide a deterministic test fixture for unit tests of the encryption code, as documented in the constant's Javadoc. The production key material is loaded from `EncryptionConfigService.getProductionKey()` at runtime; the test fixture value never reaches production code paths. The tool's analysis matched on the name-plus-string-literal pattern without examining the constant's documented purpose, the use sites, or the runtime configuration that supplies the real key. No remediation required; the documentation comment serves as the audit trail.

Apply this style to whichever finding you chose.

### Task 5.3 -- Add the justification to SonarQube

In SonarQube, find the issue you wrote about. Add your justification as a comment on the issue. Set the status to "Resolved as False Positive" (for false positives) or "Confirmed" with an explanation (for accepted risks).

---

## What You Have Built

You now have hands-on experience with the full SAST workflow:

- Running a SAST tool against a real codebase
- Reading findings and connecting them to the underlying code
- Triaging findings into the four standard categories
- Remediating a true positive and verifying the fix
- Writing audit-quality suppression justifications

The vocabulary you've learned (CWE numbers, severity levels, the Confirm/Classify/Act workflow) maps directly to Checkmarx and to every other modern SAST tool. When you join a team that uses Checkmarx, you will recognize the workflow immediately.

### Key takeaways

1. **SAST tools are noisy by design.** They report things that might be vulnerabilities. Triage is the human's job. Patient analysis is the skill.
2. **Triage produces an audit trail.** "Resolved as False Positive" without a comment is worse than no triage at all. The comment is the deliverable.
3. **CWE is the portable vocabulary.** CWE-327 means weak crypto in SonarQube, in Checkmarx, in Snyk, in Semgrep. The tool changes; the vocabulary doesn't.
4. **Re-scan after every fix.** The fix isn't done until the scan confirms it. A change that "should fix it" but doesn't is more dangerous than no change at all (because the team thinks the issue is closed).
5. **Free tools see less than commercial tools.** SonarQube Community caught the pattern-based findings in this lab. Checkmarx (and SonarQube's commercial editions) would have caught additional findings that require taint analysis. The bank's pipeline uses the more comprehensive tool; the workflow is the same.

---

## What's Next

This is the last lab in Module 10.

- Module 10 wraps with the **Capstone Preparation Discussion**: an instructor-led 30-minute Q&A about the capstone, evaluation criteria, and common pitfalls.
- **Capstone reminder:** capstone projects will be scanned by the bank's AppSec pipeline (typically Checkmarx). High-severity findings must be remediated or formally suppressed with justification. The skills from this lab are direct preparation for that evaluation.

### Cleanup (optional)

When you are done with this lab and don't need SonarQube anymore, you can stop and remove the container:

```bash
docker stop sonarqube
docker rm sonarqube
```

The image stays on disk so you can start a fresh container quickly later. To remove the image entirely (about 700 MB):

```bash
docker rmi sonarqube:community
```

If you plan to keep the SonarQube instance for personal use after the course (for example, scanning your capstone), you can leave the container running. The next time you need to start it after a VM reboot:

```bash
docker start sonarqube
```
