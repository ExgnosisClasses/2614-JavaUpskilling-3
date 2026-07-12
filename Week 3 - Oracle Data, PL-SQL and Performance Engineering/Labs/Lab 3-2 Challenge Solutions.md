# Lab 3.2 - Challenge Exercise Solutions

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**
**Module 7 - Indexes, Execution Plans, and Partitioning**

This file provides reference solutions for the Challenge Exercises at the end of Lab 3.2. Attempt each challenge before consulting these solutions. Use the IntelliJ query console connected as `labuser` to `XEPDB1`, with the schema from Parts 1-5 already in place.

---

## Challenge 1 - Index Design

### 1.1 INACTIVE accounts with balance > 5000

**Step 1: check the plan before adding any index.**

```sql
EXPLAIN PLAN FOR
SELECT account_id, customer_id, balance
FROM   pl_accounts
WHERE  status = 'INACTIVE'
AND    balance > 5000;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Expected: `TABLE ACCESS FULL` on `PL_ACCOUNTS`. There are no user-defined indexes on `pl_accounts` at this point in the lab, so Oracle has nothing to use.

**Step 2: design the index.**

```sql
-- Both columns are filter predicates, so a composite index is appropriate.
-- status is an equality predicate, balance is a range predicate.
-- Per the lab's design rule (Step 3.4): equality first, range second.
-- This places matching status values together in the index, and within each
-- status value the entries are sorted by balance so the range scan is tight.
CREATE INDEX idx_acct_status_balance ON pl_accounts (status, balance);
```

**Step 3: re-gather statistics so the optimizer knows the index exists with current cardinality information.**

```sql
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_ACCOUNTS', cascade => TRUE);
END;
```

**Step 4: verify the plan changed.**

```sql
EXPLAIN PLAN FOR
SELECT account_id, customer_id, balance
FROM   pl_accounts
WHERE  status = 'INACTIVE'
AND    balance > 5000;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Expected plan: `INDEX RANGE SCAN` on `IDX_ACCT_STATUS_BALANCE` followed by `TABLE ACCESS BY INDEX ROWID BATCHED` on `PL_ACCOUNTS` (the trip back to the table is needed because `customer_id` is not in the index).

**Why composite over two single-column indexes:**

A single-column index on `status` alone would identify all INACTIVE rows but then require Oracle to fetch every one of them from the table just to check the balance. Roughly 20% of accounts are INACTIVE (one in five per the data load), so that is around 180 row fetches before any balance filtering happens.

A single-column index on `balance` alone would let Oracle find rows above 5000 but then check the status after fetching, with the same kind of waste in the other direction.

The composite index applies both predicates inside the index. Oracle descends to `status = 'INACTIVE'`, then range-scans within that section to find `balance > 5000`, fetching only the rows that match both conditions. For a query that filters on both columns simultaneously, the composite is always cheaper.

If your application also runs queries that filter on `status` alone (without `balance`), the composite index still serves them because `status` is the leading column. A query that filters on `balance` alone would not benefit and would need a separate index.

### 1.2 Function-based index on TRUNC(created_date)

**Step 1: create the regular index first to demonstrate the problem.**

```sql
CREATE INDEX idx_cust_created ON pl_customers (created_date);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_CUSTOMERS', cascade => TRUE);
END;
```

**Step 2: verify the regular index is NOT used.**

