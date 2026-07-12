# Module 9: React SPA Development with Secure OAuth
## Lab 4.5 -- Introduction to React: Building a Banking UI

> **Course:** MD282 - Java Full-Stack Development
> **Module:** 9 - React SPA Development with Secure OAuth
> **Estimated time:** 75-90 minutes

---

## Overview

This lab is your introduction to React. You will build a small banking UI that displays a list of customer accounts and lets the customer transfer money between accounts. The application uses TypeScript, Vite as the build tool, and Mock Service Worker (MSW) to simulate the backend API. In a later lab you will replace the mock with a real Spring Boot BFF, but for now the focus stays entirely on React fundamentals.

Most of the project, including styling, project structure, mock API, and the form layout, has been written for you. Your job is to fill in the React-specific code: component state, data loading, event handlers, and conditional rendering. Each section you need to complete is marked with `// TODO:` comments.

By the end of this lab you will be able to:

- Read and write functional React components in TypeScript
- Use the `useState` and `useEffect` hooks to manage component state and side effects
- Render lists of data with proper keys
- Build controlled form inputs that synchronize with component state
- Make HTTP calls from a React component and handle loading and error states
- Update the UI in response to a successful API call

---

## Before You Start

You will need:

- **Node.js 20 or higher** installed. Verify with `node --version`.
- **npm 10 or higher**. It comes with Node. Verify with `npm --version`.
- **Visual Studio Code** as your code editor for this lab.

If you have only worked in Java and IntelliJ before, VS Code will feel different but lighter. The TypeScript and React tooling is built in.

### VS Code extensions

Install these extensions before you start the lab. From VS Code, press `Ctrl+Shift+X` (or `Cmd+Shift+X` on macOS) and search for each by name:

| Extension | Publisher | Why you need it |
|---|---|---|
| **ESLint** | Microsoft | Flags React hook rule violations as you type, including missing `useEffect` dependencies. Critical for catching the bugs Exercise 1 sets you up to make. |
| **Prettier - Code formatter** | Prettier | Auto-formats your code on save so you do not have to think about indentation and spacing. |
| **ES7+ React/Redux/React-Native snippets** | dsznajder | React snippets such as `rfc`, `useState`, and `useEffect` save typing during the TODO sections. |
| **Error Lens** | Alexander | Shows TypeScript and ESLint errors inline at the end of the line. Much faster than hovering over red squiggles. |
| **Path Intellisense** | Christian Kohler | Autocompletes file paths in `import` statements. |

After installing, enable **Format on Save**:

1. Open the Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P` on macOS).
2. Search for "Preferences: Open User Settings".
3. In the search box at the top, type `format on save`.
4. Check the **Editor: Format On Save** checkbox.

With Prettier installed and this setting enabled, your `.tsx` files will be formatted automatically every time you save.

> **Tip:** When you first open the starter project, VS Code may prompt you to install recommended extensions. Click **Install All**. The starter project includes a `.vscode/extensions.json` file that lists exactly the extensions above.

---

## A Brief Orientation for C# Developers

If you are coming from C#, several things in this lab will feel familiar:

| Concept | C# / .NET | TypeScript / React |
|---|---|---|
| Strong typing | Built into the language | Built into TypeScript |
| Components | Razor components, Blazor | React functional components |
| Properties / Props | Component parameters | Props passed as a function argument |
| Events | C# events, delegates | Callback functions passed as props |
| Async data loading | `async`/`await` with `HttpClient` | `async`/`await` with `fetch` |
| State changes trigger UI updates | Two-way binding, observable properties | The `useState` hook returns a setter that triggers re-render |
| Build tool | MSBuild, dotnet | Vite |
| Package manager | NuGet | npm |

You will not need to learn TypeScript syntax from scratch. The type annotations look very similar to C# (`accountId: string`, `accounts: Account[]`). The biggest mental shift is the React rendering model: instead of mutating UI elements directly, you describe what the UI should look like for the current state, and React figures out what to update.

---

## Starter Project

A starter project has been prepared for you. It contains the project structure, the styling, the mock API, and skeleton components with `// TODO:` markers showing where to add code.

### Solution Project

A completed solution project has also been provided.

Since this is not a course about building React applications, the solution is provided for you to either:

