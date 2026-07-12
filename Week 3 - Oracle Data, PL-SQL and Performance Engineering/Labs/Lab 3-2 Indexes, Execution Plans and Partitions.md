# Lab 3.2 - Indexes, Execution Plans, and Partitioning

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**  
**Module 7 | Estimated time: 90-105 minutes | Tools: IntelliJ IDEA Ultimate**

---

## Overview

Fast SQL is not accidental. Oracle's query optimizer makes decisions based on the physical structures you provide: indexes, partitions, and statistics. Those decisions are visible in the execution plan. This lab teaches you to read what the optimizer is doing, understand why it made each choice, and change the physical design to steer it toward better plans.

This lab creates its own self-contained schema so there is nothing to carry forward from earlier labs and nothing that can break if earlier steps were done differently. You will build the tables, load realistic data volumes, and then work through a systematic cycle: run a query, read the plan, identify the problem, apply a fix, and measure the improvement.

By the end of this lab you will have:

- Read and interpreted Oracle execution plans using IntelliJ's Explain Plan and the `DBMS_XPLAN` package
- Identified full table scans and understood when they are a problem versus when they are the correct choice
- Created B-tree indexes and observed how they change the optimizer's plan
- Built composite indexes and understood leading-column rules
- Recognised when a function applied to an indexed column suppresses the index
- Used function-based indexes to fix suppressed indexes
- Applied range partitioning to a transactions table and observed partition pruning
- Distinguished between local and global indexes on a partitioned table
- Understood why bitmap indexes are dangerous in OLTP environments

---

## Background - From SQL Server to Oracle Query Tuning

If you have tuned SQL Server queries before, most concepts carry directly across. The terminology differs in a few key places.

| SQL Server Concept | Oracle Equivalent | Key Difference |
|--------------------|-------------------|----------------|
| Execution plan (SSMS graphical) | Explain Plan / `DBMS_XPLAN` | IntelliJ shows a tree view similar to SSMS. `DBMS_XPLAN.DISPLAY` shows text output. |
| Clustered index scan | Full Table Scan | Oracle heap tables have no clustered index. Every table scan reads all blocks. |
| Index seek | Index Range Scan / Index Unique Scan | `UNIQUE SCAN` = single-row lookup. `RANGE SCAN` = one or more rows matching a predicate. |
| Statistics update | `DBMS_STATS.GATHER_TABLE_STATS` | SQL Server auto-updates stats. Oracle requires explicit gathering in most environments. |
| Query hints (`WITH (NOLOCK)`) | Optimizer hints (`/*+ INDEX(t idx_name) */`) | Both are escape hatches. Use them only after exhausting physical design options. |
| Table partitioning | Table partitioning | Oracle's partitioning syntax differs but the pruning concept is identical. |

---

## Part 1 - Build the Lab Schema

This lab uses its own tables prefixed with `pl_`. If you have run this lab before, the cleanup script in Step 1.1 will drop those tables and let you start fresh. If this is your first run, the cleanup block will produce harmless "table does not exist" errors that you can ignore.

### Step 1.1 - Connect and Clean Up

Open an IntelliJ query console connected as `labuser` to `XEPDB1`.

Run this cleanup block to drop any `pl_` tables left over from a previous attempt. Execute it with `Ctrl+Enter`.

```sql
BEGIN
    FOR t IN (
        SELECT table_name FROM user_tables
        WHERE  table_name IN (
            'PL_TRANSACTIONS_PART',
            'PL_TRANSACTIONS',
            'PL_ACCOUNTS',
            'PL_CUSTOMERS'
        )
        ORDER BY table_name
    ) LOOP
        EXECUTE IMMEDIATE
            'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
```

`CASCADE CONSTRAINTS` drops any foreign key constraints that reference the table before dropping the table itself. `PURGE` bypasses the recycle bin so the names are immediately available for reuse.

The block will always complete without errors. If this is your first run, the query inside the loop returns no rows and the loop body never executes. That is correct behaviour.

Confirm the `pl_` tables do not exist before continuing:

```sql
SELECT table_name
FROM   user_tables
WHERE  table_name IN ('PL_CUSTOMERS', 'PL_ACCOUNTS', 'PL_TRANSACTIONS', 'PL_TRANSACTIONS_PART')
ORDER  BY table_name;
```

This query should return no rows on a first run. If you are re-running the lab after a previous attempt, the cleanup block will have dropped them and this query will also return no rows. Either way, no rows means you are clear to proceed.

> **Note:** You may have other tables in your schema from Labs 3.0 and 3.1 such as `CUSTOMERS`, `ACCOUNTS`, `TRANSACTIONS`, and `TRANSACTION_AUDIT`. Those are unrelated to this lab and the cleanup block does not touch them. This lab uses only the `pl_` prefixed tables created in the steps below.

---

### Step 1.2 - Create the Tables

Run each `CREATE TABLE` statement individually with `Ctrl+Enter`. Wait for each to complete before running the next.

```sql
CREATE TABLE pl_customers (
    customer_id   NUMBER         GENERATED AS IDENTITY PRIMARY KEY,
    full_name     VARCHAR2(100)  NOT NULL,
    email         VARCHAR2(150)  UNIQUE NOT NULL,
    status        VARCHAR2(20)   DEFAULT 'ACTIVE' NOT NULL
                                     CONSTRAINT chk_cust_status
                                     CHECK (status IN ('ACTIVE', 'INACTIVE', 'FROZEN')),
    created_date  DATE           DEFAULT SYSDATE NOT NULL
);
```

