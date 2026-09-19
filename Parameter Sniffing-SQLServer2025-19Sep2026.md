# SQL Server 2025 — Parameter Sniffing

## 10 Focused Labs: Analysis + Resolution

**Environment**

```text
SQL Server        : 2025
Database          : AdventureWorks2025
Compatibility     : 170
Focus             : Parameter Sniffing, PSP, OPPO, Query Store
```

---

## Lab 1 — Establish the SQL Server 2025 Baseline

### Objective

Verify that the database is configured for the SQL Server 2025 optimization features used in the labs.

### Step 1 — Verify version

```sql
SELECT
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductMajorVersion') AS MajorVersion,
    SERVERPROPERTY('Edition') AS Edition;
GO
```

Expected:

```text
MajorVersion = 17
```

### Step 2 — Verify compatibility

```sql
SELECT
    name,
    compatibility_level
FROM sys.databases
WHERE name = 'AdventureWorks2025';
GO
```

Required:

```text
170
```

If required:

```sql
ALTER DATABASE AdventureWorks2025
SET COMPATIBILITY_LEVEL = 170;
GO
```

### Step 3 — Check PSP and OPPO

```sql
USE AdventureWorks2025;
GO

SELECT
    name,
    value,
    value_desc
FROM sys.database_scoped_configurations
WHERE name IN
(
    'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION',
    'OPTIONAL_PARAMETER_OPTIMIZATION'
);
GO
```

### Notes

For this lab:

```text
PSP  = ON
OPPO = ON
Compatibility = 170
```

**Why:** SQL Server 2025's modern approach is not simply "disable parameter sniffing." PSP and OPPO are designed to handle specific parameter-sensitive scenarios automatically.

---

# Lab 2 — Enable Query Store and Understand the Evidence

### Objective

Use Query Store as the primary historical evidence source.

### Enable

```sql
ALTER DATABASE AdventureWorks2025
SET QUERY_STORE = ON;
GO

ALTER DATABASE AdventureWorks2025
SET QUERY_STORE
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);
GO
```

### Verify

```sql
SELECT
    actual_state_desc,
    current_storage_size_mb,
    max_storage_size_mb,
    size_based_cleanup_mode_desc,
    stale_query_threshold_days
FROM sys.database_query_store_options;
GO
```

### What Query Store gives you

```text
Query
  ↓
Execution
  ↓
Plan
  ↓
Runtime statistics
  ↓
Historical comparison
```

You can identify:

* Multiple plans
* Duration differences
* CPU differences
* Logical-read differences
* Plan regressions
* Execution history

### Critical note

**Query Store does not itself fix parameter sniffing.**

It gives you the evidence required to determine whether the problem is parameter sensitivity and then choose an appropriate resolution.

---

# Lab 3 — Reproduce Parameter Sniffing

### Objective

Create a controlled skewed workload.

```sql
USE AdventureWorks2025;
GO

IF OBJECT_ID('dbo.ParameterSniffingLab') IS NOT NULL
    DROP TABLE dbo.ParameterSniffingLab;
GO

CREATE TABLE dbo.ParameterSniffingLab
(
    ID BIGINT IDENTITY(1,1) NOT NULL,
    CustomerGroup INT NOT NULL,
    OrderDate DATE NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    Filler CHAR(200) NULL,

    CONSTRAINT PK_ParameterSniffingLab
        PRIMARY KEY CLUSTERED (ID)
);
GO
```

Insert approximately 1 million rows:

```sql
;WITH N AS
(
    SELECT TOP (1000000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.ParameterSniffingLab
(
    CustomerGroup,
    OrderDate,
    Amount,
    Filler
)
SELECT
    CASE
        WHEN n <= 900000 THEN 1
        WHEN n <= 950000 THEN 2
        WHEN n <= 970000 THEN 3
        WHEN n <= 980000 THEN 4
        ELSE 999
    END,
    DATEADD
    (
        DAY,
        -(n % 3650),
        CAST(GETDATE() AS DATE)
    ),
    CAST((n % 10000) / 10.0 AS DECIMAL(18,2)),
    'Parameter Sniffing Lab'
FROM N;
GO
```

Create index:

```sql
CREATE INDEX IX_ParameterSniffingLab_CustomerGroup
ON dbo.ParameterSniffingLab(CustomerGroup)
INCLUDE
(
    OrderDate,
    Amount
);
GO

UPDATE STATISTICS dbo.ParameterSniffingLab
WITH FULLSCAN;
GO
```

