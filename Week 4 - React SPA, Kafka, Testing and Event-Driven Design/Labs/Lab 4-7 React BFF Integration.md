# Module 8: React SPA Development with Secure OAuth
## Lab 4.7 -- Wiring the React SPA to the BFF

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 8 - React SPA Development with Secure OAuth
> **Estimated time:** 90-105 minutes

---

## Overview

In Lab 4.5 you built a React SPA that displayed accounts and processed transfers using a fake backend (Mock Service Worker) running in the browser. In Lab 4.6 you built a real backend: a Spring Boot Backend-for-Frontend (BFF) that authenticates users via OAuth2 and proxies API calls to a resource server.

This lab is the moment they meet. You will:

1. Apply two required corrections to your Lab 4.6 backend: the BFF's authentication entry point (so unauthenticated JSON calls return a clean 401) and bankapi's account store (so a transfer actually changes the displayed balances)
2. Register a new redirect URI on the auth server so the React-app-via-Vite-proxy flow works
3. Add a Vite dev server proxy so the browser sees a single origin (no CORS to deal with in development)
4. Remove MSW from the React app and point its fetch calls at the real BFF
5. Align the React data types and field names to the JSON the BFF actually returns
6. Add a `/api/me` call that runs on app load to detect whether the user is logged in
7. Add a Sign-in screen for unauthenticated users that links to the BFF's OAuth login URL
8. Add a Sign-out button to the header that POSTs to `/logout`
9. Display the logged-in user's name in the header and load accounts only after login

By the end of this lab the full system works end to end: alice opens the React app, clicks "Sign in", logs in on the auth server, returns to the SPA, sees the five bank accounts (A001 through A005) now served by the real resource server through the BFF instead of the in-browser mock, makes a transfer, and sees the balances update.

**This lab assumes Lab 4.5 and Lab 4.6 are complete and working.** You will modify three projects in this lab: the BFF, the auth server, and the React app.

By the end of this lab you will be able to:

- Correct and explain a dual-audience authentication entry point (401 for API calls, redirect for browsers)
- Configure a Vite dev server proxy to forward API calls to a backend
- Replace browser-side mocks with real backend calls
- Align a React app's TypeScript types and field names to the JSON a real backend returns
- Implement an authentication context using React Context
- Wire a React app to an OAuth-protected backend with cookie-based sessions
- Gate data loading on authentication state so requests only fire after login

> **A note on security hardening.** This lab connects the SPA to the BFF and gets the full system working end to end. It does not turn on CSRF protection or apply the other production-grade security measures that a real banking application would need. Those topics are covered in a separate lab on application hardening. Your Lab 4.6 BFF already has CSRF disabled for this reason; leave it disabled for now.

---

## Before You Start

You will need three backend services running for this lab:

| Service | Port | How to start |
|---|---|---|
| Authorization Server | 9000 (reach it at `127.0.0.1`) | Run from IntelliJ |
| Banking Resource Server (`bankapi`) | 8081 | Run from IntelliJ |
| Banking BFF (`bankbff`) | 8080 | Run from IntelliJ |

The React dev server will run on port 5173 (Vite's default).

Confirm all three backend services are healthy before starting:

```
http://127.0.0.1:9000/.well-known/openid-configuration
```

Should return JSON. Confirm the `issuer` field reads `"http://127.0.0.1:9000"`. The auth server is the one service that must be reached at `127.0.0.1`, not `localhost`, so the `iss` claim in its tokens matches what the BFF and resource server expect.

```
http://localhost:8081/api/v1/accounts
```

Should return 401 Unauthorized (correct: the resource server requires a token, and this is the actual path the BFF proxies to).

```
http://localhost:8080/oauth2/authorization/bank-auth
```

In a browser, should redirect you to the auth server's login page.

If any of these fail, return to Lab 4.6 to fix the relevant service before continuing.

---

## Patch 1 (Required Before You Begin): Fix the BFF Authentication Entry Point

**Estimated time:** 10 minutes
**Topics covered:** `ExceptionHandlingConfigurer`, `defaultAuthenticationEntryPointFor` vs `authenticationEntryPoint`, dual-audience routing, `MediaTypeRequestMatcher`

**Do this before any other exercise. The rest of the lab depends on it.**

### Why this is here

Lab 4.6's `SecurityConfig` contains a subtle bug that only shows up once a real client (this lab's SPA) depends on the response. The intent in Lab 4.6 was dual-audience routing: an unauthenticated request that says `Accept: application/json` should get a `401`, while a browser navigation should get a redirect to the login page. The SPA's `/api/me` check relies on that 401 to decide "the user is logged out, show the Sign in button."

As written, every unauthenticated request, JSON or not, gets the login redirect. You can confirm whether you are affected with one command:

```bash
curl -i -H "Accept: application/json" http://localhost:8080/api/me
```

- A `401` means your BFF is already correct and you can skip to Exercise 1.
- A `302` with `Location: .../oauth2/authorization/bank-auth` means you have the bug. Fix it now.

### Task 0.1 -- Understand the bug

Open the BFF project and find `SecurityConfig.java`. The `exceptionHandling` block from Lab 4.6 looks like this:

```java
.exceptionHandling(ex -> ex
        .defaultAuthenticationEntryPointFor(
                new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED),
                new MediaTypeRequestMatcher(MediaType.APPLICATION_JSON))
        .authenticationEntryPoint(
                new LoginUrlAuthenticationEntryPoint(
                        "/oauth2/authorization/bank-auth")))
```

The two calls look complementary, but they are not additive. Spring Security selects the entry point like this:

```java
AuthenticationEntryPoint getAuthenticationEntryPoint(H http) {
    AuthenticationEntryPoint entryPoint = this.authenticationEntryPoint;   // set by .authenticationEntryPoint(...)
    if (entryPoint == null) {
        entryPoint = createDefaultEntryPoint(http);  // the matcher-based one from defaultAuthenticationEntryPointFor
    }
    return entryPoint;
}
```

The instant you call `.authenticationEntryPoint(...)`, `this.authenticationEntryPoint` is non-null, so the framework returns it directly and **never builds the matcher-based entry point**. Your `defaultAuthenticationEntryPointFor(401, JSON)` mapping becomes dead code, and the `LoginUrlAuthenticationEntryPoint` handles every unauthenticated request, including JSON ones. That is why the curl above returns a redirect instead of a 401.