- Review and run to see how the React library works. If you only run the solution, be sure to review the code so that you have a high level understanding of what React is doing.
- If want to write code, then use the solution code as a guide to completing the TODOs

You can follow the same instructions below for installing and running the solution that work for the starter

The solution can be downloaded as

```bash
git clone https://github.com/ExgnosisClasses/2609-ReactSolution.git banking-ui
```

**Note** Since both repos clone into the directory `banking-ui,` make to clone them into different locations to avoid conflicts with directory names



### Get the starter project

Clone the starter repository and install dependencies:

```bash
git clone https://github.com/ExgnosisClasses/2609-ReactStarter.git banking-ui
cd banking-ui
npm install
```

###

The `npm install` step downloads all the dependencies listed in `package.json`. It is the equivalent of running a `dotnet restore` in a .NET project.

### Run the dev server

```bash
npm run dev
```

You should see output like:

```
  VITE v5.x.x  ready in 432 ms

  ➜  Local:   http://localhost:5173/
  ➜  Network: use --host to expose
```

Open `http://localhost:5173` in a browser. You should see a banking application shell with a header and a placeholder message saying "Loading accounts..." that never resolves. That is because none of the React code is written yet. You will fix that.

The dev server has hot module replacement turned on. As you save changes to a file, the page updates automatically without a full reload.

### Project layout

```
banking-ui/
├── public/
├── src/
│   ├── api/
│   │   ├── client.ts          ← provided: fetch wrapper
│   │   └── types.ts           ← provided: TypeScript types for API data
│   ├── components/
│   │   ├── AccountList.tsx    ← TODO sections
│   │   ├── TransferForm.tsx   ← TODO sections
│   │   └── Header.tsx         ← provided
│   ├── mocks/
│   │   ├── handlers.ts        ← provided: MSW request handlers
│   │   └── browser.ts         ← provided: MSW browser setup
│   ├── App.tsx                ← TODO sections
│   ├── App.css                ← provided
│   ├── main.tsx               ← provided: app entry point
│   └── index.css              ← provided
├── index.html
├── package.json
├── tsconfig.json
└── vite.config.ts
```

The files marked **provided** are complete. You will not need to edit them. The files marked **TODO sections** contain the React code you need to write.

### Provided files for reference

Open these in your editor and skim them. You do not need to understand every line, but knowing what is available will help you complete the exercises.

**`src/api/types.ts`** declares the shape of the data the API returns:

```typescript
export type AccountStatus = 'ACTIVE' | 'INACTIVE';
export type AccountType = 'SAVINGS' | 'CHECKING';

export type Account = {
  accountNumber: string;
  status: AccountStatus;
  balance: number;
  type: AccountType;
};

export type TransferRequest = {
  fromAccountNumber: string;
  toAccountNumber: string;
  amount: number;
};

export type TransferResponse = {
  transactionId: string;
  status: 'COMPLETE' | 'FAILED';
};
```

**`src/api/client.ts`** is a small wrapper around `fetch`:

```typescript
export async function getAccounts(): Promise<Account[]> {
  const response = await fetch('/api/accounts');
  if (!response.ok) {
    throw new Error(`Failed to load accounts: ${response.status}`);
  }
  return response.json();
}

export async function postTransfer(request: TransferRequest): Promise<TransferResponse> {
  const response = await fetch('/api/transfers', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  });
  if (!response.ok) {
    throw new Error(`Transfer failed: ${response.status}`);
  }
  return response.json();
}
```

**`src/mocks/handlers.ts`** is the mock API. It intercepts the fetch calls above and returns canned responses without an actual network round-trip. This means you can develop the UI before the real backend exists, which is exactly the situation you are in for this lab.

> **Why we are using a mock.** In a later lab you will replace MSW with a real Spring Boot BFF. The fetch calls in `client.ts` will not change. From the React code's perspective, MSW and a real backend are indistinguishable. This is one of the wins of treating data fetching as a clean abstraction.

---

## Exercise 1 -- Your First Component: Display the Account List

**Estimated time:** 25-30 minutes
**Topics covered:** Functional components, `useState`, `useEffect`, list rendering with keys, conditional rendering

### Context

