# Module 8: React SPA Development with Secure OAuth
## Lab 4.7 -- Solutions and Checkpoint Answers

> **Course:** MD282 - Java Full-Stack Development
> **Purpose:** This file is the complete, working reference solution for Lab 4.7.
> It contains the final state of every file you touch, the answers to every
> Reflection question, and a clear before/after for each change so you can check
> your work. Reading the solution before attempting a task defeats the purpose
> of the exercise.

> **Companion:** A complete, runnable copy of the finished React app is provided
> separately as `banking-ui.zip`. This file is the per-file reference plus the
> backend patches and answers.

---

## How to Use This File

The solution spans two codebases:

- **The backend** (the auth server, `bankapi`, and `bankbff` you built in Lab 4.6). Lab 4.7 makes three corrections to it: one on the auth server and two patches to fix bugs carried over from Lab 4.6.
- **The React app** (`banking-ui`, from Lab 4.5). Lab 4.7 rewires it to talk to the real BFF.

Changes to the backend are described as deltas from your **Lab 4.6** solution. Changes to the React app are deltas from your **Lab 4.5** solution. Each section marks what changed and why.

---

## Summary of Changes from Lab 4.6 (and Lab 4.5)

**Backend (changes to your Lab 4.6 solution):**

| File | Project | Change |
|---|---|---|
| `AuthorizationServerConfig.java` | auth server | Add a second redirect URI for `http://localhost:5173/...` (Exercise 1) |
| `SecurityConfig.java` | `bankbff` | Fix the authentication entry point so JSON requests get 401 and browsers get a redirect (Patch 1) |
| `AccountController.java` | `bankapi` | Serve accounts from `TransferService.listAccounts()` instead of a private static list, so transfers are reflected on reads (Patch 2) |

**React app (changes to your Lab 4.5 solution):**

| File | Change |
|---|---|
| `vite.config.ts` | Add a dev-server proxy to the BFF (Exercise 2) |
| `src/main.tsx` | Remove MSW; wrap `<App />` in `<AuthProvider>` (Exercises 3, 4) |
| `src/mocks/` | Deleted (Exercise 3) |
| `package.json` | `msw` removed (Exercise 3) |
| `public/mockServiceWorker.js` | Deleted (Exercise 3) |
| `src/api/types.ts` | Types aligned to the BFF JSON: `id`/`customerId`/`accountType`, `fromAccountId`/`toAccountId`, and a `User` matching `UserInfoDto` (Exercise 4) |
| `src/api/client.ts` | Every request sends `Accept: application/json`; add `getCurrentUser` and `logout` (Exercise 4) |
| `src/auth/AuthContext.tsx` | New: `AuthProvider` + `useAuth` (Exercise 4) |
| `src/components/SignInScreen.tsx` | New: anchor to the OAuth login URL (Exercise 5) |
| `src/components/Header.tsx` | Show `preferredUsername` and a Sign-out button (Exercise 5) |
| `src/App.tsx` | Conditional rendering and the auth gate (`if (user) loadAccounts()`) (Exercise 5) |
| `src/components/AccountList.tsx` | Use `id`/`accountType`; drop the Status column (Exercise 5) |
| `src/components/TransferForm.tsx` | Use `id`/`accountType` and `fromAccountId`/`toAccountId`; check `result.status` (Exercise 5) |
| `src/App.css` | Header and sign-in styles (Exercise 5) |

The two backend patches (Patch 1 and Patch 2) fix defects that were latent in Lab 4.6 and only surface once the SPA depends on the responses.

---

## Patch 1 (Backend) -- BFF Authentication Entry Point

**File:** `bankbff` / `SecurityConfig.java`

### What was wrong in the Lab 4.6 solution

The Lab 4.6 `exceptionHandling` block looked like this:

```java
// LAB 4.6 (buggy)
.exceptionHandling(ex -> ex
        .defaultAuthenticationEntryPointFor(
                new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED),
                new MediaTypeRequestMatcher(MediaType.APPLICATION_JSON))
        .authenticationEntryPoint(
                new LoginUrlAuthenticationEntryPoint(
                        "/oauth2/authorization/bank-auth")))
```

