# Lab 3.1 - PL/SQL Fundamentals

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**  
**Module 7 | Estimated time: 75-90 minutes | Tools: IntelliJ IDEA Ultimate**

---

## Overview

SQL is powerful for set-based operations but cannot on its own validate complex business rules, loop over rows conditionally, or handle errors differently depending on what went wrong. PL/SQL is Oracle's procedural extension to SQL that solves these problems by running directly inside the database engine.

This lab builds on the banking schema you created in Lab 3.0. You will write anonymous blocks to explore PL/SQL structure, create stored procedures that encapsulate business logic, and build triggers that enforce rules and maintain an audit trail automatically.

By the end of this lab you will have:

- Written and executed anonymous PL/SQL blocks from the IntelliJ query console
- Used variables, control flow, and exception handling inside PL/SQL blocks
- Created and called a stored procedure with IN and OUT parameters
- Observed how procedures encapsulate logic and reduce network round-trips
- Created a trigger that fires automatically on DML events
- Browsed compiled procedures and triggers in IntelliJ's schema browser

---

## Background - PL/SQL for C# / SQL Server Developers

The table below maps PL/SQL concepts to their C# and T-SQL equivalents.

| C# / T-SQL Concept | PL/SQL Equivalent | Key Difference |
|--------------------|-------------------|----------------|
| `try/catch` block | `EXCEPTION` section | PL/SQL exceptions are named; Oracle provides a set of predefined names like `NO_DATA_FOUND` and `TOO_MANY_ROWS`. |
| Local variable `int x = 0;` | `x NUMBER := 0;` | Variables are declared in the `DECLARE` section before `BEGIN`. Assignment uses `:=` not `=`. |
| `Console.WriteLine()` | `DBMS_OUTPUT.PUT_LINE()` | Output appears in the IntelliJ console output panel after execution. |
| Stored procedure | `CREATE PROCEDURE` | Oracle procedures use `IN`, `OUT`, and `IN OUT` parameter modes instead of `ref` and `out`. |
| Function returning a value | `CREATE FUNCTION` | PL/SQL functions can be called from SQL statements; procedures cannot. |
| SQL Server trigger | Oracle trigger | Syntax differs; Oracle triggers have more granular options including row-level and statement-level firing. |
| `IF...ELSE` | `IF...ELSIF...ELSE...END IF;` | Every PL/SQL control structure ends with a closing keyword. Note `ELSIF` not `ELSEIF`. |
| `for` loop | `FOR i IN 1..10 LOOP...END LOOP;` | Range loops use `..` notation. Cursor FOR loops iterate over query results automatically. |

---

## Using the IntelliJ Query Console for PL/SQL

Before starting the lab exercises, take a few minutes to understand how IntelliJ handles PL/SQL differently from plain SQL.

### Opening a Console

In the Database panel, right-click the `labuser` connection and choose **New -> Query Console**. A new editor tab opens connected to your schema.

### Running PL/SQL Blocks

IntelliJ detects PL/SQL blocks automatically. When you press `Ctrl+Enter` with your cursor inside a `BEGIN...END` block, IntelliJ submits the entire block to Oracle as a single unit. You do not need the `/` character that SQL\*Plus requires - IntelliJ handles the block boundary detection itself.

For a `CREATE OR REPLACE PROCEDURE` or `CREATE OR REPLACE TRIGGER` statement, place your cursor anywhere inside the statement and press `Ctrl+Enter`. IntelliJ will submit the entire DDL statement including the procedure body.

> **Tip:** If you have multiple statements in the console and want to run just one, highlight it with the mouse before pressing `Ctrl+Enter`. IntelliJ will run only the selected text.

### Seeing DBMS_OUTPUT

IntelliJ captures `DBMS_OUTPUT.PUT_LINE` output automatically and displays it in the output panel below the editor. You do not need to run `SET SERVEROUTPUT ON` as you would in SQL\*Plus. The output appears alongside any result sets or messages from the executed statement.

