# Clustered vs. Nonclustered Indexes and Included Columns in SQL Server

## Practical DBA Guide for Real-Time Performance Tuning

### 1. Introduction

Indexes are one of the most important performance-tuning features in SQL Server.

A well-designed index can reduce:

* Logical reads
* Physical I/O
* CPU consumption
* Query execution time
* Lock duration
* Blocking
* Storage engine work

But indexes are **not free**.

Every additional index can also increase:

* INSERT cost
* UPDATE cost
* DELETE cost
* Storage consumption
* Index maintenance time
* Backup/restore size
* Write workload

Therefore, a DBA should not follow the rule:

> "Create an index whenever a query is slow."

The correct approach is:

> **Understand the query access pattern, determine how SQL Server is accessing the table, and then design the smallest useful index that supports the workload.**

Microsoft describes an index as an on-disk structure associated with a table or view that helps SQL Server locate rows efficiently. Rowstore indexes use a B+ tree structure. ([Microsoft Learn][1])

---

# 2. What Problem Does an Index Solve?

Consider a table containing 20 million customer orders.

```sql
SELECT
    OrderID,
    OrderDate,
    CustomerID,
    OrderTotal
FROM Sales.Orders
WHERE CustomerID = 10525;
```

Without a useful index, SQL Server may need to examine a large portion of the table.

Conceptually:

```text
20 Million Rows
       |
       v
   Table Scan
       |
       v
Find CustomerID = 10525
       |
       v
Return matching rows
```

With an appropriate index:

```text
CustomerID Index
       |
       v
Find 10525
       |
       v
Locate matching rows
       |
       v
Return data
```

The second approach can dramatically reduce I/O when the query is selective.

However, SQL Server's optimizer decides whether an index is actually cheaper than scanning the table. A table scan is not automatically bad; if a query needs a large percentage of the table, scanning can be the better plan. ([Microsoft Learn][1])

---

# 3. Clustered Index

A clustered index determines how the table's data rows are stored according to the clustered key.

Microsoft states that a table can have **only one clustered index**, because the data rows themselves can have only one clustered ordering. ([Microsoft Learn][1])

Example:

```sql
CREATE CLUSTERED INDEX CX_Orders_OrderID
ON Sales.Orders(OrderID);
```

Conceptually:

```text
Clustered Index

OrderID
   |
   +---- 1001
   +---- 1002
   +---- 1003
   +---- 1004
   +---- 1005
```

The leaf level of the clustered index contains the table's data rows.

Therefore:

> **A clustered index is not simply another copy of the table. The clustered index represents the table's rowstore organization.**

---

# 4. Why Can a Table Have Only One Clustered Index?

Suppose we have:

```text
Orders
--------------------------
OrderID
CustomerID
OrderDate
OrderTotal
Status
```

You might want:

```text
OrderID
CustomerID
OrderDate
```

to all be clustered.

But SQL Server cannot physically organize the same rowstore table three different ways simultaneously.

Therefore:

```text
ONE TABLE
   |
   +---- ONE clustered index
```

But you can create multiple nonclustered indexes:

```text
Orders
 |
 +-- Clustered Index
 |
 +-- Nonclustered Index 1
 |
 +-- Nonclustered Index 2
 |
 +-- Nonclustered Index 3
```

---

# 5. Heap vs. Clustered Table

A table without a clustered index is called a **heap**.

```text
Table
 |
 +-- Data pages
 +-- Data pages
 +-- Data pages
```

The rows are not stored according to a clustered index key.

When a clustered index exists:

```text
Clustered Table

Clustered B+ Tree
       |
       v
Data rows stored at leaf level
```

Microsoft explicitly distinguishes a table without a clustered index as a heap and a table with a clustered index as a clustered table. ([Microsoft Learn][1])

### Important DBA point

Do not assume:

> "Every heap is bad."

A heap can be appropriate for certain workloads, especially staging and bulk-load scenarios.

The decision should be workload-driven.

---

# 6. Nonclustered Index

A nonclustered index is a separate structure from the table data.

