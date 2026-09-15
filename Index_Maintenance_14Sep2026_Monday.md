Microsoft’s current guidance emphasizes that **page density can matter as much as or more than fragmentation**, and recommends measuring the actual workload impact before automatically rebuilding indexes. ([Microsoft Learn][1])

[Microsoft Learn — Optimize index maintenance to improve query performance and reduce resource consumption](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/reorganize-and-rebuild-indexes?view=sql-server-ver17)

# SQL Server Index Maintenance

## Reorganize vs Rebuild — Production DBA Technical Guide

### Purpose

Index maintenance is one of the most common responsibilities of a SQL Server DBA.

However, a production DBA should not follow a simple rule such as:

> “If fragmentation is greater than 30%, rebuild the index.”

That approach is too simplistic for modern SQL Server environments.

A better approach is:

**Measure → Analyze → Determine impact → Choose maintenance method → Execute safely → Validate**

The goal is not to achieve **0% fragmentation**.

The goal is to maintain acceptable:

* Query performance
* Page density
* I/O efficiency
* Memory usage
* CPU utilization
* Storage utilization
* Statistics quality
* Application availability

Microsoft's current guidance specifically recommends considering both **fragmentation and page density**, and measuring the actual performance benefit of index maintenance.

---

# 1. What Is an Index?

An index is a database structure that helps SQL Server locate rows efficiently.

Without an appropriate index, SQL Server may need to scan many or all pages of a table.

For example:

```sql
SELECT *
FROM Sales.SalesOrderHeader
WHERE CustomerID = 11000;
```

If CustomerID is not appropriately indexed, SQL Server may perform a table or clustered-index scan.

With an appropriate nonclustered index:

```sql
CREATE INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader(CustomerID);
```

SQL Server can potentially locate the required rows much more efficiently.

---

# 2. Why Do Indexes Become Fragmented?

SQL Server indexes are continuously modified as data changes.

Typical operations include:

* INSERT
* UPDATE
* DELETE

Over time, these changes can cause index pages to become physically out of order.

For rowstore indexes, Microsoft describes fragmentation as a condition where the logical ordering of index pages does not match their physical ordering.

---

# 3. What Is a Page Split?

A page can hold only a limited amount of data.

Suppose a page is nearly full:

```text
Page 100
+--------------------------------+
| Row 1 | Row 2 | Row 3 | Row 4 |
+--------------------------------+
```

Now SQL Server needs to insert a row that belongs in the middle of the page.

If sufficient free space is unavailable, SQL Server can perform a page split.

Conceptually:

```text
Before:

Page 100
+------------------------+
| 1 | 2 | 3 | 4 | 5 | 6 |
+------------------------+

After:

Page 100                 Page 250
+---------------+        +---------------+
| 1 | 2 | 3     |        | 4 | 5 | 6     |
+---------------+        +---------------+
```

The operation creates additional pages and can reduce page density.

Frequent page splits can therefore contribute to:

* Fragmentation
* Lower page density
* Additional I/O
* Additional storage consumption
* Increased write activity

---

# 4. Fragmentation vs Page Density

This is one of the most important concepts in modern SQL Server index maintenance.

## Fragmentation

Fragmentation primarily describes the logical ordering of pages.

Example:

```text
Logical order:

Page 10 → Page 11 → Page 12 → Page 13

Physical order:

Page 10 → Page 25 → Page 7 → Page 40
```

The index may be logically fragmented.

---

# 5. Page Density

Page density describes how much data is stored on each page.

Example:

```text
100% density:

+---------------------------+
| DATA DATA DATA DATA DATA |
+---------------------------+

50% density:

+---------------------------+
| DATA DATA       |         |
+---------------------------+
```

If the same amount of data is stored across more pages, SQL Server has to read more pages.

That can increase:

* I/O
* Memory pressure
* Buffer pool usage
* Query cost
* Storage requirements

Microsoft specifically notes that improving page density can have a greater performance impact than reducing fragmentation in many workloads.

---

# 6. Important DBA Rule

Do NOT automatically assume:

```text
High fragmentation = bad performance
```

Instead think:

```text
Fragmentation
      +
Page Density
      +
Index Size
      +
Access Pattern
      +
Query Workload
      +
I/O Characteristics
      +
Statistics
      =
Maintenance Decision
```

---

# 7. How to Measure Index Fragmentation

The primary DMV used for rowstore index physical information is:

```sql
sys.dm_db_index_physical_stats
```

A practical query:

```sql
SELECT
    DB_NAME(database_id) AS DatabaseName,
    OBJECT_SCHEMA_NAME(object_id, database_id) AS SchemaName,
    OBJECT_NAME(object_id, database_id) AS TableName,
    index_id,
    index_type_desc,
    avg_fragmentation_in_percent,
    avg_page_space_used_in_percent,
    page_count
FROM sys.dm_db_index_physical_stats
(
    DB_ID(),
    NULL,
    NULL,
    NULL,
    'LIMITED'
)
WHERE index_id > 0
ORDER BY avg_fragmentation_in_percent DESC;
```