Check distribution:

```sql
SELECT
    CustomerGroup,
    COUNT_BIG(*) AS RowCount
FROM dbo.ParameterSniffingLab
GROUP BY CustomerGroup
ORDER BY RowCount DESC;
GO
```

You should have a highly skewed distribution.

---

## Create procedure

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetCustomerGroup
    @CustomerGroup INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ID,
        CustomerGroup,
        OrderDate,
        Amount
    FROM dbo.ParameterSniffingLab
    WHERE CustomerGroup = @CustomerGroup;
END;
GO
```

---

## Test A — selective parameter first

```sql
EXEC sys.sp_recompile
    N'dbo.usp_GetCustomerGroup';
GO

EXEC dbo.usp_GetCustomerGroup
    @CustomerGroup = 999;
GO

EXEC dbo.usp_GetCustomerGroup
    @CustomerGroup = 1;
GO
```

## Test B — non-selective parameter first

```sql
EXEC sys.sp_recompile
    N'dbo.usp_GetCustomerGroup';
GO

EXEC dbo.usp_GetCustomerGroup
    @CustomerGroup = 1;
GO

EXEC dbo.usp_GetCustomerGroup
    @CustomerGroup = 999;
GO
```

### Analyze

Enable **Actual Execution Plan** and record:

| Metric         | 999 |  1 |
| -------------- | --: | -: |
| Actual rows    |     |    |
| Estimated rows |     |    |
| CPU            |     |    |
| Duration       |     |    |
| Logical reads  |     |    |
| Access method  |     |    |

### What you are proving

The same stored procedure can behave differently depending on **which parameter caused the initial compilation**.

That is the classic parameter-sensitive plan problem.

---

# Lab 4 — Prove the Root Cause

### Objective

Do not immediately call it "parameter sniffing."

Prove it.

### Query Store

```sql
SELECT
    qsq.query_id,
    qsp.plan_id,
    qsp.execution_type_desc,
    qsp.avg_duration,
    qsp.avg_cpu_time,
    qsp.avg_logical_io_reads,
    qsp.last_execution_time,
    qsp.is_forced_plan,
    qt.query_sql_text
FROM sys.query_store_query AS qsq
JOIN sys.query_store_query_text AS qt
    ON qsq.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS qsp
    ON qsq.query_id = qsp.query_id
WHERE qt.query_sql_text LIKE '%usp_GetCustomerGroup%'
ORDER BY
    qsq.query_id,
    qsp.plan_id;
GO
```

### Look for

```text
Same query
   +
Different parameter values
   +
Different runtime performance
   +
Different/unsuitable plans
   +
Data skew
```

### Execution-plan investigation

Compare:

```text
Compiled Value
Runtime Value
Estimated Rows
Actual Rows
Seek vs Scan
Memory Grant
CPU
Logical Reads
```

### Root-cause statement

If the evidence matches:

> **The query is parameter-sensitive because different parameter values have substantially different cardinalities and therefore require different execution strategies. A plan compiled for one parameter value is inefficient for another value.**

That is a much stronger RCA than simply saying:

> "Parameter sniffing happened."

---

# Lab 5 — Resolution #1: OPTION(RECOMPILE)

### Objective

Prove that recompilation produces a plan optimized for the current parameter.

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetCustomerGroup_Recompile
    @CustomerGroup INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ID,
        CustomerGroup,
        OrderDate,
        Amount
    FROM dbo.ParameterSniffingLab
    WHERE CustomerGroup = @CustomerGroup
    OPTION (RECOMPILE);
END;
GO
```

Test:

```sql
EXEC dbo.usp_GetCustomerGroup_Recompile
    @CustomerGroup = 999;
GO

EXEC dbo.usp_GetCustomerGroup_Recompile
    @CustomerGroup = 1;
GO
```

### Analyze

Compare both actual plans.

Expected principle:

```text
999
 ↓
Optimize for 999
 ↓
Selective plan

1
 ↓
Optimize for 1
 ↓
Large-result-set plan
```

### Resolution

`OPTION(RECOMPILE)` eliminates reuse of the cached plan for that execution.

### Cost

Every execution incurs compilation overhead.

### When useful

Good candidate when:

* Query execution is relatively infrequent
* Parameter distribution is highly skewed
* Optimal plans vary significantly
* Compilation cost is acceptable