Example:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Sales.Orders(CustomerID);
```

Conceptually:

```text
Nonclustered Index

CustomerID
    |
    +---- 1001
    +---- 1001
    +---- 1005
    +---- 1010
    +---- 10525
```

The index contains:

* Index key
* Row locator

Microsoft explains that the row locator points to the actual data row. For a heap, it points to the row; for a clustered table, the row locator is the clustered index key. ([Microsoft Learn][1])

---

# 7. The Most Important Difference

| Feature                         | Clustered Index                   | Nonclustered Index      |
| ------------------------------- | --------------------------------- | ----------------------- |
| Number per table                | One                               | Multiple                |
| Stores table data at leaf level | Yes                               | No                      |
| Separate from table data        | Represents table organization     | Yes                     |
| Has key columns                 | Yes                               | Yes                     |
| Has row locator                 | Not in the same sense as NCI      | Yes                     |
| Useful for range access         | Yes                               | Yes                     |
| Can include non-key columns     | No `INCLUDE` concept              | Yes                     |
| Can exist on heap               | Converts table to clustered table | Yes                     |
| Common use                      | Main row organization             | Additional access paths |

---

# 8. Real-Time Scenario #1 — Customer Lookup

Suppose an application frequently executes:

```sql
SELECT *
FROM Sales.Orders
WHERE CustomerID = @CustomerID;
```

A DBA may create:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Sales.Orders(CustomerID);
```

Now SQL Server can use the index to find the relevant customer rows.

But there is an important question:

> Does the query need additional columns that are not in the index?

For example:

```sql
SELECT
    OrderID,
    OrderDate,
    OrderTotal,
    Status
FROM Sales.Orders
WHERE CustomerID = @CustomerID;
```

SQL Server may find the rows through the nonclustered index and then need additional lookups into the clustered table.

This can result in:

```text
Nonclustered Index Seek
        |
        v
Key Lookup
        |
        v
Clustered Index
        |
        v
Retrieve remaining columns
```

For a small number of rows, this can be perfectly acceptable.

For thousands of rows, repeated key lookups can become expensive.

This is where **included columns** become very useful.

---

# 9. Included Columns

Included columns are **non-key columns** added to the leaf level of a nonclustered index.

Example:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Sales.Orders(CustomerID)
INCLUDE
(
    OrderID,
    OrderDate,
    OrderTotal,
    Status
);
```

Now the index contains everything required by the query.

Conceptually:

```text
Index

KEY
CustomerID
     |
     +----------------------+
     |                      |
     v                      v
Included columns        Included columns
OrderID                 OrderDate
OrderTotal              Status
```

The optimizer may now retrieve all required values directly from the index.

Microsoft refers to this as a **covering index** when all columns referenced by the query are available in the index as key or non-key columns. ([Microsoft Learn][2])

---

# 10. Key Column vs. Included Column

This distinction is extremely important for DBAs.

Consider:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Sales.Orders(CustomerID)
INCLUDE
(
    OrderDate,
    OrderTotal,
    Status
);
```

Here:

```text
Key column:
    CustomerID

Included columns:
    OrderDate
    OrderTotal
    Status
```

### Key columns

Key columns are used to:

* Search
* Seek
* Sort
* Navigate the index
* Support predicates and ordering

### Included columns

Included columns primarily exist to:

* Return additional data
* Cover queries
* Avoid Key Lookups

Microsoft specifically recommends keeping columns used for searching and lookup as key columns and putting other columns needed to cover the query into the non-key portion of the index. ([Microsoft Learn][2])

---

# 11. Why Not Put Everything in the Key?

Consider:

```sql
CREATE NONCLUSTERED INDEX IX_Orders
ON Sales.Orders
(
    CustomerID,
    OrderDate,
    OrderTotal,
    Status,
    SalesPersonID,
    RegionID
);
```

This may technically work, but it may not be the best design.