### Handling Errors

When a PL/SQL block fails to compile or raises a runtime error, IntelliJ displays the Oracle error message in the output panel. For compilation errors on stored procedures, you can also right-click the procedure in the schema browser and choose **Jump to Source** to see the error location highlighted in the editor.

---

## Prerequisite Check

This lab uses the schema built in Lab 3.0. Open a query console connected as `labuser` and confirm the tables exist.

```sql
SELECT table_name FROM user_tables ORDER BY table_name;
```

Run this with `Ctrl+Enter`. You should see `ACCOUNTS`, `CUSTOMERS`, and `TRANSACTIONS` in the results grid. If not, return to Lab 3.0 and complete the schema setup before continuing.

---

## Part 1 - Anonymous Blocks

An anonymous block is a PL/SQL block submitted directly to Oracle for immediate execution. It has no name, is not stored in the database, and cannot be called by other code. It is the PL/SQL equivalent of a shell script - useful for one-time operations, data corrections, and exploring logic before formalising it as a stored procedure.

### The Block Structure

Every PL/SQL block follows this structure:

```sql
DECLARE
    -- optional: variables, constants, cursors, types
BEGIN
    -- mandatory: executable statements
EXCEPTION
    -- optional: error handlers
END;
```

The `DECLARE` section is optional but must appear if you need variables. The `EXCEPTION` section is optional. The `BEGIN`/`END` section is mandatory. In IntelliJ you do not add a trailing `/` - just place your cursor inside the block and press `Ctrl+Enter`.

---

### Step 1.1 - Your First Anonymous Block

Type the following into your query console and press `Ctrl+Enter`:

```sql
BEGIN
    DBMS_OUTPUT.PUT_LINE('Hello from PL/SQL');
END;
```

Look at the output panel below the editor. You should see:

```
Hello from PL/SQL
```

IntelliJ may also show a message such as `PL/SQL procedure successfully completed`. If you see the completion message but no output text, check that your cursor was inside the block when you pressed `Ctrl+Enter` and not on a blank line outside it.

---

### Step 1.2 - Variables and Assignment

```sql
DECLARE
    v_customer_count   NUMBER := 0;
    v_message          VARCHAR2(100);
BEGIN
    SELECT COUNT(*)
    INTO   v_customer_count
    FROM   customers;

    v_message := 'Number of customers: ' || v_customer_count;
    DBMS_OUTPUT.PUT_LINE(v_message);
END;
```

Note several things here that differ from C#:

- Variables are declared before `BEGIN` with their type, not inside the executable block.
- Assignment uses `:=` not `=`.
- The `||` operator concatenates strings, equivalent to `+` in C#.
- `SELECT INTO` fetches a single value from the database directly into a variable. It must return exactly one row - not zero, not two.

---

### Step 1.3 - Anchored Types with %TYPE

Rather than hard-coding data types, PL/SQL can anchor a variable to the data type of a table column. If the column definition changes, the variable automatically picks up the new type the next time the block compiles.

```sql
DECLARE
    v_name     customers.full_name%TYPE;
    v_email    customers.email%TYPE;
BEGIN
    SELECT full_name, email
    INTO   v_name, v_email
    FROM   customers
    WHERE  customer_id = 1;

    DBMS_OUTPUT.PUT_LINE('Name:  ' || v_name);
    DBMS_OUTPUT.PUT_LINE('Email: ' || v_email);
END;
```

> **Note:** `%TYPE` is the preferred approach over hard-coding `VARCHAR2(100)`. It keeps your PL/SQL code in sync with the schema automatically and is standard practice in enterprise Oracle development.

Notice that IntelliJ provides code completion inside PL/SQL blocks. After typing `customers.` you should see column names suggested. This works for `%TYPE` anchoring as well.

---

### Step 1.4 - Control Flow