A React component is a TypeScript function that returns markup describing what the UI should look like. The "markup" is JSX: HTML-like syntax that compiles into JavaScript function calls. When component state changes, React re-runs the function and updates the parts of the page that changed.

For the account list, you need three pieces:

1. **State** to hold the list of accounts and any loading or error status.
2. **An effect** that calls the API once when the component first appears.
3. **JSX** that renders the list, a loading message, or an error message depending on state.

### Task 1.1 -- Open the AccountList component

Open `src/components/AccountList.tsx`. The file is structured for you and has TODO markers showing where to add code:

```tsx
import { useState, useEffect } from 'react';
import { getAccounts } from '../api/client';
import type { Account } from '../api/types';

export function AccountList() {
  // TODO 1.1: Declare three pieces of state:
  //   - accounts: an array of Account, initially empty
  //   - loading: a boolean, initially true
  //   - error: a string or null, initially null


  // TODO 1.2: Add a useEffect that loads accounts from the API when
  // the component first renders. Update state with the result, or
  // set the error state if the call fails. Set loading to false
  // when the call completes (whether it succeeded or failed).


  // TODO 1.3: Add conditional rendering. If loading is true, return
  // a "Loading accounts..." message. If error is not null, return
  // an error message. Otherwise, render the accounts list below.


  return (
    <section className="account-list">
      <h2>Your Accounts</h2>
      <table>
        <thead>
          <tr>
            <th>Account Number</th>
            <th>Type</th>
            <th>Status</th>
            <th>Balance</th>
          </tr>
        </thead>
        <tbody>
          {/* TODO 1.4: Render one <tr> for each account in the accounts array.
              Each <tr> needs a unique 'key' prop set to account.accountNumber.
              Show the account number, type, status, and balance. Format
              the balance as currency, e.g. $1,234.56 */}
        </tbody>
      </table>
    </section>
  );
}
```

### Task 1.2 -- Add component state

State is what makes a component remember things between renders. The `useState` hook returns a tuple: the current value and a setter function. Calling the setter triggers a re-render with the new value.

Replace the **TODO 1.1** comment with three calls to `useState`:

```tsx
const [accounts, setAccounts] = useState<Account[]>([]);
const [loading, setLoading] = useState<boolean>(true);
const [error, setError] = useState<string | null>(null);
```

A few things to notice:

- The destructuring syntax `const [a, setA] = useState(...)` is required. The hook returns a two-element array; the names you use for `a` and `setA` are arbitrary, but the convention is `[thing, setThing]`.
- The TypeScript generic on `useState<Account[]>([])` tells TypeScript "this is going to hold an array of Account." Without it, TypeScript would infer `never[]` from the empty array literal, which would cause errors later.
- The initial value passed to `useState` is used **only on the first render**. On subsequent renders, React already has the stored value and uses that.

> **C# comparison:** This is roughly equivalent to private fields on a Razor component, but with one critical difference: setting the value via the setter triggers a re-render. Mutating the field in place would not. **Always call the setter to update state.**

### Task 1.3 -- Load accounts when the component appears

Components do not load their data on construction. Instead, you tell React "after this component renders, run this side effect." That is what `useEffect` is for.

Replace the **TODO 1.2** comment with this:

```tsx
useEffect(() => {
  let cancelled = false;

  async function loadAccounts() {
    try {
      const data = await getAccounts();
      if (!cancelled) {
        setAccounts(data);
      }
    } catch (e) {
      if (!cancelled) {
        setError(e instanceof Error ? e.message : 'Unknown error');
      }
    } finally {
      if (!cancelled) {
        setLoading(false);
      }
    }
  }

  loadAccounts();

  return () => {
    cancelled = true;
  };
}, []);
```

Walk through what this does:

- The function passed to `useEffect` runs after the component renders.
- The empty dependency array `[]` at the end means "run this only once, when the component first appears." Without `[]`, the effect would run after every render, causing an infinite loop of API calls.
- The inner `async function loadAccounts()` is needed because the function passed to `useEffect` itself cannot be async. React expects either nothing or a cleanup function as the return value.
- The `cancelled` flag protects against updating state on a component that has been unmounted, which is a common source of warnings. The `return () => { cancelled = true; }` is the cleanup function React calls when the component is removed.
- The `try`/`catch`/`finally` handles the three outcomes of an async call: success (set the data), failure (set the error), and "always" (clear the loading flag).