If only `CustomerID` is needed for navigation, the other columns may be better as included columns:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID
ON Sales.Orders(CustomerID)
INCLUDE
(
    OrderDate,
    OrderTotal,
    Status,
    SalesPersonID,
    RegionID
);
```

This keeps the index key narrower.

Microsoft recommends this design approach because included columns are not counted toward the index key column count or index key size limits. ([Microsoft Learn][2])

---

# 12. Key Lookup — A Real Production Problem

Consider:

```sql
SELECT
    OrderID,
    OrderDate,
    OrderTotal
FROM Sales.Orders
WHERE CustomerID = 10525;
```

Suppose the index is:

```sql
CREATE INDEX IX_Orders_CustomerID
ON Sales.Orders(CustomerID);
```

Execution plan might conceptually look like:

```text
Index Seek
    |
    v
CustomerID = 10525
    |
    v
Key Lookup
    |
    v
Clustered Index
    |
    v
Retrieve OrderID
OrderDate
OrderTotal
```

If only 3 rows are returned:

```text
3 Key Lookups
```

Probably fine.

If 500,000 rows are returned:

```text
500,000 Key Lookups
```

Now the lookup operation may become a significant performance problem.

---

# 13. Covering the Query

We can potentially eliminate the lookup:

```sql
CREATE INDEX IX_Orders_CustomerID
ON Sales.Orders(CustomerID)
INCLUDE
(
    OrderID,
    OrderDate,
    OrderTotal
);
```

Now:

```text
Index Seek
    |
    v
CustomerID = 10525
    |
    v
All required columns available
    |
    v
Return result
```

No additional access to the clustered table is required for those columns.

Microsoft specifically states that covering indexes can reduce disk I/O because the optimizer can obtain the required column values directly from the index. ([Microsoft Learn][2])

---

# 14. Real-Time Scenario #2 — Banking Transaction Application

Imagine a banking application executing:

```sql
SELECT
    TransactionID,
    TransactionDate,
    Amount,
    TransactionType,
    Status
FROM Banking.Transactions
WHERE AccountID = @AccountID
ORDER BY TransactionDate DESC;
```

A potential index design could be:

```sql
CREATE INDEX IX_Transactions_AccountID_TransactionDate
ON Banking.Transactions
(
    AccountID,
    TransactionDate DESC
)
INCLUDE
(
    TransactionID,
    Amount,
    TransactionType,
    Status
);
```

Why?

### Search

```text
AccountID
```

is used to locate the customer's transactions.

### Ordering

```text
TransactionDate DESC
```

supports the requested ordering.

### Returned values

```text
TransactionID
Amount
TransactionType
Status
```

are included to cover the query.

This is a practical example of separating:

```text
Search / ordering columns
        ↓
Index key

Output columns
        ↓
INCLUDE
```

---

# 15. Real-Time Scenario #3 — Order Management System

Application query:

```sql
SELECT
    OrderID,
    OrderDate,
    CustomerID,
    OrderTotal
FROM Sales.Orders
WHERE Status = 'OPEN'
AND OrderDate >= '2026-09-01';
```

A possible index:

```sql
CREATE INDEX IX_Orders_Status_OrderDate
ON Sales.Orders
(
    Status,
    OrderDate
)
INCLUDE
(
    OrderID,
    CustomerID,
    OrderTotal
);
```

The optimizer can potentially:

```text
Seek Status
   |
   v
Seek OrderDate range
   |
   v
Read included columns
   |
   v