```sql
DECLARE
    v_balance    accounts.balance%TYPE;
    v_status     VARCHAR2(20);
BEGIN
    SELECT balance
    INTO   v_balance
    FROM   accounts
    WHERE  account_id = 1;

    IF v_balance >= 10000 THEN
        v_status := 'HIGH VALUE';
    ELSIF v_balance >= 1000 THEN
        v_status := 'STANDARD';
    ELSE
        v_status := 'LOW BALANCE';
    END IF;

    DBMS_OUTPUT.PUT_LINE('Balance: ' || v_balance || '  Status: ' || v_status);
END;
```

> **Note:** PL/SQL uses `ELSIF` not `ELSEIF`. Every `IF` block must be closed with `END IF;`. If you mistype this, IntelliJ will underline the error and Oracle will report a compilation failure in the output panel.

---

### Step 1.5 - Exception Handling

`SELECT INTO` raises `NO_DATA_FOUND` if the query returns no rows, and `TOO_MANY_ROWS` if it returns more than one. Both are predefined Oracle exceptions.

```sql
DECLARE
    v_name    customers.full_name%TYPE;
BEGIN
    SELECT full_name
    INTO   v_name
    FROM   customers
    WHERE  customer_id = 999;

    DBMS_OUTPUT.PUT_LINE('Found: ' || v_name);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No customer found with that ID.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Unexpected error: ' || SQLERRM);
END;
```

`SQLERRM` returns the error message text for the current exception. `SQLCODE` returns the Oracle error number. Both are available inside any `EXCEPTION` handler.

Run this block. Because customer ID 999 does not exist, the `NO_DATA_FOUND` handler fires and you should see the friendly message in the output panel rather than a raw Oracle error.

> **Note:** `WHEN OTHERS THEN NULL` is a common anti-pattern - it silently swallows errors and makes debugging extremely difficult. Always log or re-raise in a `WHEN OTHERS` handler.

---

### Step 1.6 - Looping Over Query Results

The cursor FOR loop is the preferred way to iterate over a multi-row result set. Oracle handles the OPEN, FETCH, and CLOSE lifecycle automatically, eliminating a class of resource-leak bugs common with explicit cursors.

```sql
BEGIN
    FOR rec IN (
        SELECT c.full_name, a.account_type, a.balance
        FROM   customers c
        JOIN   accounts  a ON a.customer_id = c.customer_id
        ORDER  BY c.full_name, a.account_type
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            rec.full_name || ' | ' ||
            rec.account_type || ' | ' ||
            rec.balance
        );
    END LOOP;
END;
```

The loop variable `rec` is implicitly typed to match the query's column list. You access individual columns using dot notation: `rec.full_name`, `rec.balance`. IntelliJ's code completion will suggest the available field names after you type `rec.`.

---

## Part 2 - Stored Procedures

A stored procedure is a named PL/SQL block compiled and stored permanently in the database as a schema object. Unlike an anonymous block, it can be called by name from application code, other PL/SQL blocks, or the IntelliJ console. It can accept input parameters, produce output parameters, or both.

From a C# perspective, think of a stored procedure as a method that lives in the database rather than in the application tier. The key difference is that it operates on the data without network round-trips for each operation.

### Parameter Modes

Oracle procedures support three parameter modes:

| Mode | Direction | Equivalent in C# |
|------|-----------|-----------------|
| `IN` | Caller to procedure - read only inside the procedure | Regular parameter |
| `OUT` | Procedure to caller - write only inside the procedure | `out` parameter |
| `IN OUT` | Both directions - caller supplies a value the procedure may modify | `ref` parameter |

---

### Step 2.1 - Create a Simple Procedure

Place your cursor inside the following statement and press `Ctrl+Enter` to compile and store the procedure.