```sql
CREATE TABLE pl_accounts (
    account_id    NUMBER         GENERATED AS IDENTITY PRIMARY KEY,
    customer_id   NUMBER         NOT NULL,
    account_type  VARCHAR2(20)   NOT NULL
                                     CONSTRAINT chk_acct_type
                                     CHECK (account_type IN ('CHECKING', 'SAVINGS')),
    balance       NUMBER(15,2)   DEFAULT 0 NOT NULL,
    status        VARCHAR2(20)   DEFAULT 'ACTIVE' NOT NULL
                                     CONSTRAINT chk_acct_status
                                     CHECK (status IN ('ACTIVE', 'INACTIVE', 'FROZEN')),
    opened_date   DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_acct_cust FOREIGN KEY (customer_id)
        REFERENCES pl_customers (customer_id)
);
```

```sql
CREATE TABLE pl_transactions (
    txn_id        NUMBER         GENERATED AS IDENTITY PRIMARY KEY,
    account_id    NUMBER         NOT NULL,
    txn_type      VARCHAR2(10)   NOT NULL
                                     CONSTRAINT chk_txn_type
                                     CHECK (txn_type IN ('CREDIT', 'DEBIT')),
    amount        NUMBER(15,2)   NOT NULL
                                     CONSTRAINT chk_txn_amount CHECK (amount > 0),
    txn_date      DATE           DEFAULT TRUNC(SYSDATE) NOT NULL,
    description   VARCHAR2(255),
    CONSTRAINT fk_txn_acct FOREIGN KEY (account_id)
        REFERENCES pl_accounts (account_id)
);
```

Confirm all three tables were created:

```sql
SELECT table_name
FROM   user_tables
WHERE  table_name IN ('PL_CUSTOMERS', 'PL_ACCOUNTS', 'PL_TRANSACTIONS')
ORDER  BY table_name;
```

All three names should appear in the result. If any are missing, re-run the corresponding `CREATE TABLE` statement and check the output panel for errors before continuing.

---

### Step 1.3 - Load Customers

```sql
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO pl_customers (full_name, email, status, created_date)
        VALUES (
            'Customer ' || LPAD(i, 4, '0'),
            'customer' || i || '@banklab.com',
            CASE WHEN MOD(i, 20) = 0 THEN 'INACTIVE' ELSE 'ACTIVE' END,
            TRUNC(SYSDATE - DBMS_RANDOM.VALUE(0, 730))
        );
    END LOOP;
    COMMIT;
END;
```

`DBMS_RANDOM.VALUE(0, 730)` returns a random decimal between 0 and 730. Subtracting it from `SYSDATE` and truncating the result gives a random date within the past two years. This matters later when you test date-range indexes and predicates.

---

### Step 1.4 - Load Accounts

Each customer gets one checking account. Customers whose ID is not divisible by 5 also get a savings account. Every fifth account is marked `INACTIVE` to give the `status` column realistic low cardinality for the bitmap index discussion later in the lab.

```sql
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO pl_accounts (customer_id, account_type, balance, status, opened_date)
        VALUES (
            i,
            'CHECKING',
            ROUND(DBMS_RANDOM.VALUE(100, 50000), 2),
            CASE WHEN MOD(i, 5) = 0 THEN 'INACTIVE' ELSE 'ACTIVE' END,
            TRUNC(SYSDATE - DBMS_RANDOM.VALUE(0, 730))
        );

        IF MOD(i, 5) != 0 THEN
            INSERT INTO pl_accounts (customer_id, account_type, balance, status, opened_date)
            VALUES (
                i,
                'SAVINGS',
                ROUND(DBMS_RANDOM.VALUE(0, 20000), 2),
                'ACTIVE',
                TRUNC(SYSDATE - DBMS_RANDOM.VALUE(0, 730))
            );
        END IF;
    END LOOP;
    COMMIT;
END;
```

---

### Step 1.5 - Load Transactions

This block inserts approximately 50,000 rows spread across the past two years. It will run for 20 to 40 seconds depending on your environment. This is expected.

```sql
BEGIN
    FOR acct IN (SELECT account_id FROM pl_accounts) LOOP
        FOR j IN 1..ROUND(DBMS_RANDOM.VALUE(20, 120)) LOOP
            INSERT INTO pl_transactions (account_id, txn_type, amount, txn_date, description)
            VALUES (
                acct.account_id,
                CASE WHEN MOD(j, 3) = 0 THEN 'DEBIT' ELSE 'CREDIT' END,
                ROUND(DBMS_RANDOM.VALUE(1, 5000), 2),
                TRUNC(SYSDATE - DBMS_RANDOM.VALUE(0, 730)),
                'Transaction ' || j || ' for account ' || acct.account_id
            );
        END LOOP;
    END LOOP;
    COMMIT;
END;
```

Confirm row counts before continuing:

```sql
SELECT 'pl_customers'   AS table_name, COUNT(*) AS row_count FROM pl_customers
UNION ALL
SELECT 'pl_accounts',                  COUNT(*)              FROM pl_accounts
UNION ALL
SELECT 'pl_transactions',              COUNT(*)              FROM pl_transactions;
```