Return rows
```

But the DBA should still validate the actual execution plan and workload.

Do not blindly assume that this index will always be selected.

---

# 16. Column Order Matters for Key Columns

Consider:

```sql
CREATE INDEX IX_Orders
ON Sales.Orders
(
    CustomerID,
    OrderDate
);
```

The index is organized first by:

```text
CustomerID
```

and then:

```text
OrderDate
```

So this query is a natural candidate:

```sql
WHERE CustomerID = 100
AND OrderDate >= '2026-09-01';
```

But index design should always be based on the actual workload.

A common DBA mistake is to create:

```sql
(CustomerID, OrderDate, Status, RegionID, ...)
```

simply because all those columns appear somewhere in the query.

The question is:

> Which columns actually need to participate in index navigation?

The rest may belong in `INCLUDE`.

---

# 17. Included Column Order Does Not Matter for Query Performance

This is an important Microsoft-documented point.

For example:

```sql
INCLUDE
(
    OrderDate,
    Status,
    OrderTotal
);
```

and:

```sql
INCLUDE
(
    Status,
    OrderTotal,
    OrderDate
);
```

do not provide a key-ordering benefit because these are non-key columns.

Microsoft states that the order of non-key columns in the index definition doesn't affect query performance. ([Microsoft Learn][2])

---

# 18. Included Columns Are Only for Nonclustered Indexes

You cannot do:

```sql
CREATE CLUSTERED INDEX CX_Test
ON dbo.Test(ID)
INCLUDE(Name);
```

The `INCLUDE` mechanism applies to nonclustered indexes.

Microsoft explicitly lists non-key columns as a feature of nonclustered indexes. ([Microsoft Learn][2])

---

# 19. Included Columns Can Be Large

Included columns can be useful because they are not part of the index key.

For example, certain large data types that cannot be index keys may be usable as included columns, subject to SQL Server's documented limitations.

Microsoft states that all data types except `text`, `ntext`, and `image` can be used as non-key columns. ([Microsoft Learn][2])

However, this does **not** mean:

> "Put every large column into INCLUDE."

That can create an extremely wide index.

---

# 20. Wide Indexes Are Dangerous

Consider:

```sql
CREATE INDEX IX_Customer
ON Sales.Customer(CustomerID)
INCLUDE
(
    FirstName,
    LastName,
    Address,
    City,
    State,
    ZIPCode,
    Phone,
    Email,
    Notes,
    Preferences,
    ...
);
```

The query might become faster.

But the index could become very large.

Every insert/update/delete may now require maintenance of this additional structure.

Microsoft specifically warns against very wide nonclustered indexes when the included columns are not a sufficiently narrow subset of the underlying table. ([Microsoft Learn][2])

---

# 21. The DBA Trade-Off

Every index has two sides.

| Read workload         | Write workload         |
| --------------------- | ---------------------- |
| Faster SELECT         | More INSERT work       |
| Faster filtering      | More UPDATE work       |
| Fewer lookups         | More DELETE work       |
| Reduced I/O           | More storage           |
| Potentially lower CPU | More index maintenance |
| Better query response | Larger backups         |

Therefore:

> **Index tuning is a balance between read performance and write overhead.**

---

# 22. Real-Time Scenario #4 — High-Volume OLTP

Imagine:

```text
Transactions per second = 5,000
```

The table receives:

```text
INSERT
UPDATE
DELETE
```

throughout the day.

You discover 20 different query patterns and create 20 indexes.

Queries may become faster.

But now every transaction potentially needs to maintain many index structures.

The result can be:

```text
SELECT performance
       ↑
       |
       |      Good
       |
       +--------------------

Write performance
       |
       ↓
       Can deteriorate
```

This is why production DBAs should avoid creating indexes simply because a missing-index recommendation appears.

---

# 23. Missing Index Recommendations

SQL Server can identify potentially useful indexes through execution plans and missing-index DMVs.

Microsoft notes that when a beneficial index doesn't exist, the optimizer can record a suggestion in execution plans and missing-index dynamic management views. ([Microsoft Learn][1])

But:

> **Missing-index recommendations are suggestions, not production change orders.**

Before implementing one, check:

* Existing indexes
* Similar indexes
* Query frequency
* Query duration
* Logical reads
* Write workload
* Index size
* Maintenance overhead
* Business importance
* Query execution plan

---

# 24. Avoid Duplicate Indexes

Suppose you already have:

```sql
IX_Orders_CustomerID
    CustomerID
```

and someone proposes:

```sql
IX_Orders_CustomerID_2
    CustomerID
    INCLUDE(OrderDate)
```

These aren't necessarily duplicates.

But if you already have:

```sql
IX_Orders_CustomerID
    CustomerID
    INCLUDE(OrderDate, OrderTotal, Status)
```

creating another index on:

```sql
CustomerID
INCLUDE(OrderDate)
```

may be redundant.

Before creating an index:

```text
Check existing indexes
        ↓