Important columns:

| Column                           | Meaning                      |
| -------------------------------- | ---------------------------- |
| `avg_fragmentation_in_percent`   | Logical fragmentation        |
| `avg_page_space_used_in_percent` | Average page density         |
| `page_count`                     | Number of pages in the index |
| `index_type_desc`                | Type of index                |

---

# 8. Why Page Count Matters

Consider two indexes.

### Index A

```text
Fragmentation = 70%
Pages = 80
```

### Index B

```text
Fragmentation = 70%
Pages = 8,000,000
```

Both show 70% fragmentation.

But the operational impact is completely different.

Rebuilding an 8-million-page index may require:

* Significant I/O
* CPU
* Memory
* Transaction log space
* Temporary workspace
* Additional storage
* Potential blocking
* Significant execution time

Therefore:

**Do not make an index maintenance decision using fragmentation percentage alone.**

---

# 9. LIMITED vs SAMPLED vs DETAILED

`sys.dm_db_index_physical_stats` supports different scan modes.

## LIMITED

Usually the fastest option.

Good for:

* Routine health checks
* Large environments
* Regular monitoring

Example:

```sql
sys.dm_db_index_physical_stats
(
    DB_ID(),
    NULL,
    NULL,
    NULL,
    'LIMITED'
)
```

---

## SAMPLED

Uses sampling when appropriate.

```sql
'SAMPLED'
```

Useful when more information is required without the full cost of a detailed scan.

---

## DETAILED

Scans all pages.

```sql
'DETAILED'
```

Provides more detailed information but can consume significantly more resources.

For large production databases, do not casually run `DETAILED` against everything during business hours.

---

# 10. What Is Index REORGANIZE?

Syntax:

```sql
ALTER INDEX IndexName
ON SchemaName.TableName
REORGANIZE;
```

Example:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REORGANIZE;
```

Reorganize is an online operation.

This means normal queries and updates can generally continue while the operation runs.

For rowstore indexes, reorganize works primarily at the leaf level.

---

# 11. Advantages of REORGANIZE

| Advantage                | Explanation                                             |
| ------------------------ | ------------------------------------------------------- |
| Online                   | Designed to run without long-term object-level blocking |
| Lower resource usage     | Generally lighter than rebuild                          |
| Incremental              | Can make progress over time                             |
| Interruptible            | Progress is persisted if interrupted                    |
| Useful for large indexes | Can be less disruptive                                  |

Microsoft recommends reorganize as the preferred method when there is no specific reason to rebuild.

---

# 12. Disadvantages of REORGANIZE

Reorganize is not always the best solution.

Potential disadvantages:

* Can take a long time on very large indexes
* Uses CPU and I/O
* Does not update index statistics
* Does not perform the full physical rebuild
* May not be sufficient for certain maintenance requirements

The statistics point is especially important.

```text
REORGANIZE
    ↓
Index organization changes
    ↓
Statistics are NOT automatically updated
```

---

# 13. What Is Index REBUILD?

A rebuild essentially drops and recreates the index.

Example:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD;
```

A rebuild can be performed offline or online depending on the index, SQL Server version, edition/features, and selected options.

---

# 14. What Happens During a REBUILD?

Conceptually:

```text
Existing Index
      |
      v
Read Existing Structure
      |
      v
Build New Index
      |
      v
Replace Existing Structure
```

For rowstore indexes, rebuild removes fragmentation throughout the index and compacts pages according to the applicable fill factor.

---

# 15. Rebuild and Statistics

This is one of the major differences between rebuild and reorganize.

For a rowstore index rebuild, SQL Server updates the statistics associated with the index as part of the rebuild process.

Microsoft describes this as equivalent to a full scan for the index statistics in the normal non-partitioned, non-resumable case.

By contrast:

```text
REBUILD
→ Index maintenance
→ Index statistics updated

REORGANIZE
→ Index maintenance
→ Index statistics NOT updated
```

This is why an apparent performance improvement after a rebuild is not necessarily caused only by reduced fragmentation.

It may also be caused by improved statistics.

---

# 16. REBUILD vs REORGANIZE

| Feature                  | REORGANIZE               | REBUILD                              |
| ------------------------ | ------------------------ | ------------------------------------ |
| Online                   | Yes                      | Depends on operation/options         |
| Resource usage           | Lower                    | Higher                               |
| Removes fragmentation    | Yes                      | Yes                                  |
| Page compaction          | Yes                      | Yes                                  |
| Updates index statistics | No                       | Yes                                  |
| Rebuilds entire index    | No                       | Yes                                  |
| Can be resumable         | Not applicable           | Yes, where supported                 |
| Blocking risk            | Lower                    | Higher for offline                   |
| Transaction log impact   | Generally lower          | Can be significant                   |
| Duration                 | Can be long              | Can be faster but resource-intensive |
| Best use                 | Lower-impact maintenance | More complete maintenance            |