```sql
EXPLAIN PLAN FOR
SELECT customer_id, full_name
FROM   pl_customers
WHERE  TRUNC(created_date) = TRUNC(SYSDATE - 30);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Expected: `TABLE ACCESS FULL` on `PL_CUSTOMERS`. The `IDX_CUST_CREATED` index exists but is not in the plan. The reason is the lesson from Step 3.5: applying `TRUNC()` to an indexed column suppresses the index. The index stores raw `DATE` values (including the time component), but the predicate is comparing the truncated (date-only) form. Oracle cannot navigate an index built on raw values when the query filters on a transformed version.

**Step 3: create the function-based index that mirrors the predicate.**

```sql
CREATE INDEX idx_cust_created_trunc ON pl_customers (TRUNC(created_date));

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_CUSTOMERS', cascade => TRUE);
END;
```

**Step 4: re-check the plan.**

```sql
EXPLAIN PLAN FOR
SELECT customer_id, full_name
FROM   pl_customers
WHERE  TRUNC(created_date) = TRUNC(SYSDATE - 30);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Expected: `INDEX RANGE SCAN` on `IDX_CUST_CREATED_TRUNC` followed by `TABLE ACCESS BY INDEX ROWID BATCHED` on `PL_CUSTOMERS`.

The function-based index stores `TRUNC(created_date)` rather than `created_date`, so the predicate matches the index entries directly. The match might still produce zero rows for this specific date (the seed data uses random dates from the past two years and a single specific day may have no rows), but the **plan** shows the index being used. That is what the challenge asks you to verify.

**Note on keeping the regular index:** since this lab also uses date-range queries elsewhere, you may want both `IDX_CUST_CREATED` (for range queries like `created_date >= SYSDATE - 365`) and `IDX_CUST_CREATED_TRUNC` (for `TRUNC()`-style queries). In a real application, drop indexes you do not need - each one adds overhead to inserts and updates - but for this lab, leaving both in place is fine.

### 1.3 Covering index (index-only scan)

The goal is to avoid the `TABLE ACCESS BY INDEX ROWID` step entirely. Oracle can do this when every column the query needs (both in `SELECT` and `WHERE`) is present in the index.

The query selects `txn_id, amount` and filters on `account_id, txn_type, amount`. That gives us four columns total to put in the index: `account_id, txn_type, amount, txn_id`.

```sql
CREATE INDEX idx_txn_covering
    ON pl_transactions (account_id, txn_type, amount, txn_id);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_TRANSACTIONS', cascade => TRUE);
END;
```

**Verify the index-only plan:**

```sql
EXPLAIN PLAN FOR
SELECT txn_id, amount
FROM   pl_transactions
WHERE  account_id = 5
AND    txn_type   = 'DEBIT'
AND    amount     > 1000;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Expected: `INDEX RANGE SCAN` on `IDX_TXN_COVERING` with **no** `TABLE ACCESS BY INDEX ROWID` step above it in the tree. The plan jumps straight from the index scan to whatever consumes the result (a `SELECT STATEMENT` row, typically). This is the signature of a covering index - the index alone holds enough data to satisfy the query, so Oracle never visits the table heap.

**Why this column order:**

- `account_id` (equality) first - narrows the scan to one account's slice of the index
- `txn_type` (equality) second - narrows further to DEBITs within that account
- `amount` (range) third - per the equality-first rule from Step 3.4, range predicates come after equality predicates
- `txn_id` last - included only to make the index "cover" the SELECT list; it does not participate in any predicate

**Why `txn_id` is included even though no predicate uses it:**

Without `txn_id` in the index, Oracle would still do the range scan but then need to go back to the table to fetch `txn_id` for each matching row. Adding `txn_id` to the index makes those table visits unnecessary. The trade-off is that the index becomes slightly larger and more expensive to maintain on inserts and updates, but for a hot read-mostly query this is usually worth it.

**Caution:** covering indexes are powerful but specific. A small change to the SELECT list (asking for `description` too, for example) would force Oracle back to the table because `description` is not in the index. Build covering indexes for known hot queries, not speculatively.

---

## Challenge 2 - Partition Analysis

### 2.1 Query that hits all partitions, and why

```sql
EXPLAIN PLAN FOR
SELECT txn_id, txn_type, amount, txn_date
FROM   pl_transactions_part
WHERE  account_id = 5;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

In the plan output, look at the `Pstart` and `Pstop` columns. They should show:

```
Pstart = 1
Pstop  = KEY (or the highest partition number)
```

Or in some Oracle versions:

```
Pstart = 1
Pstop  = 5    (the count of remaining partitions)
```

**Why this is correct behaviour, not a bug:**

```sql
-- The partition key on pl_transactions_part is txn_date, not account_id.
-- Oracle can only prune partitions when the WHERE clause includes a predicate
-- on the partition key. Account 5's transactions could be in any partition
-- because the random date generator scattered them across the full date range.
-- Without a txn_date predicate, Oracle has no choice but to scan every
-- partition's local index (or every partition if no index existed) to find
-- the matching rows. The fact that the local index is used at each partition
-- keeps the cost reasonable, but partition pruning itself is not possible.
```

**Schema change that would enable pruning:**

You would need to repartition the table by `account_id` (for example, using `PARTITION BY HASH (account_id)` or `PARTITION BY RANGE (account_id)`). With account_id as the partition key, a predicate on account_id would prune to a single partition. The trade-off is that you would lose date-range pruning, which is more useful for most banking workloads. A possible compromise is composite partitioning - `PARTITION BY RANGE (txn_date) SUBPARTITION BY HASH (account_id)` - which would prune on either dimension, at the cost of more partitions to maintain.

In practice, the right answer for this query is usually "the global cost is low enough that we live with it" because account-only queries are typically narrower (one user looking at their own transactions, returning at most a few hundred rows). Reaching for a repartition is only worthwhile if profiling shows account-only queries are a significant share of overall load.

### 2.2 Drop oldest partition while keeping global indexes usable

After Step 5.2 split `p_future`, the partitions are `p_2025`, `p_2026`, `p_2027`, `p_2028`, `p_future`. The oldest remaining is `p_2025`.

```sql
ALTER TABLE pl_transactions_part
    DROP PARTITION p_2025
    UPDATE GLOBAL INDEXES;
```

**Verify the partition is gone:**

```sql
SELECT partition_name, partition_position
FROM   user_tab_partitions
WHERE  table_name = 'PL_TRANSACTIONS_PART'
ORDER  BY partition_position;
```

You should see `p_2026`, `p_2027`, `p_2028`, `p_future` (and no `p_2025`).

**Verify the global index is still USABLE:**

```sql
SELECT index_name, status
FROM   user_indexes
WHERE  index_name = 'IDX_TXNP_AMOUNT_GLOBAL';
```

The status should be `VALID` (or `USABLE` depending on the view used). Compare this to Step 5.3, where the global index became `UNUSABLE` after the partition drop without the `UPDATE GLOBAL INDEXES` clause. The clause tells Oracle to incrementally update the global index as part of the partition drop operation, which adds time to the DDL but leaves the index immediately ready for use.

**The trade-off in production:** `UPDATE GLOBAL INDEXES` makes the partition drop take longer (proportional to the number of rows being dropped, because Oracle has to remove their entries from the global index). For very large partitions during a maintenance window where downtime is acceptable, the faster bare `DROP PARTITION` followed by `REBUILD` of any global indexes is often preferred. For online operations where any unusable index means failed queries, `UPDATE GLOBAL INDEXES` is the safer default.

### 2.3 Compare partition drop to equivalent DELETE

First, get the partition row count history. The current state has `p_2025` already dropped (from challenge 2.2), so query the partitions that remain:

```sql
SELECT partition_name, num_rows
FROM   user_tab_partitions
WHERE  table_name = 'PL_TRANSACTIONS_PART'
ORDER  BY partition_position;
```

And the total:

```sql
SELECT COUNT(*) AS total_remaining_rows
FROM   pl_transactions_part;
```

Or look at the gathered table statistics:

```sql
SELECT num_rows
FROM   user_tables
WHERE  table_name = 'PL_TRANSACTIONS_PART';
```

For a typical run of this lab, the original transaction set was around 50,000 rows split across two years (April 2024 to April 2026, per the data generation in Step 1.5). The `p_2024` partition (dropped in Step 4.4) held roughly the first 8-9 months of that range, so around 35-40% of the total. The `p_2025` partition (dropped in 2.2) held a full year, so another roughly 50%. The exact percentages depend on the random date distribution from your particular run.