Compare key columns
        ↓
Compare included columns
        ↓
Check workload
        ↓
Create only if justified
```

---

# 25. How to Review Existing Indexes

A DBA should regularly inspect index metadata.

Example:

```sql
SELECT
    i.name AS IndexName,
    i.type_desc,
    i.is_unique,
    i.is_primary_key,
    i.is_disabled,
    c.name AS ColumnName,
    ic.key_ordinal,
    ic.is_included_column
FROM sys.indexes AS i
JOIN sys.index_columns AS ic
    ON i.object_id = ic.object_id
   AND i.index_id = ic.index_id
JOIN sys.columns AS c
    ON ic.object_id = c.object_id
   AND ic.column_id = c.column_id
WHERE i.object_id = OBJECT_ID('Sales.Orders')
ORDER BY
    i.index_id,
    ic.key_ordinal,
    ic.index_column_id;
```

Microsoft's `sys.index_columns` documentation provides the metadata needed to identify key and included columns, including the `is_included_column` attribute. ([Microsoft Learn][3])

---

# 26. Execution Plan: What a DBA Should Look For

When investigating an index-related performance problem, look at the actual execution plan.

Common operators include:

```text
Clustered Index Scan
Clustered Index Seek
Index Scan
Index Seek
Key Lookup
RID Lookup
Sort
Table Scan
```

### Good sign

```text
Index Seek
```

can be efficient when the predicate is selective.

### But don't use this rule:

> Seek = always good
> Scan = always bad

That is incorrect.

For example:

```sql
SELECT *
FROM LargeTable;
```

If SQL Server needs almost every row, scanning the table may be more efficient than repeatedly seeking.

Microsoft explicitly notes that a table scan can be the most efficient method when a high percentage of rows is required. ([Microsoft Learn][1])

---

# 27. Key Lookup: When Should You Care?

A Key Lookup isn't automatically a problem.

Ask:

### Question 1

How many rows are being returned?

### Question 2

How many lookup operations are occurring?

### Question 3

How much logical I/O is generated?

### Question 4

Is the query executed frequently?

### Question 5

Would a covering index provide a meaningful benefit?

Example:

```text
10 executions
10 rows each
```

might be fine.

But:

```text
10,000 executions
10,000 rows each
```

could be a serious problem.

---

# 28. Practical Index Design Pattern

A useful mental model is:

```text
WHERE / JOIN / ORDER BY
          |
          v
     KEY COLUMNS

SELECT output columns
          |
          v
    INCLUDE COLUMNS
```

For example:

```sql
SELECT
    OrderID,
    OrderDate,
    Amount,
    Status
FROM Sales.Orders
WHERE CustomerID = @CustomerID
AND OrderDate >= @StartDate;
```

Potential design:

```sql
CREATE INDEX IX_Orders_CustomerID_OrderDate
ON Sales.Orders
(
    CustomerID,
    OrderDate
)
INCLUDE
(
    OrderID,
    Amount,
    Status
);
```

Conceptually:

```text
                Index
                  |
       +----------+----------+
       |                     |
     KEY                  INCLUDE
       |                     |
CustomerID              OrderID
OrderDate               Amount
                        Status
```

---

# 29. Clustered Index Design Considerations

When choosing a clustered key, consider:

* Frequently used access patterns
* Key width
* Stability
* Uniqueness
* Sequential vs random inserts
* Foreign-key relationships
* Range queries
* Partitioning strategy
* Storage requirements

A clustered key also matters because nonclustered indexes on a clustered table use the clustered key as the row locator. ([Microsoft Learn][1])

Therefore:

> **A wide clustered key can indirectly make nonclustered indexes larger.**

This is an important production design consideration.

---

# 30. Real-Time Scenario #5 — GUID Clustered Key

Suppose a table uses:

```sql
CREATE TABLE Sales.Orders
(
    OrderID UNIQUEIDENTIFIER NOT NULL,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2 NOT NULL
);
```

and the DBA creates:

```sql
CREATE CLUSTERED INDEX CX_Orders
ON Sales.Orders(OrderID);
```

If the GUID values are generated randomly, inserts may cause more random page activity compared with a sequentially increasing key.

That doesn't mean:

> "Never use GUIDs."

It means:

> Understand the workload and physical characteristics before selecting a clustered key.

---

# 31. Real-Time Scenario #6 — Reporting Query

Suppose a reporting query runs every five minutes:

```sql
SELECT
    CustomerID,
    SUM(OrderTotal) AS TotalSales