> **Common mistake:** Forgetting the empty dependency array `[]` will cause `useEffect` to run after every render. Each run triggers a state update, which causes another render, which triggers the effect again. The browser tab will lock up making API calls in a tight loop. Always think about what should be in the dependency array.

### Task 1.4 -- Conditional rendering for loading and error states

You have three possible UI states: loading, error, or showing the list. React's pattern for this is early returns from the component function.

Replace the **TODO 1.3** comment with:

```tsx
if (loading) {
  return <p className="status-message">Loading accounts...</p>;
}

if (error) {
  return <p className="status-message error">Error: {error}</p>;
}
```

Notice the JSX inside the return. The `<p>` looks like HTML but is really TypeScript: the compiler turns it into a function call that creates a React element. The curly braces `{error}` mean "evaluate this expression and put its value here."

> **C# comparison:** This is similar to a Razor component returning different markup based on a property's value, except that in React you use early `return` statements with regular `if` blocks rather than `@if` directives.

### Task 1.5 -- Render the account rows

The final TODO renders one table row per account. The pattern is to use JavaScript's `Array.prototype.map` to transform the array of accounts into an array of JSX elements.

Replace the **TODO 1.4** comment with:

```tsx
{accounts.map((account) => (
  <tr key={account.accountNumber}>
    <td>{account.accountNumber}</td>
    <td>{account.type}</td>
    <td>{account.status}</td>
    <td>${account.balance.toFixed(2)}</td>
  </tr>
))}
```

A few important details:

- The `key={account.accountNumber}` is required when rendering a list. React uses the key to identify items across renders, which lets it efficiently update the DOM when items are added, removed, or reordered. The key must be unique among siblings and stable across renders. The account number is a perfect choice.
- `account.balance.toFixed(2)` formats the number as a string with two decimal places, e.g. `1500.5` becomes `"1500.50"`.
- The `()` wrapping the JSX in `accounts.map((account) => (...))` is just so that the arrow function's body is an expression. Without the parentheses, the arrow function would need a `return` statement.

### Task 1.6 -- Wire it into the App

Open `src/App.tsx`. You will see:

```tsx
import { Header } from './components/Header';
// TODO 1.5: Import the AccountList component from './components/AccountList'

import './App.css';

export function App() {
  return (
    <div className="app">
      <Header />
      <main>
        {/* TODO 1.6: Render the AccountList component here */}
      </main>
    </div>
  );
}
```

Add the import at the top:

```tsx
import { AccountList } from './components/AccountList';
```

And replace the TODO inside `<main>`:

```tsx
<main>
  <AccountList />
</main>
```

### Verify Exercise 1

Save all your files. The dev server should hot-reload. In the browser, you should now see a table listing three accounts. Watch the page during reload and you might briefly see "Loading accounts..." before the list appears. The mock API in `handlers.ts` returns a fixed delay of 300ms, so the loading state is observable.

If you see "Error: ..." instead of the list, check the browser DevTools (F12) Console tab for the actual error. Common causes:

- The MSW service worker did not start. Check `src/main.tsx` includes the worker registration code (it should already be there).
- There is a TypeScript error in `AccountList.tsx`. The dev server will show it in the terminal.

> **Open DevTools and watch what happens.** With DevTools open, go to the Network tab and reload the page. You should see a request to `/api/accounts` returning 200 with a JSON body. This is MSW intercepting the call. As far as the React code knows, this is a real API call.

---

## Exercise 2 -- Build the Transfer Form

**Estimated time:** 30-35 minutes
**Topics covered:** Controlled inputs, form submission, posting to an API, displaying success and failure feedback

### Context

A "controlled" input in React means an `<input>` whose displayed value is driven by component state. Whenever the user types, the change handler updates state, and the new state value flows back into the input on the next render. This makes the state always match what the user sees, which is the foundation for validation, formatting, and submit logic.

The transfer form has four pieces:

1. **State** for the form fields (from account, to account, amount).
2. **Change handlers** that update state as the user types or selects.
3. **A submit handler** that posts the form to the API and reports the result.
4. **State** for the API call's outcome (submitting, success, error).