---

# 17. Online Rebuild

Example:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD
WITH
(
    ONLINE = ON
);
```

Online rebuild reduces blocking compared with an offline rebuild.

However, online does NOT mean:

```text
ZERO blocking
```

There can still be a short period where SQL Server needs appropriate locks to complete the operation.

Therefore, DBAs should still plan online rebuilds carefully.

---

# 18. Online Rebuild Has a Cost

During an online rebuild, modifications to indexed data may need to maintain an additional copy of the index.

Therefore:

```text
Online Rebuild
      |
      +-- Less blocking
      |
      +-- More concurrency
      |
      +-- Additional resource overhead
```

Do not assume online operations are free.

---

# 19. Resumable Index Rebuild

For supported scenarios, SQL Server can perform resumable index rebuilds.

Example:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD
WITH
(
    ONLINE = ON,
    RESUMABLE = ON
);
```

The major benefit is that the DBA can pause and resume the operation.

For example:

```text
11:00 PM
   |
   v
Start rebuild
   |
   v
1:00 AM
   |
   v
Production workload increasing
   |
   v
PAUSE
   |
   v
Next maintenance window
   |
   v
RESUME
```

This can be extremely useful for very large production indexes.

---

# 20. Example: Pause a Resumable Rebuild

A resumable rebuild can be paused using the appropriate `ALTER INDEX` syntax.

Conceptually:

```text
Rebuild
  ↓
Running
  ↓
Pause
  ↓
Workload continues
  ↓
Resume later
```

The important operational advantage is that completed work is retained.

---

# 21. A Real Production Scenario

Suppose:

```text
Database: SalesDB
Table: SalesOrder
Rows: 500 million
Index: IX_SalesOrder_CustomerID
Size: 250 GB
Fragmentation: 65%
Page Density: 72%
```

A junior DBA might immediately say:

> Rebuild it.

A senior DBA should ask:

1. Is this index heavily used?
2. Are queries actually slow?
3. Is the workload doing range scans?
4. Is low page density causing excessive I/O?
5. Is the index large enough for fragmentation to matter?
6. Is there enough free disk space?
7. Is there enough transaction log capacity?
8. Is `ONLINE = ON` available?
9. Is the application currently busy?
10. Will the rebuild fit into the maintenance window?
11. Would statistics update solve the actual problem?
12. Can Query Store prove that the index maintenance improves performance?

That is the difference between executing maintenance and performing database engineering.

---

# 22. Production Decision Matrix

A practical decision process can look like this:

| Condition                                              | Possible Action                          |
| ------------------------------------------------------ | ---------------------------------------- |
| Small index                                            | Often leave it alone                     |
| Low fragmentation                                      | Usually no action                        |
| Moderate fragmentation + acceptable performance        | Monitor                                  |
| Moderate fragmentation + performance issue             | Investigate workload                     |
| High fragmentation + large index + scan-heavy workload | Consider REORGANIZE/REBUILD              |
| High fragmentation + low page density                  | Maintenance may be beneficial            |
| Statistics are stale                                   | Consider UPDATE STATISTICS               |
| Business-critical large index                          | Consider ONLINE/RESUMABLE rebuild        |
| Maintenance window is limited                          | Consider REORGANIZE or RESUMABLE REBUILD |
| Index rarely used                                      | Avoid unnecessary maintenance            |
| Fragmentation high but no measurable impact            | Don't automatically rebuild              |

---

# 23. Do Not Use the Old 5% / 30% Rule Blindly

A commonly seen maintenance script uses:

```text
< 5%      → Nothing
5–30%     → REORGANIZE
> 30%     → REBUILD
```

This is widely used in older maintenance approaches.

However, these thresholds should not be treated as universal Microsoft rules.

Modern SQL Server index maintenance should consider:

* Fragmentation
* Page density
* Page count
* Query workload
* Index usage
* I/O characteristics
* Statistics
* Maintenance cost

Therefore:

```text
Fragmentation threshold
        ≠
Automatic maintenance decision
```

---

# 24. Page Density Can Be More Important

Consider:

```text
Index A
Fragmentation = 20%
Page density = 95%
```

and:

```text
Index B
Fragmentation = 5%
Page density = 55%
```

Index B may actually require more pages to read because its pages are much less dense.

Therefore, a DBA should inspect:

```sql
avg_fragmentation_in_percent
```

AND:

```sql
avg_page_space_used_in_percent
```

---

# 25. Fill Factor

Fill factor controls how full index pages are when an index is created or rebuilt.

Example:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD
WITH
(
    FILLFACTOR = 90
);
```

Conceptually:

```text
FILLFACTOR 100