FROM Sales.Orders
WHERE OrderDate >= @StartDate
AND OrderDate < @EndDate
GROUP BY CustomerID;
```

A potential index might be:

```sql
CREATE INDEX IX_Orders_OrderDate
ON Sales.Orders(OrderDate)
INCLUDE
(
    CustomerID,
    OrderTotal
);
```

This may allow SQL Server to locate the relevant date range and retrieve the values needed for aggregation.

But again:

**Measure before and after.**

Do not assume the index will always improve the workload.

---

# 32. Indexes and Updates

Consider:

```sql
UPDATE Sales.Orders
SET Status = 'SHIPPED'
WHERE OrderID = @OrderID;
```

If `Status` exists in several indexes as a key or included column, SQL Server may need to update those indexes.

Therefore, an index that helps:

```sql
SELECT
```

may increase:

```sql
UPDATE
```

cost.

This is especially important in high-volume OLTP systems.

---

# 33. Index Maintenance

Indexes are automatically maintained when table data is modified. ([Microsoft Learn][1])

But that does not mean DBAs should create indexes without considering maintenance.

Production maintenance may include:

* Fragmentation analysis
* Rebuild/reorganize decisions
* Statistics maintenance
* Index usage analysis
* Duplicate index analysis
* Storage analysis

Index maintenance should be based on workload and evidence rather than a generic schedule alone.

---

# 34. A Common DBA Mistake

### Bad approach

```text
Query is slow
      ↓
Missing index warning
      ↓
Create index
      ↓
Problem solved
```

### Better approach

```text
Slow query
    ↓
Capture actual execution plan
    ↓
Check logical reads / CPU / duration
    ↓
Understand predicates and joins
    ↓
Review existing indexes
    ↓
Check missing-index suggestion
    ↓
Design candidate index
    ↓
Evaluate read/write trade-off
    ↓
Test in non-production
    ↓
Measure improvement
    ↓
