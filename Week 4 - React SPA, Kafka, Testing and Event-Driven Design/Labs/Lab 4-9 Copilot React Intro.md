# Lab: Building a React App with GitHub Copilot

#### Capstone preparation, approximately 45 minutes

## Context

You will build the capstone's front-end additions in React, with Copilot's help,
and most of you are new to React. This lab is a warm-up: you build a small app and,
more importantly, practice the workflow of prompting Copilot, reading what it gives
you, and deciding whether it is right.

That second skill is the point. Copilot is fast and usually close, but it is a
draft, not an answer. The capstone grades both how well you use Copilot and how well
you review what it produces. This lab practices both on a throwaway app so you make
your mistakes here, not in the capstone.

You will build a small Account Dashboard: a list of accounts, a detail panel for the
selected one, and a filter box. The stack is the same as the capstone SPA, so what
you learn here carries over directly.

## Setup

You need Node 18 or later and an IDE with the GitHub Copilot and Copilot Chat
extensions installed and signed in (VS Code, or a JetBrains IDE such as WebStorm or
IntelliJ).

Scaffold the project:

```
npm create vite@latest copilot-demo -- --template react-ts
cd copilot-demo
npm install
npm run dev
```

Open the URL it prints (usually `http://localhost:5173`) and confirm the starter
page loads. Then open `src/App.tsx`; you will replace its contents over the next
tasks.

## Copilot in sixty seconds

There are two ways to use Copilot, and you will use both.

**Inline completions.** As you type, Copilot shows grey suggestion text. Press Tab to
accept, Esc to dismiss. A comment describing what you want often triggers a good
suggestion, so writing a clear comment first is itself a prompting technique. (To
cycle alternative suggestions: Alt+] and Alt+[ in VS Code, or the on-hover controls
in JetBrains.)

**Copilot Chat.** A side panel where you ask in plain language and get code back with
an explanation. Best for scaffolding a whole component or file.

Rule of thumb: Chat to create something new, inline to finish the line you are on.

## Task 1: Generate the data model (Copilot Chat)

Create `src/data.ts`. In Copilot Chat, ask:

> In TypeScript, define an `Account` interface with `id` (number),
> `accountNumber` (string), `type` which is either 'CHECKING' or 'SAVINGS', and
> `balance` (number). Then export an array of four sample accounts.

Insert the result into `data.ts`.

**Review it before moving on.** Is `type` a union (`'CHECKING' | 'SAVINGS'`) rather
than a plain `string`? Are the balances numbers, not strings in quotes? Is the array
exported? If Copilot gave you `string` for the type, ask it to "make type a union of
the two literal values" and watch it fix it.

A correct result looks like this:

```ts
export interface Account {
  id: number;
  accountNumber: string;
  type: 'CHECKING' | 'SAVINGS';
  balance: number;
}

export const accounts: Account[] = [
  { id: 1, accountNumber: '128-9878-001', type: 'CHECKING', balance: 5000.00 },
  { id: 2, accountNumber: '128-9878-002', type: 'SAVINGS',  balance: 10000.00 },
  { id: 3, accountNumber: '128-9878-003', type: 'CHECKING', balance: 250.00 },
  { id: 4, accountNumber: '128-9878-004', type: 'SAVINGS',  balance: 7400.00 },
];
```

## Task 2: The account list (inline, comment-driven)

Create `src/AccountList.tsx`. Type a comment describing the component, then let
Copilot complete it:

```tsx
// A React function component that takes a list of accounts and an onSelect
// callback. Render each account as a clickable list item showing its account
// number and type. Props are typed with a TypeScript interface.
```

Accept and adjust Copilot's suggestion until you have a working component.

**Review checklist:**

- Does each list item have a `key` prop? This is the single most common thing to
  check in React list code, and Copilot sometimes omits it. Without a stable `key`,
  React cannot track list items correctly.
- Are the props typed with an interface, not `any`?
- Is it a function component (not an old class component)?

A correct result looks like this:

```tsx
import { Account } from './data';

interface AccountListProps {
  accounts: Account[];
  onSelect: (id: number) => void;
}

export function AccountList({ accounts, onSelect }: AccountListProps) {
  return (
    <ul>
      {accounts.map((account) => (
        <li key={account.id} onClick={() => onSelect(account.id)}>
          {account.accountNumber} ({account.type})
        </li>
      ))}
    </ul>
  );
}
```

## Task 3: Hold the selection in App (lifting state up)