`.authenticationEntryPoint(...)` and `.defaultAuthenticationEntryPointFor(...)` are not additive. Spring resolves the entry point with:

```java
AuthenticationEntryPoint getAuthenticationEntryPoint(H http) {
    AuthenticationEntryPoint entryPoint = this.authenticationEntryPoint; // set by .authenticationEntryPoint(...)
    if (entryPoint == null) {
        entryPoint = createDefaultEntryPoint(http);  // the matcher-based one
    }
    return entryPoint;
}
```

Once `.authenticationEntryPoint(...)` is set, the matcher-based entry point is never built. The JSON mapping is dead code, and every unauthenticated request gets the login redirect, including the SPA's JSON calls.

### The Lab 4.7 fix

Register both entry points through `defaultAuthenticationEntryPointFor`, drop the standalone `.authenticationEntryPoint(...)`, and make the JSON matcher exact so a browser's `*/*` does not match it. The complete corrected filter chain:

```java
package com.example.bankbff.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.util.matcher.AnyRequestMatcher;          // NEW import
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/oauth2/**", "/login/**").permitAll()
                        .requestMatchers("/api/**").authenticated()
                        .anyRequest().authenticated())

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
                            // Everything else (a browser) is redirected into the OAuth login flow.
                            .defaultAuthenticationEntryPointFor(
                                    new LoginUrlAuthenticationEntryPoint("/oauth2/authorization/bank-auth"),
                                    AnyRequestMatcher.INSTANCE);
                })

                .oauth2Login(Customizer.withDefaults())

                .logout(logout -> logout
                        .logoutUrl("/logout")
                        .logoutSuccessUrl("/")
                        .invalidateHttpSession(true)
                        .clearAuthentication(true))

                .csrf(AbstractHttpConfigurer::disable);

        return http.build();
    }
}
```

**Why it works.** With two mappings, Spring builds a `DelegatingAuthenticationEntryPoint` that tries each matcher in registration order. A JSON request matches the first mapping and gets 401; everything else falls through to `AnyRequestMatcher` and gets the login redirect. `setUseEquals(true)` keeps the JSON rule from matching a browser's `*/*`, which is "compatible with" `application/json` and would otherwise return 401 to browsers too.

**Verify:**

```bash
curl -i -H "Accept: application/json" http://localhost:8080/api/me   # 401
curl -i -H "Accept: text/html"        http://localhost:8080/api/me   # 302 to login
```

---

## Patch 2 (Backend) -- bankapi Single Account Source

**File:** `bankapi` / `AccountController.java`

### What was wrong in the Lab 4.6 solution

Lab 4.6 added a `TransferService` that holds a mutable account list and updates balances on a transfer, but `AccountController` kept its own separate `private static final List<Account> ACCOUNTS`. Reads came from the static list; writes mutated the service's list. The two drifted, so a transfer reported success but the account list never changed.

```java
// LAB 4.6 (the read path uses a separate, immutable list)
private static final List<Account> ACCOUNTS = List.of(
        new Account("A001", "C001", "CHECKING", new BigDecimal("1250.00")),
        ...
);

@GetMapping
public List<Account> getAll() {
    return ACCOUNTS;   // never reflects a transfer
}
```

### The Lab 4.7 fix

Point the read endpoints at `transferService.listAccounts()` (which already existed in Lab 4.6 but was unused) and delete the static list. The complete corrected controller:

```java
package com.example.bankapi.controller;

import com.example.bankapi.model.Account;
import com.example.bankapi.service.AuditService;
import com.example.bankapi.service.DownstreamAccountService;
import com.example.bankapi.service.TransferService;          // NEW import
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/accounts")
public class AccountController {

    private final DownstreamAccountService downstreamAccountService;
    private final AuditService auditService;
    private final TransferService transferService;          // NEW field

    public AccountController(AuditService auditService,
                             DownstreamAccountService downstreamAccountService,
                             TransferService transferService) {   // NEW parameter
        this.auditService = auditService;
        this.downstreamAccountService = downstreamAccountService;
        this.transferService = transferService;
    }

    @GetMapping
    public List<Account> getAll() {
        return transferService.listAccounts();               // was: return ACCOUNTS;
    }

    @GetMapping("/{id}")
    public ResponseEntity<Account> getById(@PathVariable String id) {
        return transferService.listAccounts().stream()       // was: ACCOUNTS.stream()
                .filter(a -> a.id().equals(id))
                .findFirst()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<Account> create(@RequestBody Account account) {
        // Stub: no persistence. Echoes the account to demonstrate 201 Created
        // and confirm the account.create scope rule is enforced.
        return ResponseEntity.status(HttpStatus.CREATED).body(account);
    }

    @GetMapping("/me")
    public Map<String, Object> getCurrentUser(@AuthenticationPrincipal Jwt jwt) {
        Map<String, Object> result = new HashMap<>();
        result.put("subject",     jwt.getSubject());
        result.put("issuer",      jwt.getIssuer().toString());
        result.put("scopes",      jwt.getClaimAsString("scope"));
        result.put("tokenExpiry", jwt.getExpiresAt().toString());

        var roles = jwt.getClaimAsStringList("roles");
        result.put("roles", roles != null ? roles : List.of());

        var pref = jwt.getClaimAsString("preferred_username");
        result.put("preferredUsername", pref != null ? pref : "not present");

        var name = jwt.getClaimAsString("name");
        result.put("fullName", name != null ? name : "not present");

        return result;
    }

    @GetMapping("/mine")
    public List<Account> getMyAccounts(@AuthenticationPrincipal Jwt jwt) {
        String subject = jwt.getSubject();
        List<String> roles = jwt.getClaimAsStringList("roles");
        if (roles == null) roles = List.of();

        boolean isStaff = roles.contains("teller") || roles.contains("auditor");
        if (isStaff) {
            return transferService.listAccounts();           // was: ACCOUNTS
        }
        return transferService.listAccounts().stream()       // was: ACCOUNTS.stream()
                .filter(a -> a.customerId().equals(subject))
                .toList();
    }

    @GetMapping("/downstream")
    public List<Account> getFromDownstream() {
        return downstreamAccountService.fetchAllFromDownstream();
    }
}
```

Changes from Lab 4.6: import and inject `TransferService`; read every account list from `transferService.listAccounts()`; delete the static `ACCOUNTS` field. The previously unused `AccountService` import and the now-unused `java.math.BigDecimal` import can be removed. The `/me`, `/downstream`, and `create` methods are unchanged.

> **Design note.** Keeping the account list in `TransferService` is a lab expedient. In production the account state lives in a database (one source of truth) and both read and transfer paths use a repository.

---

## Exercise 1 -- Register the SPA's Redirect URI with the Auth Server

**File:** auth server / `AuthorizationServerConfig.java`

Change from Lab 4.6: add the second `.redirectUri(...)` for port 5173. Everything else in the registration is unchanged (the dotted scope names from Lab 4.6 stay as they are).

```java
RegisteredClient bankClientBff = RegisteredClient.withId(UUID.randomUUID().toString())
        .clientId("bank-client-bff")
        .clientSecret("{noop}bank-client-bff-secret")
        .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
        .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
        .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
        // Direct access (Lab 4.6 standalone testing)
        .redirectUri("http://localhost:8080/login/oauth2/code/bank-auth")
        // Through Vite proxy (Lab 4.7 React integration)  <-- NEW
        .redirectUri("http://localhost:5173/login/oauth2/code/bank-auth")
        .scope(OidcScopes.OPENID)
        .scope(OidcScopes.PROFILE)
        .scope("account.read")
        .scope("account.write")
        .scope("account.create")
        .scope("transaction.read")
        .scope("transaction.create")
        .scope("customer.read")
        .scope("customer.write")
        .clientSettings(ClientSettings.builder()
                .requireAuthorizationConsent(false)
                .build())
        .tokenSettings(TokenSettings.builder()
                .accessTokenTimeToLive(Duration.ofMinutes(60))
                .refreshTokenTimeToLive(Duration.ofDays(1))
                .build())
        .build();
```