Page:
[████████████████████]

FILLFACTOR 90

Page:
[██████████████████░░]
```

The idea is to leave space for future inserts.

---

# 26. Should Every Index Use FILLFACTOR 80?

No.

Do not blindly configure:

```sql
FILLFACTOR = 80
```

for every index.

A lower fill factor means lower page density.

That can increase:

* Number of pages
* I/O
* Memory consumption
* Storage requirements

Microsoft's current guidance generally favors 100/0 unless there is a specific reason, such as indexes experiencing significant page splits, particularly with workloads involving nonsequential GUID keys.

---

# 27. Real-Time Scenario: Random GUID Key

Suppose a table uses:

```sql
CustomerID UNIQUEIDENTIFIER
```

and applications generate random GUIDs.

New values can belong anywhere in the index.

This can cause:

```text
Random inserts
      ↓
Page splits
      ↓
Lower page density
      ↓
More pages
      ↓
More I/O
```

In such a case, the DBA might investigate:

* Index design
* Key design
* Fill factor
* `OPTIMIZE_FOR_SEQUENTIAL_KEY`
* Insert workload
* Page split activity

Do not simply rebuild the index every night.

The underlying cause may still exist tomorrow.

---

# 28. Rebuild Does Not Fix the Root Cause

Suppose:

```text
Monday:
Index fragmentation = 5%

Tuesday:
Index fragmentation = 45%

Wednesday:
Index fragmentation = 5% after rebuild

Thursday:
Index fragmentation = 50%
```

If this pattern repeats, the problem may be workload/index design rather than maintenance scheduling.

Ask:

> Why is this index fragmenting so quickly?

Investigate:

* Insert pattern
* Update pattern
* Delete pattern
* Key distribution
* Page splits
* Fill factor
* Index design

---

# 29. How to Find Large Fragmented Indexes

Example:

```sql
SELECT
    DB_NAME(ps.database_id) AS DatabaseName,
    OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) AS SchemaName,
    OBJECT_NAME(ps.object_id, ps.database_id) AS TableName,
    i.name AS IndexName,
    ps.index_type_desc,
    ps.page_count,
    ps.avg_fragmentation_in_percent,
    ps.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats
(
    DB_ID(),
    NULL,
    NULL,
    NULL,
    'LIMITED'
) AS ps
INNER JOIN sys.indexes AS i
    ON ps.object_id = i.object_id
   AND ps.index_id = i.index_id
WHERE
    ps.index_id > 0
    AND ps.page_count > 1000
ORDER BY
    ps.page_count DESC;
```

This is more useful than simply sorting by fragmentation.

---

# 30. Practical DBA Query — Identify Candidates

```sql
SELECT
    OBJECT_SCHEMA_NAME(ps.object_id) AS SchemaName,
    OBJECT_NAME(ps.object_id) AS TableName,
    i.name AS IndexName,
    ps.index_type_desc,
    ps.page_count,
    CAST(ps.avg_fragmentation_in_percent AS decimal(10,2))
        AS FragmentationPercent,
    CAST(ps.avg_page_space_used_in_percent AS decimal(10,2))
        AS PageDensityPercent
FROM sys.dm_db_index_physical_stats
(
    DB_ID(),
    NULL,
    NULL,
    NULL,
    'LIMITED'
) ps
JOIN sys.indexes i
    ON ps.object_id = i.object_id
   AND ps.index_id = i.index_id
WHERE
    ps.index_id > 0
    AND ps.page_count >= 1000
ORDER BY
    ps.avg_fragmentation_in_percent DESC;
```

---

# 31. REORGANIZE Example

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REORGANIZE;
```

For all indexes:

```sql
ALTER INDEX ALL
ON Sales.SalesOrderHeader
REORGANIZE;
```

Use `ALL` carefully in production.

You may not want to reorganize every index on a heavily used table.

---

# 32. REBUILD Example

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD;
```

Online:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD
WITH
(
    ONLINE = ON
);
```

With controlled parallelism:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD
WITH
(
    ONLINE = ON,
    MAXDOP = 4
);
```

Use `MAXDOP` based on the server's workload and established SQL Server configuration standards.

---

# 33. SORT_IN_TEMPDB

Example:

```sql
ALTER INDEX IX_SalesOrderHeader_CustomerID
ON Sales.SalesOrderHeader
REBUILD
WITH
(
    SORT_IN_TEMPDB = ON
);
```

This directs intermediate sort results to `tempdb`.

Potential benefit:

* Reduces the amount of temporary sort space required in the destination database.

But the DBA must ensure:

* `tempdb` has sufficient free space
* `tempdb` storage can handle the workload
* I/O capacity is sufficient

Do not enable it blindly.

---

# 34. Transaction Log Considerations

Index rebuilds can generate significant transaction log activity.

Before a large production rebuild, check:

```sql
SELECT
    DB_NAME(database_id) AS DatabaseName,
    total_log_size_in_bytes / 1024.0 / 1024 AS TotalLogMB,
    used_log_space_in_bytes / 1024.0 / 1024 AS UsedLogMB,
    used_log_space_in_percent