### DBA note

**Do not use RECOMPILE blindly as the first production fix.**

---

# Lab 6 — Resolution #2: PSP — SQL Server 2025 Modern Solution

This is the most important modern lab.

### Verify PSP

```sql
SELECT
    name,
    value,
    value_desc
FROM sys.database_scoped_configurations
WHERE name = 'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION';
GO
```

It should be enabled.

### Create clean procedure

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetCustomerGroup_PSP
    @CustomerGroup INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ID,
        CustomerGroup,
        OrderDate,
        Amount
    FROM dbo.ParameterSniffingLab
    WHERE CustomerGroup = @CustomerGroup;
END;
GO
```

Clear previous compilation:

```sql
EXEC sys.sp_recompile
    N'dbo.usp_GetCustomerGroup_PSP';
GO
```

Execute different parameter values:

```sql
EXEC dbo.usp_GetCustomerGroup_PSP
    @CustomerGroup = 999;
GO

EXEC dbo.usp_GetCustomerGroup_PSP
    @CustomerGroup = 1;
GO

EXEC dbo.usp_GetCustomerGroup_PSP
    @CustomerGroup = 2;
GO
```

### Analyze Query Store

```sql
SELECT
    qsq.query_id,
    qsp.plan_id,
    qsp.avg_duration,
    qsp.avg_cpu_time,
    qsp.avg_logical_io_reads,
    qsp.last_execution_time,
    qt.query_sql_text
FROM sys.query_store_query AS qsq
JOIN sys.query_store_query_text AS qt
    ON qsq.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS qsp
    ON qsq.query_id = qsp.query_id
WHERE qt.query_sql_text LIKE '%usp_GetCustomerGroup_PSP%'
ORDER BY
    qsq.query_id,
    qsp.plan_id;
GO
```

### Important note

Do **not** expect every query to automatically produce multiple PSP variants.

PSP has eligibility rules. SQL Server decides whether parameter-sensitive optimization is appropriate.

### Concept

```text
                 Query
                   |
            Dispatcher Plan
                   |
       +-----------+-----------+
       |           |           |
     Range 1     Range 2     Range 3
       |           |           |
     Plan 1      Plan 2      Plan 3
```

### Resolution

For eligible parameter-sensitive queries, **PSP allows SQL Server to maintain multiple plan variants for different parameter cardinality ranges.**

This is fundamentally different from simply disabling parameter sniffing.

---

# Lab 7 — Resolution #3: OPPO — Optional Parameters

### Objective

Learn the SQL Server 2025 solution for optional search predicates.

Create:

```sql
CREATE OR ALTER PROCEDURE dbo.usp_SearchCustomerGroup
    @CustomerGroup INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ID,
        CustomerGroup,
        OrderDate,
        Amount
    FROM dbo.ParameterSniffingLab
    WHERE
        CustomerGroup = @CustomerGroup
        OR @CustomerGroup IS NULL;
END;
GO
```

Test:

```sql
EXEC dbo.usp_SearchCustomerGroup
    @CustomerGroup = NULL;
GO

EXEC dbo.usp_SearchCustomerGroup
    @CustomerGroup = 999;
GO

EXEC dbo.usp_SearchCustomerGroup
    @CustomerGroup = 1;
GO
```

### Why this is different

When:

```text
@CustomerGroup IS NULL
```

the query potentially needs a very large result set.

When:

```text
@CustomerGroup = 999
```

the query needs a highly selective result.

One traditional plan may not be optimal for both.

### Verify OPPO

```sql
SELECT
    name,
    value,
    value_desc
FROM sys.database_scoped_configurations
WHERE name = 'OPTIONAL_PARAMETER_OPTIMIZATION';
GO
```

### Concept

```text
                 Dispatcher
                     |
            @CustomerGroup NULL?
                 /       \
               YES       NO
                |         |
              Scan      Variant
                          |
                        Seek
```

### Resolution

**OPPO is SQL Server 2025's optimization for eligible optional-parameter predicates.**

Do not confuse:

```text
PSP → different cardinality ranges for parameter values

OPPO → optional predicates, particularly NULL vs supplied parameter
```

---

# Lab 8 — Resolution #4: Query Store Hint

### Objective

Fix a problematic query **without modifying application code**.

First locate the query:

```sql
SELECT
    qsq.query_id,
    qt.query_sql_text
