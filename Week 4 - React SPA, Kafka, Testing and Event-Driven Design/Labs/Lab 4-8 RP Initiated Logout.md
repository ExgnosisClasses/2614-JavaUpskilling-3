# Module 8: React SPA Development with Secure OAuth
## Lab 4.8 -- RP-Initiated Logout (Ending Both Sessions)

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 8 - React SPA Development with Secure OAuth
> **Estimated time:** 35-45 minutes
> **Prerequisite:** Lab 4.7 complete and working (login, accounts, and transfers all functioning)

---

## Overview

At the end of Lab 4.7 the application logs in, shows accounts, and processes transfers. But the logout is incomplete. If you sign out and then return to `http://localhost:5173`, you are silently signed back in as the previous user, with no password prompt. The "Sign out" button appears to work (the header clears), but the next login does not actually ask who you are.

This lab fixes that. You will implement **RP-initiated logout** (also called single logout), so that signing out ends both sessions involved in the OAuth flow, not just one. The fix touches three files, one in each project:

1. The **auth server**: register a post-logout redirect URI.
2. The **BFF**: replace the local logout redirect with an OIDC logout success handler.
3. The **React app**: navigate to `/logout` instead of fetching it.

By the end of this lab, signing out clears both the BFF session and the auth server session, so the next sign-in prompts for credentials and you can log in as a different user.

By the end of this lab you will be able to:

- Explain the two-session model behind a BFF + OAuth login
- Implement RP-initiated logout with Spring Authorization Server and Spring Security
- Explain why a logout must be a browser navigation, not an AJAX call

---

## The Problem: Two Sessions, One Logout

When you log in, two independent sessions are created:

| Session | Where it lives | Cookie | Set by |
|---|---|---|---|
| BFF session | the BFF, port 8080 (seen by the browser as `localhost:5173`) | `BFF_SESSION` | the BFF after the OAuth callback |
| Auth server session | the auth server, `127.0.0.1:9000` | `JSESSIONID` | the auth server when you submit the login form |

The Lab 4.7 logout calls `fetch('/logout')`, which invalidates the **BFF session only**. The **auth server session is never touched**. So after "logging out":

- The BFF has forgotten you (its cookie is gone).
- The auth server still considers you logged in (its cookie is alive).

The next time the SPA starts the OAuth flow, the browser is sent to the auth server's authorization endpoint. The auth server sees its own live session, decides you are already authenticated, and issues a fresh authorization code with no login prompt. The BFF exchanges it for tokens and you are back in, as the same user. The local logout worked; the identity-provider logout never happened.

RP-initiated logout closes this gap. "RP" stands for Relying Party (the BFF). After clearing its own session, the BFF sends the browser to the auth server's `end_session_endpoint`, which ends the auth server session too and then returns the browser to the SPA.

You can confirm the auth server supports this:

```bash
curl -s http://127.0.0.1:9000/.well-known/openid-configuration | grep -o '"end_session_endpoint":"[^"]*"'
```

You should see `"end_session_endpoint":"http://127.0.0.1:9000/connect/logout"`. That endpoint is what the BFF will redirect to.

---

## Before You Start

Make sure all three backend services and the React dev server are running, and that Lab 4.7 works end to end (you can log in, see accounts, and make a transfer). You will modify and restart the auth server and the BFF in this lab, and edit one React component.

---

## Exercise 1 -- Register a Post-Logout Redirect URI on the Auth Server

**Estimated time:** 10 minutes
**File:** auth server / `AuthorizationServerConfig.java`

### Context

RP-initiated logout ends with the auth server redirecting the browser back to the application. For security, the auth server will only redirect to a URL that has been pre-registered for the client, exactly as it does for login redirect URIs. You must register where the browser is allowed to land after logout.

### Task 1.1 -- Add the post-logout redirect URI

Open `AuthorizationServerConfig.java` and find the `bankClientBff` `RegisteredClient` registration. Add a `.postLogoutRedirectUri(...)` call. Placement in the builder chain does not matter; next to the existing `.redirectUri(...)` lines reads well because they are conceptually paired:

```java
.redirectUri("http://localhost:8080/login/oauth2/code/bank-auth")
.redirectUri("http://localhost:5173/login/oauth2/code/bank-auth")
.postLogoutRedirectUri("http://localhost:5173/")
```

### Task 1.2 -- Restart the auth server

Stop and restart the auth server. The registration is built at startup, so the new value is not active until you restart.

### What this change does and fixes

- **What it is:** a registered, allowed destination for the browser after the auth server ends its session.
- **What it does:** lets the auth server honor the `post_logout_redirect_uri` parameter that the BFF will send, returning the user to the SPA's home page after logout.
- **What it fixes:** without it, the auth server would reject the post-logout redirect as unregistered and the logout would dead-end on an error page instead of returning to the app.