**Calculation example** (substitute your actual numbers):

```sql
-- If p_2025 had 24,000 rows and the table originally had 50,000 rows:
-- Percentage = 24000 / 50000 = 48%
SELECT 24000 / 50000 * 100 AS percentage_dropped FROM dual;
```

**Comment comparing to DELETE on a non-partitioned table:**

```sql
-- Dropping a partition is a DDL operation. Oracle removes the segment
-- descriptor from the data dictionary in a single transaction. The data
-- blocks themselves are deallocated, not row-by-row deleted. The operation
-- generates almost no undo (only the dictionary changes) and almost no
-- redo. It completes in milliseconds regardless of how many rows the
-- partition contained.
--
-- An equivalent DELETE on a non-partitioned table to remove the same
-- 24,000 rows would:
--   1. Full-scan the table to find rows matching the date predicate
--   2. Lock each row individually
--   3. Generate undo for every deleted row (so the transaction can be
--      rolled back) - this is significant for 24,000 rows
--   4. Generate redo for every deleted row (so the deletion can be
--      replayed during recovery)
--   5. Leave the table at its original size with empty space inside
--      the data blocks until a future REORG or shrink operation
--   6. Force index maintenance for every deleted row across every
--      index on the table
--
-- A DELETE of 24,000 rows on a 50,000-row table might take 10-30 seconds
-- and generate hundreds of MB of undo and redo. The partition drop takes
-- milliseconds and generates kilobytes. At enterprise scale (millions of
-- rows per partition), the difference becomes hours versus seconds, and
-- is often the only reason a periodic data purge is operationally viable.
```

---

## Challenge 3 - Plan Comparison and Tuning

### 3.1 Improve a full-table-scan query with an appropriate index

The lab has several queries that produce full table scans on `pl_transactions`. The best candidate is the date-only query from Step 3.4 that demonstrated the leading-column rule:

```sql
EXPLAIN PLAN FOR
SELECT COUNT(*) FROM pl_transactions
WHERE  txn_date BETWEEN DATE '2024-06-01' AND DATE '2024-06-30';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

This query was deliberately left unable to use any index in Step 3.4 because `idx_txn_account_date` has `account_id` as its leading column. Capture the `Cost` value from the plan now.

**Create an index with `txn_date` as the leading column:**

```sql
CREATE INDEX idx_txn_date ON pl_transactions (txn_date);

BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('LABUSER', 'PL_TRANSACTIONS', cascade => TRUE);
END;
```

**Re-run the plan:**

```sql
EXPLAIN PLAN FOR
SELECT COUNT(*) FROM pl_transactions
WHERE  txn_date BETWEEN DATE '2024-06-01' AND DATE '2024-06-30';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Expected change: `INDEX RANGE SCAN` on `IDX_TXN_DATE`, often followed by `INDEX FAST FULL SCAN` if the query is just `COUNT(*)` (Oracle can count from the index without visiting the table at all). The cost should drop substantially.

**Document the before/after in a comment:**

```sql
-- Cost before idx_txn_date:  ~145  (TABLE ACCESS FULL on pl_transactions)
-- Cost after  idx_txn_date:  ~5    (INDEX RANGE SCAN on idx_txn_date)
--
-- The query estimated to scan all 50,000 rows is now estimated to read
-- only the small fraction of index entries within the date range.
-- The COUNT(*) does not need any non-indexed columns, so Oracle does
-- not need to touch the table heap at all - the index entries alone
-- provide the row count.
--
-- (Your specific cost numbers will differ depending on your row count
-- and the random data distribution from your lab data load.)
```

**Important note:** the actual cost values vary by environment, table size, and the random data distribution. The point of the comment is the structure - capture the actual `Cost` column values from your plan output before and after. The relative magnitude (large drop) is what matters, not the exact numbers.

