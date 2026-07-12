# Lab 3.0 Part 2 - Challenge Exercise Solutions

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**

This file provides reference solutions for the Challenge Exercises at the end of Lab 3.0 Part 2. Attempt each challenge before consulting these solutions.

---

## Challenge 1 - Query Writing

### 1.1 Each customer's most recent transaction date (outer join)

```sql
SELECT c.full_name,
       MAX(t.txn_date) AS last_txn_date
FROM   customers c
LEFT JOIN accounts     a ON a.customer_id = c.customer_id
LEFT JOIN transactions t ON t.account_id  = a.account_id
GROUP BY c.full_name
ORDER BY c.full_name;
```

**Notes:**

- `LEFT JOIN` (the SQL standard syntax Oracle accepts) ensures customers with no accounts or no transactions still appear in the result. Their `last_txn_date` will be `NULL`.
- The `MAX(t.txn_date)` over a `GROUP BY c.full_name` returns the latest transaction across all accounts a customer owns.
- Oracle also supports the older `(+)` outer-join syntax: `WHERE t.account_id (+) = a.account_id`. Avoid it in new code - the SQL standard `LEFT JOIN` is clearer and portable.

Given the sample data, Bob has no transactions; his row appears with `LAST_TXN_DATE` as null. Carol has one transaction; Alice has two (her most recent is "Rent payment").

### 1.2 Accounts whose balance is above the average

```sql
SELECT account_id, customer_id, account_type, balance
FROM   accounts
WHERE  balance > (SELECT AVG(balance) FROM accounts)
ORDER  BY balance DESC;
```

**Notes:**