### Task 0.2 -- Apply the fix

Replace the entire `exceptionHandling(...)` block with the version below. The change is to register both entry points through `defaultAuthenticationEntryPointFor` and remove the standalone `.authenticationEntryPoint(...)` call:

```java
.exceptionHandling(ex -> {
    // Match an explicit "application/json" Accept header, not a browser's "*/*".
    MediaTypeRequestMatcher jsonMatcher =
            new MediaTypeRequestMatcher(MediaType.APPLICATION_JSON);
    jsonMatcher.setUseEquals(true);
    ex
            // JSON clients (the SPA's fetch) get a clean 401.
            .defaultAuthenticationEntryPointFor(
                    new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED),
                    jsonMatcher)
            // Everything else (a browser navigating to a protected URL) is
            // redirected into the OAuth login flow.
            .defaultAuthenticationEntryPointFor(
                    new LoginUrlAuthenticationEntryPoint("/oauth2/authorization/bank-auth"),
                    AnyRequestMatcher.INSTANCE);
})
```

Add one import at the top of the file (the others are already present from Lab 4.6):

```java
import org.springframework.security.web.util.matcher.AnyRequestMatcher;
```

Two points worth understanding, because they are the heart of dual-audience routing:

- When more than one mapping is registered, Spring builds a `DelegatingAuthenticationEntryPoint` that tries each matcher in the order you registered it. A JSON request matches the first mapping and gets 401. Anything else falls through to `AnyRequestMatcher`, which matches everything, and gets the login redirect.
- `jsonMatcher.setUseEquals(true)` is the line that makes this actually work. A browser's `Accept` header ends in `*/*`, which is technically "compatible with" `application/json`. Without `useEquals(true)`, a browser navigation would also match the JSON rule and receive a 401 instead of the login page, which defeats the whole point. With `useEquals(true)`, only an Accept header that explicitly contains `application/json` matches, which is exactly what your SPA sends and exactly what a browser address-bar navigation does not.

### Task 0.3 -- Restart and verify

Fully stop and restart the BFF (the security filter chain is built once at startup; a hot reload does not always rebuild it). Then confirm both audiences:

```bash
# JSON client: expect 401
curl -i -H "Accept: application/json" http://localhost:8080/api/me

# Browser navigation: expect 302 to the login flow
curl -i -H "Accept: text/html" http://localhost:8080/api/me
```

When the first command returns `401`, the BFF is correct and you are ready to continue. If it still returns `302`, re-check that you removed the standalone `.authenticationEntryPoint(...)` call, that `@EnableWebSecurity` is present on the class (without it your custom chain can be silently ignored), and that you restarted the process rather than relying on a hot reload.

---

## Patch 2 (Required Before You Begin): Make bankapi Read and Write the Same Account List

**Estimated time:** 5 minutes
**Topics covered:** single source of truth, why the read path and write path must share state

**Do this before Exercise 5.** Without it, a transfer will report success but the displayed balances will never change.

### Why this is here

Lab 4.6 added a `TransferService` to bankapi that holds a mutable list of accounts and updates balances when a transfer runs. But bankapi's `AccountController` still serves `GET /api/v1/accounts` from its own separate, static `ACCOUNTS` list. The two lists drift: a transfer changes the `TransferService` copy, while the SPA reads the `AccountController` copy, which never changes. The result is a transfer that reports success and returns a real transaction ID, but leaves the displayed balances untouched.

`TransferService` already exposes a `listAccounts()` method that was meant to be the single source of truth. You will point `AccountController`'s read endpoints at it and delete the duplicate static list.

### Task 0.4 -- Wire AccountController to TransferService

Open `AccountController.java` in the bankapi project and make three changes.

1. Add the import:

```java
import com.example.bankapi.service.TransferService;
```

2. Add a `TransferService` field and update the constructor to receive it:

```java
private final DownstreamAccountService downstreamAccountService;
private final AuditService auditService;
private final TransferService transferService;

public AccountController(AuditService auditService,
                        DownstreamAccountService downstreamAccountService,
                        TransferService transferService) {
    this.auditService = auditService;
    this.downstreamAccountService = downstreamAccountService;
    this.transferService = transferService;
}
```

3. Replace every read of the static `ACCOUNTS` list with `transferService.listAccounts()`:

```java
@GetMapping
public List<Account> getAll() {
    return transferService.listAccounts();
}

@GetMapping("/{id}")
public ResponseEntity<Account> getById(@PathVariable String id) {
    return transferService.listAccounts().stream()
            .filter(a -> a.id().equals(id))
            .findFirst()
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
}

@GetMapping("/mine")
public List<Account> getMyAccounts(@AuthenticationPrincipal Jwt jwt) {
    String subject = jwt.getSubject();
    List<String> roles = jwt.getClaimAsStringList("roles");
    if (roles == null) roles = List.of();

    boolean isStaff = roles.contains("teller") || roles.contains("auditor");
    if (isStaff) {
        return transferService.listAccounts();
    }
    return transferService.listAccounts().stream()
            .filter(a -> a.customerId().equals(subject))
            .toList();
}
```

Then delete the now-unused static list:

```java
// DELETE this block. TransferService now owns the account state.
private static final List<Account> ACCOUNTS = List.of(
        new Account("A001", "C001", "CHECKING", new BigDecimal("1250.00")),
        new Account("A002", "C001", "SAVINGS",  new BigDecimal("8400.00")),
        new Account("A003", "C002", "CHECKING", new BigDecimal("300.50")),
        new Account("A004", "C003", "CHECKING", new BigDecimal("2100.75")),
        new Account("A005", "C003", "SAVINGS",  new BigDecimal("15000.00"))
);
```

After deleting it, the `java.math.BigDecimal` import in this file is no longer used and can be removed. Leave the `/me`, `/downstream`, and `POST` (create) methods unchanged.

### Task 0.5 -- Restart and verify

Restart bankapi. Reads and writes now share one list, so a transfer is reflected the next time accounts are read. You will confirm this end to end through the SPA in Exercise 5: after a $50 transfer from A001 to A002, A001's balance drops by $50 and A002's rises by $50.