You should see approximately 500 customers, 900 accounts, and between 40,000 and 55,000 transactions. The exact transaction count varies because the number of transactions per account is random. Any total above 30,000 is sufficient for the optimizer to behave as it would in production.

---

### Step 1.6 - Gather Statistics

Oracle's cost-based optimizer makes decisions using statistics about table size, column cardinality, and data distribution. After a bulk load those statistics do not exist and the optimizer is working without accurate information. Gather them now.

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(ownname => 'LABUSER', tabname => 'PL_CUSTOMERS',    cascade => TRUE);
    DBMS_STATS.GATHER_TABLE_STATS(ownname => 'LABUSER', tabname => 'PL_ACCOUNTS',     cascade => TRUE);
    DBMS_STATS.GATHER_TABLE_STATS(ownname => 'LABUSER', tabname => 'PL_TRANSACTIONS', cascade => TRUE);
END;
```

`CASCADE => TRUE` gathers statistics on both the table and all indexes on that table in a single call. You will re-run this after creating each new index so the optimizer always has current information.

Confirm statistics were gathered:

```sql
SELECT table_name, num_rows, last_analyzed
FROM   user_tables
WHERE  table_name IN ('PL_CUSTOMERS', 'PL_ACCOUNTS', 'PL_TRANSACTIONS')
ORDER  BY table_name;
```

`NUM_ROWS` should show realistic counts and `LAST_ANALYZED` should show the current timestamp.

> **Note:** In production, Oracle runs an automated statistics job during the nightly maintenance window. In this lab environment you gather statistics manually after bulk loads and after creating indexes.

---

## Part 2 - Reading Execution Plans

### How Oracle Executes a Query

When you submit a SQL statement, Oracle's optimizer evaluates every reasonable way to satisfy it and assigns a cost to each candidate plan. It selects the plan with the lowest estimated cost and passes it to the execution engine. The execution plan is the record of that decision. Reading it tells you exactly what Oracle decided to do and, equally important, what data volume it estimated at each step.

### Step 2.1 - Explain Plan from IntelliJ

Type the following query into your console. Do not run it with `Ctrl+Enter` yet.

```sql
SELECT t.txn_id, t.amount, t.txn_date, a.account_type
FROM   pl_transactions t
JOIN   pl_accounts     a ON a.account_id = t.account_id
WHERE  t.amount > 4000;
```

Instead of running it, right-click anywhere inside the query text and choose **Explain Plan** from the context menu, or press `Ctrl+Shift+E`. IntelliJ opens a tree-format plan in a new panel.

Look for the following in the plan output:

| Column | What it tells you |
|--------|-------------------|
| Operation | What Oracle is doing at this step: TABLE ACCESS FULL, INDEX RANGE SCAN, HASH JOIN, etc. |
| Object | Which table or index is being accessed |
| Rows (E-Rows) | Oracle's estimated row count coming out of this step |
| Cost | Oracle's internal unit representing estimated I/O and CPU work |

You should see `TABLE ACCESS FULL` for both `PL_TRANSACTIONS` and `PL_ACCOUNTS`. This is expected because neither table has any user-defined indexes yet. The primary key indexes exist but they cannot help a query filtering on `amount`.

---

### Step 2.2 - Explain Plan with DBMS_XPLAN

IntelliJ's tree view is convenient for exploration. `DBMS_XPLAN.DISPLAY` produces the full text output that DBAs use at the command line and in tuning reports. Run the following two statements in sequence, each with `Ctrl+Enter`.

```sql
EXPLAIN PLAN FOR
SELECT t.txn_id, t.amount, t.txn_date, a.account_type
FROM   pl_transactions t
JOIN   pl_accounts     a ON a.account_id = t.account_id
WHERE  t.amount > 4000;
```

```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

The text output includes additional columns beyond what the IntelliJ tree view shows. Most columns are self-explanatory from the header names. Two columns worth knowing about are `Pstart` and `Pstop`, but they will not appear in this plan because `pl_transactions` is not yet a partitioned table. These columns only appear when the accessed table is partitioned, and they show which partitions Oracle read. You will see them in Part 4 once you create the partitioned version of the transactions table.

> **Note for SQL Server developers:** SSMS graphical plans are read from right to left, with the rightmost node running first. Oracle text plans are read from the most-indented line upward. The most-indented operation runs first and feeds its output to the less-indented operation above it. IntelliJ's tree view matches SSMS's reading order and may feel more natural if you are new to Oracle text plans.

---

### Step 2.3 - Understand Full Table Scans

A Full Table Scan reads every block in the table from start to finish. It is not always wrong. For small tables, or for queries that need a large percentage of the rows, it is often the fastest access path. The problem arises when you see it on a large table with a highly selective predicate that should be eliminating most rows.

Run this query and check its plan:

```sql
EXPLAIN PLAN FOR
SELECT txn_id, amount, txn_date
FROM   pl_transactions
WHERE  txn_id = 42;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

`txn_id` is the primary key, so Oracle created a unique index on it automatically when you defined `GENERATED AS IDENTITY PRIMARY KEY`. The plan should show `INDEX UNIQUE SCAN` on the primary key index followed by `TABLE ACCESS BY INDEX ROWID`. This is the standard two-step index access pattern: the index finds the ROWID (the physical address of the row), then Oracle fetches the row from the table using that address.

If you see `TABLE ACCESS FULL` instead, re-gather statistics and re-run the explain plan:

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_TRANSACTIONS', cascade => TRUE);
END;
```