### Task 2.1 -- Open the TransferForm component

Open `src/components/TransferForm.tsx`. The structure and styling are provided. You will fill in the React logic.

```tsx
import { useState } from 'react';
import { postTransfer } from '../api/client';
import type { Account } from '../api/types';

type TransferFormProps = {
  accounts: Account[];
  onTransferComplete: () => void;
};

export function TransferForm({ accounts, onTransferComplete }: TransferFormProps) {
  // TODO 2.1: Declare state for the three form fields:
  //   - fromAccount: a string, initially ''
  //   - toAccount: a string, initially ''
  //   - amount: a string, initially ''
  // (Why string for amount? Form inputs always produce strings;
  // we will convert to a number when we submit.)


  // TODO 2.2: Declare state for the API call status:
  //   - submitting: a boolean, initially false
  //   - message: a string or null, initially null
  //   - messageType: 'success' or 'error' or null, initially null


  // TODO 2.3: Write the submit handler. It should:
  //   - Prevent the browser's default form submission
  //   - Set submitting to true and clear any previous message
  //   - Call postTransfer with the current form values
  //     (convert amount with parseFloat)
  //   - On success: set a success message, clear the form, and
  //     call onTransferComplete to refresh the account list
  //   - On failure: set an error message
  //   - In all cases: set submitting back to false


  return (
    <section className="transfer-form">
      <h2>Transfer Money</h2>
      {/* TODO 2.4: Wire the onSubmit prop on the form below to the handler */}
      <form>
        <div className="form-row">
          <label htmlFor="fromAccount">From Account</label>
          {/* TODO 2.5: Make this a controlled select.
              - The 'value' prop should be fromAccount.
              - The 'onChange' handler should update fromAccount.
              - The options should be one per account in the accounts prop. */}
          <select id="fromAccount">
            <option value="">-- Select an account --</option>
          </select>
        </div>

        <div className="form-row">
          <label htmlFor="toAccount">To Account Number</label>
          {/* TODO 2.6: Make this a controlled text input.
              - The 'value' prop should be toAccount.
              - The 'onChange' handler should update toAccount. */}
          <input id="toAccount" type="text" placeholder="Destination account number" />
        </div>

        <div className="form-row">
          <label htmlFor="amount">Amount</label>
          {/* TODO 2.7: Make this a controlled text input.
              - The 'value' prop should be amount.
              - The 'onChange' handler should update amount.
              - type="number" hints at numeric input but the value is still a string. */}
          <input id="amount" type="number" step="0.01" min="0.01" placeholder="0.00" />
        </div>

        {/* TODO 2.8: When submitting is true, the button should be disabled and show "Submitting..."
                     Otherwise the button should be enabled and show "Transfer". */}
        <button type="submit">Transfer</button>

        {/* TODO 2.9: If message is not null, render a <p> with the message.
                     Use the className "form-message success" or "form-message error"
                     based on messageType. */}
      </form>
    </section>
  );
}
```

Notice the `TransferFormProps` type at the top. This is how a parent component passes data and callbacks to a child. The parent provides:

- `accounts`: the list of accounts to populate the "From" dropdown.
- `onTransferComplete`: a callback the form invokes after a successful transfer, so the parent can refresh the account balances.

> **C# comparison:** Props are like component parameters in Blazor or Razor. The function signature `function TransferForm({ accounts, onTransferComplete }: TransferFormProps)` is destructuring the single props object into named variables.

### Task 2.2 -- Add form field state

Replace the **TODO 2.1** comment with:

```tsx
const [fromAccount, setFromAccount] = useState<string>('');
const [toAccount, setToAccount] = useState<string>('');
const [amount, setAmount] = useState<string>('');
```

Three pieces of state, one per form field. Each holds a string because that is what HTML form inputs produce. We will convert `amount` to a number only at submit time.

### Task 2.3 -- Add submission status state

Replace the **TODO 2.2** comment with:

```tsx
const [submitting, setSubmitting] = useState<boolean>(false);
const [message, setMessage] = useState<string | null>(null);
const [messageType, setMessageType] = useState<'success' | 'error' | null>(null);
```