FROM sys.query_store_query AS qsq
JOIN sys.query_store_query_text AS qt
    ON qsq.query_text_id = qt.query_text_id
WHERE qt.query_sql_text LIKE '%usp_GetCustomerGroup%';
GO
```

Suppose your actual result is:

```text
query_id = 57
```

Use **your actual query ID**.

### Apply `RECOMPILE`

```sql
EXEC sys.sp_query_store_set_hints
    @query_id = 57,
    @value = N'OPTION(RECOMPILE)';
GO
```

Verify:

```sql
SELECT
    query_id,
    query_hint_id,
    query_hint_text,
    source_desc,
    state_desc
FROM sys.query_store_query_hints
WHERE query_id = 57;
GO
```

### Remove hint

```sql
EXEC sys.sp_query_store_clear_hints
    @query_id = 57;
GO
```

### Another option

```sql
EXEC sys.sp_query_store_set_hints
    @query_id = 57,
    @value =
    N'OPTION(USE HINT(''DISABLE_PARAMETER_SNIFFING''))';
GO
```

### Production scenario

```text
Application code
       |
       | cannot change immediately
       ↓
DBA identifies problematic query
       |
       ↓
Query Store
       |
       ↓
Query Store Hint
       |
       ↓
Targeted remediation
```

### Important

Query Store Hints should be applied **to a specific query based on evidence**, not used as a blanket database-wide solution.

---

# Lab 9 — Resolution #5: Compare Traditional Workarounds

Now deliberately compare the older techniques.

## A. OPTIMIZE FOR UNKNOWN

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetCustomerGroup_Unknown
    @CustomerGroup INT
AS
BEGIN
    SELECT
        ID,
        CustomerGroup,
        OrderDate,
        Amount
    FROM dbo.ParameterSniffingLab
    WHERE CustomerGroup = @CustomerGroup
    OPTION (OPTIMIZE FOR UNKNOWN);
END;
GO
```

Test:

```sql
EXEC dbo.usp_GetCustomerGroup_Unknown 999;
EXEC dbo.usp_GetCustomerGroup_Unknown 1;
```

### Principle

SQL Server doesn't optimize specifically for the current parameter.

Potential benefit:

```text
Avoid extreme sensitivity to first compiled value
```

Potential problem:

```text
Generic estimate may be poor for both extremes
```

---

## B. OPTIMIZE FOR a specific value

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetCustomerGroup_OptimizeFor
    @CustomerGroup INT
AS
BEGIN
    SELECT
        ID,
        CustomerGroup,
        OrderDate,
        Amount
    FROM dbo.ParameterSniffingLab
    WHERE CustomerGroup = @CustomerGroup
    OPTION
    (
        OPTIMIZE FOR (@CustomerGroup = 999)
    );
END;
GO
```

### Principle

Force optimization around a chosen representative value.

### Risk

If the workload changes:

```text
Chosen value
     ↓
no longer representative
     ↓
plan becomes inefficient
```

---

## C. DISABLE_PARAMETER_SNIFFING

```sql
CREATE OR ALTER PROCEDURE dbo.usp_GetCustomerGroup_NoSniff
    @CustomerGroup INT
AS
BEGIN
    SELECT
        ID,
        CustomerGroup,
        OrderDate,
        Amount
    FROM dbo.ParameterSniffingLab
    WHERE CustomerGroup = @CustomerGroup
    OPTION
    (
        USE HINT('DISABLE_PARAMETER_SNIFFING')
    );
END;
GO
```

### Important SQL Server 2025 note

This is a **deliberate fallback/workaround**, not automatically the preferred modern resolution.

Disabling parameter sniffing also prevents the query from benefiting from parameter-sensitive plan optimization.

---

# Lab 10 — Final L3 DBA Incident: Diagnose → Resolve → Validate

This is your **interview + production simulation**.

## Incident

Application team reports:

> "The same stored procedure sometimes finishes in milliseconds and sometimes takes several seconds."

---

## Step 1 — Identify query

Use Query Store:

```sql
SELECT
    qsq.query_id,
    qsp.plan_id,
    qsp.avg_duration,
    qsp.avg_cpu_time,
    qsp.avg_logical_io_reads,
    qsp.last_execution_time,
    qt.query_sql_text
FROM sys.query_store_query AS qsq
JOIN sys.query_store_query_text AS qt
    ON qsq.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS qsp
    ON qsq.query_id = qsp.query_id
