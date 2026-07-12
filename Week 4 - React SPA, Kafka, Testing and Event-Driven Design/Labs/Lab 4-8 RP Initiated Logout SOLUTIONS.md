# Module 8: React SPA Development with Secure OAuth
## Lab 4.8 -- Solutions (Complete Changed Files)

> **Course:** MD282 - Java Full-Stack Development
> **Purpose:** Complete reference for the three files changed in Lab 4.8, plus the
> answers to the Reflection questions. Each file is shown in full, with the Lab 4.8
> changes marked.

---

## Summary of Changes

| File | Project | Change |
|---|---|---|
| `AuthorizationServerConfig.java` | auth server | Add `.postLogoutRedirectUri("http://localhost:5173/")` to the `bank-client-bff` registration |
| `SecurityConfig.java` | `bankbff` | Inject `ClientRegistrationRepository`; replace `logoutSuccessUrl("/")` with `OidcClientInitiatedLogoutSuccessHandler` |
| `Header.tsx` | `banking-ui` | Replace `fetch('/logout')` with `window.location.href = '/logout'` |

A fourth, optional cleanup is noted at the end: the now-unused `logout()` function in `client.ts`.

---

## 1. Auth Server -- the changed registration

**File:** `AuthorizationServerConfig.java`

Only the `bank-client-bff` registration changed: the single `.postLogoutRedirectUri(...)` line was added. The complete bean that produces the client registration is shown below. The rest of `AuthorizationServerConfig` (the authorization-server and default security filter chains, the JWK source, and the issuer settings) is unchanged from Lab 4.6. If your repository registers more than one client, pass all of them to the repository constructor as before; only `bankClientBff` changed.

```java
@Bean
public RegisteredClientRepository registeredClientRepository() {

    RegisteredClient bankClientBff = RegisteredClient.withId(UUID.randomUUID().toString())
            .clientId("bank-client-bff")
            .clientSecret("{noop}bank-client-bff-secret")
            .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
            .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
            .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
            // Login redirect URIs (Lab 4.6 and Lab 4.7)
            .redirectUri("http://localhost:8080/login/oauth2/code/bank-auth")
            .redirectUri("http://localhost:5173/login/oauth2/code/bank-auth")
            // Post-logout redirect URI (NEW in Lab 4.8)
            .postLogoutRedirectUri("http://localhost:5173/")
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

    return new InMemoryRegisteredClientRepository(bankClientBff);
}
```

The only line that differs from Lab 4.7 is:

```java
.postLogoutRedirectUri("http://localhost:5173/")
```

This must match, character for character including the trailing slash, the value the BFF sets with `setPostLogoutRedirectUri(...)`.

---

## 2. BFF -- complete SecurityConfig.java

**File:** `bankbff` / `SecurityConfig.java`

Changes from Lab 4.7 (Patch 1 version):

- The bean signature now takes a `ClientRegistrationRepository` (Spring injects it).
- An `OidcClientInitiatedLogoutSuccessHandler` is built and given the post-logout redirect URI.
- `.logoutSuccessUrl("/")` is replaced by `.logoutSuccessHandler(oidcLogoutSuccessHandler)`.
- Two imports added.