> **Design note.** Keeping the account list inside `TransferService` is expedient for the lab, not a pattern to copy. In a real system the account state lives in a database that is the single source of truth, and both an account-read path and a transfer path operate on it through a repository. Later modules introduce that persistence layer.

---

## Architecture

```
   ┌──────────────────────┐
   │   Browser            │
   │                      │
   │  React SPA           │
   │  (loaded from        │
   │   Vite dev server)   │
   └──────────┬───────────┘
              │
              │ fetch('/api/...') and similar
              │ all to localhost:5173
              ▼
   ┌──────────────────────┐         ┌─────────────────────┐         ┌──────────────────┐
   │   Vite Dev Server    │         │   Banking BFF       │         │  bankapi         │
   │   Port 5173          │ proxies │   (Spring Boot)     │◄───────►│  Resource Server │
   │                      │ /api,   │   Port 8080         │ bearer  │   Port 8081      │
   │   Serves React app   ├────────►│                     │ token   │                  │
   │   Forwards /api,     │ /oauth2,│   From Lab 4.6      │         │   From Lab 4.6   │
   │   /oauth2, /login,   │ /login, │                     │         │                  │
   │   /logout to BFF     │ /logout │                     │         │                  │
   └──────────────────────┘         └──────────┬──────────┘         └──────────────────┘
                                               │
                                               │ OAuth flow
                                               ▼
                                    ┌─────────────────────┐
                                    │  Authorization      │
                                    │  Server             │
                                    │  Port 9000          │
                                    └─────────────────────┘
```

The Vite proxy is the key element that makes development simple. As far as the browser is concerned, every URL is `http://localhost:5173/something`. There is only one origin, so cookies, the OAuth redirect flow, and same-origin restrictions all behave naturally. The proxy quietly forwards `/api/*`, `/oauth2/*`, `/login/*`, and `/logout` to the BFF.

---

## Exercise 1 -- Register the SPA's Redirect URI with the Auth Server

**Estimated time:** 15 minutes
**Topics covered:** OAuth client registration, redirect URI matching, single-origin development with a proxy

### Context

The React dev server runs on port 5173. The BFF runs on port 8080. From the browser's perspective, both look like the same origin (`localhost:5173`) thanks to the Vite proxy you will configure in Exercise 2. There is a subtlety in how the OAuth flow handles redirects, and you need to tell the auth server about it before it will work.

When the React app starts the OAuth flow, the browser sends `GET http://localhost:5173/oauth2/authorization/bank-auth`. Vite proxies this to the BFF on port 8080. The BFF builds an OAuth authorization URL containing a `redirect_uri` parameter and sends a 302 redirect to the auth server.

**Critical detail:** The BFF builds the `redirect_uri` parameter using the `Host` header of the incoming request. Because the proxy is configured with `changeOrigin: false` (Exercise 2), the Host stays as `localhost:5173`. So the `redirect_uri` ends up being `http://localhost:5173/login/oauth2/code/bank-auth`, not `http://localhost:8080/...`.

This is the behavior we want. After login, the browser must come back to port 5173 (where the React app lives), not port 8080. The auth server only accepts `redirect_uri` values that have been pre-registered. In Lab 4.6 you registered only the port-8080 redirect URI. To support the React app integration, you need to add the port-5173 redirect URI as well.

> **This is the single most common cause of a 500 / Whitelabel error page later in this lab.** If the port-5173 redirect URI is not registered on the running auth server, the auth server refuses the redirect and renders a generic error page when you click Sign in. Register it carefully, and restart the auth server afterward.

### Task 1.1 -- Open the auth server project

In IntelliJ, open the auth server project. Navigate to `src/main/java/com/example/authserver/config/AuthorizationServerConfig.java`.

### Task 1.2 -- Add a second redirect URI to bank-client-bff

Find the `bankClientBff` `RegisteredClient` registration. It currently has one `.redirectUri(...)` line. Add a second one right below it:

```java
// Direct access (Lab 4.6 standalone testing)
.redirectUri("http://localhost:8080/login/oauth2/code/bank-auth")
// Through Vite proxy (Lab 4.7 React integration)
.redirectUri("http://localhost:5173/login/oauth2/code/bank-auth")
```

Leave the scopes, client secret, grant types, and token settings exactly as they were in Lab 4.6. You are only adding the second redirect URI.

### Task 1.3 -- Restart the auth server

Stop the auth server in IntelliJ (red Stop button). Start it again (green Run button). Wait for `Started AuthServerApplication` in the console. The restart matters: editing the registration without restarting leaves the old registration in memory.

### Verify Exercise 1

There is no endpoint that lists registered redirect URIs, but you can confirm the proxy-path redirect URI is accepted end to end with curl. First, see what the BFF builds when it thinks the request came through the proxy:

```bash
curl -is -H "Host: localhost:5173" http://localhost:8080/oauth2/authorization/bank-auth | grep -i '^location'
```

The `Location` should contain `redirect_uri=http://localhost:5173/login/oauth2/code/bank-auth`. Copy that entire `http://127.0.0.1:9000/oauth2/authorize?...` URL and request it:

```bash
curl -is "PASTE_THE_AUTHORIZE_URL_HERE" | head -5
```

- A `302` to `http://127.0.0.1:9000/login` means the redirect URI is registered and accepted. You are good.
- An error page (or a non-redirect) means the URI is not registered on the running auth server. Recheck Task 1.2 and confirm you restarted the auth server in Task 1.3.

---

## Exercise 2 -- Configure the Vite Dev Server Proxy

**Estimated time:** 10 minutes
**Topics covered:** Vite configuration, dev server proxying, single-origin architecture

### Task 2.1 -- Open the React project

Open the `banking-ui` project from Lab 4.5 in VS Code.

### Task 2.2 -- Add the proxy configuration