---

## Part 3 - B-tree Indexes

### Step 3.1 - Check Existing Indexes

Before creating any indexes, establish the baseline. Query the data dictionary to see exactly what indexes currently exist on your tables.

```sql
SELECT i.table_name,
       i.index_name,
       i.index_type,
       i.uniqueness,
       ic.column_name,
       ic.column_position
FROM   user_indexes     i
JOIN   user_ind_columns ic ON ic.index_name = i.index_name
WHERE  i.table_name IN ('PL_CUSTOMERS', 'PL_ACCOUNTS', 'PL_TRANSACTIONS')
ORDER  BY i.table_name, i.index_name, ic.column_position;
```

You should see four indexes. Three are on each table's primary key column, created automatically when you defined `GENERATED AS IDENTITY PRIMARY KEY`. The fourth is a unique index on `pl_customers.email`, created automatically by Oracle to enforce the `UNIQUE NOT NULL` constraint defined on that column. Oracle enforces both primary key and unique constraints using indexes, so any column declared `UNIQUE` will have a corresponding index even if you did not create one explicitly. No other indexes exist yet.

---

### Step 3.2 - Index a Foreign Key Column

Foreign key columns are almost always good index candidates. Without an index on `pl_transactions.account_id`, any query that joins transactions to accounts must scan the entire transactions table for every account row it processes.

Capture the plan before adding an index:

```sql
EXPLAIN PLAN FOR
SELECT a.account_id,
       COUNT(t.txn_id)  AS txn_count,
       SUM(t.amount)    AS total_amount
FROM   pl_accounts     a
JOIN   pl_transactions t ON t.account_id = a.account_id
WHERE  a.account_id = 17
GROUP  BY a.account_id;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Note the operation used to access `PL_TRANSACTIONS` and record the total plan cost. Now create the index:

```sql
CREATE INDEX idx_txn_account ON pl_transactions (account_id);
```

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_TRANSACTIONS', cascade => TRUE);
END;
```

Re-run the `EXPLAIN PLAN FOR` block on the same query. Compare the new plan to your notes. You should observe:

- `TABLE ACCESS FULL` on `PL_TRANSACTIONS` is replaced by `INDEX RANGE SCAN` on `IDX_TXN_ACCOUNT` followed by `TABLE ACCESS BY INDEX ROWID`
- The estimated row count at the join step is much lower
- The total plan cost drops significantly

> **Enterprise note:** Unindexed foreign keys are one of the most common performance mistakes in new Oracle schemas. A foreign key on a large child table without a corresponding index will cause full table scans on every join to the parent. They are a standard item on any DBA schema review checklist.

---

### Step 3.3 - Index Selectivity

An index is most valuable when it eliminates a large fraction of rows quickly. If a predicate returns 40% of the table, a full scan is frequently faster than using the index because the index-plus-row-fetch pattern requires many scattered I/O operations, while a full scan reads blocks sequentially.

Create an index on `amount` and observe how the optimizer uses it differently depending on the predicate:

```sql
CREATE INDEX idx_txn_amount ON pl_transactions (amount);
```

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_TRANSACTIONS', cascade => TRUE);
END;
```

```sql
-- Highly selective: very few rows match amounts above 4990
EXPLAIN PLAN FOR
SELECT txn_id, amount, txn_date FROM pl_transactions WHERE amount > 4990;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

```sql
-- Low selectivity: the majority of rows match amounts above 50
EXPLAIN PLAN FOR
SELECT txn_id, amount, txn_date FROM pl_transactions WHERE amount > 50;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

For the first query the optimizer should choose `INDEX RANGE SCAN` because only a tiny fraction of rows qualify. For the second it will likely choose `TABLE ACCESS FULL` because most rows qualify and a full scan is cheaper than thousands of individual row fetches.

This is correct behaviour. The optimizer is not broken when it ignores an available index. It is making the right choice based on estimated row counts from the statistics you gathered.

> **Key insight:** An index is a tool for selective access. The threshold at which Oracle switches from index to full scan is not fixed. It depends on block size, clustering factor, and buffer cache state, but as a working rule, if a predicate matches more than roughly 10 to 20 percent of a table's rows, expect a full scan.

---

### Step 3.4 - Composite Indexes and Leading Column Rules

A composite index covers multiple columns. Its usefulness depends critically on the order in which those columns are listed. Oracle can use the index for any query that filters on a leading prefix of the indexed columns, but not for queries that skip the leading column.

Consider this frequent query pattern in a banking application: find all transactions for a specific account within a date range.

```sql
EXPLAIN PLAN FOR
SELECT txn_id, amount, txn_date, description
FROM   pl_transactions
WHERE  account_id = 17
AND    txn_date BETWEEN DATE '2024-01-01' AND DATE '2024-12-31'
ORDER  BY txn_date;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

The existing `idx_txn_account` index will be used, but Oracle must scan all rows for account 17 and then filter by date after fetching them from the table. Create a composite index that covers both columns:

```sql
CREATE INDEX idx_txn_account_date ON pl_transactions (account_id, txn_date);
```

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_TRANSACTIONS', cascade => TRUE);
END;
```

Re-run the explain plan. Oracle should now use `IDX_TXN_ACCOUNT_DATE` with a tighter range scan, navigating directly to the section of the index for account 17 and scanning only the entries within the date range. Both predicates are applied at the index level rather than after fetching rows from the table.

Now test the leading column rule:

```sql
-- This CAN use the composite index because the leading column is present
EXPLAIN PLAN FOR
SELECT COUNT(*) FROM pl_transactions WHERE account_id = 17;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

```sql
-- This CANNOT use the composite index efficiently because the leading column is absent
EXPLAIN PLAN FOR
SELECT COUNT(*) FROM pl_transactions
WHERE  txn_date BETWEEN DATE '2024-06-01' AND DATE '2024-06-30';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

The second query skips `account_id` and filters only on `txn_date`. Because `account_id` is the leading column in `IDX_TXN_ACCOUNT_DATE`, Oracle cannot use that index efficiently for this predicate. The optimizer will fall back to a full table scan or another available index. To support date-range queries across all accounts, a separate index with `txn_date` as the first column is needed.

> **Design rule:** Put the column you filter on with equality predicates first in a composite index, followed by columns you filter on with range predicates. An index on `(account_id, txn_date)` serves queries filtering on account and date range. A separate index on `(txn_date)` alone serves cross-account date queries. Maintaining both is worthwhile when both query patterns matter to the application.

---

### Step 3.5 - Function-Based Indexes

Applying a function to an indexed column in a WHERE clause prevents the index from being used. Oracle cannot navigate an index built on raw column values when the query filters on a transformed version of those values.

Run this and check the plan:

```sql
EXPLAIN PLAN FOR
SELECT customer_id, full_name, email
FROM   pl_customers
WHERE  UPPER(email) = UPPER('customer42@banklab.com');

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

The plan will show `TABLE ACCESS FULL` even though `email` has a unique index from the `UNIQUE NOT NULL` constraint defined in Step 1.2. The `UPPER()` function applied to the column prevents the index from being used because the index stores raw values, not uppercased values.

The fix is a function-based index that stores the transformed value:

```sql
CREATE INDEX idx_cust_email_upper ON pl_customers (UPPER(email));
```

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_CUSTOMERS', cascade => TRUE);
END;
```

Re-run the explain plan. Oracle should now use `IDX_CUST_EMAIL_UPPER` with an `INDEX RANGE SCAN`. The index stores uppercased values, so the predicate can navigate it directly.

> **Common real-world scenario:** Case-insensitive search on name or email is one of the most frequent function-based index use cases in enterprise applications. Without the function-based index, every case-insensitive search forces a full table scan regardless of how many rows the table contains.

---

## Part 4 - Partitioning

Indexes help Oracle find rows quickly within a table. Partitioning helps Oracle ignore entire segments of the table before reading a single row. For very large tables, partitioning is often the only way to keep time-range queries fast regardless of how well the table is indexed.

### Step 4.1 - Create a Partitioned Transactions Table

You will create a separate partitioned version of the transactions table. This keeps the partition demonstration clean and isolated from the unpartitioned table you have been using in Parts 2 and 3.

```sql
CREATE TABLE pl_transactions_part (
    txn_id        NUMBER         GENERATED AS IDENTITY,
    account_id    NUMBER         NOT NULL,
    txn_type      VARCHAR2(10)   NOT NULL
                                     CONSTRAINT chk_txnp_type
                                     CHECK (txn_type IN ('CREDIT', 'DEBIT')),
    amount        NUMBER(15,2)   NOT NULL
                                     CONSTRAINT chk_txnp_amount CHECK (amount > 0),
    txn_date      DATE           NOT NULL,
    description   VARCHAR2(255),
    CONSTRAINT pk_txnp    PRIMARY KEY (txn_id),
    CONSTRAINT fk_txnp_acct FOREIGN KEY (account_id)
        REFERENCES pl_accounts (account_id)
)
PARTITION BY RANGE (txn_date) (
    PARTITION p_2024    VALUES LESS THAN (DATE '2025-01-01'),
    PARTITION p_2025    VALUES LESS THAN (DATE '2026-01-01'),
    PARTITION p_2026    VALUES LESS THAN (DATE '2027-01-01'),
    PARTITION p_future  VALUES LESS THAN (MAXVALUE)
);
```

The `PARTITION BY RANGE (txn_date)` clause tells Oracle to route each row to a partition based on its `txn_date` value. The `VALUES LESS THAN` boundaries are exclusive upper bounds. A row with `txn_date = 2024-03-15` goes to `p_2024` because `2024-03-15 < 2025-01-01`.

The boundaries cover 2024, 2025, and 2026 because the transaction data was generated as `SYSDATE - DBMS_RANDOM.VALUE(0, 730)`. With today being April 2026, that range produces dates from roughly April 2024 through April 2026. Partitions covering years outside that window would be empty and serve no purpose in this lab.

`MAXVALUE` in the final partition is a catch-all for any row whose date does not fit the explicitly defined ranges. Without it, inserting a row with a date beyond `2026-12-31` would raise `ORA-14400`. Always include a `MAXVALUE` partition on a range-partitioned table.

---

### Step 4.2 - Populate the Partitioned Table

Copy the rows from `pl_transactions` into the partitioned table. The `/*+ APPEND */` hint enables direct-path insert, which bypasses the buffer cache and writes directly to new data blocks. This is significantly faster for bulk loads.

```sql
INSERT /*+ APPEND */ INTO pl_transactions_part
    (account_id, txn_type, amount, txn_date, description)