The list reports which account was clicked, but the selected account has to be
remembered somewhere both the list and the detail panel can reach. That place is the
parent, `App`. In Chat:

> In my App component, use the useState hook to track a selected account id
> (number or null). Render AccountList, passing the accounts and a handler that
> sets the selected id. Look up the selected account from the accounts array.

**Review checklist:**

- Is the state typed, for example `useState<number | null>(null)`?
- Is the handler passed down to `AccountList` as the `onSelect` prop?

A correct `App.tsx` looks like this:

```tsx
import { useState } from 'react';
import { accounts } from './data';
import { AccountList } from './AccountList';
import { AccountDetail } from './AccountDetail';

export default function App() {
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const selected = accounts.find((a) => a.id === selectedId) ?? null;

  return (
    <div>
      <h1>Accounts</h1>
      <AccountList accounts={accounts} onSelect={setSelectedId} />
      <AccountDetail account={selected} />
    </div>
  );
}
```

## Task 4: The detail panel (conditional rendering)

Create `src/AccountDetail.tsx` with Copilot. Prompt it for a component that takes an
`account` prop which may be `null`, shows a placeholder message when it is null, and
otherwise shows the account number, type, and balance.

**Review checklist:**

- Does it handle the `null` case, rather than crashing when nothing is selected?
- Is the balance shown with two decimals (`balance.toFixed(2)`)?

A correct result:

```tsx
import { Account } from './data';

interface AccountDetailProps {
  account: Account | null;
}

export function AccountDetail({ account }: AccountDetailProps) {
  if (!account) {
    return <p>Select an account to see its details.</p>;
  }
  return (
    <div>
      <h2>{account.accountNumber}</h2>
      <p>Type: {account.type}</p>
      <p>Balance: {account.balance.toFixed(2)}</p>
    </div>
  );
}
```

Run the app. Clicking a row should fill the detail panel. If it does, you have the
core of every React UI: components, props, state, list rendering, and conditional
rendering, all generated with Copilot.

## Task 5: The critical-review task (a filter box)

Ask Copilot Chat to add a search box that filters the account list as you type. Then
do **not** trust the first answer. Walk this checklist against what it produced:

- Is the input a controlled component, with both `value={query}` and an `onChange`
  that calls `setQuery`? An input with only one of these is a common Copilot miss and
  behaves strangely.
- Is the filter case-insensitive (lowercasing both sides), or does it only match
  exact case?
- Did adding the filter accidentally drop the `key` prop on the list, or break the
  selection handler?
- Did Copilot reach for a `useEffect` to compute the filtered list? It does not need
  one; the filtered list is just derived from state during render. If it added an
  effect, simplify it.

If any of those is wrong, fix it with a follow-up prompt ("make the input
controlled", "filter case-insensitively", "remove the unnecessary useEffect") and
confirm the fix. That loop, generate, review against a checklist, refine, is the
whole skill.

A correct, minimal version derives the list during render:

```tsx
const [query, setQuery] = useState('');
const filtered = accounts.filter((a) =>
  a.accountNumber.toLowerCase().includes(query.toLowerCase())
);
// ...
<input
  value={query}
  onChange={(e) => setQuery(e.target.value)}
  placeholder="Filter by account number"
/>
```

## Checkpoints

Answer these in your own words; they are the concepts the tasks exercised.

1. Why does React need a `key` on each item in a rendered list, and what kind of bug
   appears if you leave it out?
2. The selection state lives in `App`, not in `AccountList`. What is "lifting state
   up", and why does the selected id belong in the parent here?
3. Pick one Copilot suggestion you accepted and one you rejected or changed. How did
   you decide each was right or wrong?
4. When did inline completion serve you better than Chat, and when was it the
   reverse?

## Effective Copilot prompting, in short

- Be specific: name the framework, the types, the prop names, the behavior.
- Give context: open the related file (like `data.ts`) so Copilot can see your types.
- Iterate: treat the first answer as a draft and refine it with follow-ups.
- Review everything: check it compiles, follows React's rules, and is typed.
- The one rule that matters most: do not accept code you cannot explain. In the
  capstone you will be asked how your AI-assisted code works, and "Copilot wrote it"
  is not an answer.

## Notes 
- Copilot's output is a draft to be reviewed, not a verdict
  to be accepted. 
- Students who internalize "do not accept code you cannot explain"
  do well on the capstone's AI criteria; those who paste blindly do not.
- Data fetching and auth are intentionally absent. The capstone SPA already reaches
  the BankService through the BFF; this lab stays on components and state so the
  React fundamentals land first.