Open `vite.config.ts` in the project root. Replace its contents with:

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      // Forward all backend paths to the BFF on port 8080.
      // The browser only ever talks to localhost:5173 in development.
      '/api':     { target: 'http://localhost:8080', changeOrigin: false },
      '/oauth2':  { target: 'http://localhost:8080', changeOrigin: false },
      '/login':   { target: 'http://localhost:8080', changeOrigin: false },
      '/logout':  { target: 'http://localhost:8080', changeOrigin: false },
    },
  },
});
```

Notes on the proxy configuration:

- `target` is where requests get forwarded.
- `changeOrigin: false` keeps the original `Host` header (`localhost:5173`). This matters for OAuth: the BFF builds redirect URIs from the Host header it sees. Keeping it as `localhost:5173` means the redirect URI is `http://localhost:5173/login/oauth2/code/bank-auth`, which sends the browser back through the proxy on the callback and preserves the session cookie. With `changeOrigin: true`, the Host would become `localhost:8080`, the auth server would redirect the browser directly to port 8080, and the proxied session would be lost.
- The four prefixes cover everything: `/api/*` is the application API, `/oauth2/*` starts the OAuth flow, `/login/*` is where the OAuth callback lands, `/logout` ends the session.

### Verify Exercise 2

Stop the React dev server if it is running, then start it again:

```bash
npm run dev
```

The server should start on port 5173 with no errors. You will not see the proxy do anything yet because we have not modified the React code to call the BFF.

---

## Exercise 3 -- Remove Mock Service Worker

**Estimated time:** 10 minutes
**Topics covered:** Removing development scaffolding, real backend integration

### Context

The React app from Lab 4.5 used MSW to intercept fetch calls in the browser and return canned data. With the BFF and resource server providing real data, MSW is no longer needed. You will remove it cleanly.

### Task 3.1 -- Stop the MSW worker from starting

Open `src/main.tsx`. Replace its contents with:

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

The `enableMocking` wrapper is gone. The app starts directly. (Exercise 4 will add the `AuthProvider` here.)

### Task 3.2 -- Delete the mocks folder

In VS Code's file explorer, right-click `src/mocks/` and delete it. Two files go away: `handlers.ts` and `browser.ts`.

### Task 3.3 -- Uninstall the MSW package

In a terminal at the project root:

```bash
npm uninstall msw
```

### Task 3.4 -- Delete the MSW service worker file

In `public/`, delete the file `mockServiceWorker.js`.

### Verify Exercise 3

Restart the dev server (`npm run dev`) and open `http://localhost:5173`. The Header renders, but the accounts area shows an error. That is expected at this stage: the SPA is now sending real calls to the BFF, but there is no session yet.

Open DevTools, switch to the Network tab, tick **Preserve log**, and reload. Look at the `/api/accounts` request:

- Request URL: `http://localhost:5173/api/accounts` (the SPA still talks to its own origin; the Vite proxy forwards it to the BFF on 8080)
- Status: **302**, redirected into `/oauth2/authorization/bank-auth`. The `fetch` then fails because it cannot complete the cross-origin redirect to the auth server, so the accounts area shows an error.

**Why a redirect and not a 401?** The Lab 4.5 version of `client.ts` calls `fetch('/api/accounts')` with no `Accept` header, so the browser sends `Accept: */*`. After the Patch section, your BFF treats `*/*` as a browser navigation and redirects it into the login flow rather than returning a 401. In Exercise 4 you will rewrite `client.ts` to send `Accept: application/json`, which is what makes the BFF return a clean 401 the app can detect. For now, the redirect-then-error in the accounts area is the expected Exercise 3 result. It proves MSW is gone and the SPA is reaching the real BFF through the proxy.

---

## Exercise 4 -- Align the Data Types and Build the Authentication Context

**Estimated time:** 25 minutes
**Topics covered:** Matching a backend's JSON contract, React Context, useState, useEffect, conditional rendering, auth state propagation

### Context

Two things change in this exercise.

First, the data shapes. In Lab 4.5 the mock returned accounts shaped for the UI: an `accountNumber`, a `status`, and a `type`. The real backend is different. The BFF passes the resource server's JSON straight through, so an account now arrives as:

```json
{ "id": "A001", "customerId": "C001", "accountType": "CHECKING", "balance": 1250.00 }
```

There is no `accountNumber` (the identifier is `id`), the type field is `accountType`, and there is no `status` field at all. The transfer request the BFF expects uses `fromAccountId` and `toAccountId`. And `/api/me` returns the BFF's `UserInfoDto`: `subject`, `preferredUsername`, `fullName`, `roles`. You will update the React types to match these real shapes exactly. Once the types match, the rest of the React code reads the backend's data directly with no translation layer.

Second, authentication state. The Header needs the user's name; the App needs to choose between the login screen and the main UI and to load accounts only after login. React Context lets us put the auth state in one place and let any descendant component read it directly.

You will also add the `Accept: application/json` header to every request in `client.ts`. Combined with the BFF fix from the Patch section, this is what turns the unauthenticated `/api/me` response from a redirect into a clean 401, which the AuthContext uses to mean "not logged in."

### Task 4.1 -- Update the API types to match the BFF

Open `src/api/types.ts` and replace its contents:

```ts
/**
 * TypeScript types for the banking API.
 *
 * These types mirror the JSON the BFF returns. The BFF passes the resource
 * server's shapes straight through, so Account here matches bankapi's
 * AccountDto (id, customerId, accountType, balance) and User matches the
 * BFF's UserInfoDto returned by /api/me.
 */

export type AccountType = 'SAVINGS' | 'CHECKING';

export type Account = {
  id: string;
  customerId: string;
  accountType: AccountType;
  balance: number;
};

export type TransferRequest = {
  fromAccountId: string;
  toAccountId: string;
  amount: number;
};

export type TransferResponse = {
  transactionId: string;
  status: 'COMPLETE' | 'FAILED';
};

// Matches the UserInfoDto returned by the BFF's /api/me endpoint.
export type User = {
  subject: string;
  preferredUsername: string;
  fullName: string;
  roles: string[];
};
```

What changed from your Lab 4.5 version, and why:

- `Account.accountNumber` becomes `Account.id`, and `Account.type` becomes `Account.accountType`. These are the field names the resource server uses.
- `Account.status` is gone. The resource server does not return an account status, so the Lab 4.5 "Status" column and the ACTIVE filter both come out in this lab.
- `customerId` is added because the backend returns it.
- `TransferRequest` now uses `fromAccountId` and `toAccountId`. The BFF binds the POST body by field name; these must match its `TransferRequestDto` exactly or it will read null account IDs and the transfer will fail.
- `User` now uses `subject`, `preferredUsername`, and `fullName`, matching the BFF's `UserInfoDto`.