SELECT account_id, txn_type, amount, txn_date, description
FROM   pl_transactions;

COMMIT;
```

A `COMMIT` is required after a direct-path insert before the table can be queried again.

Gather statistics at both the table and partition level:

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(
        ownname     => 'LABUSER',
        tabname     => 'PL_TRANSACTIONS_PART',
        cascade     => TRUE,
        granularity => 'ALL'
    );
END;
```

`GRANULARITY => 'ALL'` gathers statistics at both the overall table level and at each individual partition. Without partition-level statistics the optimizer cannot accurately estimate how many rows are in each partition and partition pruning will not work reliably.

Verify that rows were distributed across partitions:

```sql
SELECT partition_name,
       num_rows,
       blocks
FROM   user_tab_partitions
WHERE  table_name = 'PL_TRANSACTIONS_PART'
ORDER  BY partition_position;
```

You should see row counts distributed across `p_2024`, `p_2025`, and `p_2026`. `p_2024` will hold transactions from April 2024 through December 2024. `p_2025` will hold all of 2025. `p_2026` will hold January 2026 through today. `p_future` should be empty because no generated dates fall beyond `2026-12-31`. `p_2023` does not exist in this version of the table because no generated dates fall that far back.

---

### Step 4.3 - Observe Partition Pruning

Run a query that filters on the partition key and check the plan:

```sql
EXPLAIN PLAN FOR
SELECT SUM(amount) AS total_credits
FROM   pl_transactions_part
WHERE  txn_type  = 'CREDIT'
AND    txn_date >= DATE '2025-01-01'
AND    txn_date <  DATE '2026-01-01';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

In the plan output, find the row for `PL_TRANSACTIONS_PART` and look at the `Pstart` and `Pstop` columns:

| Pstart | Pstop | Meaning |
|--------|-------|---------|
| 2 | 2 | Only partition 2 (p_2024) was read |
| 1 | 4 | All four partitions were read, no pruning occurred |
| KEY | KEY | Partition is determined at runtime from a bind variable |

A query that reads only `p_2024` is skipping `p_2023`, `p_2025`, and `p_future` entirely. On a table with ten years of data this means reading one-tenth of the data. No index on a non-partitioned table can achieve that level of elimination. An index still points into the full table heap and must traverse that heap to fetch rows. Partition pruning eliminates data at the storage segment level before any block is read.

Now compare with a query that cannot prune:

```sql
EXPLAIN PLAN FOR
SELECT SUM(amount)
FROM   pl_transactions_part
WHERE  txn_type = 'CREDIT';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

`Pstart` and `Pstop` will show all four partitions. Without a predicate on `txn_date`, Oracle must scan every partition because any of them could contain `CREDIT` rows.

> **Key design rule:** The partition key must align with your most critical query predicates. A transactions table almost always filters by date range, making `txn_date` a natural partition key. Partitioning by `account_id` instead would serve queries for a single account's full history but would not help date-range aggregations across all accounts. Choose the key that prunes the most data for the queries that matter most.

---

### Step 4.4 - Partition Lifecycle Management

One of the most operationally valuable benefits of partitioning is the ability to remove old data in a single instantaneous DDL statement. In a non-partitioned table, deleting two years of transactions requires a full scan, generates large amounts of undo log, and can run for hours. On a partitioned table, dropping an entire partition takes milliseconds and generates almost no undo.

Confirm the row count in the 2024 partition before dropping it:

```sql
SELECT COUNT(*) AS rows_in_p2024
FROM   pl_transactions_part PARTITION (p_2024);
```

Drop the partition:

```sql
ALTER TABLE pl_transactions_part DROP PARTITION p_2024;
```

Confirm it is gone and check the remaining partitions:

```sql
SELECT partition_name, num_rows
FROM   user_tab_partitions
WHERE  table_name = 'PL_TRANSACTIONS_PART'
ORDER  BY partition_position;
```

You should now see only `p_2025`, `p_2026`, and `p_future`. Add a dedicated 2027 partition by splitting the catch-all `p_future`:

```sql
ALTER TABLE pl_transactions_part
    SPLIT PARTITION p_future
    AT (DATE '2028-01-01')
    INTO (
        PARTITION p_2027,
        PARTITION p_future
    );
```

Verify the updated partition structure:

```sql
SELECT partition_name, partition_position
FROM   user_tab_partitions
WHERE  table_name = 'PL_TRANSACTIONS_PART'
ORDER  BY partition_position;
```

You should now see `p_2025`, `p_2026`, `p_2027`, and `p_future`. The 2024 data is gone and the table is ready to accept 2027 rows in their own dedicated partition.

> **Enterprise relevance:** In financial services, regulatory requirements often mandate retaining transaction data for seven years and then purging it. With a non-partitioned table this purge is a multi-day DBA project with significant risk. With range partitioning by year it is a single command that runs in seconds with no downtime.

---

## Part 5 - Local vs Global Indexes on Partitioned Tables

When a table is partitioned, indexes can be either local or global. A local index has one index partition per table partition and the two are always kept in alignment. A global index is a single structure spanning all table partitions. The choice has significant consequences for partition maintenance.