`submitting` is a flag that we will use to disable the button while a transfer is in flight. `message` and `messageType` together determine what feedback to show after a transfer attempt.

The `'success' | 'error' | null` type is a TypeScript **literal union**. It says the value can be one of those three exact things and nothing else. The TypeScript compiler will catch any other value at compile time.

### Task 2.4 -- Write the submit handler

Replace the **TODO 2.3** comment with:

```tsx
async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
  event.preventDefault();

  setSubmitting(true);
  setMessage(null);
  setMessageType(null);

  try {
    const result = await postTransfer({
      fromAccountNumber: fromAccount,
      toAccountNumber: toAccount,
      amount: parseFloat(amount),
    });

    if (result.status === 'COMPLETE') {
      setMessage(`Transfer complete. Transaction ID: ${result.transactionId}`);
      setMessageType('success');
      setFromAccount('');
      setToAccount('');
      setAmount('');
      onTransferComplete();
    } else {
      setMessage('Transfer failed. Please try again.');
      setMessageType('error');
    }
  } catch (e) {
    setMessage(e instanceof Error ? e.message : 'Unknown error occurred');
    setMessageType('error');
  } finally {
    setSubmitting(false);
  }
}
```

Walk through the key parts:

- `event.preventDefault()` stops the browser's default form behavior, which is to submit the form by reloading the page. We want React to handle the submission, not the browser.
- `setSubmitting(true)` immediately disables the button (once the next render happens).
- `parseFloat(amount)` converts the string from the amount input into a number for the API.
- After a successful transfer, we clear the form fields and call `onTransferComplete()` so the parent can refresh the account list and show the new balances.
- The `try`/`catch`/`finally` mirrors the pattern from Exercise 1: handle success, handle failure, and always clean up the loading flag.

### Task 2.5 -- Wire the form to the submit handler

Replace the **TODO 2.4** comment by adding `onSubmit` to the `<form>`:

```tsx
<form onSubmit={handleSubmit}>
```

This connects the form's submit event (triggered by clicking the submit button or pressing Enter) to your handler.

### Task 2.6 -- Make the "From Account" dropdown controlled

Replace the **TODO 2.5** comment and the `<select>` element with:

```tsx
<select
  id="fromAccount"
  value={fromAccount}
  onChange={(e) => setFromAccount(e.target.value)}
  required
>
  <option value="">-- Select an account --</option>
  {accounts.map((account) => (
    <option key={account.accountNumber} value={account.accountNumber}>
      {account.accountNumber} ({account.type}) - ${account.balance.toFixed(2)}
    </option>
  ))}
</select>
```

Three things make this a controlled select:

- The `value={fromAccount}` prop forces the `<select>` to display whatever the state says.
- The `onChange` handler updates state when the user picks a different option.
- Each option has a unique `key` (the account number) and a `value` that React Router-style code can read.

### Task 2.7 -- Make the "To Account" input controlled

Replace the **TODO 2.6** comment and `<input>` with:

```tsx
<input
  id="toAccount"
  type="text"
  placeholder="Destination account number"
  value={toAccount}
  onChange={(e) => setToAccount(e.target.value)}
  required
/>
```

### Task 2.8 -- Make the "Amount" input controlled

Replace the **TODO 2.7** comment and `<input>` with:

```tsx
<input
  id="amount"
  type="number"
  step="0.01"
  min="0.01"
  placeholder="0.00"
  value={amount}
  onChange={(e) => setAmount(e.target.value)}
  required
/>
```

> **Note on `type="number"`:** Setting `type="number"` on an HTML input tells the browser to show numeric controls and validate that the input is a number. However, the `value` you read out of `e.target.value` is **still a string**. That is why we keep `amount` as a string in state and convert with `parseFloat` only at submit time.

### Task 2.9 -- Submit button and feedback

Replace the **TODO 2.8** button with:

```tsx
<button type="submit" disabled={submitting}>
  {submitting ? 'Submitting...' : 'Transfer'}
</button>
```

The `disabled` attribute is bound to the `submitting` state. When `submitting` is true, the button is disabled and its text changes. The `{submitting ? 'Submitting...' : 'Transfer'}` is a JavaScript ternary expression evaluated inside JSX.