The `authorizeHttpRequests` rules, the dual-audience `exceptionHandling` block, `oauth2Login`, and the disabled CSRF are unchanged.

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
import org.springframework.security.oauth2.client.oidc.web.logout.OidcClientInitiatedLogoutSuccessHandler; // NEW
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;               // NEW
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.util.matcher.AnyRequestMatcher;
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            ClientRegistrationRepository clientRegistrationRepository) throws Exception {   // CHANGED signature

        // NEW: redirect to the auth server's end-session endpoint after local logout.
        OidcClientInitiatedLogoutSuccessHandler oidcLogoutSuccessHandler =
                new OidcClientInitiatedLogoutSuccessHandler(clientRegistrationRepository);
        oidcLogoutSuccessHandler.setPostLogoutRedirectUri("http://localhost:5173/");

        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/oauth2/**", "/login/**").permitAll()
                        .requestMatchers("/api/**").authenticated()
                        .anyRequest().authenticated())

                // Dual-audience entry point (Lab 4.7 Patch 1) -- unchanged.
                .exceptionHandling(ex -> {
                    MediaTypeRequestMatcher jsonMatcher =
                            new MediaTypeRequestMatcher(MediaType.APPLICATION_JSON);
                    jsonMatcher.setUseEquals(true);
                    ex
                            .defaultAuthenticationEntryPointFor(
                                    new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED),
                                    jsonMatcher)
                            .defaultAuthenticationEntryPointFor(
                                    new LoginUrlAuthenticationEntryPoint("/oauth2/authorization/bank-auth"),
                                    AnyRequestMatcher.INSTANCE);
                })

                .oauth2Login(Customizer.withDefaults())

                .logout(logout -> logout
                        .logoutUrl("/logout")
                        .logoutSuccessHandler(oidcLogoutSuccessHandler)   // CHANGED: was .logoutSuccessUrl("/")
                        .invalidateHttpSession(true)
                        .clearAuthentication(true))

                .csrf(AbstractHttpConfigurer::disable);

        return http.build();
    }
}
```

---

## 3. React App -- complete Header.tsx

**File:** `banking-ui` / `src/components/Header.tsx`

Changes from Lab 4.7:

- The import of `logout as logoutApi` from `../api/client` is removed.
- `useAuth()` no longer destructures `refresh` (the full-page reload re-checks auth state).
- `handleSignOut` is no longer `async`; it navigates with `window.location.href = '/logout'`.

```tsx
/**
 * Header component.
 *
 * Reads the current user from the auth context. When a user is logged in, shows
 * their name and a Sign-out button. Sign-out is a full-page navigation to
 * /logout so the browser walks the entire logout chain: the BFF clears its
 * session and redirects to the auth server's end-session endpoint, which clears
 * the identity-provider session and returns the browser here.
 */

import { useAuth } from '../auth/AuthContext';

export function Header() {
  const { user } = useAuth();

  function handleSignOut() {
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

### Optional cleanup -- client.ts

After this change, `logout()` in `src/api/client.ts` is no longer referenced. You may delete it. The rest of `client.ts` (`getCurrentUser`, `getAccounts`, `postTransfer`, `safeReadErrorMessage`) is unchanged.

---

## Reflection Question Answers

### Q1: Name the two sessions, where each cookie lives, and which one the old `fetch('/logout')` failed to clear.

Logging in creates a **BFF session** (cookie `BFF_SESSION`, scoped to `localhost:5173`, set by the BFF after the OAuth callback) and an **auth server session** (cookie `JSESSIONID`, scoped to `127.0.0.1:9000`, set by the auth server when the login form is submitted). The old `fetch('/logout')` cleared only the BFF session. The auth server session survived, so the next login was silent and re-used the same identity.

### Q2: Why must logout be a browser navigation rather than a `fetch`, and how is this the same reasoning as the Sign-in anchor?

Logout, like login, is a chain of cross-origin redirects the browser must follow: the BFF clears its session and redirects to the auth server's end-session endpoint, the auth server clears its session and redirects back to the SPA. Each step must run in the browser so the right cookies are in scope and get cleared, and so the address bar follows along. A `fetch` cannot follow a cross-origin redirect to the auth server in a way that clears its cookie; at best it clears the same-origin BFF session and stops. This is the same reason the Sign-in element is an `<a>` tag and not a `fetch`: OAuth login and logout are both browser navigations, not data calls.

### Q3: Why is the registered-`post_logout_redirect_uri` restriction important, and what attack would be possible without it?

If the auth server redirected to any `post_logout_redirect_uri` supplied in the request, an attacker could craft a logout link that sends the user to an attacker-controlled site after logout. That enables open-redirect phishing (the user trusts the flow because it started on the real auth server) and can be chained with session-fixation or credential-harvesting pages. Requiring the redirect target to be pre-registered for the client limits the destination to URLs the application owner has explicitly approved.

### Q4: Why might ending the shared auth server session on every app logout be undesirable in a single-sign-on estate, and what is the trade-off?

In an SSO setup, several applications share one auth server session. RP-initiated logout ends that shared session, which logs the user out of every SSO application at once, not just the one they clicked "Sign out" in. Sometimes that is exactly what you want (a true "log out everywhere"), but often a user signing out of one app expects to stay logged in to the others. The trade-off is between a clean, complete logout for a single application and preserving the convenience of SSO across the rest. Real deployments choose per-application logout, global logout, or back-channel logout depending on the security and usability requirements. For this single-application demo, ending the auth server session is the correct, expected behavior.