### Step 5.1 - Create a Local Index

```sql
CREATE INDEX idx_txnp_account_local ON pl_transactions_part (account_id) LOCAL;
```

Verify that Oracle created one index partition per table partition:

```sql
SELECT index_name, partition_name, status
FROM   user_ind_partitions
WHERE  index_name = 'IDX_TXNP_ACCOUNT_LOCAL'
ORDER  BY partition_position;
```

You should see one row per table partition, each with `STATUS = USABLE`.

---

### Step 5.2 - Observe Local Index Behaviour After Partition Maintenance

Split the `p_future` partition to simulate adding another new year:

```sql
ALTER TABLE pl_transactions_part
    SPLIT PARTITION p_future
    AT (DATE '2029-01-01')
    INTO (
        PARTITION p_2028,
        PARTITION p_future
    );
```

Re-check the local index partitions:

```sql
SELECT index_name, partition_name, status
FROM   user_ind_partitions
WHERE  index_name = 'IDX_TXNP_ACCOUNT_LOCAL'
ORDER  BY partition_position;
```

All existing partitions of the local index remain `USABLE`. A new index partition was automatically created for `p_2027`. The local index stays aligned with the table structure and partition maintenance never invalidates partitions that were not directly affected by the operation.

---

### Step 5.3 - Create a Global Index and Observe the Difference

The local index created in Step 5.1 already covers `account_id`, so Oracle will not allow a second index on the same column. For this demonstration, create the global index on `amount` instead. This is also a realistic example: a global index on `amount` supports cross-partition queries that filter on transaction amount without filtering on the partition key, which is exactly the scenario where a global index adds value over a local one.

```sql
CREATE INDEX idx_txnp_amount_global ON pl_transactions_part (amount) GLOBAL;
```

Drop a partition and observe what happens to the global index:

```sql
ALTER TABLE pl_transactions_part DROP PARTITION p_2025;
```

Check the global index status:

```sql
SELECT index_name, status
FROM   user_indexes
WHERE  index_name = 'IDX_TXNP_AMOUNT_GLOBAL';
```

The status will be `UNUSABLE`. Any query that attempts to use this index will fail with `ORA-01502` until it is rebuilt.

Rebuild it:

```sql
ALTER INDEX idx_txnp_amount_global REBUILD;
```

The partition drop can be made index-safe by including `UPDATE GLOBAL INDEXES` in the DDL. This keeps the global index usable throughout the operation but adds extra work to the partition maintenance step:

```sql
-- For reference only - do not run, the partition was already dropped above
-- ALTER TABLE pl_transactions_part DROP PARTITION p_2025 UPDATE GLOBAL INDEXES;
```

> **Key takeaway:** Use local indexes as the default on partitioned tables. They are maintenance-safe because partition operations on one partition do not affect any other partition's index. Use global indexes only when you need cross-partition uniqueness on a non-partition-key column, or when queries frequently access rows across multiple partitions without filtering on the partition key. When you do use global indexes, always include `UPDATE GLOBAL INDEXES` in your partition DDL or plan for a post-maintenance rebuild.

---


## Part 6 - Why Bitmap Indexes Do Not Belong in OLTP

The module slides explain bitmap indexes and their locking behaviour under concurrent DML. This section reinforces that understanding with a concrete scenario and a data dictionary verification.

### Step 6.1 - Understand the Locking Mechanism

Do not create a bitmap index on any of the lab tables. Read through the following reasoning and then confirm the absence of bitmap indexes with a data dictionary query.

A bitmap index on `pl_accounts.status` would store one bitmap per distinct value:

```
ACTIVE   : 1 1 1 0 1 1 1 0 1 1 ...  (one bit per row, 1 means this row is ACTIVE)
INACTIVE : 0 0 0 1 0 0 0 1 0 0 ...
FROZEN   : 0 0 0 0 0 0 0 0 0 0 ...
```

When Session A updates one row from `ACTIVE` to `INACTIVE`, Oracle must modify both the `ACTIVE` bitmap and the `INACTIVE` bitmap. Because each bitmap covers every row that has that value, Oracle locks the entire bitmap for the duration of the transaction. Session B, even if it is updating a completely different account row, is blocked if that account is `ACTIVE` or `INACTIVE` because it needs to write to the same bitmaps.

In a system with 100 concurrent tellers each processing their own unrelated accounts, every update to account status causes all 99 other tellers to wait. What should be 100 independent parallel operations is serialised into a queue. Throughput collapses under even moderate load.

The rule is absolute: bitmap indexes must never be used on tables that receive concurrent DML in production. The only safe environment for bitmap indexes is a data warehouse where data is loaded in bulk, the bitmap indexes are built after the load completes, and the table is then queried read-only until the next bulk load.

Confirm there are no bitmap indexes on your tables:

```sql
SELECT table_name, index_name, index_type
FROM   user_indexes
WHERE  table_name IN ('PL_CUSTOMERS', 'PL_ACCOUNTS', 'PL_TRANSACTIONS', 'PL_TRANSACTIONS_PART')
AND    index_type = 'BITMAP';
```

This query must return no rows. If you ever see bitmap indexes on OLTP tables during a production schema review, treat it as a defect requiring immediate correction.

---

## Part 7 - Inspecting Indexes and Plans in IntelliJ