Deploy through change process
```

This is the production DBA approach.

---

# 35. Clustered vs Nonclustered — Interview View

### Clustered Index

Think:

> **Where/how the table's rowstore data is organized.**

### Nonclustered Index

Think:

> **An additional access path to find rows efficiently.**

### Included Column

Think:

> **Extra data stored in a nonclustered index so the query may not need to go back to the base table/clustered index.**

### Covering Index

Think:

> **The index contains everything required by the query.**

---

# 36. Quick Decision Matrix

| Situation                            | Possible approach                                   |
| ------------------------------------ | --------------------------------------------------- |
| Table needs primary row organization | Clustered index                                     |
| Frequent lookup by another column    | Nonclustered index                                  |
| Query has expensive Key Lookup       | Consider covering index                             |
| Search column                        | Usually index key candidate                         |
| Output-only column                   | Consider `INCLUDE`                                  |
| Large index key                      | Move appropriate columns to `INCLUDE`               |
| Too many indexes                     | Review overlap and write cost                       |
| Very wide index                      | Reconsider included columns                         |
| Query returns most rows              | Scan may be appropriate                             |
| High-volume OLTP                     | Keep indexes focused                                |
| Reporting workload                   | Consider covering/columnstore depending on workload |
| Missing-index suggestion             | Validate before implementing                        |

---

# 37. Practical Production Checklist

Before creating a new nonclustered index, ask:

### Query

* What query is slow?
* How often does it execute?
* How many rows does it return?
* What are the `WHERE` predicates?
* What are the JOIN predicates?
* Is there an `ORDER BY`?
* Which columns are returned?

### Existing indexes

* Does an appropriate index already exist?
* Is there an overlapping index?
* Can an existing index be modified instead?

### Performance

* What are the logical reads?
* What is the CPU time?
* What is the elapsed time?
* Is there a Key Lookup?
* Is the query using a Scan or Seek?
* Is the estimated row count accurate?

### Write impact

* How frequently is the table modified?
* How large will the index become?
* How much additional storage will it consume?
* What will be the INSERT/UPDATE/DELETE overhead?

### Deployment

* Test in non-production.
* Capture before/after metrics.
* Check execution plans.
* Check blocking and CPU impact.
* Follow the production change process.

---

# 38. Golden Rules for SQL Server Index Design

### Rule 1

**Do not create indexes blindly.**

### Rule 2

**Do not treat every table scan as a performance problem.**

### Rule 3

**Keep index keys focused on search, join, and ordering requirements.**

### Rule 4

**Use included columns when you need to cover a query without making the index key unnecessarily wide.**

### Rule 5

**Do not create extremely wide covering indexes without measuring the write and storage cost.**

### Rule 6

**Review existing indexes before creating new ones.**

### Rule 7

**Treat missing-index recommendations as suggestions, not commands.**

### Rule 8

**Always validate with actual execution plans and workload metrics.**

### Rule 9

**Remember that every additional index has a maintenance cost.**

### Rule 10

**Design indexes for the workload, not for a textbook example.**

---

# 39. One-Page Mental Model

Keep this model in mind during production troubleshooting:

```text
                         SQL QUERY
                            |
                            v
                  WHERE / JOIN / ORDER BY
                            |
                            v
                     INDEX KEY
                            |
                +-----------+-----------+
                |                       |
                v                       v
          Find the rows          Sort / range access
                |
                v
        Need additional columns?
                |
          +-----+-----+
          |           |
         NO          YES
          |           |
          v           v
      Covered      Key Lookup
       query          |
          |            v
          |      Clustered index
          |       / heap access
          |            |
          +------------+
                |
                v
             Result
```

The key idea is simple:

> **Keys help SQL Server find and navigate. Included columns help SQL Server return the data without an additional lookup.**

---

# 40. Final DBA Takeaway

Clustered and nonclustered indexes solve different parts of the data-access problem.

A **clustered index** defines the rowstore organization of the table and can exist only once per table. A **nonclustered index** provides an additional access path and can exist multiple times. ([Microsoft Learn][1])

**Included columns** extend nonclustered indexes by storing non-key columns at the leaf level. They are especially useful when you want to create a covering index while keeping the actual index key narrow. ([Microsoft Learn][2])

The production mindset should therefore be:

```text
Understand Query
       ↓
Understand Access Pattern
       ↓
Review Existing Indexes
       ↓
Choose Correct Key Columns
       ↓
Add INCLUDE Columns Only When Useful
       ↓
Evaluate Read vs Write Cost
       ↓
Test
       ↓
Measure
       ↓
Deploy
       ↓
Monitor
```

**The goal is not to have more indexes.
The goal is to have the right indexes for the workload.**

### Microsoft Learn references

[Clustered and nonclustered indexes – Microsoft Learn](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described?view=sql-server-ver17)

[Create indexes with included columns – Microsoft Learn](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-indexes-with-included-columns?view=sql-server-ver17)

[SQL Server Indexes – Microsoft Learn](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/indexes?view=sql-server-ver17)

This is also a good foundation for your **AdventureWorks2025 hands-on lab**: create the indexes, capture the actual execution plan and `STATISTICS IO/TIME`, compare **Key Lookup vs. covering index**, and then measure the write overhead.

[1]: https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described?view=sql-server-ver17 "Clustered and Nonclustered Indexes - SQL Server | Microsoft Learn"
[2]: https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-indexes-with-included-columns?view=sql-server-ver17 "Create Indexes with Included Columns - SQL Server | Microsoft Learn"
[3]: https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-index-columns-transact-sql?view=sql-server-ver17 "sys.index_columns (Transact-SQL) - SQL Server | Microsoft Learn"