### Task 4.2 -- Rewrite the API client

Open `src/api/client.ts` and replace its contents:

```ts
/**
 * API client for the banking backend.
 *
 * All HTTP communication with the backend goes through this file. Requests use
 * same-origin URLs that the Vite proxy forwards to the BFF on port 8080. Every
 * request sends "Accept: application/json", which is what makes the BFF return
 * a 401 (rather than a login redirect) when there is no session. The response
 * shapes match the types in types.ts directly, so there is no translation layer.
 */

import type { Account, TransferRequest, TransferResponse, User } from './types';

export async function getCurrentUser(): Promise<User | null> {
  const response = await fetch('/api/me', {
    headers: { Accept: 'application/json' },
  });
  if (response.status === 401) {
    return null; // not logged in
  }
  if (!response.ok) {
    throw new Error(`Failed to load user: ${response.status}`);
  }
  return response.json();
}

export async function getAccounts(): Promise<Account[]> {
  const response = await fetch('/api/accounts', {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`Failed to load accounts: ${response.status}`);
  }
  return response.json();
}

export async function postTransfer(
  request: TransferRequest
): Promise<TransferResponse> {
  const response = await fetch('/api/transfers', {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(request),
  });
  if (!response.ok) {
    const message = await safeReadErrorMessage(response);
    throw new Error(message || `Transfer failed: ${response.status}`);
  }
  return response.json();
}

export async function logout(): Promise<void> {
  const response = await fetch('/logout', {
    method: 'POST',
    headers: { Accept: 'application/json' },
  });
  if (!response.ok && response.status !== 302) {
    throw new Error(`Logout failed: ${response.status}`);
  }
}

async function safeReadErrorMessage(response: Response): Promise<string | null> {
  try {
    const body = await response.json();
    if (body && typeof body.message === 'string') {
      return body.message;
    }
    return null;
  } catch {
    return null;
  }
}
```

Notes:

- The `Accept: application/json` header on every request is the client side of the dual-audience routing you fixed in the Patch section. The BFF sees it and returns 401 for unauthenticated calls instead of a login redirect.
- `getCurrentUser` returns `null` instead of throwing when the user is not logged in. That is a normal state, not an error, and it is the signal the AuthContext uses to show the Sign in screen.
- `logout` accepts both 200 and 302 as success.

### Task 4.3 -- Create the AuthContext

Create a new file `src/auth/AuthContext.tsx` (create the `auth` folder first):

```tsx
/**
 * Authentication context.
 *
 * Exposes the current logged-in user (or null) and a function to re-check
 * authentication state with the BFF. Wraps the whole app so any component can
 * read auth state via the useAuth() hook.
 */

/* eslint-disable react-refresh/only-export-components */

import { createContext, useContext, useState, useEffect, useCallback } from 'react';
import type { ReactNode } from 'react';
import { getCurrentUser } from '../api/client';
import type { User } from '../api/types';

type AuthContextValue = {
  user: User | null;
  loading: boolean;
  refresh: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

type AuthProviderProps = {
  children: ReactNode;
};

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState<boolean>(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const result = await getCurrentUser();
      setUser(result);
    } catch (e) {
      console.error('Failed to refresh auth state:', e);
      setUser(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return (
    <AuthContext.Provider value={{ user, loading, refresh }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return ctx;
}
```

### Task 4.4 -- Wrap the app in the AuthProvider

Open `src/main.tsx` and wrap `<App />` in `<AuthProvider>`:

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './App';
import { AuthProvider } from './auth/AuthContext';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <AuthProvider>
      <App />
    </AuthProvider>
  </React.StrictMode>
);
```

### Verify Exercise 4

Restart the dev server and open `http://localhost:5173`. Open DevTools, go to the Network tab, tick **Preserve log**, and reload.

You should see a `GET /api/me` request that returns **401** (not a 302 redirect). That 401 is the AuthProvider's initial check working correctly: `getCurrentUser` reads it as "logged out" and returns `null`.

Two things that are normal and not errors:

- You will likely see `/api/me` fire **twice**. In development, `React.StrictMode` deliberately mounts, unmounts, and remounts each component once to surface side-effect bugs, so the effect runs twice. Both calls return 401. This double-invoke does not happen in a production build.
- The accounts area still looks broken. That is expected. The Sign-in screen and the working accounts list arrive in Exercise 5. The only thing Exercise 4 proves is that `/api/me` returns a clean 401 and the app does not crash.

If `/api/me` returns a `302` instead of `401`, or its Response is an HTML login page, the BFF patch did not take effect. Re-run the curl from the Patch section and restart the BFF.

---

## Exercise 5 -- Build the Sign-In Screen and Conditional UI

**Estimated time:** 25 minutes
**Topics covered:** Conditional rendering, anchor tags vs button-driven navigation, React Context consumption, auth-gated data loading

### Context

Now that the AuthContext knows whether the user is logged in, the App component can decide what to show:

- **While the auth check is in progress (`loading: true`)**: a loading indicator
- **When no user is logged in (`user === null`)**: a Sign-in screen with a link to start the OAuth flow
- **When a user is logged in (`user !== null`)**: the accounts list and transfer form

Your `AccountList` and `TransferForm` already receive their data as props (you lifted that state up to App in Lab 4.5). The structural change here is smaller than it sounds: App must now wait until a user is authenticated before loading accounts, and the two components must reference the real BFF field names (`id`, `accountType`) instead of the Lab 4.5 mock fields (`accountNumber`, `type`, `status`).

### Task 5.1 -- Create the SignInScreen component

Create `src/components/SignInScreen.tsx`:

```tsx
/**
 * Sign-in screen shown to unauthenticated users.
 *
 * Renders a single anchor tag pointing at the BFF's OAuth login URL. We use an
 * anchor (full page navigation) rather than a fetch call because the OAuth flow
 * involves redirects through the auth server that the browser must follow on
 * its own. fetch and AJAX cannot follow cross-origin redirects to HTML pages.
 */

export function SignInScreen() {
  return (
    <section className="sign-in-screen">
      <h2>Welcome to MD282 Bank</h2>
      <p>Sign in to view your accounts and transfer funds.</p>
      <a href="/oauth2/authorization/bank-auth" className="sign-in-button">
        Sign in
      </a>
    </section>
  );
}
```