### 3.2 Three-table join with name and amount filters

```sql
EXPLAIN PLAN FOR
SELECT c.full_name, a.account_type, t.txn_date, t.amount
FROM   pl_customers      c
JOIN   pl_accounts       a ON a.customer_id = c.customer_id
JOIN   pl_transactions   t ON t.account_id  = a.account_id
WHERE  c.full_name LIKE 'Customer 1%'
AND    t.amount    > 3000;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

**Reading the plan:**

The plan will typically show:

1. `TABLE ACCESS FULL` on `PL_CUSTOMERS` (no index on `full_name`, and a LIKE 'pattern%' predicate is range-scannable but only with a regular B-tree index that does not exist here)
2. `INDEX RANGE SCAN` on `IDX_TXN_AMOUNT` for the `amount > 3000` predicate, with a table fetch back to `PL_TRANSACTIONS`
3. Joins between the three results - likely `HASH JOIN` rather than nested loops because the result sets at each step are not tiny

**Identifying the most expensive operation:**

The most expensive operation is usually the full table scan on `pl_customers` combined with the hash join that follows. The `LIKE 'Customer 1%'` matches a meaningful fraction of customers (around 11% - any customer whose ID starts with 1: 1, 10-19, 100-199). The `amount > 3000` predicate is similarly non-trivial in selectivity (roughly 40% of amounts are above 3000 given the uniform $1-$5000 distribution).

**The reasoning - written as a SQL comment:**

```sql
-- The most expensive single operation in this plan is the hash join that
-- combines pl_customers with pl_accounts, driven by the LIKE 'Customer 1%'
-- predicate on full_name.
--
-- Options considered:
--
-- 1. Add an index on pl_customers(full_name).
--    A regular B-tree index would be usable for LIKE 'Customer 1%' because
--    the wildcard is on the right side of the pattern. However:
--    - 'Customer 1%' matches roughly 11% of the table (Customer 1, 10-19,
--      100-199). That is below the rough 10-20% threshold where Oracle
--      typically switches to a full table scan anyway.
--    - The cost saving on a 500-row table is small in absolute terms.
--    - Names rarely appear in WHERE clauses in real banking applications;
--      customers are usually looked up by customer_id from a session.
--    Decision: not worth adding.
--
-- 2. Rewrite the query.
--    There is no obvious rewrite that helps. The predicates are independent
--    (one on each end of the join chain) and both are non-trivially selective.
--    The optimizer's choice of hash join is appropriate for the row counts
--    involved.
--
-- 3. Accept the current plan.
--    The cost is bounded by the small size of pl_customers (500 rows) and
--    pl_accounts (~900 rows). The expensive part is the table access on
--    pl_transactions, which is already index-supported via idx_txn_amount.
--    Adding indexes on the small tables would not significantly change
--    the wall-clock time and would add maintenance overhead.
--
-- Decision: accept the current plan. The full table scan on pl_customers
-- is the optimizer's correct choice for a table of this size.
--
-- The general lesson: not every full table scan is a problem. On small
-- tables, full scans are often faster than indexed access because they
-- read sequential blocks instead of jumping around. Tune indexes for
-- queries on large tables where selectivity is high; leave small tables
-- alone unless profiling proves otherwise.
```

---

## A Note on Reproducing These Results

Several factors mean your exact plan output and cost numbers will differ from this document:

- The lab data load uses `DBMS_RANDOM` so row counts and value distributions vary per run.
- The optimizer's chosen plan depends on gathered statistics, table block layout, and Oracle version.
- IntelliJ's visual plan output and `DBMS_XPLAN.DISPLAY` show the same plan but format it differently.

Focus on the structural changes (full scan to index scan, table access to index-only) rather than exact cost matching. If your plan shows the predicted operation type after a change, the index is working as intended even if the cost number differs from what is shown here.

---

*End of Lab 3.2 Challenge Solutions*