- The subquery in the `WHERE` clause is evaluated once and produces a single number (the average balance across all accounts).
- With the sample data, the average is approximately 6,762.63. Accounts above that average are Alice's savings (12,000) and Carol's savings (9,750).
- This pattern (scalar subquery comparing a row's column to an aggregate of the same table) is one of the most common analytical queries you will write. An alternative using window functions is shown below for comparison:

```sql
SELECT account_id, customer_id, account_type, balance
FROM   (
  SELECT a.*, AVG(balance) OVER () AS avg_balance
  FROM   accounts a
)
WHERE  balance > avg_balance
ORDER  BY balance DESC;
```

The window-function version computes the average in a single pass over the table. The subquery version does two scans (one for the average, one to filter). For small tables, the difference is invisible; for large tables, the window function is usually faster.

### 1.3 Top 2 customers by total balance using FETCH FIRST

```sql
SELECT c.full_name, SUM(a.balance) AS total_balance
FROM   customers c
JOIN   accounts  a ON a.customer_id = c.customer_id
GROUP  BY c.full_name
ORDER  BY total_balance DESC
FETCH FIRST 2 ROWS ONLY;
```

**Notes:**

- `FETCH FIRST n ROWS ONLY` is the SQL standard syntax for row limiting, supported by Oracle since 12c. Prefer it over `ROWNUM`.
- The `ORDER BY total_balance DESC` runs **before** `FETCH FIRST` takes its slice, so you get the top 2 by balance, not the first 2 the database happens to find.
- If two customers tie at position 2, you would only see one of them with `FETCH FIRST 2 ROWS ONLY`. To include ties, use `FETCH FIRST 2 ROWS WITH TIES` (and the ORDER BY must be unambiguous - Oracle uses it to decide which rows tie).
- Given the sample data: Alice (16,500.00) and Carol (9,750.00).

---

## Challenge 2 - Schema Changes

### 2.1 Add a phone_number column

```sql
ALTER TABLE customers
  ADD (phone_number VARCHAR2(20));
```

**Notes:**

- Oracle's `ALTER TABLE ... ADD (...)` takes a parenthesised list, even for a single column. The parentheses are required.
- The new column is created as nullable. Existing rows get `NULL` for `phone_number` without rewriting the table.
- If you wanted to add the column as `NOT NULL`, you would need to either supply a `DEFAULT` value or add the column as nullable first, populate it, then `ALTER TABLE ... MODIFY (phone_number NOT NULL)`. Trying to add a `NOT NULL` column with no default to a table that already has rows will fail.

Verify the column was added:

```sql
SELECT column_name, data_type, data_length, nullable
FROM   user_tab_columns
WHERE  table_name = 'CUSTOMERS'
ORDER  BY column_id;
```

`PHONE_NUMBER` should appear at the bottom of the list with `DATA_TYPE = 'VARCHAR2'`, `DATA_LENGTH = 20`, `NULLABLE = 'Y'`.

### 2.2 Add a CHECK constraint requiring amount > 0

```sql
ALTER TABLE transactions
  ADD CONSTRAINT chk_txn_amount_positive
  CHECK (amount > 0);
```

**Notes:**

- Always name your constraints explicitly with a `CONSTRAINT <name>` clause. If you omit the name, Oracle generates one like `SYS_C00012345` that is unstable across environments and confusing in error messages.
- The naming convention used here (`chk_<table>_<purpose>`) is one common pattern. Others include `<table>_<column>_chk`. Pick a convention and use it consistently.
- Oracle validates the constraint against existing rows when you add it. If any existing row has `amount <= 0`, the `ALTER TABLE` fails and the constraint is not added. Your sample data has positive amounts only, so this succeeds. If you needed to add a constraint that existing data violates, you could add it as `NOVALIDATE` to only enforce it on future rows.

Verify the constraint by trying to insert a violating row:

```sql
INSERT INTO transactions (account_id, txn_type, amount, description)
VALUES (1, 'DEBIT', -50.00, 'Should be rejected');
```

Oracle responds with:

```
ORA-02290: check constraint (LABUSER.CHK_TXN_AMOUNT_POSITIVE) violated
```

Roll back the failed insert (it never committed) and move on:

```sql
ROLLBACK;
```

### 2.3 Create an index on transactions.account_id

```sql
CREATE INDEX idx_txn_account_id ON transactions(account_id);
```

**Notes:**

- The naming pattern `idx_<table>_<column>` is one common convention. Some shops prefix indexes with `i_` instead. Stick with whatever your codebase uses.
- The index is a B-tree by default, which is what you want for foreign-key columns like this one. Bitmap indexes are a specialised choice for low-cardinality columns in data warehouse workloads - never use them on transactional tables.
- This index also speeds up the foreign-key parent delete check on `accounts`. Without an index on the child's foreign-key column, deleting an account requires Oracle to full-scan `transactions` to confirm no orphan rows would be created. With the index, that check is a single index probe. Adding indexes to foreign-key columns is a near-universal best practice.

Verify the index was created:

```sql
SELECT index_name, table_name, uniqueness, index_type
FROM   user_indexes
WHERE  table_name = 'TRANSACTIONS';
```

You should see `IDX_TXN_ACCOUNT_ID` along with the implicit indexes Oracle creates for primary keys (`SYS_C...` for the `txn_id` PK).

You can also inspect the index columns:

```sql
SELECT index_name, column_name, column_position
FROM   user_ind_columns
WHERE  table_name = 'TRANSACTIONS'
ORDER  BY index_name, column_position;
```

---

## Challenge 3 - IntelliJ Exploration

### 3.1 Export the three-way join query to CSV

The "three-way join query" refers to query 4 from Step 2.3:

```sql
SELECT c.full_name, t.txn_type, t.amount, t.description, t.txn_date
FROM   transactions t
JOIN   accounts     a ON a.account_id  = t.account_id
JOIN   customers    c ON c.customer_id = a.customer_id;
```

**Steps in IntelliJ:**

1. Run the query in a query console. The results appear in a grid below the editor.
2. Right-click anywhere in the result grid and choose **Export Data**.
3. In the Export Data dialog, set:
   - **Format:** `CSV`
   - **Extractor:** `CSV` (this maps directly to comma-separated output; other choices include `Excel CSV` for Excel-friendly UTF-8 BOM)
   - **Scope:** select either `Whole table` (all rows in the grid) or `Selection` (only highlighted rows)
   - **First row is header:** keep checked so column names appear at the top of the file
4. Click **To File** and choose a destination. The file is written immediately.
5. Open the resulting `.csv` file in a text editor or Excel to confirm the export.

**Things to know:**

- The extractor controls the column delimiter, quote style, and null representation. For Oracle data that includes commas in `VARCHAR2` columns (like descriptions), the default CSV extractor wraps those values in double quotes correctly. The `Excel CSV` variant adds a UTF-8 BOM so Excel detects non-ASCII characters correctly.
- For one-off exports, use **To Clipboard** in the Export Data dialog instead of **To File**. The data is copied as CSV and can be pasted directly into another application.



### 3.2 Explain Plan after adding the index

This challenge ties back to Challenge 2.3. After creating `IDX_TXN_ACCOUNT_ID`, re-run Explain Plan on a query that filters on `transactions.account_id`:

```sql
SELECT t.txn_type, t.amount, t.description, t.txn_date
FROM   transactions t
WHERE  t.account_id = 1;
```

**Steps in IntelliJ:**

1. Type the query in a query console.
2. Highlight the query, then right-click and choose **Explain Plan** (or use the menu **Database -> Explain Plan**).
3. IntelliJ displays the execution plan tree.

**What you might see (and why):**

The answer is *probably* "no, Oracle still chooses a full table scan." This is the right answer for the sample data and worth understanding.

Oracle's cost-based optimizer (CBO) makes index-vs-scan decisions based on **statistics** about table size and data distribution. For your `transactions` table:

- Only 3 rows exist.
- An index scan involves reading the index block, then jumping back to the table block for each matching row.
- A full table scan reads all 3 rows in a single block.

For a table this small, the full table scan is genuinely faster, and the CBO knows it. The index exists and is available, but the optimizer chose not to use it.

**To make the index actually get used,** you can do one of two things:

**Option 1: gather statistics and add more rows.** Oracle won't use the index for tiny tables. Insert several thousand rows, gather statistics, then re-explain:

```sql
-- Insert lots of rows
BEGIN
  FOR i IN 1..5000 LOOP
    INSERT INTO transactions (account_id, txn_type, amount, description)
    VALUES (MOD(i, 4) + 1, CASE WHEN MOD(i,2)=0 THEN 'CREDIT' ELSE 'DEBIT' END,
            i * 1.5, 'Bulk insert ' || i);
  END LOOP;
  COMMIT;
END;
/

-- Gather statistics so the optimizer knows the new size
EXEC DBMS_STATS.GATHER_TABLE_STATS('LABUSER','TRANSACTIONS');

-- Re-run Explain Plan on the same query
```

Now Explain Plan should show `INDEX RANGE SCAN` on `IDX_TXN_ACCOUNT_ID` followed by `TABLE ACCESS BY INDEX ROWID BATCHED` on `TRANSACTIONS`. Selectivity is what changed the optimizer's mind: filtering one of 5000+ rows is much more efficient via an index than a full scan, while filtering one of 3 rows is not.

**Option 2: force the index with a hint.** This is a teaching tool, not a recommendation - hints override the optimizer and should be a last resort in real code:

```sql
SELECT /*+ INDEX(t IDX_TXN_ACCOUNT_ID) */
       t.txn_type, t.amount
FROM   transactions t
WHERE  t.account_id = 1;
```

Even with only 3 rows, the hint forces the index. Run Explain Plan on this version and you will see the index scan. Compare the plan to the unhinted version to see the structural difference.

**The lesson:** indexes are an enabling capability, not a guarantee of use. The optimizer decides whether to use them based on data distribution and statistics. This is why Lab 3.2 (index tuning) spends significant time on `DBMS_STATS` and selectivity, not just on `CREATE INDEX`.

---

*End of Lab 3.0 Part 2 Challenge Solutions*