```sql
CREATE OR REPLACE PROCEDURE show_customer_summary (
    p_customer_id   IN customers.customer_id%TYPE
) AS
    v_name          customers.full_name%TYPE;
    v_account_count NUMBER;
    v_total_balance NUMBER;
BEGIN
    SELECT full_name
    INTO   v_name
    FROM   customers
    WHERE  customer_id = p_customer_id;

    SELECT COUNT(*), SUM(balance)
    INTO   v_account_count, v_total_balance
    FROM   accounts
    WHERE  customer_id = p_customer_id;

    DBMS_OUTPUT.PUT_LINE('Customer:  ' || v_name);
    DBMS_OUTPUT.PUT_LINE('Accounts:  ' || v_account_count);
    DBMS_OUTPUT.PUT_LINE('Total:     ' || v_total_balance);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Customer ' || p_customer_id || ' not found.');
END show_customer_summary;
```

`CREATE OR REPLACE` is the standard Oracle pattern. If the procedure already exists it is replaced atomically without losing any grants on it. This is safe to run repeatedly as you develop and refine the procedure.

After running, refresh the Database panel by right-clicking the `labuser` connection and choosing **Refresh**. Navigate to **labuser -> Procedures** and confirm `SHOW_CUSTOMER_SUMMARY` appears. If the procedure has a red error icon instead, right-click it and choose **Jump to Source** to see the compilation error highlighted in the editor.

You can also verify the status with a query:

```sql
SELECT object_name, status
FROM   user_objects
WHERE  object_name = 'SHOW_CUSTOMER_SUMMARY';
```

The status should be `VALID`.

---

### Step 2.2 - Call the Procedure

Call the procedure using an anonymous block:

```sql
BEGIN
    show_customer_summary(1);
END;
```

```sql
BEGIN
    show_customer_summary(2);
END;
```

```sql
BEGIN
    show_customer_summary(999);
END;
```

The last call should trigger the `NO_DATA_FOUND` handler and display a friendly message rather than surfacing a raw Oracle error.

---

### Step 2.3 - Create a Procedure with OUT Parameters

This procedure performs a deposit, updating the account balance and returning the new balance to the caller. OUT parameters are how procedures communicate results back to calling code in a production application.

```sql
CREATE OR REPLACE PROCEDURE deposit_funds (
    p_account_id    IN  accounts.account_id%TYPE,
    p_amount        IN  accounts.balance%TYPE,
    p_new_balance   OUT accounts.balance%TYPE,
    p_result_code   OUT VARCHAR2
) AS
    v_current_balance   accounts.balance%TYPE;
BEGIN
    IF p_amount <= 0 THEN
        p_result_code := 'ERR_INVALID_AMOUNT';
        p_new_balance := NULL;
        RETURN;
    END IF;

    SELECT balance
    INTO   v_current_balance
    FROM   accounts
    WHERE  account_id = p_account_id
    FOR UPDATE;

    UPDATE accounts
    SET    balance = balance + p_amount
    WHERE  account_id = p_account_id;

    INSERT INTO transactions (account_id, txn_type, amount, description)
    VALUES (p_account_id, 'CREDIT', p_amount, 'Deposit via procedure');

    SELECT balance
    INTO   p_new_balance
    FROM   accounts
    WHERE  account_id = p_account_id;

    COMMIT;
    p_result_code := 'SUCCESS';

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_result_code := 'ERR_ACCOUNT_NOT_FOUND';
        p_new_balance := NULL;
        ROLLBACK;
    WHEN OTHERS THEN
        p_result_code := 'ERR_UNEXPECTED: ' || SQLERRM;
        p_new_balance := NULL;
        ROLLBACK;
END deposit_funds;
```

Several important patterns are shown here. `FOR UPDATE` locks the row while the transaction is in progress, preventing a concurrent session from reading a stale balance. `RETURN` inside a procedure exits immediately without raising an exception - it handles the invalid amount validation gracefully. The procedure commits when it succeeds and rolls back on any failure.

---

### Step 2.4 - Call the Procedure with OUT Parameters

