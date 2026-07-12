# Lab 3.1 - Challenge Solutions

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**  
**Instructor Reference | Not for Student Distribution**

---

## Challenge 1 - Anonymous Block

### Requirement

Write an anonymous block that loops over all customers, prints each customer's name and account count, prints a warning for any customer with a total balance below 1000, and handles per-customer errors without aborting the entire loop.

### Solution

The key design decision here is where to place the exception handler. If the `EXCEPTION` block is at the outer level of the anonymous block, any error aborts the entire loop. To handle errors per-customer without stopping execution, a nested `BEGIN...EXCEPTION...END` block is placed inside the loop body. This is a standard PL/SQL pattern for batch processing where individual row failures should be logged rather than causing a full rollback.

```sql
DECLARE
    v_account_count   NUMBER;
    v_total_balance   NUMBER;
BEGIN
    FOR cust IN (
        SELECT customer_id, full_name
        FROM   customers
        ORDER  BY full_name
    ) LOOP
        BEGIN
            SELECT COUNT(*), NVL(SUM(balance), 0)
            INTO   v_account_count, v_total_balance
            FROM   accounts
            WHERE  customer_id = cust.customer_id;

            DBMS_OUTPUT.PUT_LINE(
                'Customer: ' || cust.full_name ||
                '  Accounts: ' || v_account_count ||
                '  Total balance: ' || v_total_balance
            );

            IF v_total_balance < 1000 THEN
                DBMS_OUTPUT.PUT_LINE(
                    '  WARNING: ' || cust.full_name ||
                    ' has a low total balance of ' || v_total_balance
                );
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE(
                    'ERROR processing customer ' || cust.customer_id ||
                    ' (' || cust.full_name || '): ' || SQLERRM
                );
        END;
    END LOOP;
END;
```

**Points to note:**

The outer cursor FOR loop iterates over customers. The inner `BEGIN...EXCEPTION...END` block wraps all processing for a single customer. If anything fails for that customer - a data error, a constraint violation, anything - the `WHEN OTHERS` handler logs the customer ID and error message and then the outer loop continues to the next customer. Without the inner block, an error on any one customer would propagate to the outer `EXCEPTION` section and terminate the loop.

`NVL(SUM(balance), 0)` handles the case where a customer has no accounts at all. `SUM` of an empty set returns `NULL` in Oracle, which would cause the comparison `v_total_balance < 1000` to evaluate to `NULL` rather than `TRUE`, silently skipping the warning. Wrapping it in `NVL` converts the NULL to zero and makes the warning fire correctly for customers with no accounts.

---

## Challenge 2 - Stored Procedure

### Requirement

Create a `withdraw_funds` procedure that mirrors `deposit_funds` but performs a debit. It should reject the withdrawal if the resulting balance would go below zero using its own logic rather than relying on the trigger, and should be called from an anonymous block capturing the OUT parameters.

### Solution - Create the Procedure

```sql
CREATE OR REPLACE PROCEDURE withdraw_funds (
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

    IF v_current_balance - p_amount < 0 THEN
        p_result_code := 'ERR_INSUFFICIENT_FUNDS';
        p_new_balance := v_current_balance;
        ROLLBACK;
        RETURN;
    END IF;

    UPDATE accounts
    SET    balance = balance - p_amount
    WHERE  account_id = p_account_id;

    INSERT INTO transactions (account_id, txn_type, amount, description)
    VALUES (p_account_id, 'DEBIT', p_amount, 'Withdrawal via procedure');

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
END withdraw_funds;
```

### Solution - Successful Withdrawal

```sql
DECLARE
    v_new_balance   NUMBER;
    v_result        VARCHAR2(50);
BEGIN
    withdraw_funds(
        p_account_id  => 1,
        p_amount      => 200.00,
        p_new_balance => v_new_balance,
        p_result_code => v_result
    );
    DBMS_OUTPUT.PUT_LINE('Result:      ' || v_result);
    DBMS_OUTPUT.PUT_LINE('New balance: ' || v_new_balance);
END;
```

Expected output: `Result: SUCCESS` and the balance reduced by 200.

### Solution - Overdraft Attempt

```sql
DECLARE
    v_new_balance   NUMBER;
    v_result        VARCHAR2(50);
BEGIN
    withdraw_funds(
        p_account_id  => 1,
        p_amount      => 99999.00,
        p_new_balance => v_new_balance,
        p_result_code => v_result
    );
    DBMS_OUTPUT.PUT_LINE('Result:          ' || v_result);
    DBMS_OUTPUT.PUT_LINE('Current balance: ' || v_new_balance);
END;
```

Expected output: `Result: ERR_INSUFFICIENT_FUNDS`. The balance is returned unchanged and no transaction record is created.

### Solution - Verify the Transaction Record

```sql
SELECT txn_id, account_id, txn_type, amount, description, txn_date
FROM   transactions
ORDER  BY txn_id DESC;
```