The most important detail: the Sign-in element is an `<a href="...">` tag, not a `<button>` with an onClick handler. The OAuth flow needs the browser to navigate, following the redirect from the BFF to the auth server and back. A `fetch` call cannot do that because it cannot follow a redirect to an HTML page on a different origin.

### Task 5.2 -- Update the Header to show the logged-in user

Open `src/components/Header.tsx` and replace its contents:

```tsx
/**
 * Header component.
 *
 * Reads the current user from the auth context. When a user is logged in, shows
 * their name and a Sign-out button.
 */

import { useAuth } from '../auth/AuthContext';
import { logout as logoutApi } from '../api/client';

export function Header() {
  const { user, refresh } = useAuth();

  async function handleSignOut() {
    try {
      await logoutApi();
    } catch (e) {
      console.error('Logout failed:', e);
    } finally {
      // Re-check auth state regardless of whether the call succeeded.
      await refresh();
    }
  }

  return (
    <header className="header">
      <div className="header-content">
        <div>
          <h1>MD282 Bank</h1>
          <p className="tagline">Online Banking</p>
        </div>
        {user && (
          <div className="header-user">
            <span className="user-name">Hello, {user.preferredUsername}</span>
            <button type="button" onClick={handleSignOut} className="sign-out-button">
              Sign out
            </button>
          </div>
        )}
      </div>
    </header>
  );
}
```

`{user && (...)}` renders the user block only when `user` is truthy. The header shows `user.preferredUsername` (the login name, for example `alice`), not `user.fullName` (the display name, `Alice Nguyen`). Use whichever fits your design; this lab uses the login name to match the verify steps.

### Task 5.3 -- Update App.tsx to render conditionally

Open `src/App.tsx` and replace its contents:

```tsx
/**
 * Root component.
 *
 * Reads the auth state and decides what to render:
 *  - loading: a "checking sign-in state" message
 *  - not logged in: the SignInScreen
 *  - logged in: the accounts list and transfer form
 *
 * App owns the accounts data (lifted up in Lab 4.5) and, new in this lab, only
 * loads it once a user is authenticated. After a successful transfer,
 * onTransferComplete re-fetches accounts so balances update.
 */

import { useState, useEffect, useCallback } from 'react';
import { Header } from './components/Header';
import { AccountList } from './components/AccountList';
import { TransferForm } from './components/TransferForm';
import { SignInScreen } from './components/SignInScreen';
import { useAuth } from './auth/AuthContext';
import { getAccounts } from './api/client';
import type { Account } from './api/types';
import './App.css';

export function App() {
  const { user, loading: authLoading } = useAuth();

  const [accounts, setAccounts] = useState<Account[]>([]);
  const [accountsLoading, setAccountsLoading] = useState<boolean>(false);
  const [accountsError, setAccountsError] = useState<string | null>(null);

  const loadAccounts = useCallback(async () => {
    setAccountsLoading(true);
    setAccountsError(null);
    try {
      const data = await getAccounts();
      setAccounts(data);
    } catch (e) {
      setAccountsError(e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setAccountsLoading(false);
    }
  }, []);

  // Load accounts once a user becomes available (the auth gate).
  useEffect(() => {
    if (user) {
      loadAccounts();
    }
  }, [user, loadAccounts]);

  return (
    <div className="app">
      <Header />
      <main>
        {authLoading && <p className="status-message">Checking sign-in state...</p>}
        {!authLoading && !user && <SignInScreen />}
        {!authLoading && user && (
          <>
            <AccountList
              accounts={accounts}
              loading={accountsLoading}
              error={accountsError}
            />
            <TransferForm accounts={accounts} onTransferComplete={loadAccounts} />
          </>
        )}
      </main>
    </div>
  );
}
```

The `if (user)` guard in the effect is the auth gate: accounts load only after the `/api/me` check returns a user. Without it, the SPA would fire `GET /api/accounts` before login and get a 401 every time.

### Task 5.4 -- Update AccountList and TransferForm for the real field names

Your Lab 4.5 versions of these components already accept their data as props. The change here is to reference the BFF's field names (`account.id`, `account.accountType`) instead of the mock's, and to drop the Status column and the ACTIVE filter, since the backend returns no status.

#### Update src/components/AccountList.tsx

```tsx
import type { Account } from '../api/types';

type AccountListProps = {
  accounts: Account[];
  loading: boolean;
  error: string | null;
};

export function AccountList({ accounts, loading, error }: AccountListProps) {
  if (loading) {
    return <p className="status-message">Loading accounts...</p>;
  }

  if (error) {
    return <p className="error-message">Error loading accounts: {error}</p>;
  }

  if (accounts.length === 0) {
    return <p className="status-message">No accounts found.</p>;
  }

  return (
    <section className="account-list">
      <h2>Your Accounts</h2>
      <table>
        <thead>
          <tr>
            <th>Account</th>
            <th>Type</th>
            <th>Balance</th>
          </tr>
        </thead>
        <tbody>
          {accounts.map((account) => (
            <tr key={account.id}>
              <td>{account.id}</td>
              <td>{account.accountType}</td>
              <td>${account.balance.toFixed(2)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
```

If your Lab 4.5 version used the `formatCurrency` helper from `src/utils/format.ts`, you can keep using it in place of `account.balance.toFixed(2)`.

#### Update src/components/TransferForm.tsx

