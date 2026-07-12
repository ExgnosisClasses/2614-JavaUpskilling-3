# Lab 3.0 Part 2 - Oracle Navigation and Querying

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**
**Module 6 | Estimated time: 45-60 minutes | Tools: IntelliJ IDEA Ultimate**

---

## Overview

Part 1 set up an Oracle 21c environment (either VM-installed or running in a Docker container) and connected IntelliJ to it. Part 2 is what you do with that connection: create tables, load sample data, run queries, explore the schema browser, and observe several Oracle-specific behaviours that differ from SQL Server.

This part is **identical regardless of which Part 1 path you took**. Every step is run from inside IntelliJ - SQL\*Plus is not used at all. Your data lives in the PDB `XEPDB1` under the user `labuser`, and IntelliJ's database tool talks to that PDB over JDBC.

By the end of Part 2 you will have:

- Built a small relational schema (customers, accounts, transactions) using DDL
- Loaded sample data and observed Oracle's explicit-commit behaviour
- Used IntelliJ's schema browser to navigate tables and constraints
- Run queries from the IntelliJ query console
- Viewed an execution plan
- Worked with several Oracle features that differ from SQL Server: `DUAL`, `SYSDATE`, `NVL`, `ROWNUM`, data dictionary views

Open IntelliJ now and confirm the `labuser@XEPDB1` connection from Part 1 is still working before continuing.

---

## Working in the IntelliJ Query Console

Everything in Part 2 runs in IntelliJ's query console. Before starting, get familiar with the workflow:

1. In the **Database** tool window, right-click the `labuser` connection and choose **New -> Query Console**. This opens a SQL editor associated with that connection.
2. Type or paste a SQL statement.
3. Press **Ctrl+Enter** (Windows/Linux) or **Cmd+Enter** (macOS) to execute the statement under the cursor. If multiple statements are selected, all selected statements run.
4. Results appear in a panel below the editor. For SELECT statements, you get a result grid. For DDL or DML, you get a confirmation message and row count.

> **Tip:** You can save the query console as a `.sql` file in your project. IntelliJ remembers which connection it is bound to, so reopening the file goes straight to a working console.

> **About commits:** unlike SQL Server, Oracle does **not** auto-commit DML. Your `INSERT`, `UPDATE`, and `DELETE` statements are invisible to other sessions until you `COMMIT`. IntelliJ defaults to **manual commit mode** for Oracle - look at the toolbar above the query results for the commit/rollback buttons (the green checkmark and red X). You can switch to auto-commit using the dropdown next to those buttons, but for this lab keep the default manual mode so you experience the Oracle behaviour directly.

---

## Step 2.1 - Create the Tables

You will build a minimal banking schema: customers, accounts, and transactions. This schema will be expanded in later labs.

Open a fresh query console (right-click `labuser` -> **New -> Query Console**) and run each `CREATE TABLE` statement separately by placing your cursor on it and pressing **Ctrl+Enter**.

```sql
CREATE TABLE customers (
  customer_id   NUMBER GENERATED AS IDENTITY PRIMARY KEY,
  full_name     VARCHAR2(100)  NOT NULL,
  email         VARCHAR2(150)  UNIQUE NOT NULL,
  created_date  DATE           DEFAULT SYSDATE NOT NULL
);
```

```sql
CREATE TABLE accounts (
  account_id    NUMBER GENERATED AS IDENTITY PRIMARY KEY,
  customer_id   NUMBER         NOT NULL,
  account_type  VARCHAR2(20)   CHECK (account_type IN ('CHECKING','SAVINGS')),
  balance       NUMBER(15,2)   DEFAULT 0 NOT NULL,
  opened_date   DATE           DEFAULT SYSDATE NOT NULL,
  CONSTRAINT fk_acct_cust FOREIGN KEY (customer_id)
    REFERENCES customers(customer_id)
);
```

```sql
CREATE TABLE transactions (
  txn_id        NUMBER GENERATED AS IDENTITY PRIMARY KEY,
  account_id    NUMBER         NOT NULL,
  txn_type      VARCHAR2(10)   CHECK (txn_type IN ('CREDIT','DEBIT')),
  amount        NUMBER(15,2)   NOT NULL,
  txn_date      TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  description   VARCHAR2(255),
  CONSTRAINT fk_txn_acct FOREIGN KEY (account_id)
    REFERENCES accounts(account_id)
);
```