Only the successful withdrawal should appear as a `DEBIT` transaction row. The failed overdraft attempt should leave no transaction record.

**Points to note:**

The balance check `v_current_balance - p_amount < 0` happens after the `SELECT...FOR UPDATE` which locks the row. This is important - the lock must be acquired before reading the balance to prevent a race condition where two concurrent withdrawals both read the same balance, both decide it is sufficient, and both proceed, resulting in a negative balance. Locking first and then checking gives the procedure a consistent view of the balance for the duration of its decision.

The `ROLLBACK` before the `RETURN` in the insufficient funds branch releases the row lock. Without it the lock would be held until the calling session commits or rolls back, which could block other sessions trying to access the same account.

The procedure handles the insufficient funds case with a `RETURN` code rather than `RAISE_APPLICATION_ERROR`. Either approach is valid. Using a return code gives the calling application more control - it can display a user-friendly message or offer alternatives without catching an exception. Using `RAISE_APPLICATION_ERROR` is simpler for callers that just need to know it failed. The important thing is that the team is consistent.

---

## Challenge 3 - Triggers

### Requirement Part A - Add account_type to the audit table and trigger

First add the column to the audit table:

```sql
ALTER TABLE transaction_audit
ADD account_type VARCHAR2(20);
```

Then replace the trigger to populate it. Inside an audit trigger, `:NEW` and `:OLD` give access to all columns of the row that changed, not just the ones that were modified. For an UPDATE the `account_type` is available on both `:OLD` and `:NEW`.

```sql
CREATE OR REPLACE TRIGGER trg_accounts_audit
AFTER INSERT OR UPDATE OR DELETE ON accounts
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        INSERT INTO transaction_audit (
            account_id, action, old_balance, new_balance, account_type
        )
        VALUES (
            :NEW.account_id, 'INSERT', NULL, :NEW.balance, :NEW.account_type
        );

    ELSIF UPDATING THEN
        INSERT INTO transaction_audit (
            account_id, action, old_balance, new_balance, account_type
        )
        VALUES (
            :NEW.account_id, 'UPDATE', :OLD.balance, :NEW.balance, :NEW.account_type
        );

    ELSIF DELETING THEN
        INSERT INTO transaction_audit (
            account_id, action, old_balance, new_balance, account_type
        )
        VALUES (
            :OLD.account_id, 'DELETE', :OLD.balance, NULL, :OLD.account_type
        );
    END IF;
END trg_accounts_audit;
```

Verify the column is being captured:

```sql
UPDATE accounts
SET    balance = balance + 1
WHERE  account_id = 1;

COMMIT;
```

```sql
SELECT audit_id, account_id, action, account_type, old_balance, new_balance
FROM   transaction_audit
ORDER  BY audit_id DESC;
```

The most recent row should show the `account_type` value for account 1.

---

### Requirement Part B - Prevent duplicate email on customers table

```sql
CREATE OR REPLACE TRIGGER trg_customers_unique_email
BEFORE UPDATE OF email ON customers
FOR EACH ROW
DECLARE
    v_existing_count NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO   v_existing_count
    FROM   customers
    WHERE  email       = :NEW.email
    AND    customer_id != :OLD.customer_id;

    IF v_existing_count > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20002,
            'Email address ' || :NEW.email ||
            ' is already in use by another customer.'
        );
    END IF;
END trg_customers_unique_email;
```

**Points to note:**

The `WHERE` clause excludes the row being updated using `customer_id != :OLD.customer_id`. This is essential. Without it, updating any other column on a customer row - their name for example - would trigger the email check, find the customer's own existing email, count it as a duplicate, and reject the update incorrectly.

The trigger fires `BEFORE UPDATE OF email`, which means it only fires when the `email` column is specifically included in the UPDATE statement. Updating `full_name` alone does not fire this trigger at all. This is more efficient than a general `BEFORE UPDATE` which would fire on every update to the table regardless of which columns changed.

The error number `-20002` is used rather than `-20001` which was already taken by the negative balance trigger. Each `RAISE_APPLICATION_ERROR` in an application should use a distinct error number so that callers can handle specific errors by code if needed.

---

### Requirement Part C - Verify the trigger

First check what emails currently exist:

```sql
SELECT customer_id, full_name, email FROM customers;
```

Then attempt to assign an existing email to a different customer:

```sql
UPDATE customers
SET    email = 'alice@example.com'
WHERE  customer_id = 2;
```

The output panel should show the custom error message. Confirm no data changed:

```sql
SELECT customer_id, full_name, email FROM customers;
```

Bob Patel's email should still be `bob@example.com`, not `alice@example.com`.

Confirm that a legitimate email change still works:

```sql
UPDATE customers
SET    email = 'bob.patel@example.com'
WHERE  customer_id = 2;

COMMIT;
```

```sql
SELECT customer_id, full_name, email FROM customers;
```

This should succeed and the new email should be visible.