```tsx
import { useState } from 'react';
import { postTransfer } from '../api/client';
import type { Account } from '../api/types';

type TransferFormProps = {
  accounts: Account[];
  onTransferComplete: () => void;
};

export function TransferForm({ accounts, onTransferComplete }: TransferFormProps) {
  const [fromAccount, setFromAccount] = useState<string>('');
  const [toAccount, setToAccount] = useState<string>('');
  const [amount, setAmount] = useState<string>('');
  const [submitting, setSubmitting] = useState<boolean>(false);
  const [message, setMessage] = useState<string | null>(null);
  const [messageType, setMessageType] = useState<'success' | 'error' | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setMessage(null);
    setMessageType(null);

    const amountNumber = parseFloat(amount);
    if (!fromAccount || !toAccount || isNaN(amountNumber) || amountNumber <= 0) {
      setMessage('Please fill in all fields with valid values.');
      setMessageType('error');
      return;
    }

    if (fromAccount === toAccount) {
      setMessage('From and to accounts must be different.');
      setMessageType('error');
      return;
    }

    setSubmitting(true);
    try {
      const result = await postTransfer({
        fromAccountId: fromAccount,
        toAccountId: toAccount,
        amount: amountNumber,
      });
      if (result.status === 'FAILED') {
        setMessage('Transfer failed. Check the accounts and that the source has sufficient funds.');
        setMessageType('error');
      } else {
        setMessage(`Transfer complete. Transaction ID: ${result.transactionId}`);
        setMessageType('success');
        setFromAccount('');
        setToAccount('');
        setAmount('');
        onTransferComplete();
      }
    } catch (e) {
      setMessage(e instanceof Error ? e.message : 'Transfer failed.');
      setMessageType('error');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="transfer-form">
      <h2>Transfer Funds</h2>
      <form onSubmit={handleSubmit}>
        <div className="form-row">
          <label htmlFor="from-account">From Account</label>
          <select
            id="from-account"
            value={fromAccount}
            onChange={(e) => setFromAccount(e.target.value)}
          >
            <option value="">-- Select --</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.id} ({a.accountType}, ${a.balance.toFixed(2)})
              </option>
            ))}
          </select>
        </div>
        <div className="form-row">
          <label htmlFor="to-account">To Account</label>
          <select
            id="to-account"
            value={toAccount}
            onChange={(e) => setToAccount(e.target.value)}
          >
            <option value="">-- Select --</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.id} ({a.accountType}, ${a.balance.toFixed(2)})
              </option>
            ))}
          </select>
        </div>
        <div className="form-row">
          <label htmlFor="amount">Amount</label>
          <input
            id="amount"
            type="number"
            step="0.01"
            min="0.01"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>
        <button type="submit" disabled={submitting}>
          {submitting ? 'Processing...' : 'Submit Transfer'}
        </button>
        {message && (
          <p className={messageType === 'success' ? 'success-message' : 'error-message'}>
            {message}
          </p>
        )}
      </form>
    </section>
  );
}
```

The key changes from your Lab 4.5 version:

1. The dropdown `key`, `value`, and label use `a.id` and `a.accountType` instead of `a.accountNumber` and `a.type`.
2. The transfer body sends `fromAccountId` and `toAccountId`, which is what the BFF's `TransferRequestDto` expects. Sending `fromAccountNumber` here would bind to null on the server and the transfer would fail.
3. If your Lab 4.5 TransferForm filtered the dropdown to `status === 'ACTIVE'` accounts, remove that filter. The backend returns no status, so the dropdown should list every account.
4. The success branch checks `result.status`. The BFF can return `{ status: 'FAILED' }` with a 200 (for example, insufficient funds), so treating any 2xx as success would show a false "Transfer complete". Only a `COMPLETE` clears the form and refreshes the balances.

### Task 5.5 -- Add CSS for the new components

Open `src/App.css` and add the following at the bottom:

```css
/* Header user info */

.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.header-user {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.user-name {
  font-size: 0.9375rem;
}

.sign-out-button {
  padding: 0.375rem 1rem;
  background-color: rgba(255, 255, 255, 0.15);
  color: white;
  border: 1px solid rgba(255, 255, 255, 0.4);
  border-radius: 4px;
  font-size: 0.875rem;
  transition: background-color 0.15s ease;
}

.sign-out-button:hover {
  background-color: rgba(255, 255, 255, 0.25);
}

/* Sign-in screen */

.sign-in-screen {
  background-color: white;
  padding: 3rem 2rem;
  border-radius: 8px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  text-align: center;
}

.sign-in-screen h2 {
  margin: 0 0 0.5rem 0;
  font-size: 1.5rem;
  color: #2d3748;
}

.sign-in-screen p {
  margin: 0 0 2rem 0;
  color: #4a5568;
}

.sign-in-button {
  display: inline-block;
  padding: 0.75rem 2rem;
  background-color: #1f6feb;
  color: white;
  text-decoration: none;
  border-radius: 4px;
  font-weight: 500;
  font-size: 1rem;
  transition: background-color 0.15s ease;
}

.sign-in-button:hover {
  background-color: #1858c4;
}
```

This assumes your Lab 4.5 `App.css` already defines `.status-message`, `.error-message`, and `.success-message`. If it does not, add them:

```css
.status-message { color: #4a5568; font-size: 0.9375rem; }
.error-message { margin-top: 1rem; color: #c53030; font-size: 0.9375rem; }
.success-message { margin-top: 1rem; color: #276749; font-size: 0.9375rem; }
```

### Verify Exercise 5

Restart the dev server if needed. Open `http://localhost:5173`.

You should see:

1. Briefly: "Checking sign-in state..."
2. Then: the Welcome screen with a "Sign in" button

