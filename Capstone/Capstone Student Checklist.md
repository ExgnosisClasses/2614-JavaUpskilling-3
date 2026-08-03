# Capstone Checklist: What You Need to Do

This is a high-level map of the work, not a how-to. Each item is something your team
must get done; the details and the rules live in the supplements named in
parentheses. Use it to stay oriented and to divide the work. The testing and SAST
section is intentionally brief because a separate testing document follows.

A good rule before you start: stand up everything and confirm the provided
scaffolding works end to end *before* you change any of it. That gives you a
known-good baseline to compare against when something breaks.

---

## 1. Set up and confirm the starting state

The scaffolding you are given: the authorization server (a ready project), the React
SPA (login, logout, account list, transfers all working), the BFF (passthrough plus
logout), and the BankService/bankapi (a REST mockup with no persistence yet).

- [ ] Create the shared team GitHub repo and agree on how you will integrate work
      (Overview).
- [ ] Bring up Oracle and Kafka in Docker, load the schema and seed, and create the
      Kafka topic (Environment and Build-Day Setup).
- [ ] Run the authorization server and confirm it issues tokens (its `.http` tests).
- [ ] Build and run the payment mock as a standalone service (Payment Mock How-To).
- [ ] Run the SPA, BFF, and bankapi, and confirm the baseline works: you can log in
      and see accounts through the existing flow.
- [ ] Confirm the connection details line up across components: ports, the Oracle
      service name, and the auth server issuer (Environment and Build-Day Setup).

When all of that is green, you have a baseline. Now start building.

---

## 2. React SPA (use Copilot throughout)

The SPA already does customer login, logout, account viewing, and transfers. You add
the missing capability and wire it through the BFF. Lean on Copilot for the
components and forms, and review everything it gives you.

- [ ] Add a payment action for customers, alongside the existing transfer.
- [ ] Add deposit and withdrawal actions for bank staff (teller-only).
- [ ] Differentiate the UI by role: customers and tellers see different actions
      (API Contract and Endpoint Security).
- [ ] Route every new call through the BFF, not directly to bankapi.
- [ ] Handle the error responses the contract defines (403, 422, 502) so the user
      sees a sensible message, not a crash.
- [ ] Build with Copilot and be ready to explain how your AI-assisted code works;
      keep track of how you used it.

---

## 3. BankService (bankapi)

This is the largest piece. The mockup becomes a real, persistent, secured service.

- [ ] Add the JPA persistence layer: entities mapped to the Oracle schema, accessed
      through repositories (JPA Persistence; Data Model).
- [ ] Move all business logic into the service layer, accessed through the
      repositories, with transfers written as two legs in one transaction
      (Business Rules; Data Model).
- [ ] Enforce the business rules in the service layer, including the allow/decline
      conditions and the FAILED-transaction policy (Business Rules).
- [ ] Implement the endpoints with their methods, payloads, and status codes,
      including the public health endpoint (API Contract and Endpoint Security).
- [ ] Secure the service at two layers: the security filter chain for
      authentication and coarse rules, and `@PreAuthorize` plus ownership checks at
      the service layer (API Contract; JPA Persistence).
- [ ] Make the external payment call to the mock and map its failure to the right
      response (API Contract; Payment Mock How-To).
- [ ] Publish the anonymized statistic to Kafka on each completed transaction
      (Kafka Message Schema).
- [ ] Confirm the balance audit trigger fires on balance changes (Data Model).
- [ ] Wrap database errors into domain exceptions so the service stays decoupled
      from the vendor (JPA Persistence).

---

## 4. BFF

The BFF connects the SPA to bankapi. Most of it exists; you extend it for the new
actions and confirm the security boundary.

- [ ] Add passthrough routes for the new endpoints (payments, deposits,
      withdrawals).
- [ ] Confirm the BFF relays the user's token to bankapi so the service sees an
      authenticated caller.
- [ ] Confirm logout invalidates the session and token correctly.
- [ ] Confirm the session and CSRF handling still hold for the new state-changing
      requests coming from the SPA.

---

## 5. Tests and SAST

High level for now; a separate testing document will give the detail.

- [ ] Write unit tests for the service-layer business rules, with the repositories
      mocked (Copilot can help; review what it writes).
- [ ] Write integration tests that exercise a request through to the database,
      including a failure case.
- [ ] Run a SonarQube scan on your code and review and address the findings.

---

## Before the presentation

- [ ] Be able to demonstrate one transaction end to end, from the SPA through the
      BFF, BankService, database, and Kafka, including a failure path.
- [ ] Make sure every team member can speak to part of the system.