Replace the **TODO 2.9** comment with the message rendering:

```tsx
{message && (
  <p className={`form-message ${messageType}`}>
    {message}
  </p>
)}
```

The `&&` is a JavaScript short-circuit. If `message` is null (falsy), the whole expression evaluates to null and nothing is rendered. If `message` has a value (truthy), the `<p>` is rendered. The backtick template literal `` `form-message ${messageType}` `` builds a CSS class string like `"form-message success"` or `"form-message error"`.

### Verify Exercise 2

The form is not yet visible because the App component has not been updated. That is the next exercise.

---

## Exercise 3 -- Compose the App

**Estimated time:** 15-20 minutes
**Topics covered:** Lifting state up, passing props and callbacks between components, refreshing data after an action

### Context

The `AccountList` and `TransferForm` components are independent right now. But they need to talk to each other: when a transfer completes, the account list should refresh to show the new balances. The React pattern for this is **lifting state up**: move the shared state to a common parent (the `App` component) and pass it down to both children.

This is also the part of React that surprises C# developers most. In MVVM-style frameworks, two child components might both bind to the same observable on a shared view model. In React, the data lives in the parent and flows down as props, and changes flow back up via callback functions.

### Task 3.1 -- Move account loading to App

Currently the `AccountList` component loads its own accounts. We are going to move that logic into `App` so the `TransferForm` can also use the accounts data.

Open `src/App.tsx`. Replace its entire contents with:

```tsx
import { useState, useEffect, useCallback } from 'react';
import { Header } from './components/Header';
import { AccountList } from './components/AccountList';
import { TransferForm } from './components/TransferForm';
import { getAccounts } from './api/client';
import type { Account } from './api/types';
import './App.css';

export function App() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const loadAccounts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getAccounts();
      setAccounts(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadAccounts();
  }, [loadAccounts]);

  return (
    <div className="app">
      <Header />
      <main>
        <AccountList
          accounts={accounts}
          loading={loading}
          error={error}
        />
        <TransferForm
          accounts={accounts}
          onTransferComplete={loadAccounts}
        />
      </main>
    </div>
  );
}
```

Walk through the changes:

- `App` now owns the account state, loading flag, and error.
- `loadAccounts` is wrapped in `useCallback` so its identity is stable across renders. Without that, its identity would change on every render, the `useEffect` dependency would always have changed, and the effect would re-run forever.
- `loadAccounts` is passed to `TransferForm` as `onTransferComplete`. After a successful transfer, the form invokes this callback, the App re-fetches the accounts, and the new balances flow back down.

### Task 3.2 -- Update AccountList to receive props