> **Exact match matters.** The value here (`http://localhost:5173/`, including the trailing slash) must match exactly what the BFF sends in Exercise 2. A mismatch causes the auth server to reject the redirect. The `openid` scope is also required (it is already on this client); RP-initiated logout uses the `id_token` as proof of which session to end.

---

## Exercise 2 -- Wire the BFF to Redirect to the End-Session Endpoint

**Estimated time:** 15 minutes
**File:** BFF / `SecurityConfig.java`

### Context

In Lab 4.7 the BFF's logout was configured with `.logoutSuccessUrl("/")`: after clearing its session, it simply sent the browser to `/`. That is a purely local logout. To also end the auth server session, the BFF must instead redirect the browser to the auth server's `end_session_endpoint`, carrying an `id_token_hint` (so the auth server knows which session to end) and a `post_logout_redirect_uri` (so it knows where to send the browser afterward).

Spring Security provides a ready-made handler for exactly this: `OidcClientInitiatedLogoutSuccessHandler`. It reads the `end_session_endpoint` from the auth server's discovery document and builds the logout URL for you.

### Task 2.1 -- Inject the ClientRegistrationRepository

Update the `securityFilterChain` bean to take a `ClientRegistrationRepository` parameter. Spring injects it automatically; the handler needs it to look up the auth server's logout endpoint.

```java
@Bean
public SecurityFilterChain securityFilterChain(
        HttpSecurity http,
        ClientRegistrationRepository clientRegistrationRepository) throws Exception {
```

### Task 2.2 -- Build the logout success handler

Near the top of the bean method, before the `http` configuration, create the handler and set the post-logout redirect URI (matching what you registered in Exercise 1):

```java
OidcClientInitiatedLogoutSuccessHandler oidcLogoutSuccessHandler =
        new OidcClientInitiatedLogoutSuccessHandler(clientRegistrationRepository);
oidcLogoutSuccessHandler.setPostLogoutRedirectUri("http://localhost:5173/");
```

### Task 2.3 -- Use the handler in the logout config

Replace `.logoutSuccessUrl("/")` with `.logoutSuccessHandler(oidcLogoutSuccessHandler)`:

```java
.logout(logout -> logout
        .logoutUrl("/logout")
        .logoutSuccessHandler(oidcLogoutSuccessHandler)   // was: .logoutSuccessUrl("/")
        .invalidateHttpSession(true)
        .clearAuthentication(true))
```

### Task 2.4 -- Add the imports

```java
import org.springframework.security.oauth2.client.oidc.web.logout.OidcClientInitiatedLogoutSuccessHandler;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
```

Leave the rest of the security configuration (the dual-audience `exceptionHandling` block, `oauth2Login`, and the disabled CSRF) unchanged. Restart the BFF.

### What this change does and fixes

- **What it is:** a logout success handler that, after the BFF session is cleared, redirects the browser to the auth server's `end_session_endpoint` with the `id_token_hint` and `post_logout_redirect_uri`.
- **What it does:** converts the BFF's local logout into a federated logout that also ends the auth server session, then returns the browser to the SPA.
- **What it fixes:** this is the core of the bug. Previously the auth server session survived logout, so the next login was silent and re-used the same user. Now both sessions end, so the next login starts fresh.

> **Why the handler instead of a hardcoded URL?** `OidcClientInitiatedLogoutSuccessHandler` discovers the `end_session_endpoint` from the issuer metadata and attaches the `id_token_hint` automatically. You never hardcode `127.0.0.1:9000/connect/logout`; if the issuer changes, the handler follows it.

---

## Exercise 3 -- Make the SPA Navigate to Logout

**Estimated time:** 10 minutes
**File:** React app / `src/components/Header.tsx`

### Context

The BFF is now ready to drive a full federated logout, but it only happens if the browser actually visits `/logout` and then follows the redirect to the auth server. The Lab 4.7 Header used `fetch('/logout')`. A `fetch` cannot do this: it can clear the BFF session (a same-origin call), but it cannot follow the cross-origin redirect to the auth server's logout page, so the auth server session would still survive. Logout must be a real browser navigation, for the same reason login is an anchor and not a fetch.

### Task 3.1 -- Replace the fetch with a navigation

Open `src/components/Header.tsx` and change the sign-out handler to navigate the browser to `/logout`:

```tsx
import { useAuth } from '../auth/AuthContext';

export function Header() {
  const { user } = useAuth();

  function handleSignOut() {
    // Full-page navigation (not fetch) so the browser walks the whole logout
    // chain: the BFF clears its session and redirects to the auth server's
    // end-session endpoint, which clears the IdP session and returns here.
    window.location.href = '/logout';
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

Compared with Lab 4.7, the handler is no longer `async`, it no longer imports or calls `logoutApi`, and it no longer needs `refresh` from `useAuth` (the page fully reloads after logout, so the auth state is re-checked from scratch).

### Task 3.2 -- Remove the now-unused client function (optional cleanup)

The `logout()` function in `src/api/client.ts` is no longer called by anything. You can delete it to keep the client tidy. The `getCurrentUser`, `getAccounts`, and `postTransfer` functions stay.

### What this change does and fixes

- **What it is:** a full-page navigation to `/logout` instead of an AJAX call.
- **What it does:** lets the browser walk the entire logout redirect chain, so both the BFF cookie (on `localhost:5173`) and the auth server cookie (on `127.0.0.1:9000`) are cleared in their own origins.
- **What it fixes:** even with the BFF handler from Exercise 2 in place, a `fetch`-based logout would clear only the BFF session, because `fetch` cannot follow the redirect to the auth server. The navigation is what actually triggers the federated logout end to end.

> **A note on CSRF.** This works as a `GET` navigation because CSRF protection is disabled in this lab, which lets Spring's logout filter accept `GET /logout`. When CSRF is turned on in the application-hardening lab, logout must become a `POST` carrying a CSRF token (typically a small hidden form), since a plain navigation would no longer be accepted.

---

## Exercise 4 -- End-to-End Verification

**Estimated time:** 5 minutes

1. Open `http://localhost:5173` in a fresh (incognito) window. You should see the Welcome screen.
2. Click "Sign in" and log in as `alice` / `password`. You should see "Hello, alice" and the five accounts.
3. Click "Sign out". The browser should briefly bounce through the BFF and the auth server and land back on the Welcome screen.
4. Click "Sign in" again. **You should now see the auth server's login page with a password prompt**, not a silent re-login.
5. Log in as `bob` / `password`. The header should show "Hello, bob".

If step 4 shows the password prompt and step 5 logs you in as a different user, RP-initiated logout is working. The previous behavior (silently returning as `alice`) is gone.

To watch the chain explicitly, open DevTools, tick **Preserve log** in the Network tab, and click Sign out. You should see `/logout` (handled by the BFF) followed by a redirect to `127.0.0.1:9000/connect/logout`, then a redirect back to `localhost:5173/`.

---

## How the Logout Flow Works Now

```
  Browser clicks "Sign out"
        │  window.location.href = '/logout'
        ▼
  ┌──────────────────┐
  │  BFF /logout     │  invalidates BFF session (BFF_SESSION cleared)
  │  (port 8080)     │  OidcClientInitiatedLogoutSuccessHandler builds the
  └────────┬─────────┘  end-session URL with id_token_hint + post_logout_redirect_uri
           │ 302
           ▼
  ┌──────────────────────────┐
  │  Auth server             │  ends its own session (JSESSIONID cleared)
  │  /connect/logout         │  validates post_logout_redirect_uri against the
  │  (127.0.0.1:9000)        │  registered value
  └────────┬─────────────────┘
           │ 302 to http://localhost:5173/
           ▼
  ┌──────────────────┐
  │  SPA reloads     │  AuthProvider calls /api/me -> 401 -> Welcome screen
  │  (port 5173)     │
  └──────────────────┘
```

Both cookies are now gone. The next login genuinely re-authenticates.

---

## Troubleshooting

**After Sign out, clicking Sign in still logs me straight back in as the same user.**
The auth server session is not being ended. Check that the BFF uses `OidcClientInitiatedLogoutSuccessHandler` (not `logoutSuccessUrl`), and that the SPA uses `window.location.href = '/logout'` (not `fetch`). A `fetch`-based logout cannot reach the auth server.

**Logout ends on an error page instead of returning to the SPA.**
The `post_logout_redirect_uri` the BFF sends does not match a registered value. Confirm `setPostLogoutRedirectUri("http://localhost:5173/")` in the BFF exactly matches `.postLogoutRedirectUri("http://localhost:5173/")` on the auth server (trailing slash included), and that you restarted the auth server.

**Logout returns a 405 or does nothing.**
If CSRF has been enabled, `GET /logout` is no longer accepted and you need a `POST`. In this lab CSRF is disabled, so the navigation should work; if it does not, confirm CSRF is still disabled in the BFF `SecurityConfig`.

---

## Reflection Questions

In `lab-4.8-notes.md`, answer:

1. Logging in created two sessions but the Lab 4.7 logout cleared only one. Name the two sessions, where each cookie lives, and which one the old `fetch('/logout')` failed to clear.

2. Why must logout be a browser navigation (`window.location.href`) rather than a `fetch`, and how is this the same reasoning as the Sign-in anchor tag from Lab 4.7?

3. The auth server refuses to redirect to a `post_logout_redirect_uri` that is not pre-registered. Why is that restriction important, and what attack would be possible without it?

4. Ending the auth server session is "single logout" for this one identity provider. In an organization where the same auth server provides single sign-on to several applications, why might ending the shared session on every app logout be undesirable? What is the trade-off?

---

## What's Next

Logout now ends both sessions, completing the authentication lifecycle for the BFF pattern: login, authenticated API access, token refresh, and full logout. The remaining labs cover application hardening (turning CSRF back on, which changes logout to a POST, plus secure cookie flags and other production measures) and swapping the local auth server for a commercial identity provider.