FROM sys.dm_db_log_space_usage;
```

For a production maintenance window, verify:

* Log file size
* Available disk space
* Log growth configuration
* Recovery model
* Backup strategy
* AG/log shipping impact
* Downstream replica health

---

# 35. Always On Availability Groups Scenario

Suppose the primary replica contains:

```text
1 TB database
250 GB index
```

You perform a large index rebuild.

The rebuild generates log records.

Those log records must be transported to secondary replicas.

Potential consequences:

```text
Index rebuild
      ↓
Large transaction log generation
      ↓
Log transport
      ↓
Secondary redo workload
      ↓
Possible synchronization delay
```

Therefore, index maintenance can affect:

* AG synchronization
* Log send queue
* Redo queue
* Network utilization
* Secondary I/O

A DBA should check AG health before and after major maintenance.

---

# 36. Log Shipping Scenario

The same principle applies to log shipping.

A large index rebuild can generate substantial transaction log activity.

That can result in:

```text
Primary
   ↓
Large log generation
   ↓
Log backup
   ↓
Network transfer
   ↓
Secondary copy
   ↓
Restore
```

Potentially increasing:

* Copy latency
* Restore latency
* Secondary lag

Therefore, large index rebuilds should be considered when planning log shipping maintenance.

---

# 37. Query Store Should Be Used

One of the strongest recommendations from Microsoft's current guidance is to measure whether index maintenance actually improves workload performance.

Query Store can help perform before/after comparisons.

Example:

```text
Before maintenance
        ↓
Capture query performance
        ↓
Perform index maintenance
        ↓
Capture query performance
        ↓
Compare
```

Look at:

* Duration
* CPU
* Logical reads
* Physical reads
* Execution count
* Query plan changes

Do not assume success merely because:

```text
Fragmentation = 2%
```

---

# 38. Real Production Scenario — Query Still Slow After Rebuild

Application team reports:

> Customer search is still taking 12 seconds.

DBA checks:

```text
Index fragmentation = 3%
```

The index was rebuilt last night.

Does that mean the index is healthy and the query should be fast?

Not necessarily.

Investigate:

* Statistics
* Execution plan
* Missing indexes
* Parameter sensitivity
* Blocking
* Memory pressure
* CPU
* Storage latency
* Cardinality estimation
* Query design
* Data growth

The rebuild may not have addressed the actual problem.

---

# 39. Statistics vs Index Maintenance

Consider:

```text
Query performance degraded
        ↓
DBA sees fragmentation = 40%
        ↓
Rebuild
        ↓
Query becomes faster
```

It is tempting to conclude:

> Rebuild fixed fragmentation.

But another possibility is:

```text
Rebuild
   ↓
Statistics updated
   ↓
Better cardinality estimate
   ↓
Better execution plan
   ↓
Query becomes faster
```

Therefore, if updating statistics produces the same benefit, an expensive rebuild may not be necessary.

---

# 40. A Better Maintenance Workflow

Use this production workflow:

```text
1. Identify index
        ↓
2. Check size/page count
        ↓
3. Check fragmentation
        ↓
4. Check page density
        ↓
5. Check index usage
        ↓
6. Check query workload
        ↓
7. Check statistics
        ↓
8. Check storage/log/tempdb capacity
        ↓
9. Select REORGANIZE / REBUILD / UPDATE STATISTICS / NONE
        ↓
10. Execute during suitable window
        ↓
11. Monitor
        ↓
12. Validate
        ↓
13. Measure business/query impact
```

---

# 41. Index Usage Information

You can inspect index usage with:

```sql
SELECT
    OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats ius
    ON i.object_id = ius.object_id
   AND i.index_id = ius.index_id
   AND ius.database_id = DB_ID()
WHERE
    i.object_id > 0
ORDER BY
    ius.user_updates DESC;