The `AccountList` component now receives data from its parent rather than fetching it itself. Open `src/components/AccountList.tsx` and replace the entire file with:

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
    return <p className="status-message error">Error: {error}</p>;
  }

  return (
    <section className="account-list">
      <h2>Your Accounts</h2>
      <table>
        <thead>
          <tr>
            <th>Account Number</th>
            <th>Type</th>
            <th>Status</th>
            <th>Balance</th>
          </tr>
        </thead>
        <tbody>
          {accounts.map((account) => (
            <tr key={account.accountNumber}>
              <td>{account.accountNumber}</td>
              <td>{account.type}</td>
              <td>{account.status}</td>
              <td>${account.balance.toFixed(2)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
```

The component is now much simpler. No `useState`, no `useEffect`. It is what React calls a "presentational" component: given props, render markup. Easier to test and easier to reason about.

> **The principle:** Components do not need to own their data. Often it is better to push data ownership up the tree to a parent that can coordinate between siblings. This is what "lifting state up" means.

### Verify Exercise 3

Save and reload. You should now see:

1. The account list renders.
2. Below it, the transfer form renders.
3. You can pick a from-account, enter a to-account number (try `ACC-002`), enter an amount (try `100`), and click Transfer.
4. After a brief delay, you see "Transfer complete..." and the source account's balance is now lower.
5. The form fields reset to empty, ready for another transfer.

If you try to transfer more than the source account's balance, the mock API returns a failure and the form shows an error message. Try transferring `99999` from any account to see this.

---

## Exercise 4 -- Polish: Format and Improve the UX

**Estimated time:** 10-15 minutes
**Topics covered:** Derived values, helper functions, common React refinements

### Context

The application works, but a few small improvements will make it more pleasant to use and demonstrate idiomatic React patterns you will see in real codebases.

### Task 4.1 -- Format currency consistently

You are calling `account.balance.toFixed(2)` in two places. That is a smell: if you ever change the format (e.g. add a thousand separator: `$1,234.56`), you have to update both places. Extract a helper.

Create `src/utils/format.ts`:

```typescript
export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount);
}
```

`Intl.NumberFormat` is a built-in browser API that handles locale-aware number formatting. It produces strings like `$1,234.56` automatically.

Update `src/components/AccountList.tsx`:

```tsx
import { formatCurrency } from '../utils/format';
```

Then replace `${account.balance.toFixed(2)}` with `{formatCurrency(account.balance)}`.

Update `src/components/TransferForm.tsx` similarly. Replace `${account.balance.toFixed(2)}` in the dropdown with `{formatCurrency(account.balance)}`.

### Task 4.2 -- Disable the form when no source accounts are available

If for some reason no accounts have loaded yet (or the user has no accounts), the form should disable itself. Add this check inside `TransferForm`:

```tsx
if (accounts.length === 0) {
  return (
    <section className="transfer-form">
      <h2>Transfer Money</h2>
      <p className="status-message">No accounts available for transfer.</p>
    </section>
  );
}
```

Add this above the existing `return` statement. Now if `accounts` is empty, the form is replaced with a clear status message.

### Task 4.3 -- Filter inactive accounts from the dropdown

Customers should not be able to transfer from inactive accounts. Filter the accounts shown in the dropdown:

```tsx
const activeAccounts = accounts.filter((a) => a.status === 'ACTIVE');
```

Add this near the top of the `TransferForm` function (after the state declarations). Then use `activeAccounts` instead of `accounts` in the dropdown's `.map()`.

This is a **derived value**: it is calculated from existing state on every render. There is no need to store it in `useState` because it is fully determined by `accounts`. Storing it in state would risk having two pieces of state that disagree.

> **The principle:** If you can compute something from existing state and props, do not put it in state. Derive it.

### Verify Exercise 4

Reload the app. The balances now display with thousand separators. The dropdown only shows ACTIVE accounts. If somehow no accounts loaded, the form would show a clean status message instead of an empty dropdown.

---

## What You Have Built

You now have a working React application with:

- A list of accounts loaded from an API on startup
- A transfer form with controlled inputs, validation feedback, and success messaging
- Two components that communicate via state lifted up to a common parent
- Loading and error states handled gracefully

You have used the core React hooks: `useState`, `useEffect`, and `useCallback`. You have written controlled forms, rendered lists with keys, made async API calls, and refreshed the UI after a successful action.

The data layer (the `getAccounts` and `postTransfer` functions in `api/client.ts`) was deliberately kept simple and unaware of where the data comes from. In a later lab you will replace MSW with a real Spring Boot BFF and the React code will not need to change at all. That is the architectural payoff of treating data fetching as a clean abstraction.

---

## Reflection Questions

In a new file `lab-a-notes.md`, answer these in your own words:

1. What is the difference between calling `setAccounts(newData)` and just doing `accounts = newData`? Why does React require you to use the setter?

2. Why does `useEffect` need an empty dependency array `[]` to run only on mount? What would happen with no array at all?

3. What is a "controlled input" and why is it useful?

4. The `TransferForm` does not own the accounts data. It receives `accounts` and `onTransferComplete` from its parent. Why is this a better design than having `TransferForm` load and own the accounts itself?

5. Coming from C#, what was the most surprising thing about the React rendering model?

---

## What's Next

In the next lab, you will build a Spring Boot Backend-for-Frontend (BFF) using Spring Security and `spring-boot-starter-oauth2-client`. The BFF will handle OAuth authentication against the mock authorization server you have used in previous modules and will hold tokens server-side, exposing only an HttpOnly session cookie to the browser.

In the lab after that, you will replace MSW in this React application with real calls to the BFF. The React code you wrote here will continue to work with minimal changes: the same `fetch('/api/accounts')` call will work against either backend.