### Step 7.1 - Browse Indexes in the Schema Panel

In IntelliJ's Database panel, expand **labuser -> Indexes**. You should see all of the indexes created in this lab. Double-click any index to view its definition, the columns it covers, and whether it is unique. This is the Oracle equivalent of SSMS's Object Explorer for non-clustered indexes.

### Step 7.2 - Use the Visual Explain Plan for a Complex Query

Write this three-table join in a console, highlight it, and press `Ctrl+Shift+E`. IntelliJ renders the plan as a colour-coded tree. Expensive operations on large tables appear in red or orange. Efficient index operations appear in green.

```sql
SELECT c.full_name,
       COUNT(a.account_id)  AS num_accounts,
       SUM(a.balance)       AS total_balance,
       MAX(t.txn_date)      AS last_txn_date
FROM   pl_customers      c
JOIN   pl_accounts       a ON a.customer_id = c.customer_id
JOIN   pl_transactions   t ON t.account_id  = a.account_id
WHERE  c.created_date >= SYSDATE - 365
GROUP  BY c.full_name
ORDER  BY total_balance DESC;
```

This query gives the optimizer several decisions: join order across three tables, join method (hash join vs nested loops), and which indexes to apply at each step. The plan tree makes all of those decisions visible at once. Notice the join method Oracle chose and consider whether the indexes you created earlier in this lab are being used.

---

## Challenge Exercises

Complete these independently. No solution is provided. Use the IntelliJ query console and `DBMS_XPLAN.DISPLAY` for all plan work.

### Challenge 1 - Index Design

- [ ] Write a query that finds all accounts with `status = 'INACTIVE'` and `balance > 5000`. Check the execution plan before adding any index. Create the most appropriate index for this query, re-gather statistics, and confirm the plan changes. Consider whether a composite index on both columns or a single-column index serves this query better and justify your choice in a comment.
- [ ] The query `SELECT customer_id, full_name FROM pl_customers WHERE TRUNC(created_date) = TRUNC(SYSDATE - 30)` will not benefit from a regular B-tree index on `created_date`. Create a regular index on `created_date`, verify with `EXPLAIN PLAN FOR` that it is not used, then create a function-based index that allows the predicate to be index-driven. Verify the plan change.
- [ ] Create an index that allows the query `SELECT txn_id, amount FROM pl_transactions WHERE account_id = 5 AND txn_type = 'DEBIT' AND amount > 1000` to be answered entirely from the index without any table access. Verify in the plan that no `TABLE ACCESS BY INDEX ROWID` step appears above the index scan.

### Challenge 2 - Partition Analysis

- [ ] Write a query against `pl_transactions_part` that filters on `account_id` only, with no predicate on `txn_date`. Use `DBMS_XPLAN.DISPLAY` to confirm that `Pstart` and `Pstop` show all partitions being read. In a SQL comment, explain why this is correct behaviour and not a bug, and describe what schema change would allow this query to prune partitions.
- [ ] Write the DDL to drop the oldest remaining partition from `pl_transactions_part` while keeping all global indexes usable throughout the operation without requiring a separate `REBUILD` step. Run it and verify both that the partition is gone and that the global index remains `USABLE`.
- [ ] Query `user_tab_partitions` and calculate what percentage of total table rows lived in the partition you dropped. Write a comment explaining how this compares to the cost of an equivalent `DELETE` statement on a non-partitioned table of the same size.

### Challenge 3 - Plan Comparison and Tuning

- [ ] Find a query pattern in this lab that currently produces a full table scan on `pl_transactions`. Improve it by creating an appropriate index. Use `EXPLAIN PLAN FOR` and `DBMS_XPLAN.DISPLAY` before and after to document the cost change. Record the before and after `Cost` values in a comment in your SQL file.
- [ ] Write a query joining all three non-partitioned tables that filters on `pl_customers.full_name LIKE 'Customer 1%'` and `pl_transactions.amount > 3000`. Check the plan. Identify the most expensive operation and decide whether creating an additional index, rewriting the query, or accepting the current plan is the right response. Write your reasoning as a SQL comment.

---

## Lab Summary

In this lab you:

- Created a self-contained lab schema with three related tables and loaded a realistic dataset of approximately 50,000 transaction rows
- Gathered table and index statistics using `DBMS_STATS` so the optimizer had accurate information throughout the lab
- Read Oracle execution plans using IntelliJ's visual explain plan and `DBMS_XPLAN.DISPLAY`, identifying full table scans, index range scans, unique scans, and hash joins
- Created B-tree indexes on a foreign key column and a selective predicate column, and observed the resulting plan changes
- Built a composite index on `(account_id, txn_date)` and verified Oracle's leading-column rule by testing queries that use and skip the leading column
- Fixed a function-suppressed index by creating a function-based index and confirmed the optimizer began using it
- Created a range-partitioned transactions table, loaded data into it, and observed partition pruning in the `Pstart` and `Pstop` columns of the execution plan
- Managed partition lifecycle by dropping old partitions and splitting the catch-all partition to add new named ranges
- Compared local and global index behaviour after partition maintenance, observing that local indexes remain usable while a global index becomes unusable without `UPDATE GLOBAL INDEXES`
- Confirmed that no bitmap indexes exist on any OLTP table and understood the locking mechanism that makes them dangerous under concurrent write load

---