In IntelliJ, OUT parameters are captured using PL/SQL variables declared inside the calling anonymous block. This is simpler than the bind variable syntax required by SQL\*Plus.

```sql
DECLARE
    v_new_balance   NUMBER;
    v_result        VARCHAR2(50);
BEGIN
    deposit_funds(
        p_account_id  => 1,
        p_amount      => 500.00,
        p_new_balance => v_new_balance,
        p_result_code => v_result
    );
    DBMS_OUTPUT.PUT_LINE('Result:      ' || v_result);
    DBMS_OUTPUT.PUT_LINE('New balance: ' || v_new_balance);
END;
```

The output panel should show `Result: SUCCESS` and the updated balance.

Try calling it with an invalid amount:

```sql
DECLARE
    v_new_balance   NUMBER;
    v_result        VARCHAR2(50);
BEGIN
    deposit_funds(
        p_account_id  => 1,
        p_amount      => -100,
        p_new_balance => v_new_balance,
        p_result_code => v_result
    );
    DBMS_OUTPUT.PUT_LINE('Result: ' || v_result);
END;
```

And with a non-existent account:

```sql
DECLARE
    v_new_balance   NUMBER;
    v_result        VARCHAR2(50);
BEGIN
    deposit_funds(
        p_account_id  => 999,
        p_amount      => 100,
        p_new_balance => v_new_balance,
        p_result_code => v_result
    );
    DBMS_OUTPUT.PUT_LINE('Result: ' || v_result);
END;
```

> **Note:** The `=>` syntax is Oracle's named parameter notation, equivalent to named arguments in C#. It makes calls self-documenting and is the preferred style for procedures with more than two or three parameters.

---

### Step 2.5 - Browse Procedure Source in IntelliJ

In the Database panel, expand **labuser -> Procedures** and double-click `DEPOSIT_FUNDS`. IntelliJ opens the procedure source in a read-only editor tab. This is a convenient way to review any stored procedure without writing a query.

You can also query the source directly:

```sql
SELECT text
FROM   user_source
WHERE  name = 'DEPOSIT_FUNDS'
ORDER  BY line;
```

---

## Part 3 - Triggers

A trigger is a named PL/SQL block that Oracle executes automatically in response to a specific DML event on a table. Unlike a procedure which must be called explicitly, a trigger fires without any action from the calling application.

Common uses in enterprise systems include audit logging, enforcing complex business rules that cannot be expressed as simple constraints, and maintaining derived data.

### Trigger Anatomy

An Oracle trigger definition specifies:

- **Timing** - `BEFORE` or `AFTER` the DML statement executes
- **Event** - `INSERT`, `UPDATE`, `DELETE`, or any combination
- **Scope** - `FOR EACH ROW` (row-level, fires once per affected row) or statement-level (fires once per DML statement)
- **Body** - the PL/SQL block to execute

Inside a row-level trigger, `:NEW` refers to the new version of the row and `:OLD` refers to the old version. For an INSERT, `:OLD` values are NULL. For a DELETE, `:NEW` values are NULL.

---

### Step 3.1 - Create an Audit Log Table

```sql
CREATE TABLE transaction_audit (
    audit_id        NUMBER GENERATED AS IDENTITY PRIMARY KEY,
    account_id      NUMBER          NOT NULL,
    action          VARCHAR2(10)    NOT NULL,
    old_balance     NUMBER(15,2),
    new_balance     NUMBER(15,2),
    changed_by      VARCHAR2(100)   DEFAULT USER NOT NULL,
    changed_at      TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL
);
```

After running, refresh the Database panel and confirm `TRANSACTION_AUDIT` appears under **labuser -> Tables**. Double-click it to open the table editor and verify the columns are correct.

---

### Step 3.2 - Create an Audit Trigger

This trigger fires after any INSERT, UPDATE, or DELETE on the `accounts` table and writes a record to `transaction_audit`.