```

Interpret the output carefully.

For example:

```text
user_seeks = 0
user_scans = 0
user_lookups = 0
user_updates = 5,000,000
```

This may indicate an index that receives significant maintenance overhead but provides little read benefit.

Do not immediately drop it, though.

Validate:

* Application dependencies
* Query Store
* Missing index information
* Execution plans
* Business workload
* Recent server restart history

---

# 42. Why `sys.dm_db_index_usage_stats` Needs Care

The DMV's counters are not permanent historical data.

They can reset under circumstances such as:

* SQL Server restart
* Database detach/attach
* Database restart/recovery scenarios
* Other lifecycle events

Therefore, do not conclude:

> “This index has never been used.”

unless you know the monitoring period covers the required workload.

---

# 43. Fragmentation Is Not Corruption

This distinction is extremely important.

Fragmentation:

```text
Performance / storage organization issue
```

Corruption:

```text
Data integrity issue
```

Do not use:

```sql
ALTER INDEX ... REBUILD
```

as a replacement for:

```sql
DBCC CHECKDB
```

when investigating database corruption.

For suspected corruption, follow the appropriate CHECKDB and recovery process.

---

# 44. Rebuild for Corruption — Important Exception

Microsoft documents a special case where rebuilding a nonclustered index offline can sometimes repair inconsistencies in that index.

However:

* This is not normal index maintenance.
* Online rebuild does not provide the same corruption-repair behavior.
* `DBCC CHECKDB` remains the primary tool for database consistency checks.

Never convert your regular index maintenance job into a corruption repair process.

---

# 45. Partitioned Indexes

For partitioned indexes, maintenance can be performed at the partition level.

This is important for large data warehouse and OLTP systems.

Instead of:

```text
1 TB entire index
```

you may have:

```text
Partition 1 → 2023
Partition 2 → 2024
Partition 3 → 2025
Partition 4 → 2026
```

If only the current partition is heavily modified, you may be able to target that partition rather than performing unnecessary maintenance across the entire index.

---

# 46. Partition-Level Rebuild Example

Conceptually:

```sql
ALTER INDEX IX_SalesOrder_OrderDate
ON Sales.SalesOrder
REBUILD PARTITION = 4;
```

Partition-level maintenance can significantly reduce the maintenance scope in large systems.

Always validate the partitioning design and workload before choosing this approach.

---

# 47. Columnstore Indexes Are Different

Do not apply rowstore fragmentation rules directly to columnstore indexes.

Columnstore indexes have concepts such as:

* Rowgroups
* Delta stores
* Deleted rows
* Compression

For example:

```text
Columnstore
    |
    +-- Compressed rowgroups
    |
    +-- Delta store
    |
    +-- Deleted rows
```

Microsoft documents different maintenance behavior for columnstore indexes.

For many columnstore scenarios, `REORGANIZE` performs important work that historically might have required rebuilding.

---

# 48. Small Indexes

Small indexes often do not justify aggressive maintenance.

Suppose:

```text
Index size = 2 MB
Fragmentation = 80%
```

The percentage looks terrible.

But the actual performance impact may be negligible.

Compare that with:

```text
Index size = 200 GB
Fragmentation = 25%
```

The second index may deserve much more attention.

Therefore:

**Fragmentation percentage without index size is incomplete information.**

---

# 49. Common DBA Mistakes

## Mistake 1 — Rebuild Everything Every Night

Example:

```sql
ALTER INDEX ALL
ON Database.Table
REBUILD;
```

against every table.

Problems:

* CPU
* I/O
* Transaction log growth
* Blocking
* AG impact
* Log shipping impact
* Maintenance window overruns
* Unnecessary work

---

## Mistake 2 — Rebuild Based Only on 30%

Example:

```text
> 30% = rebuild
```

This ignores:

* Page count
* Page density
* Workload
* Index usage
* Statistics
* Business impact

---

## Mistake 3 — Assume Rebuild Updates All Statistics

It does not.

Index rebuild updates the statistics associated with the index, but unrelated column statistics are not automatically refreshed simply because another index was rebuilt.

---

## Mistake 4 — Use Low Fill Factor Everywhere

For example:

```sql
FILLFACTOR = 70
```

on every index.

This can unnecessarily reduce page density and increase storage/I/O.

---

## Mistake 5 — Ignore Transaction Log

A large rebuild can generate significant logging.

---

## Mistake 6 — Ignore Availability Groups

Large maintenance operations can affect secondary synchronization.

---

## Mistake 7 — Ignore Query Store

If you do not measure before and after, you may not know whether maintenance actually helped.

---

# 50. Production Pre-Check

Before a large rebuild, check:

### Database

```sql
SELECT
    name,
    recovery_model_desc,
    state_desc