WHERE qt.query_sql_text LIKE '%ParameterSniffingLab%'
ORDER BY
    qsp.avg_duration DESC;
GO
```

---

## Step 2 — Check plans

Determine:

```text
Same query?
Different plans?
Different parameter values?
Different cardinalities?
Different runtime?
```

---

## Step 3 — Check statistics

```sql
DBCC SHOW_STATISTICS
(
    'dbo.ParameterSniffingLab',
    'IX_ParameterSniffingLab_CustomerGroup'
);
GO
```

Look at:

```text
Histogram
Rows
Rows sampled
Density
```

---

## Step 4 — Check SQL Server 2025 features

```sql
SELECT
    name,
    value,
    value_desc
FROM sys.database_scoped_configurations
WHERE name IN
(
    'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION',
    'OPTIONAL_PARAMETER_OPTIMIZATION'
);
GO
```

And:

```sql
SELECT
    compatibility_level
FROM sys.databases
WHERE name = 'AdventureWorks2025';
GO
```

Required:

```text
170
```

---

## Step 5 — Determine the scenario

### Scenario A

```text
Normal equality predicate
+
Different cardinalities
```

Investigate:

```text
PSP
```

### Scenario B

```text
Optional parameter
+
@Parameter IS NULL
```

Investigate:

```text
OPPO
```

### Scenario C

```text
PSP/OPPO not applicable
or
specific behavior must be controlled
```

Consider:

```text
Query Store Hint
RECOMPILE
OPTIMIZE FOR UNKNOWN
OPTIMIZE FOR specific value
DISABLE_PARAMETER_SNIFFING
```

---

# Final Resolution Matrix

| Situation                                                      | Primary investigation/resolution       |
| -------------------------------------------------------------- | -------------------------------------- |
| Different parameter values require different plans             | **PSP**                                |
| Optional `@p IS NULL OR column = @p` pattern                   | **OPPO**                               |
| Query executes infrequently but values are extremely sensitive | `RECOMPILE`                            |
| Application cannot be changed                                  | **Query Store Hint**                   |
| Generic plan is acceptable                                     | `OPTIMIZE FOR UNKNOWN`                 |
| One value is consistently representative                       | `OPTIMIZE FOR (@p = value)`            |
| Need to deliberately suppress sniffing                         | `DISABLE_PARAMETER_SNIFFING`           |
| Statistics are inaccurate                                      | Update/review statistics               |
| Missing/poor index                                             | Index/query tuning                     |
| Need temporary plan invalidation                               | `sp_recompile` / targeted cache action |
| Need historical evidence                                       | **Query Store**                        |

---

# Strict DBA Notes to Remember

### 1. Parameter sniffing is not automatically a bug

```text
Parameter sniffing
       ↓
SQL Server uses parameter information
       ↓
Can produce an excellent plan
```

The problem is when **one reused plan is inefficient for materially different parameter values**.

---

### 2. Do not diagnose from duration alone

You need:

```text
Actual plan
+
Estimated vs actual rows
+
Parameter values
+
Query Store history
+
Statistics
+
Logical reads
+
CPU
```

---

### 3. `DBCC FREEPROCCACHE` is not a permanent fix

It merely causes recompilation.

```text
Clear cache
   ↓
Recompile
   ↓
New plan
   ↓
Problem may return
```

---

### 4. `OPTION(RECOMPILE)` is powerful but has a cost

```text
Good plan per execution
        +
Compilation overhead
```

Use based on workload frequency and compilation cost.

---

### 5. SQL Server 2025 changes the troubleshooting mindset

For eligible workloads, first investigate:

```text
Compatibility 170
       ↓
PSP
       ↓
OPPO
       ↓
Query Store
       ↓
Targeted remediation
```

rather than immediately applying:

```sql
DBCC FREEPROCCACHE;
```

or:

```sql
OPTION(RECOMPILE)
```

---

## The 10 labs you actually need to master

```text
01  SQL 2025 Baseline
02  Query Store
03  Reproduce Parameter Sniffing
04  Prove RCA
05  RECOMPILE
06  PSP
07  OPPO
08  Query Store Hints
09  Traditional Workarounds
10  Complete L3 Incident
```

This is the tighter lab set I would use for your **SQL Server 2025 L3 DBA preparation**—enough to understand the problem deeply without creating 30+ repetitive exercises.