DDL statements (CREATE/ALTER/DROP) are implicitly committed in Oracle, so you do not need to manually commit after these. DML (INSERT/UPDATE/DELETE) does require an explicit commit, which you will see in the next step.

Confirm the tables exist:

```sql
SELECT table_name FROM user_tables ORDER BY table_name;
```

You should see `ACCOUNTS`, `CUSTOMERS`, and `TRANSACTIONS`.

> **A note on naming:** Oracle stores object names in uppercase by default. The lowercase `customers` in the CREATE statement becomes `CUSTOMERS` internally, and that is how it appears in the data dictionary views and in IntelliJ's schema browser. References from SQL are case-insensitive unless you wrap a name in double quotes (which you should generally avoid).

---

## Step 2.2 - Insert Sample Data

Run each block as a unit. You can highlight all three INSERTs for customers and press Ctrl+Enter to execute them together, or run them one at a time.

```sql
INSERT INTO customers (full_name, email) VALUES ('Alice Nguyen', 'alice@example.com');
INSERT INTO customers (full_name, email) VALUES ('Bob Patel',   'bob@example.com');
INSERT INTO customers (full_name, email) VALUES ('Carol Kim',   'carol@example.com');
```

```sql
INSERT INTO accounts (customer_id, account_type, balance) VALUES (1, 'CHECKING', 4500.00);
INSERT INTO accounts (customer_id, account_type, balance) VALUES (1, 'SAVINGS',  12000.00);
INSERT INTO accounts (customer_id, account_type, balance) VALUES (2, 'CHECKING', 800.50);
INSERT INTO accounts (customer_id, account_type, balance) VALUES (3, 'SAVINGS',  9750.00);
```

```sql
INSERT INTO transactions (account_id, txn_type, amount, description)
VALUES (1, 'CREDIT', 2000.00, 'Payroll deposit');

INSERT INTO transactions (account_id, txn_type, amount, description)
VALUES (1, 'DEBIT',  450.00,  'Rent payment');

INSERT INTO transactions (account_id, txn_type, amount, description)
VALUES (3, 'DEBIT',  200.00,  'Grocery store');
```

At this point, your INSERTs have been made in your session but they have **not been committed**. Other sessions (or a second IntelliJ console) cannot see them. Verify this is the case if you want to: open a second query console on the same connection and run `SELECT * FROM customers;` - you will see the rows (because IntelliJ shares a transaction across consoles on the same connection by default), but a separate connection would see an empty table.

Now commit explicitly:

```sql
COMMIT;
```

You can also press the green checkmark in the toolbar above the result grid. Either way, your changes are now permanent and visible to everyone.

> **Important:** Always commit (or rollback) explicitly when you are done with a logical unit of work. A long-uncommitted transaction holds row-level locks that can block other sessions. If you close IntelliJ without committing, the implicit rollback on disconnect will undo all your DML - this is a frequent way to lose work when you are new to Oracle.

---

## Step 2.3 - Run Basic Queries

Try the following queries and note the results. These exercise the relationships you just defined.

```sql
-- 1. List all customers
SELECT * FROM customers;
```

```sql
-- 2. Join customers and accounts
SELECT c.full_name, a.account_type, a.balance
FROM   customers c
JOIN   accounts  a ON a.customer_id = c.customer_id
ORDER  BY c.full_name, a.account_type;
```

```sql
-- 3. Total balance per customer
SELECT c.full_name, SUM(a.balance) AS total_balance
FROM   customers c
JOIN   accounts  a ON a.customer_id = c.customer_id
GROUP  BY c.full_name
ORDER  BY total_balance DESC;
```

```sql
-- 4. Transactions with account owner
SELECT c.full_name, t.txn_type, t.amount, t.description, t.txn_date
FROM   transactions t
JOIN   accounts     a ON a.account_id  = t.account_id
JOIN   customers    c ON c.customer_id = a.customer_id;
```

Query 3 should show Alice with the largest total balance (16,500.00 across her two accounts), then Carol (9,750.00), then Bob (800.50).

---

## Step 2.4 - Explore the IntelliJ Schema Browser

The query console is one way to interact with the database; the schema browser is the other. Get comfortable with both - some tasks are faster in the browser, some are faster in SQL.