FROM sys.databases
WHERE name = DB_NAME();
```

### Index

Check:

* Size
* Fragmentation
* Page density
* Usage

### Storage

Check:

* Data free space
* Log free space
* Tempdb free space

### HA/DR

Check:

* AG synchronization
* Log shipping latency
* Replication status if applicable

### Workload

Check:

* CPU
* I/O
* Blocking
* Query Store

---

# 51. Production Execution Checklist

Before executing:

```text
[ ] Change ticket approved
[ ] Maintenance window approved
[ ] Backup status verified
[ ] Database healthy
[ ] Disk space checked
[ ] Transaction log capacity checked
[ ] tempdb capacity checked
[ ] AG/log shipping status checked
[ ] Application impact reviewed
[ ] ONLINE option evaluated
[ ] RESUMABLE option evaluated
[ ] MAXDOP evaluated
[ ] Monitoring in place
```

---

# 52. Post-Maintenance Validation

After the operation:

```text
[ ] Fragmentation checked
[ ] Page density checked
[ ] Query performance checked
[ ] CPU checked
[ ] I/O checked
[ ] Transaction log checked
[ ] AG synchronization checked
[ ] Log shipping checked
[ ] Blocking checked
[ ] Query Store compared
```

Do not stop at:

```text
Command completed successfully.
```

The real question is:

> Did the maintenance improve the production workload without creating a new problem?

---

# 53. Recommended DBA Decision Model

A strong production approach is:

### Step 1 — Is the index important?

If not:

```text
No immediate action
```

### Step 2 — Is it large?

If very small:

```text
Usually low priority
```

### Step 3 — Is fragmentation significant?

Check it.

### Step 4 — Is page density poor?

Check it.

### Step 5 — Is the index heavily used?

Check usage and Query Store.

### Step 6 — Is performance actually affected?

Measure it.

### Step 7 — Is maintenance worth the cost?

Calculate the operational impact.

### Step 8 — Choose the least disruptive effective method.

Possible choices:

```text
NONE
UPDATE STATISTICS
REORGANIZE
REBUILD ONLINE
REBUILD RESUMABLE
REBUILD OFFLINE
```

---

# 54. Practical Example — OLTP Database

Environment:

```text
Database: BankingDB
Table: Transaction
Rows: 700 million
Index: IX_Transaction_AccountID
Size: 180 GB
Fragmentation: 42%
Page Density: 68%
```

Application:

```text
24x7 transaction processing
```

A reasonable approach:

1. Confirm the index is heavily used.
2. Review Query Store.
3. Check scan/range-scan workload.
4. Check page density.
5. Check page split activity.
6. Check storage and transaction log.
7. Evaluate online rebuild.
8. Consider resumable rebuild if the operation is too large for one window.
9. Monitor AG/log shipping impact.
10. Compare query performance after completion.

---

# 55. Practical Example — Data Warehouse

Environment:

```text
Database: DW
Table: FactSales
Rows: 2 billion
Partitioned by SalesDate
```

Only the current partition receives heavy modifications.

Instead of rebuilding every partition:

```text
Old partitions
    ↓
Mostly static
```

Focus maintenance on:

```text
Current / active partition
```

This can dramatically reduce maintenance cost.

---

# 56. Practical Example — SQL Server Always On

Scenario:

```text
Primary
PMSQL01

Secondary
PMSQL02
```

You start a 300 GB index rebuild.

During the rebuild:

```text
Primary
   ↓
High log generation
   ↓
AG transport
   ↓
Secondary redo
```

You observe:

```text
Log Send Queue increasing
Redo Queue increasing
Synchronization delay
```

The DBA should not simply continue because:

> “The rebuild is already 70% complete.”

Production stability comes first.

Depending on the operation type and business requirements, a resumable rebuild may provide a better operational model.

---

# 57. Practical Example — Log Shipping

Suppose the log shipping secondary normally has:

```text
Copy latency: 30 seconds
Restore latency: 45 seconds
```

After a large index rebuild:

```text
Copy latency: 10 minutes
Restore latency: 20 minutes
```

The index operation itself may have completed successfully, but the maintenance window has created downstream recovery lag.

This is why HA/DR must be part of index maintenance planning.

---

# 58. Should Index Maintenance Run Daily?

Not necessarily.

The right schedule depends on:

* Data modification rate
* Database size
* Workload
* Index design
* Business criticality
* Maintenance cost
* Performance impact

Some environments may require frequent maintenance.

Others may need little or none.

Do not create a schedule first and investigate later.

---

# 59. Recommended Monitoring Model

Instead of:

```text
Every Sunday:
Rebuild all indexes
```

consider:

```text
Daily/regular monitoring
        ↓
Collect:
- fragmentation
- page density
- page count
- usage
- query performance
        ↓
Identify candidates
        ↓
Perform targeted maintenance
        ↓
Measure results
```

This is a much stronger production DBA approach.

---

# 60. Recommended Enterprise Maintenance Framework

A mature SQL Server environment can implement:

```text
                    SQL SERVER
                         |
             +-----------+-----------+
             |                       |
        Index Health             Workload
             |                       |
     +-------+-------+        +------+------+
     |       |       |        |             |
Fragmentation Density Size   Query Store   DMV
     |       |       |        |             |
     +-------+-------+--------+-------------+
                         |
                    Decision Engine
                         |
          +--------------+--------------+
          |              |              |
         NONE       REORGANIZE       REBUILD
                                        |
                              +---------+---------+
                              |                   |
                           ONLINE             RESUMABLE