```sql
CREATE OR REPLACE TRIGGER trg_accounts_audit
AFTER INSERT OR UPDATE OR DELETE ON accounts
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        INSERT INTO transaction_audit (account_id, action, old_balance, new_balance)
        VALUES (:NEW.account_id, 'INSERT', NULL, :NEW.balance);

    ELSIF UPDATING THEN
        INSERT INTO transaction_audit (account_id, action, old_balance, new_balance)
        VALUES (:NEW.account_id, 'UPDATE', :OLD.balance, :NEW.balance);

    ELSIF DELETING THEN
        INSERT INTO transaction_audit (account_id, action, old_balance, new_balance)
        VALUES (:OLD.account_id, 'DELETE', :OLD.balance, NULL);
    END IF;
END trg_accounts_audit;
```

`INSERTING`, `UPDATING`, and `DELETING` are Boolean predicates available inside triggers that identify which DML operation fired the trigger. `USER` is an Oracle function that returns the current database username.

After running, refresh the Database panel and navigate to **labuser -> Triggers** to confirm `TRG_ACCOUNTS_AUDIT` appears with a valid status.

Verify with a query:

```sql
SELECT trigger_name, status
FROM   user_triggers
WHERE  trigger_name = 'TRG_ACCOUNTS_AUDIT';
```

---

### Step 3.3 - Test the Trigger

The trigger fires automatically - you do not call it. Simply perform DML on the `accounts` table.

Run each of the following statements separately using `Ctrl+Enter`:

```sql
UPDATE accounts
SET    balance = balance + 250
WHERE  account_id = 2;
```

```sql
COMMIT;
```

```sql
INSERT INTO accounts (customer_id, account_type, balance)
VALUES (3, 'CHECKING', 1500.00);
```

```sql
COMMIT;
```

Now check the audit table:

```sql
SELECT audit_id, account_id, action, old_balance, new_balance, changed_by, changed_at
FROM   transaction_audit
ORDER  BY audit_id;
```

You should see one row for the UPDATE showing the old and new balances, and one row for the INSERT. The trigger captured both without any change to the calling code.

You can also browse the audit table visually. In the Database panel, double-click `TRANSACTION_AUDIT` to open the table editor and see the rows in a grid.

---

### Step 3.4 - Create a Validation Trigger

Triggers can also enforce business rules that are too complex for a simple CHECK constraint. This trigger prevents a withdrawal from taking an account balance below zero.

```sql
CREATE OR REPLACE TRIGGER trg_no_negative_balance
BEFORE UPDATE OF balance ON accounts
FOR EACH ROW
BEGIN
    IF :NEW.balance < 0 THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Insufficient funds: balance cannot go below zero. ' ||
            'Current balance: ' || :OLD.balance ||
            ', Attempted balance: ' || :NEW.balance
        );
    END IF;
END trg_no_negative_balance;
```

`RAISE_APPLICATION_ERROR` raises a user-defined error with a custom error number and message. Error numbers must be in the range -20000 to -20999, which Oracle reserves for application use. The error propagates to the caller exactly like any Oracle error.

Test it with a withdrawal that would overdraw the account:

```sql
UPDATE accounts
SET    balance = balance - 99999
WHERE  account_id = 1;
```

The output panel should display your custom error message. The `BEFORE` timing means the UPDATE is stopped before it reaches the table - no data changes.

Now try a valid withdrawal:

```sql
UPDATE accounts
SET    balance = balance - 100
WHERE  account_id = 1;
```

```sql
COMMIT;
```

This should succeed. Check the audit table to confirm the audit trigger also fired for this UPDATE:

```sql
SELECT account_id, action, old_balance, new_balance, changed_at
FROM   transaction_audit
ORDER  BY audit_id;
```

---

### Step 3.5 - Review All Triggers in IntelliJ

In the Database panel, expand **labuser -> Triggers**. You should see both triggers listed. Double-click either one to view its source in the editor.

You can also review them with a data dictionary query:

```sql
SELECT trigger_name, trigger_type, triggering_event, status
FROM   user_triggers
ORDER  BY trigger_name;
```

---

## Part 4 - Using IntelliJ's Schema Browser

Now that you have created procedures and triggers, take a few minutes to explore them through the IntelliJ Database panel. This is the equivalent of using SSMS's Object Explorer in the SQL Server world.

### Browsing Compiled Objects

In the Database panel, expand the `labuser` connection and explore the following nodes:

- **Tables** - double-click `TRANSACTION_AUDIT` to open the table editor and see the audit rows in a grid view. You can sort and filter the grid without writing a query.
- **Procedures** - double-click `DEPOSIT_FUNDS` or `SHOW_CUSTOMER_SUMMARY` to view their source. Right-click a procedure and choose **Execute** to run it interactively with a parameter input dialog.
- **Triggers** - double-click `TRG_ACCOUNTS_AUDIT` or `TRG_NO_NEGATIVE_BALANCE` to view their source. Right-click and choose **Disable** or **Enable** to toggle a trigger without dropping it - useful during data migration or bulk loading.

### Executing a Procedure Interactively

Right-click `SHOW_CUSTOMER_SUMMARY` in the Procedures node and choose **Execute**. IntelliJ opens a dialog asking for the value of `p_customer_id`. Enter `1` and click **OK**. IntelliJ wraps the call in an anonymous block, executes it, and displays the output - without you writing any code.

### Viewing Errors on Invalid Objects

If a trigger or procedure has a compilation error, it appears in the schema browser with a warning indicator. Right-click it and choose **Jump to Source** to open the source with the error position highlighted and the error message shown inline.

---

## Challenge Exercises

Complete these independently. No solution is provided. Use the IntelliJ query console for all work.

### Challenge 1 - Anonymous Block

- [ ] Write an anonymous block that loops over all customers and for each one prints their name and the count of their accounts. Use a cursor FOR loop.
- [ ] Extend the block to also print a warning line for any customer who has a total balance below 1000 across all their accounts.
- [ ] Add exception handling so that if any individual customer lookup fails, the block logs the error and continues to the next customer rather than aborting.

### Challenge 2 - Stored Procedure

- [ ] Create a procedure called `withdraw_funds` that mirrors `deposit_funds` but performs a debit. It should reject the withdrawal if the resulting balance would go below zero, returning an appropriate result code rather than relying on the trigger to block it.
- [ ] Call the procedure from an anonymous block, capturing the OUT parameters into local variables and printing the result using `DBMS_OUTPUT.PUT_LINE`.
- [ ] Call the procedure with an amount that would overdraw the account and confirm the result code is returned correctly without the trigger needing to fire.

### Challenge 3 - Triggers

- [ ] Modify `trg_accounts_audit` to also capture the `account_type` column in the audit record. Add the column to `transaction_audit` first, then use `CREATE OR REPLACE TRIGGER` to update the trigger body.
- [ ] Create a new trigger on the `customers` table that prevents the email address from being changed to one that already exists in the table for a different customer. Use `RAISE_APPLICATION_ERROR` with a clear message.
- [ ] Verify your trigger fires correctly by attempting an UPDATE that would create a duplicate email. Confirm the error appears in the IntelliJ output panel and that no data was changed.

---

## Lab Summary

In this lab you:

- Wrote and executed anonymous PL/SQL blocks directly from the IntelliJ query console
- Used `%TYPE` to anchor variable declarations to table column definitions
- Iterated over multi-row query results using cursor FOR loops
- Created stored procedures with `IN` and `OUT` parameters and called them using local variables in anonymous blocks
- Built a row-level audit trigger that fires automatically on INSERT, UPDATE, and DELETE
- Used `RAISE_APPLICATION_ERROR` to enforce business rules from a BEFORE trigger
- Browsed and executed compiled procedures and triggers using IntelliJ's schema browser and interactive Execute dialog

---