Click "Sign in". You should be redirected to `http://127.0.0.1:9000/login` (the auth server's login page). Log in as `alice` / `password`.

After login, the auth server redirects back to `/login/oauth2/code/bank-auth`, the BFF processes the callback, and the browser ends up at `/`. The AuthContext runs `/api/me` again, gets a 200 with alice's info, and renders the header with "Hello, alice", the accounts list with five accounts (A001 through A005), and the transfer form.

Try a transfer of $50 from A001 to A002. The success message appears with a real transaction ID (for example `T-1A2B3C4D`), and the AccountList table updates to reflect the new balances: A001 drops by $50 and A002 rises by $50. (If the success message shows but the balances do not change, you skipped Patch 2.)

Click Sign out. You should return to the welcome screen with no user info in the header.

---

## Exercise 6 -- Final End-to-End Test

**Estimated time:** 10 minutes

1. **Open the app fresh.** In a private/incognito window, navigate to `http://localhost:5173`. You should briefly see "Checking sign-in state..." then the Welcome screen.
2. **Sign in.** Click "Sign in", log in as `alice` / `password`. You should land back at `http://localhost:5173` with the header showing "Hello, alice" and five accounts (A001 through A005).
3. **Make a transfer.** Transfer $250 from A001 to A002. The success message appears with a real transaction ID, and the balances update (A001 down $250, A002 up $250).
4. **Reload the page.** Hit F5. The auth check runs again, you stay logged in, and accounts reload with post-transfer balances.
5. **Open a new tab.** In a new tab, open `http://localhost:5173`. You should be logged in immediately (the `BFF_SESSION` cookie is shared between tabs).
6. **Sign out.** Click "Sign out". You return to the Welcome screen. Reloading keeps you on the Welcome screen.
7. **Sign in as bob.** Sign in again as `bob` / `password`. The header shows "Hello, bob". (The accounts are the same five for every user; the resource server in this lab returns all accounts rather than filtering by the logged-in customer.)

If all seven steps work, you have built a complete OAuth-secured React + Spring Boot system using the BFF pattern.

---

## Troubleshooting

These are the failure modes most commonly hit in this lab, with the symptom you see in the browser and the fix.

**Clicking "Sign in" shows a Whitelabel 500 / "no explicit mapping for /error".**
The auth server is rejecting the redirect URI the BFF built for the proxy path. The port-5173 redirect URI is not registered on the running auth server, or the auth server was not restarted after you edited it. Redo Exercise 1, including the restart, and use the Exercise 1 curl check to confirm the authorize URL returns a 302 to `/login`.

**`/api/me` returns a 302 (or an HTML login page) instead of a 401.**
The BFF authentication entry point is not doing dual-audience routing. Redo the Patch section: remove the standalone `.authenticationEntryPoint(...)` call, register both entry points via `defaultAuthenticationEntryPointFor`, set `jsonMatcher.setUseEquals(true)`, confirm `@EnableWebSecurity` is on the class, and fully restart the BFF.

**The SPA shows "accounts not available" and never shows the Sign-in screen.**
This usually follows from the previous item. If `/api/me` returns a redirect instead of a 401, `getCurrentUser` cannot cleanly detect "logged out", so the app never renders the Sign-in screen and never gives you a chance to log in. Fix the 401 first.

**A direct visit to `http://localhost:5173/api/accounts` shows data, but the SPA does not.**
That direct visit is a browser navigation (`Accept: text/html`): the BFF runs you through login, sets a session, and returns data. The SPA's `fetch` is a separate path with no session yet. This is expected before you finish Exercises 4 and 5. It is not a bug.

**A `fetch` to `/api/me` fails with a CORS / "Failed to fetch" error in the console.**
The BFF answered with a 302 to the auth server and the browser tried to follow it cross-origin. The underlying cause is again the entry point returning a redirect instead of a 401. Fix the Patch section.

**The OAuth round trip completes but the BFF 500s on the callback (`/login/oauth2/code/bank-auth`).**
Token exchange is failing. Confirm the BFF's `client-secret` matches the auth server registration (`bank-client-bff-secret`), and that the BFF's `provider.bank-auth.issuer-uri` is `http://127.0.0.1:9000` so the token and JWKS endpoints resolve to the same host that issues the tokens.

**A transfer shows "Transfer complete" but the balances never change.**
You skipped Patch 2. bankapi is serving `GET /api/v1/accounts` from its static `ACCOUNTS` list while `TransferService` mutates a separate list, so reads never see writes. Wire `AccountController`'s read endpoints to `transferService.listAccounts()`, delete the static list, and restart bankapi.

**The transfer message shows `Transaction ID: null` or reports failure.**
The transfer returned `FAILED` from bankapi, which happens when an account ID does not exist or the source has insufficient funds. Confirm you are transferring between two of A001 through A005 and that the amount does not exceed the source balance.

---

## What You Have Built

You have built the full reference architecture for a modern web application that uses OAuth for authentication:

- **A React SPA** that owns the user interface. It has no idea what an OAuth token looks like and holds no API keys.
- **A Spring Boot BFF** that owns authentication. It performs the OAuth Authorization Code flow, holds tokens server-side in the user's session, refreshes them transparently, and proxies API calls to the resource server with bearer tokens attached. It returns 401 to JSON clients and redirects browsers to login.
- **A Spring Boot Resource Server** that owns the business data. It validates JWT bearer tokens against the auth server's JWKS endpoint and serves accounts and transfers.

To add a feature you typically only add a resource-server endpoint, a thin BFF proxy method, and a SPA fetch call. The authentication and token handling were built once and apply to every endpoint.

A separate lab on application hardening covers the production security measures this lab leaves out: CSRF protection, secure cookie flags, content security policies, and so on.

---

## Reflection Questions

In a new file `lab-4.7-notes.md` in the `banking-ui` project root, answer these:

1. The Vite proxy made cross-origin calls disappear in development. What would you need to add or change to deploy this app to production where the React build is served by a separate web server?

2. The Sign-in element is an `<a>` tag, not a `<button>` with an onClick handler. Why? What would happen if you tried `fetch('/oauth2/authorization/bank-auth')` instead?

3. The BFF returns a 401 for `Accept: application/json` and a redirect for a browser navigation, even though both are unauthenticated requests to the same URL. Explain the mechanism that makes this work, and why `setUseEquals(true)` on the JSON matcher is necessary.

4. App.tsx owns the accounts state and passes it to both AccountList and TransferForm. After a transfer, `onTransferComplete` triggers a single reload in App. Why is having App own the data better here than letting each component fetch its own copy? Give at least two concrete behaviors this enables.

5. In Lab 4.5 the mock returned an `accountNumber`, a `type`, and a `status` for each account. The real backend returns `id`, `accountType`, and no status. You updated the React types to match. What would have happened if you had left the types as they were in Lab 4.5 and just pointed the fetch calls at the BFF?

6. The `useAuth()` hook reads from a Context. What would change about the application's structure if every component needed to know about the user, but you used prop-drilling instead of Context?

7. Coming from C#, how does this React + BFF architecture compare to a Blazor Server or ASP.NET MVC application? What are the trade-offs?

---

## What's Next

You have completed the React-to-BFF integration. The full system runs end to end with real OAuth-based authentication. Subsequent labs cover:

- **Application hardening:** CSRF protection, secure cookies, and other production-grade security measures
- **Real-world OAuth providers:** swapping the local mock auth server for Google or another commercial identity provider

Together, these labs prepare you to build production-quality OAuth-protected applications for your capstone project.