```

---

# 61. The Most Important Interview Answer

### Question:

**When do you rebuild or reorganize an index?**

A strong production answer is:
> “I don't decide based only on fragmentation percentage.
> I first check index size, fragmentation, page density, workload, index usage, query performance, and statistics.
> If maintenance is justified, I prefer the least disruptive effective operation. Reorganize is an online, lower-resource option, while rebuild provides a more complete reconstruction and also updates the index statistics. For large production indexes, I evaluate online and resumable rebuild options and always consider transaction log, tempdb, storage, Always On, log shipping, and the maintenance window. Finally, I use Query Store or workload metrics to confirm that the maintenance actually improved performance.”
 

That is much stronger than:

> “Below 5% do nothing, 5–30% reorganize, above 30% rebuild.”

---

# 62. Quick Reference

| Area                      | REORGANIZE               | REBUILD                              |
| ------------------------- | ------------------------ | ------------------------------------ |
| Main purpose              | Defragment/compact       | Recreate index                       |
| Resource usage            | Lower                    | Higher                               |
| Online                    | Yes                      | Depends                              |
| Statistics                | Not updated              | Index statistics updated             |
| Full index reconstruction | No                       | Yes                                  |
| Resumable                 | No                       | Supported in applicable scenarios    |
| Best for                  | Lower-impact maintenance | Significant maintenance requirements |
| Blocking                  | Lower                    | Offline can block                    |
| Log impact                | Generally lower          | Potentially significant              |
| HA/DR impact              | Usually lower            | Can be significant                   |

---

# 63. Production DBA Golden Rules

1. **Do not rebuild every index blindly.**

2. **Do not use fragmentation percentage as the only decision factor.**

3. **Always consider page density.**

4. **Consider index size/page count.**

5. **Understand the workload using the index.**

6. **Use Query Store to measure real performance impact.**

7. **Remember that REORGANIZE does not update statistics.**

8. **Remember that REBUILD updates the statistics associated with the rebuilt rowstore index.**

9. **Do not use a low fill factor everywhere.**

10. **Investigate repeated page splits instead of repeatedly rebuilding the index.**

11. **Check transaction log capacity before large rebuilds.**

12. **Check tempdb when using options that depend on tempdb.**

13. **Consider ONLINE rebuild for business-critical systems where supported.**

14. **Consider RESUMABLE rebuild for very large indexes where supported.**

15. **Consider partition-level maintenance for partitioned tables.**

16. **Treat columnstore indexes differently from rowstore indexes.**

17. **Consider Always On and log shipping impact.**

18. **Do not confuse fragmentation with corruption.**

19. **Do not assume an improvement after rebuild was caused only by fragmentation reduction.**

20. **Measure before and after maintenance.**

---

# 64. Final Production Perspective

Index maintenance is not simply a database housekeeping task.

It is a **performance engineering activity**.

The old mindset was:

```text
Fragmentation > 30%
        ↓
REBUILD
```

The modern production mindset should be:

```text
                INDEX
                  |
        +---------+---------+
        |         |         |
 Fragmentation Density    Size
        |         |         |
        +---------+---------+
                  |
             Workload
                  |
             Query Store
                  |
          Statistics Health
                  |
        Storage / Log / Tempdb
                  |
             HA / DR
                  |
          Business Window
                  |
                  v
             DBA Decision
                  |
       +----------+----------+
       |          |          |
      NONE    REORGANIZE   REBUILD
                             |
                     +-------+-------+
                     |               |
                   ONLINE         RESUMABLE
```

The objective is **not to make every index look perfect**.

The objective is to keep the database performing well while using the **least amount of infrastructure resources and operational risk necessary**.

That is the mindset expected from a senior SQL Server DBA.

## Microsoft Learn References

Primary reference:

Microsoft Learn — **Optimize index maintenance to improve query performance and reduce resource consumption**

The current Microsoft documentation covers fragmentation, page density, `sys.dm_db_index_physical_stats`, reorganize, rebuild, online operations, resumable rebuilds, statistics behavior, partitioned indexes, columnstore considerations, and the recommended evidence-based maintenance strategy. ([Microsoft Learn][1])

Additional Microsoft reference:

**Set Index Options** — covers index options such as `FILLFACTOR`, `SORT_IN_TEMPDB`, `ONLINE`, `MAXDOP`, `ALLOW_PAGE_LOCKS`, and related `ALTER INDEX` options. ([Microsoft Learn][2])

**Key takeaway:** 
For your DBA practice, I would memorize the decision chain as **Fragmentation + Page Density + Page Count + Workload + Statistics + Operational Cost → Maintenance Decision**. 

That is much closer to how index maintenance should be handled in a real production SQL Server environment.

[1]: https://learn.microsoft.com/en-us/sql/relational-databases/indexes/reorganize-and-rebuild-indexes?view=sql-server-ver17 "Maintain Indexes Optimally to Improve Performance and Reduce Resource Utilization - SQL Server | Microsoft Learn"
[2]: https://learn.microsoft.com/en-us/sql/relational-databases/indexes/set-index-options?view=sql-server-ver17 "Set Index Options - SQL Server | Microsoft Learn"