### Browsing tables

- In the **Database** tool window, expand the connection node, then expand `labuser`.
- Expand `Tables`. You should see `ACCOUNTS`, `CUSTOMERS`, and `TRANSACTIONS`.
- Double-click any table name. IntelliJ opens a grid view of the table's data. You can edit cells directly in the grid (commit using the green checkmark in the grid's toolbar, just like the query console).
- Right-click a table and choose **Modify Table**. This opens a dialog showing every column with its data type, default value, nullability, and any constraints. This is the IntelliJ equivalent of `DESCRIBE` in SQL\*Plus.

### Inspecting constraints

- Expand `ACCOUNTS` in the tree. You should see sub-nodes for `Columns`, `Keys`, `Indexes`, `Foreign Keys`, and `Checks`.
- Click on `Foreign Keys`. You should see `FK_ACCT_CUST` pointing to `CUSTOMERS`.
- Click on `Checks`. You should see the check constraint on `ACCOUNT_TYPE` that restricts it to `'CHECKING'` or `'SAVINGS'`.

### Generating DDL

- Right-click any table and choose **SQL Scripts -> SQL Generator**.
- IntelliJ produces the exact CREATE TABLE statement Oracle would use to recreate the table, including all constraints and storage clauses. This is useful for documenting your schema or migrating to another environment.

> **Tip:** The schema browser is read-only-by-default for safety. Edits in the data grid require an explicit submit (the green checkmark) before they are sent to the database. Schema changes via Modify Table are queued as DDL that you can preview before executing.

---

## Step 2.5 - Run a Query in the IntelliJ Console and View its Execution Plan

You already used the query console to create tables. Now use it for analysis.

In your query console, type and run:

```sql
SELECT c.full_name,
       COUNT(a.account_id)  AS num_accounts,
       SUM(a.balance)       AS total_balance
FROM   customers c
JOIN   accounts  a ON a.customer_id = c.customer_id
GROUP  BY c.full_name
ORDER  BY total_balance DESC;
```

Results appear in the output panel below the editor. You can:

- Right-click the grid to export to CSV, JSON, or copy as INSERT statements.
- Click a column header to sort.
- Use the search box (Ctrl+F when the grid is focused) to filter rows.

### Viewing the execution plan

Highlight the query above, then right-click and choose **Explain Plan** (or use the menu **Database -> Explain Plan**). IntelliJ runs `EXPLAIN PLAN FOR ...` against Oracle and displays the result as a tree.

For these small tables with no indexes, you will see:

- A `TABLE ACCESS FULL` on both `CUSTOMERS` and `ACCOUNTS` (Oracle's term for a full table scan)
- A `HASH JOIN` connecting them
- A `SORT GROUP BY` for the aggregation
- A `SORT ORDER BY` for the final sort

A full table scan on small tables is normal and not a problem. Lab 3.2 covers when and how to add indexes to make queries use index scans instead. For now, just notice that the plan exists and that you can read it.

> **Tip:** IntelliJ provides Oracle-aware code completion. Start typing `SELECT c.` after declaring `c` as an alias and the IDE will suggest the columns of `CUSTOMERS`. This is especially useful when writing complex joins or remembering exact column names.

---

## Step 2.6 - Oracle-Specific Observations

Run the following short exercises to observe Oracle behaviours that differ from SQL Server. All run in the IntelliJ query console.

### Exercise A - Date arithmetic

```sql
-- Oracle DATE includes time. Add 7 days to today:
SELECT SYSDATE, SYSDATE + 7 AS next_week FROM dual;
```

```sql
-- Extract just the date part:
SELECT TRUNC(SYSDATE) AS today_only FROM dual;
```

```sql
-- Days between two dates (returns a NUMBER, not an interval):
SELECT SYSDATE - TO_DATE('2024-01-01','YYYY-MM-DD') AS days_since FROM dual;
```

The Oracle `DATE` type always includes a time component, which catches SQL Server developers used to a date-only type. The `TRUNC()` function chops off the time, leaving midnight on the same day.

### Exercise B - NULL handling and NVL

```sql
-- Oracle equivalent of ISNULL / COALESCE:
SELECT NVL(NULL, 'default')   AS nvl_result,
       COALESCE(NULL,'b','c') AS coalesce_result
FROM   dual;
```

```sql
-- NVL2(expr, val_if_not_null, val_if_null):
SELECT full_name, NVL2(email, 'Has email', 'No email') AS email_status
FROM   customers;
```

`NVL` is Oracle-specific and takes exactly two arguments. `COALESCE` is the SQL standard and takes any number of arguments - use `COALESCE` in new code unless you specifically need Oracle's `NVL2`, which has no SQL standard equivalent.

### Exercise C - Sequences and ROWNUM

```sql
-- ROWNUM is Oracle's traditional row-limiting mechanism:
SELECT full_name FROM customers WHERE ROWNUM <= 2;
```

```sql
-- Modern approach - use FETCH FIRST (SQL standard, Oracle 12c+):
SELECT full_name FROM customers FETCH FIRST 2 ROWS ONLY;
```

> **Important:** Prefer `FETCH FIRST` over `ROWNUM` for new code. `ROWNUM` is applied **before** `ORDER BY`, which produces surprising results when sorting - a classic Oracle gotcha. Try the following two queries and compare:
>
> ```sql
> SELECT full_name FROM customers WHERE ROWNUM <= 2 ORDER BY full_name;
> ```
>
> ```sql
> SELECT full_name FROM customers ORDER BY full_name FETCH FIRST 2 ROWS ONLY;
> ```
>
> The first picks 2 arbitrary rows and then sorts them. The second sorts the entire table and then picks the first 2. These often give different answers.

### Exercise D - Data dictionary views

```sql
-- Your objects (equivalent of INFORMATION_SCHEMA for your own schema):
SELECT object_name, object_type FROM user_objects ORDER BY object_type, object_name;
```

```sql
-- Column info for a specific table:
SELECT column_name, data_type, nullable, data_default
FROM   user_tab_columns
WHERE  table_name = 'CUSTOMERS';
```

```sql
-- Constraints on your tables:
SELECT constraint_name, constraint_type, table_name
FROM   user_constraints
WHERE  table_name IN ('CUSTOMERS','ACCOUNTS','TRANSACTIONS');
```

> **Tip:** The `USER_*` views show your own objects. `ALL_*` views show everything you have access to. `DBA_*` views (SYS only) show the entire database. This three-tier pattern is consistent across all Oracle data dictionary views. The `WHERE table_name = 'CUSTOMERS'` predicate must be uppercase because Oracle stores names in uppercase by default - lowercase here would return no rows.

---

## Challenge Exercises

Complete these independently. No solution is provided - use the techniques from this lab and Oracle documentation in IntelliJ's built-in help.

### Challenge 1 - Query writing

- [ ] Write a query that returns each customer's name and their most recent transaction date. Customers with no transactions should still appear (use an outer join).
- [ ] Write a query showing accounts whose balance is above the average balance across all accounts.
- [ ] Return the top 2 customers by total balance using `FETCH FIRST` syntax.

### Challenge 2 - Schema changes

- [ ] Add a `phone_number VARCHAR2(20)` column to the `CUSTOMERS` table using `ALTER TABLE`.
- [ ] Add a `CHECK` constraint to `TRANSACTIONS` ensuring `amount > 0`.
- [ ] Create an index on `transactions.account_id` and verify it appears in `user_indexes`.

### Challenge 3 - IntelliJ exploration

- [ ] Export the result of your three-way join query to a CSV file from the IntelliJ grid.
- [ ] After adding the index from Challenge 2, re-run Explain Plan and identify whether Oracle now chooses an index scan over a full table scan.

---

## Lab Summary

In Part 1 you set up an Oracle 21c environment using either a VM-installed instance or a Docker container, and connected IntelliJ to it. In Part 2 you:

- Created a PDB-scoped schema with tables, constraints, and sample data using DDL from the IntelliJ console
- Ran DML and queries, observing Oracle's explicit commit requirement
- Navigated the IntelliJ schema browser to inspect tables, foreign keys, and check constraints
- Viewed an execution plan in IntelliJ
- Explored Oracle-specific behaviours: `DUAL`, `SYSDATE`, `NVL`, `ROWNUM`, and data dictionary views

You are now ready for the rest of the Oracle labs in this module: index tuning (Lab 3.2), PL/SQL stored procedures, and Spring Data integration. All of those labs build on the schema you just created.

---