Restart the auth server after editing. The Exercise 1 curl checks in the lab confirm the proxy-path redirect URI is accepted.

---

## Exercise 2 -- Vite Dev Server Proxy

**File (new content):** `vite.config.ts`

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api':     { target: 'http://localhost:8080', changeOrigin: false },
      '/oauth2':  { target: 'http://localhost:8080', changeOrigin: false },
      '/login':   { target: 'http://localhost:8080', changeOrigin: false },
      '/logout':  { target: 'http://localhost:8080', changeOrigin: false },
    },
  },
});
```

`changeOrigin: false` keeps the `Host` header as `localhost:5173` so the BFF builds redirect URIs that point back through the proxy, preserving the session cookie.

---

## Exercise 3 -- Remove Mock Service Worker

Confirm: `src/mocks/` deleted, `msw` removed from `package.json`, `public/mockServiceWorker.js` deleted.

`src/main.tsx` after removing MSW (before Exercise 4 adds the provider):

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

**Expected verify result:** at this stage the SPA's `fetch('/api/accounts')` (the Lab 4.5 client, which sends no `Accept` header, so `Accept: */*`) is treated as a browser request by the patched BFF and redirected (302) into the login flow; the `fetch` then fails on the cross-origin hop and the accounts area shows an error. This is correct for Exercise 3. The clean 401 appears in Exercise 4 once `client.ts` sends `Accept: application/json`.

---

## Exercise 4 -- Data Types and Authentication Context

### Complete src/api/types.ts

Change from Lab 4.5: fields aligned to the BFF JSON. The Lab 4.5 `AccountStatus` and any unused `Customer`/`Transaction` types are removed.

```ts
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

export type User = {
  subject: string;
  preferredUsername: string;
  fullName: string;
  roles: string[];
};
```

### Complete src/api/client.ts

Change from Lab 4.5: every request sends `Accept: application/json`; `getCurrentUser` and `logout` are added; responses are returned directly because the types now match the JSON.

```ts
import type { Account, TransferRequest, TransferResponse, User } from './types';

export async function getCurrentUser(): Promise<User | null> {
  const response = await fetch('/api/me', {
    headers: { Accept: 'application/json' },
  });
  if (response.status === 401) {
    return null;
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

### Complete src/auth/AuthContext.tsx (new file)

```tsx
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

### Complete src/main.tsx (after Exercise 4)

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

**Expected verify result:** a single logical `GET /api/me` returns **401** (you may see it twice because of `React.StrictMode`'s development double-invoke). `getCurrentUser` reads the 401 as "logged out" and returns `null`. The accounts area still looks broken; that is fixed in Exercise 5.

---

## Exercise 5 -- Sign-In Screen and Conditional UI

### Complete src/components/SignInScreen.tsx (new file)

```tsx
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

### Complete src/components/Header.tsx

Change from Lab 4.5: reads the user from `useAuth`, shows `preferredUsername`, and adds a Sign-out button.

```tsx
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

`user.preferredUsername` produces "Hello, alice". Use `user.fullName` if you prefer the display name.

### Complete src/App.tsx

Change from Lab 4.5: reads auth state, renders one of three states, and gates the account load on `user`.

```tsx
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

### Complete src/components/AccountList.tsx

Change from Lab 4.5: renders `account.id` and `account.accountType`; the Status column is gone (the backend returns no status).

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

### Complete src/components/TransferForm.tsx

Changes from Lab 4.5: dropdowns use `a.id`/`a.accountType`; the POST body sends `fromAccountId`/`toAccountId`; any `status === 'ACTIVE'` filter is removed; and the success branch checks `result.status` so a `FAILED` transfer is shown as an error rather than a false success.

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

### CSS additions

The header and sign-in styles from the lab handout (Task 5.5). If your Lab 4.5 `App.css` did not already define `.status-message`, `.error-message`, and `.success-message`, add them as shown in the lab.

---

## Exercise 6 -- End-to-End Expected Results

| Step | Expected result |
|---|---|
| Open fresh (incognito) | Brief "Checking sign-in state...", then the Welcome screen |
| Sign in as `alice` / `password` | Redirect to `127.0.0.1:9000/login`, then back to the SPA showing "Hello, alice" and five accounts (A001-A005) |
| Transfer $250 A001 to A002 | Success message with a real `T-XXXXXXXX` id; A001 down $250, A002 up $250 |
| Reload | Still logged in; accounts reload with post-transfer balances |
| New tab | Logged in immediately (shared `BFF_SESSION` cookie) |
| Sign out | Back to Welcome screen; reload stays on Welcome |
| Sign in as `bob` | Header shows "Hello, bob" |

Auditor check (optional): signing in as `audit` and attempting a transfer should surface a failure, because the auditor role lacks `transaction.create`; the BFF forwards the token and bankapi returns 403.

---

## Reflection Question Answers (lab-4.7-notes.md)

### Q1: The Vite proxy made cross-origin calls disappear in development. What would change to deploy to production where the React build is served by a separate web server?

Two approaches.

**Approach A (one origin in production).** Build the SPA with `npm run build` and serve the static `dist/` from the same origin as the API, either from the BFF itself or from a reverse proxy in front of it. `/api/*` goes to the BFF; everything else is served as files. Cookies and the OAuth flow work unchanged because there is still one origin. This mirrors what the Vite proxy does in development, so the transition is small.

**Approach B (two origins with CORS).** The SPA at `spa.example.com` and the BFF at `api.example.com`. This requires a CORS config on the BFF allowing the SPA origin, `credentials: 'include'` on every fetch, cookies set with `SameSite=None; Secure` (so HTTPS on both), and the OAuth redirect URI registered for the BFF's origin. More moving parts; most teams choose Approach A.

### Q2: The Sign-in element is an `<a>` tag, not a button with an onClick. Why? What would `fetch('/oauth2/authorization/bank-auth')` do?

OAuth login is a sequence of full-page, cross-origin navigations: the BFF redirects to the auth server, the user submits the login form, the auth server redirects back to the BFF callback, and the BFF redirects to the SPA. The browser must own this: update the address bar, accept the auth server's cookies, render its HTML login form. An `<a>` triggers exactly that navigation.

`fetch` cannot. It does not change the URL bar, cannot render HTML, cannot submit the login form, and cannot meaningfully follow a cross-origin redirect to an HTML page. A `fetch('/oauth2/authorization/bank-auth')` would receive the BFF's 302, follow it toward the auth server, and end up with HTML (or a CORS failure) that JavaScript cannot use. The user would never see the login page.

### Q3: The BFF returns 401 for `Accept: application/json` and a redirect for a browser, even though both are unauthenticated requests to the same URL. Explain the mechanism, and why `setUseEquals(true)` is necessary.

Spring's `exceptionHandling` lets you register several `AuthenticationEntryPoint`s, each paired with a `RequestMatcher`, via `defaultAuthenticationEntryPointFor`. When more than one is registered, Spring builds a `DelegatingAuthenticationEntryPoint` that tries the matchers in registration order and uses the first that matches. We register a `MediaTypeRequestMatcher` for `application/json` mapped to `HttpStatusEntryPoint(401)`, then `AnyRequestMatcher` mapped to a `LoginUrlAuthenticationEntryPoint`. JSON requests match the first and get 401; everything else falls through to the second and is redirected to login.

The Lab 4.6 solution broke this by also calling `.authenticationEntryPoint(loginUrl)`. That is not additive: setting an explicit `authenticationEntryPoint` makes Spring return it directly and never build the matcher-based delegating entry point, so the JSON mapping was dead code and every unauthenticated request got the redirect. The fix removes the explicit call and registers both via `defaultAuthenticationEntryPointFor`.

`setUseEquals(true)` is required because a browser's `Accept` header ends in `*/*`, and `application/json` is "compatible with" `*/*`. Without it, a browser navigation would also match the JSON rule and receive a 401 instead of the login page, defeating dual-audience routing. With `useEquals(true)`, the JSON rule only fires for an `Accept` header that explicitly contains `application/json`, which is what the SPA sends and what a browser address-bar navigation does not.

### Q4: App.tsx owns the accounts state and passes it to both components. Why is that better than each component fetching its own copy? Give two concrete behaviors.

**Auth gating.** App waits for `user` before calling `loadAccounts`. If `AccountList` fetched on mount, you would have to push an auth check into the component (or avoid mounting it), blurring its responsibility. With App owning the fetch, the components only ever receive data when it makes sense, and they know nothing about authentication.

**One refresh updates everything.** After a transfer, the new balances must appear in the table and in the form's dropdowns. Because App owns one `accounts` array, `onTransferComplete` triggers a single `loadAccounts`, and both children re-render from the same prop. Separate per-component copies would need to coordinate a refresh.

Also: the components are trivially testable with mock props, and a third consumer of the same data just receives the same prop.

### Q5: If you had left the Lab 4.5 types in place and just pointed the fetch calls at the BFF, what would happen?

Nothing would crash at the network layer, but the UI would be quietly broken. `AccountList` reads `accountNumber`, `type`, and `status`; the BFF JSON has none of those, so every cell renders `undefined` and `key={account.accountNumber}` is `undefined` for all rows. The dropdowns' `value` comes from `a.accountNumber` (undefined). The transfer body sends `fromAccountNumber`/`toAccountNumber`, which the BFF binds as null, so every transfer fails. And a Lab 4.5 `status === 'ACTIVE'` filter would match nothing, emptying the dropdown. TypeScript only checks that your code is consistent with the type you declared, not that the type matches the server, so aligning the type to the real JSON is what makes the compiler useful.

### Q6: `useAuth()` reads from a Context. What changes if you used prop-drilling instead?

You would pass `user` (and `loading`, `refresh`) from App down through every intermediate component to wherever it is needed. Consequences: intermediate components forward props they do not use; their prop types gain fields they never read; adding a new piece of auth state means editing every component on the path. Context exists to let cross-cutting state tunnel past components that do not care about it. The tradeoff is that data flow becomes less visible, so Context is best reserved for truly cross-cutting concerns (auth, theme, i18n); linear parent-to-child data stays clearer as props.

### Q7: Coming from C#, how does React + BFF compare to Blazor Server or ASP.NET MVC?

**ASP.NET MVC** server-renders HTML; every interaction is a round trip; auth is a server-side cookie; no tokens reach the browser. Simple security model, fewer parts, but less interactive.

**Blazor Server** runs C# on the server and updates the UI over SignalR; tokens stay server-side. Rich UI with one language, but needs a persistent connection and is heavier per user.

**React + BFF** runs the UI as a SPA with no client-side tokens; the BFF is the OAuth client and holds tokens server-side. Independent deployment of front and back, rich UX, CDN-friendly, framework-flexible, at the cost of more moving parts and two codebases. It has won for most modern web apps because the flexibility and ecosystem outweigh the setup cost; for internal tools, MVC or Blazor can still be the better fit.

---

## Notes for Instructors

- **Both backend patches fix defects that originate in Lab 4.6**, not in student work. Patch 1 (the `.authenticationEntryPoint(...)` override that cancels the JSON 401) and Patch 2 (bankapi's `AccountController` serving a static list while `TransferService` mutates a separate one, with `listAccounts()` written but never consumed) are latent in the Lab 4.6 solution and only surface in Lab 4.7 when the SPA depends on the responses. The lab provides them as student-facing remediation; fixing them in the Lab 4.6 source as well means future cohorts never hit them.
- **Data contract follows Option A.** The React `Account`, `TransferRequest`, and `User` types mirror the BFF's `AccountDto`, `TransferRequestDto`, and `UserInfoDto` exactly. There is no adapter layer and no fabricated `status` field; the Lab 4.5 Status column and ACTIVE filter are removed.
- **Account IDs are A001-A005 (five accounts)**, matching the seed data, and the auth server uses `127.0.0.1:9000`.
- **The Exercise 3 verify expects a 302, not a 401**, because at that point the Lab 4.5 client sends no `Accept` header and the patched BFF (with `setUseEquals(true)`) treats `*/*` as a browser request. The clean 401 arrives in Exercise 4 once `client.ts` sends `Accept: application/json`.
- A complete runnable copy of the finished React app is in `banking-ui.zip`.
