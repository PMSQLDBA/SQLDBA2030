**Important documentation note:
** Questions **2–8 are MongoDB questions**. 

MongoDB is not a Microsoft product, so Microsoft Learn does not provide the authoritative documentation for native/self-managed MongoDB. 
For those questions, used the **official MongoDB documentation**. 
Questions **9–49 are SQL Server topics**, used **Microsoft Learn** as the primary reference.

Treating **SQL Server 2025 (17.x)** as the current SQL Server generation where relevant.

---

# L1 DBA Interview Questions – Accurate Answers

## 1. Tell me about yourself and your SQL Server DBA experience.

**Interview answer:**

* I am a **Senior Database Engineer / SQL Server DBA with 10+ years of experience**.
* I have worked with SQL Server from **SQL Server 2000 through SQL Server 2025**.
* My experience covers **on-premises, Azure, AWS, and hybrid environments**.
* My core SQL Server responsibilities include:

  * Installation and configuration
  * Patching and upgrades
  * Database migrations and consolidations
  * Backup and restore
  * Disaster recovery
  * Always On Availability Groups
  * Failover clustering
  * Log shipping and replication
  * Performance tuning
  * Blocking and deadlock troubleshooting
  * Storage and capacity management
  * SQL Agent
  * Security, RBAC, auditing and TDE
* I work extensively with **T-SQL and PowerShell automation** and also have experience with Python and shell scripting.
* On the cloud side, I have worked with **Azure SQL Database, Azure SQL Managed Instance, AWS RDS and EC2**.
* I also have experience supporting **PostgreSQL, MongoDB and Oracle** environments.
* My approach to DBA work is to first understand the business impact, identify the root cause, implement a controlled fix, and then document and automate the solution where possible.

**Good short interview version:**

> "I have 10+ years of experience as a SQL Server DBA/Senior Database Engineer, working across SQL Server 2000 through 2025 in on-prem, Azure, AWS and hybrid environments. 

My core areas are HA/DR, Always On, migrations, upgrades, backup and recovery, performance tuning, security and automation using T-SQL and PowerShell. 

I have also worked with Azure SQL, AWS RDS/EC2, PostgreSQL, MongoDB and Oracle. I focus strongly on availability, performance, automation and root-cause troubleshooting."

---

# MongoDB Questions

## 2. What is MongoDB?

* MongoDB is a **document-oriented NoSQL database**.
* It stores data as **BSON documents**.
* Documents are grouped into **collections**.
* Collections are grouped into databases.
* Unlike a traditional relational database, MongoDB does not require a fixed table/row/column structure.
* Documents can contain nested documents and arrays.
* MongoDB supports indexing, aggregation, transactions, replication and sharding.

**Simple comparison:**

`Database → Collection → Document → Field`

Official MongoDB documentation describes MongoDB as storing records as BSON documents in collections. ([MongoDB][1])

---

## 3. What is a collection in MongoDB?

* A **collection** is a group of MongoDB documents.
* It is broadly comparable to a **table** in SQL Server.
* Documents within a collection normally represent related types of data.
* A collection does not require every document to have exactly the same fields.
* MongoDB can create a collection automatically when data is first inserted.

**SQL Server comparison:**

| SQL Server | MongoDB    |
| ---------- | ---------- |
| Database   | Database   |
| Table      | Collection |
| Row        | Document   |
| Column     | Field      |

([MongoDB][1])

---

## 4. What is a document in MongoDB?

* A document is the basic unit of data stored by MongoDB.
* It is represented internally as **BSON**.
* BSON is a binary representation of JSON-like documents.
* A document contains **field-value pairs**.
* Fields can contain:

  * Strings
  * Numbers
  * Dates
  * Arrays
  * Embedded documents
  * Boolean values
  * ObjectIds
  * Other BSON data types.
* MongoDB automatically uses the **`_id` field** as the primary identifier unless otherwise specified.

Example:

```javascript
{
    _id: ObjectId("..."),
    name: "John",
    age: 35,
    skills: ["SQL", "MongoDB"],
    address: {
        city: "Dallas",
        state: "Texas"
    }
}
```

([MongoDB][2])

---

## 5. What are the equivalents of tables, rows, and columns in MongoDB?

* **Table → Collection**
* **Row → Document**
* **Column → Field**
* **Primary key → `_id`**
* **Index → Index**
* **Join → `$lookup` / embedded documents**

Important interview point:

> MongoDB is not simply a relational database with different names. The document model allows nested and flexible structures.

([MongoDB][2])

---

## 6. How do you take a MongoDB backup?

For a self-managed MongoDB environment:

* `mongodump` can create a binary export.
* It can back up:

  * Databases
  * Collections
  * Documents
  * Metadata
  * Index definitions.
* Example:

```bash
mongodump --db=mydb --out=/backup/mydb
```

* For a replica set where writes continue during the dump, MongoDB provides the `--oplog` option.

```bash
mongodump --oplog --out=/backup/mydb
```

* Restore using:

```bash
mongorestore --oplogReplay /backup/mydb
```

**Important:** `mongodump` is not automatically equivalent to a production-grade physical backup strategy for every MongoDB architecture. Replica sets and sharded clusters require appropriate backup procedures.

([MongoDB][3])

---

## 7. How do you create a MongoDB user?

Using `mongosh`:

```javascript
use appdb

db.createUser({
    user: "appuser",
    pwd: passwordPrompt(),
    roles: [
        { role: "readWrite", db: "appdb" }
    ]
})
```

* `db.createUser()` creates a user on the database where the command is executed.
* Roles determine what the user can do.
* Use the minimum required privileges.
* In production, protect credentials using appropriate authentication and TLS.

([MongoDB][4])

---

## 8. How do you grant access/permissions in MongoDB?

MongoDB uses **role-based access control (RBAC)**.

* Create a user.
* Assign built-in or custom roles.
* Examples:

  * `read`
  * `readWrite`
  * `dbAdmin`
  * `userAdmin`
  * `clusterAdmin`
* Roles can be assigned at appropriate database scopes.
* Use least privilege.

Example:

```javascript
db.grantRolesToUser(
    "appuser",
    [
        { role: "readWrite", db: "appdb" }
    ]
)
```

The exact privileges should match the application's requirements.

([MongoDB][4])

---

# SQL Server Always On

## 9. What is SQL Server Always On?

* **Always On** is Microsoft's umbrella technology for SQL Server high availability and disaster recovery.
* The two major technologies are:

  1. **Always On Availability Groups**
  2. **Always On Failover Cluster Instances (FCI)**
* Availability Groups provide database-level replication between replicas.
* FCI provides instance-level protection using Windows Server Failover Clustering and shared storage.
* Availability Groups can provide:

  * HA
  * DR
  * Automatic failover
  * Readable secondary replicas
  * Backup offloading
  * Application connectivity through an AG listener.

([Microsoft Learn][5])

---

## 10. What are the basic prerequisites for Always On?

For a traditional Windows-based Always On Availability Group:

* Supported SQL Server edition/version.
* Windows Server Failover Clustering (**WSFC**) for HA availability groups.
* SQL Server instances installed on the participating servers.
* Always On Availability Groups enabled.
* Proper network connectivity between replicas.
* Database mirroring endpoint configured and started.
* Firewall rules allowing the endpoint traffic.
* Availability databases must meet AG requirements.
* Databases must use the **FULL recovery model**.
* Appropriate SQL Server/service-account permissions.
* DNS/network configuration for the AG listener if client failover connectivity is required.

Microsoft's current prerequisites documentation covers the host, WSFC, SQL Server instance, database and availability-group requirements. ([Microsoft Learn][6])

---

## 11. What is Windows Failover Clustering?

**WSFC = Windows Server Failover Clustering.**

* It is a Windows Server feature used to provide high availability.
* Multiple servers are joined into a cluster.
* Cluster resources can move between nodes when a failure occurs.
* SQL Server Always On Availability Groups use WSFC for cluster-based HA on Windows.
* WSFC provides cluster membership, health monitoring, quorum and resource management.
* SQL Server AG and WSFC are related, but they are **not the same thing**.

**Simple explanation:**

> WSFC provides the cluster foundation; Always On AG provides database-level availability and data synchronization.

([Microsoft Learn][6])

---

## 12. How do you configure a 3-node Always On environment?

Typical sequence:

1. Prepare three Windows Server nodes.
2. Join them to the appropriate domain/network.
3. Install the same supported SQL Server version/edition.
4. Configure SQL Server services and service accounts.
5. Validate WSFC.
6. Enable Always On Availability Groups on all required SQL instances.
7. Restart SQL Server services when required.
8. Create/start the database mirroring endpoint on each replica.
9. Open the endpoint port in the firewall.
10. Prepare the primary database:

    * FULL recovery model.
    * Required full backup.
    * Required log backup.
11. Create the Availability Group.
12. Add the three replicas.
13. Configure:

    * Synchronous or asynchronous commit.
    * Automatic/manual failover.
    * Readable secondary settings.
14. Initialize secondary databases:

    * Automatic seeding, or
    * Manual backup/copy/restore.
15. Join secondary databases to the AG.
16. Create the AG listener.
17. Validate synchronization.
18. Test planned and, where appropriate, unplanned failover.
19. Test application connectivity through the listener.

Microsoft's getting-started flow follows the preparation, secondary initialization/joining and listener configuration sequence. ([Microsoft Learn][7])

---

## 13. What SQL Server settings are required for Always On?

Key requirements include:

* **Always On Availability Groups enabled** on the participating SQL Server instances.
* SQL Server Database Engine running.
* Database mirroring endpoint configured and started.
* Correct endpoint authentication/security.
* Firewall/network access to the endpoint.
* Databases using **FULL recovery model**.
* Appropriate backup/initial synchronization configuration.
* Correct replica settings:

  * Availability mode
  * Failover mode
  * Seeding mode
  * Readable secondary setting where applicable.
* AG listener configuration if application connectivity/failover is required.

([Microsoft Learn][8])

---

## 14. What ports are required for Always On?

There is **no single mandatory Always On port**.

### Database mirroring/HADR endpoint

* The availability replicas communicate through the database mirroring endpoint.
* **5022** is a very commonly used example/default in Microsoft documentation.
* The actual endpoint can use another available TCP port.
* Firewall rules must allow the selected port.

### AG Listener

* The listener has its **own TCP port**.
* **1433** is commonly used as the listener port.
* A non-standard port can be configured.

### Important interview answer

> "5022 is commonly used for the HADR endpoint, but it is not a mandatory Always On port. The actual endpoint port is configurable. The AG listener also has its own configurable TCP port, commonly 1433."

([Microsoft Learn][9])

---

## 15. Why is the FULL recovery model required for Always On?

* Availability Groups depend on continuous transaction-log-based data movement.
* The secondary replica receives changes from the primary through the transaction log.
* AG databases must be in the **FULL recovery model**.
* FULL recovery supports transaction-log backups.
* The log chain is important for initialization, synchronization and recovery.
* SIMPLE recovery does not support transaction-log backups and therefore cannot be used for an AG database.

**Interview answer:**

> "FULL recovery is required because Always On Availability Groups depend on transaction-log-based data movement between replicas. FULL recovery maintains the log chain and supports log backups required by the AG."

([Microsoft Learn][10])

---

## 16. What is automatic seeding?

* Automatic seeding was introduced for Always On in SQL Server 2016.
* SQL Server automatically creates and initializes secondary database copies.
* You don't manually perform backup/copy/restore for the initial database seeding.
* It uses the availability group's database mirroring endpoint.
* The secondary must have appropriate permissions to create the database.
* It can simplify deployment of multiple AG databases.

([Microsoft Learn][10])

---

## 17. What is manual seeding?

Manual seeding means preparing the secondary database yourself.

Typical process:

1. Take a full backup on the primary.
2. Take the required transaction-log backup.
3. Copy the backup files to the secondary.
4. Restore the full backup with `NORECOVERY`.
5. Restore subsequent log backups with `NORECOVERY`.
6. Join the secondary database to the Availability Group.

**Why use it?**

* Large databases.
* Controlled initialization.
* Network bandwidth limitations.
* Environments where automatic seeding isn't desirable.

Microsoft's AG setup documentation explicitly supports manually preparing secondary databases before joining them to the AG. ([Microsoft Learn][7])

---

## 18. What is the difference between Enterprise and Standard Edition Always On?

This question needs a careful answer.

### Enterprise Edition

Supports the full/advanced Availability Group feature set, including capabilities such as:

* Multiple secondary replicas.
* Readable secondary replicas.
* Secondary backup support.
* Advanced AG capabilities.

### Standard Edition

Supports **Basic Availability Groups** with important limitations.

Current Microsoft documentation lists limitations including:

* One availability database.
* Two replicas: primary + secondary.
* No read access on the secondary.
* No backups on the secondary.
* No integrity checks on secondary replicas.
* Basic AG cannot be part of a distributed AG.

So don't simply say:

> "Standard doesn't support Always On."

That is **incorrect**.

The accurate answer is:

> "Standard Edition supports Basic Availability Groups, but Enterprise Edition provides the advanced Availability Group feature set."

([Microsoft Learn][11])

---

## 19. How do you check whether an Always On database is synchronized?

You can use:

### SSMS

* Always On Availability Groups
* Availability Group Dashboard
* Check:

  * Synchronization state
  * Synchronization health
  * Replica role
  * Log send queue
  * Redo queue
  * Database state.

### T-SQL

For database-level state:

```sql
SELECT
    DB_NAME(drs.database_id) AS DatabaseName,
    ars.role_desc,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.log_send_queue_size,
    drs.redo_queue_size
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.dm_hadr_availability_replica_states ars
    ON drs.replica_id = ars.replica_id;
```

Important states include:

* `SYNCHRONIZED`
* `SYNCHRONIZING`
* `NOT SYNCHRONIZING`
* `REVERTING`
* `INITIALIZING`

Microsoft provides dedicated Always On DMVs for replica and synchronization state monitoring. ([Microsoft Learn][12])

---

# T-SQL and Performance

## 20. How good are you at T-SQL?

**Interview answer:**

> "I am strong in T-SQL. I use it regularly for database administration, troubleshooting, performance tuning and automation."

Areas I would mention:

* Complex SELECT queries
* Joins
* CTEs
* Window functions
* Temporary tables
* Table variables
* Stored procedures
* Functions
* Dynamic SQL
* Error handling
* Transactions
* DMVs
* Backup/restore scripts
* Always On monitoring
* Blocking/deadlock analysis
* Index/statistics analysis
* SQL Agent automation
* Performance troubleshooting.

---

## 21. How do you troubleshoot a slow-running query?

I follow a structured approach:

1. Confirm the query is actually slow.
2. Check execution duration and resource consumption.
3. Capture the **Actual Execution Plan**.
4. Check:

   * CPU
   * Logical reads
   * Physical reads
   * Memory grants
   * Waits
5. Check estimated vs actual row counts.
6. Look for:

   * Table scans
   * Index scans
   * Expensive joins
   * Key lookups
   * Sorts
   * Spills
7. Check statistics.
8. Check indexes.
9. Check blocking.
10. Check parameter sensitivity/sniffing.
11. Check plan regression.
12. Check Query Store.
13. Compare the current plan with a previously good plan.
14. Make the smallest appropriate change.
15. Validate before/after performance.

Execution plans show how the Query Optimizer intends to execute the query, while Query Store provides historical query and plan information. ([Microsoft Learn][13])

---

## 22. What would you check if a query suddenly became slow?

I would focus on **what changed**.

* Did the execution plan change?
* Did statistics change?
* Did data volume/distribution change?
* Is the query blocked?
* Are there new blocking/deadlocks?
* Did an index change?
* Was an index dropped or disabled?
* Is there parameter sensitivity/sniffing?
* Did memory pressure increase?
* Did CPU increase?
* Did I/O latency increase?
* Did TempDB become a bottleneck?
* Did the database compatibility level change?
* Was SQL Server patched/upgraded?
* Did Query Store show plan regression?
* Are waits different from the normal baseline?

**Key point:**

> For a query that was fast yesterday and slow today, I first investigate regression/change rather than immediately rebuilding indexes.

Query Store is specifically designed to help identify plan regressions and historical performance changes. ([Microsoft Learn][14])

---

## 23. How do you check whether statistics are updated?

Use `STATS_DATE()`.

Example:

```sql
SELECT
    OBJECT_SCHEMA_NAME(s.object_id) AS SchemaName,
    OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatisticsName,
    STATS_DATE(s.object_id, s.stats_id) AS LastUpdated
FROM sys.stats AS s
WHERE s.object_id = OBJECT_ID('dbo.Customer');
```

You can also use:

```sql
DBCC SHOW_STATISTICS ('dbo.Customer', 'StatisticsName');
```

Check:

* Last updated date
* Rows
* Rows sampled
* Density
* Histogram
* Modification information where available.

`STATS_DATE()` returns the most recent update date for a statistics object. SQL Server can also automatically update statistics when the optimizer determines an update is needed. ([Microsoft Learn][15])

---

## 24. How do you check index fragmentation?

Use:

```sql
SELECT
    DB_NAME(database_id) AS DatabaseName,
    OBJECT_SCHEMA_NAME(object_id, database_id) AS SchemaName,
    OBJECT_NAME(object_id, database_id) AS TableName,
    index_id,
    avg_fragmentation_in_percent,
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

Look at:

* `avg_fragmentation_in_percent`
* `page_count`
* Index type
* Workload.

**Important:**

Do not blindly rebuild every index based only on a percentage.

Microsoft recommends evaluating fragmentation and page density together with workload and maintenance cost. ([Microsoft Learn][16])

---

## 25. What is an execution plan?

* An execution plan describes **how SQL Server's Query Optimizer plans to execute a query**.
* It contains logical and physical operators.
* Examples:

  * Index Seek
  * Index Scan
  * Table Scan
  * Nested Loops
  * Hash Match
  * Merge Join
  * Sort
  * Key Lookup
* Each operator has properties and estimated/actual execution information.

**Simple answer:**

> "An execution plan is SQL Server's roadmap for executing a query."

([Microsoft Learn][13])

---

## 26. What is the difference between Estimated and Actual Execution Plan?

### Estimated Execution Plan

* Generated without actually executing the query.
* Shows what SQL Server **expects** to happen.
* Uses optimizer estimates.

### Actual Execution Plan

* Generated after the query executes.
* Contains actual execution information.
* Allows comparison between:

  * Estimated rows
  * Actual rows
  * Estimated cost
  * Actual runtime-related information.

**Why important?**

A major difference between estimated and actual rows can indicate:

* Outdated statistics
* Data distribution problems
* Cardinality-estimation issues
* Parameter sensitivity
* Other optimizer estimation problems.

Microsoft's execution-plan documentation describes both estimated and runtime execution-plan concepts. ([Microsoft Learn][13])

---

## 27. What is an Index Seek?

* An Index Seek means SQL Server navigates an index to find qualifying rows/ranges.
* It normally accesses a targeted portion of the index.
* It is often efficient for selective predicates.
* It does **not automatically mean the query is fast**.
* A seek can still process many rows or perform expensive downstream operations.

**Interview answer:**

> "An Index Seek navigates an index to locate the qualifying key range instead of scanning the entire index."

---

## 28. What is an Index Scan?

* An Index Scan reads through many or all pages of an index.
* It can be appropriate when:

  * A large percentage of rows is required.
  * The query needs most of the table.
  * No useful selective access path exists.
* An Index Scan is **not automatically bad**.
* The correct operator depends on the query and data distribution.

Microsoft's execution-plan operator documentation explains how physical operators access tables and indexes. ([Microsoft Learn][17])

---

## 29. What is parameter sniffing?

* During compilation of a parameterized query, SQL Server can use the parameter values available at compilation to optimize the plan.
* The resulting plan may then be reused for later executions.
* If data distribution is highly skewed, one plan may not be optimal for every parameter value.
* This is commonly called **parameter sniffing** or, more broadly, parameter sensitivity.

Example:

```sql
EXEC dbo.GetCustomerOrders @CustomerID = 1;
```

If customer 1 has 10 rows but customer 2 has 10 million rows, the best plan may be very different.

Modern SQL Server also has **Parameter Sensitive Plan Optimization (PSP)** to address certain parameter-sensitive scenarios. ([Microsoft Learn][18])

---

## 30. How can you identify parameter sniffing?

I would:

1. Compare the same query with different parameter values.
2. Compare estimated and actual row counts.
3. Check the cached execution plan.
4. Look for a plan that works well for one parameter but poorly for another.
5. Check Query Store for:

   * Multiple plans
   * Runtime differences
   * Plan changes
6. Check whether performance improves when using:

   * `OPTION (RECOMPILE)`
   * Local variables
   * `OPTIMIZE FOR`
   * Another controlled test method.

**Important:** Don't declare parameter sniffing just because a query has parameters. You need evidence of parameter-dependent plan behavior.

Modern SQL Server provides PSP optimization for supported parameter-sensitive scenarios. ([Microsoft Learn][18])

---

## 31. How can you resolve parameter sniffing?

There is no single universal fix.

Possible approaches include:

* Improve indexes.
* Update statistics where appropriate.
* `OPTION (RECOMPILE)` for suitable queries.
* `OPTIMIZE FOR` hints when justified.
* Query/application redesign.
* Query Store plan forcing when appropriate.
* Parameter Sensitive Plan Optimization where supported.
* SQL Server 2025 also includes additional intelligent query-processing capabilities.

**Do not immediately use `WITH RECOMPILE` everywhere.**

Understand why the plan is bad first.

([Microsoft Learn][18])

---

# Query Store

## 32. What is Query Store?

* Query Store is a SQL Server feature for collecting query performance information over time.
* It stores information such as:

  * Query text
  * Query IDs
  * Execution plans
  * Runtime statistics
  * Compilation/runtime history.
* It allows DBAs to analyze performance over time.
* It can help identify plan regressions.
* It can also support plan forcing and Query Store hints.

**Simple answer:**

> "Query Store gives me historical visibility into query performance and execution plans."

([Microsoft Learn][19])

---

## 33. How does Query Store help in performance troubleshooting?

I use Query Store to:

* Find top CPU-consuming queries.
* Find high-duration queries.
* Find high-I/O queries.
* Compare query performance over time.
* Identify execution-plan changes.
* Identify plan regressions.
* Compare multiple plans for the same query.
* Force a known good plan where appropriate.
* Analyze performance after deployments/upgrades.
* Investigate performance issues even after the problematic query is no longer running.

Query Store specifically maintains historical compilation/runtime information and supports plan-regression analysis. ([Microsoft Learn][20])

---

# Indexes

## 34. What is a clustered index?

* A clustered index determines how the table's data rows are physically organized by the clustered key.
* The leaf level contains the table data.
* A table can have **only one clustered index**.
* The clustered index key is also present in nonclustered indexes as the row locator when appropriate.
* Choosing the clustered key should consider:

  * Query patterns
  * Uniqueness
  * Stability
  * Size
  * Insert/update behavior.

([Microsoft Learn][21])

---

## 35. What is a nonclustered index?

* A nonclustered index is a separate index structure from the underlying table data.
* It contains index key columns and row-location information.
* A table can have multiple nonclustered indexes.
* Nonclustered indexes can contain **included/non-key columns**.
* They can significantly improve selective queries when designed correctly.

([Microsoft Learn][22])

---

## 36. What is the difference between clustered and nonclustered indexes?

| Feature           | Clustered                  | Nonclustered                     |
| ----------------- | -------------------------- | -------------------------------- |
| Number per table  | 1                          | Multiple                         |
| Data rows         | Stored at leaf level       | Separate index structure         |
| Main purpose      | Organizes table data       | Provides additional access paths |
| Key               | Clustered key              | Nonclustered key                 |
| Included columns  | Not applicable in same way | Supported                        |
| Can cover queries | Yes                        | Yes                              |

**Interview answer:**

> "A clustered index determines the physical organization of the table's data, so there can be only one. A nonclustered index is a separate structure and multiple nonclustered indexes can exist on the same table."

([Microsoft Learn][21])

---

## 37. What is a Key Lookup?

* A Key Lookup occurs when SQL Server uses a nonclustered index to locate rows but needs additional columns from the clustered table.
* SQL Server then performs a lookup into the clustered index.
* It is normally associated with a **Nested Loops** operator.
* A small number of lookups may be perfectly acceptable.
* A large number of repeated lookups can become expensive.

([Microsoft Learn][17])

---

## 38. Why does a Key Lookup occur?

Typically:

* The nonclustered index satisfies the filtering/search condition.
* But the index doesn't contain all columns required by the query.
* SQL Server therefore goes back to the clustered index to retrieve missing columns.

Example:

```sql
SELECT CustomerID, Name, City
FROM dbo.Customer
WHERE CustomerID = 100;
```

If the nonclustered index can find `CustomerID` but doesn't contain `Name` and `City`, SQL Server may perform Key Lookups.

([Microsoft Learn][23])

---

## 39. How can you resolve a Key Lookup?

Possible solutions:

1. Determine whether the lookup is actually expensive.
2. Check how many times it executes.
3. Consider a covering nonclustered index.
4. Add required columns using `INCLUDE`.
5. Avoid adding unnecessary columns.
6. Consider whether the query itself can be improved.
7. Recheck the execution plan after the change.

Example:

```sql
CREATE INDEX IX_Customer_CustomerID
ON dbo.Customer(CustomerID)
INCLUDE (Name, City);
```

Now SQL Server may obtain all required columns directly from the nonclustered index.

([Microsoft Learn][23])

---

## 40. What are leaf pages in an index?

* The **leaf level** is the lowest level of a B-tree index.
* In a clustered index, the leaf level contains the table's data rows.
* In a nonclustered index, the leaf level contains the nonclustered index entries plus included columns and row-location information as applicable.
* Queries ultimately retrieve required information through the index's leaf level.

([Microsoft Learn][21])

---

## 41. What is an INCLUDE column?

* An INCLUDE column is a **non-key column** stored at the leaf level of a nonclustered index.
* It is not part of the index key.
* It is used mainly to make an index **covering** for a query.
* Included columns don't count toward the index key column/key-size limits in the same way as key columns.

Example:

```sql
CREATE INDEX IX_Orders_CustomerID
ON dbo.Orders(CustomerID)
INCLUDE (OrderDate, Amount);
```

([Microsoft Learn][23])

---

## 42. Why do we use INCLUDE columns in a nonclustered index?

Main reason:

**To cover a query and avoid extra lookups.**

For example:

```sql
SELECT CustomerID, OrderDate, Amount
FROM dbo.Orders
WHERE CustomerID = 100;
```

An index such as:

```sql
CREATE INDEX IX_Orders_CustomerID
ON dbo.Orders(CustomerID)
INCLUDE (OrderDate, Amount);
```

may allow SQL Server to get all required values directly from the index.

Benefits:

* Avoid Key Lookup.
* Reduce I/O.
* Potentially improve query performance.

But don't create excessively wide indexes because they increase storage and maintenance costs.

([Microsoft Learn][23])

---

# DELETE / TRUNCATE

## 43. What is the difference between DELETE and TRUNCATE?

| Feature                              | DELETE             | TRUNCATE                       |
| ------------------------------------ | ------------------ | ------------------------------ |
| Type                                 | DML                | DDL-like operation             |
| WHERE clause                         | Yes                | No                             |
| Removes selected rows                | Yes                | No — all rows                  |
| Logging                              | Logs row deletions | Logs page/extent deallocations |
| Usually faster for removing all rows | No                 | Yes                            |
| Identity reset                       | No                 | Yes                            |
| DELETE triggers                      | Fire               | Don't fire DELETE triggers     |
| Foreign-key restrictions             | More flexible      | More restrictive               |
| Table structure                      | Remains            | Remains                        |

Important correction:

> `TRUNCATE TABLE` is **logged**. It simply logs much less information than deleting every row individually because it deallocates data pages/extents.

([Microsoft Learn][24])

---

## 44. What happens when you TRUNCATE a table?

When you run:

```sql
TRUNCATE TABLE dbo.Customer;
```

SQL Server:

* Removes all rows.
* Deallocates the data pages used by the table/indexes.
* Generates much less transaction-log activity than deleting rows individually.
* Keeps the table structure.
* Keeps indexes/constraints definitions.
* Resets the identity counter to its seed behavior.
* Does not execute DELETE triggers.
* Requires appropriate permissions and is subject to restrictions such as foreign-key references.

([Microsoft Learn][24])

---

## 45. Does TRUNCATE reset the IDENTITY value?

**Yes.**

Example:

```sql
CREATE TABLE Test
(
    ID INT IDENTITY(1,1),
    Name VARCHAR(100)
);
```

After:

```sql
TRUNCATE TABLE Test;
```

the next inserted row starts from the identity seed.

Example:

```text
Before TRUNCATE:
1
2
3
4
5

TRUNCATE

Next row:
1
```

This is one of the important differences between `DELETE` and `TRUNCATE`.

If you use `DELETE`, the identity value is **not automatically reset**.

([Microsoft Learn][24])

---

## 46. If you need to delete 10 million rows, would you use DELETE or TRUNCATE? Why?

The correct answer is:

### If I need to remove ALL rows

I would consider:

```sql
TRUNCATE TABLE dbo.TableName;
```

if:

* All rows need to be removed.
* There are no blocking FK restrictions.
* DELETE triggers/auditing aren't required.
* The application/business requirements allow it.

### If I need to remove only some rows

For example:

```sql
DELETE FROM dbo.TableName
WHERE CreatedDate < '2020-01-01';
```

I would use `DELETE`.

For very large deletes, I would usually consider **batching**:

```sql
DELETE TOP (10000)
FROM dbo.TableName
WHERE CreatedDate < '2020-01-01';
```

and repeat until complete.

**Interview answer:**

> "If all 10 million rows need to be removed and TRUNCATE is allowed, I would use TRUNCATE because it deallocates pages and generates much less log activity. If only a subset needs to be deleted, I must use DELETE, and for a very large delete I would normally batch it to control transaction-log growth, blocking and transaction duration."

([Microsoft Learn][24])

---

# Recovery Models

## 47. What are the three recovery models in SQL Server?

SQL Server has:

1. **Simple**
2. **Full**
3. **Bulk-logged**

([Microsoft Learn][25])

---

## 48. What is the difference between Full, Simple and Bulk-logged recovery models?

### Simple

* No transaction-log backups.
* SQL Server automatically reuses inactive log space.
* Point-in-time recovery isn't supported.
* Cannot be used for Always On Availability Groups.
* Suitable where the required RPO does not require transaction-log recovery.

### Full

* Supports transaction-log backups.
* Supports point-in-time recovery.
* Provides the strongest recovery capability.
* Requires a proper log-backup strategy.
* Required for Availability Groups.

### Bulk-logged

* Similar to FULL for log backup management.
* Supports transaction-log backups.
* Allows certain operations to be minimally logged.
* Can reduce transaction-log usage during qualifying bulk operations.
* Point-in-time recovery has restrictions when minimally logged operations are involved.

| Feature                                        | Simple          | Full                   | Bulk-logged                   |
| ---------------------------------------------- | --------------- | ---------------------- | ----------------------------- |
| Log backups                                    | ❌               | ✅                      | ✅                             |
| Point-in-time recovery                         | ❌               | ✅                      | Restricted                    |
| AG supported                                   | ❌               | ✅                      | Not the normal AG requirement |
| Minimal logging for qualifying bulk operations | ✅               | ❌ for those operations | ✅                             |
| Log management                                 | Automatic reuse | Log backups required   | Log backups required          |

([Microsoft Learn][25])

---

# Production Recovery

## 49. Why is Full recovery used for production databases?

The technically correct answer is **not**:

> "All production databases must use FULL recovery."

That statement is too broad.

The correct answer is:

* FULL recovery is used when the business requires:

  * Point-in-time recovery.
  * Low data-loss exposure.
  * Transaction-log backups.
  * More precise recovery points.
* It is also required for technologies such as **Always On Availability Groups**.
* It supports a continuous transaction-log backup chain.
* It allows recovery to a specific point in time, assuming the required backup chain is intact.
* It requires regular transaction-log backups.
* If log backups are not taken, the transaction log can continue to grow.

**Strong interview answer:**

> "FULL recovery is commonly used for production databases when the business requires point-in-time recovery and a low RPO. It allows transaction-log backups and more granular recovery. However, FULL isn't automatically required just because a database is production; the recovery model should be selected based on the business RPO/RTO and HA/DR requirements. For example, Always On Availability Groups require FULL recovery."

([Microsoft Learn][25])

---

# ⭐ Important Interview Corrections

There are several places where the original question list can lead to **incorrect L1 answers**. I recommend remembering these specifically:

| Question | Don't say                                         | Say instead                                                                                 |
| -------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| 9        | Always On = Availability Groups only              | Always On is an umbrella term covering AG and FCI                                           |
| 14       | Always On always uses port 5022                   | 5022 is commonly used for the HADR endpoint; the port is configurable                       |
| 15       | FULL is required because AG is HA                 | AG requires FULL because it relies on transaction-log-based data movement                   |
| 18       | Standard doesn't support Always On                | Standard supports **Basic Availability Groups**, with major limitations                     |
| 24       | Rebuild everything above 30%                      | Evaluate fragmentation, page density, workload and maintenance cost                         |
| 26       | Estimated and actual plans are basically the same | Estimated = before execution; Actual = includes runtime information                         |
| 28       | Index Scan is always bad                          | A scan can be the correct plan depending on selectivity/workload                            |
| 29       | Parameter sniffing is always a problem            | It becomes a problem when a reused plan isn't suitable for other parameter values           |
| 31       | Always use RECOMPILE                              | Choose the fix based on root cause                                                          |
| 43       | TRUNCATE is not logged                            | TRUNCATE is logged, but logs page/extent deallocations rather than individual row deletions |
| 45       | DELETE resets identity                            | **TRUNCATE resets identity; DELETE does not**                                               |
| 46       | Always use TRUNCATE for millions of rows          | TRUNCATE only when all rows can be removed and restrictions permit it                       |
| 49       | Every production DB must use FULL                 | Recovery model depends on RPO/RTO and HA/DR requirements                                    |

### Official documentation set

For your interview preparation, these Microsoft Learn areas are the most useful:

* [Always On Availability Groups overview](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server?view=sql-server-ver17)
* [Always On prerequisites](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/prereqs-restrictions-recommendations-always-on-availability?view=sql-server-ver17)
* [Always On automatic seeding](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/automatically-initialize-always-on-availability-group?view=sql-server-ver17)
* [Always On listener](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-group-listener-overview?view=sql-server-ver17)
* [Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store?view=sql-server-ver17)
* [Execution plans](https://learn.microsoft.com/en-us/sql/relational-databases/performance/execution-plans?view=sql-server-ver17)
* [Clustered and nonclustered indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described?view=sql-server-ver17)
* [Included columns](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-indexes-with-included-columns?view=sql-server-ver17)
* [Index fragmentation and maintenance](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/reorganize-and-rebuild-indexes?view=sql-server-ver17)
* [Recovery models](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver17)
* [TRUNCATE TABLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/truncate-table-transact-sql?view=sql-server-ver17)

For MongoDB questions:

* [MongoDB Databases and Collections](https://www.mongodb.com/docs/manual/core/databases-and-collections/?utm_source=chatgpt.com)
* [MongoDB SQL-to-MongoDB mapping](https://www.mongodb.com/docs/v8.0/reference/sql-comparison/?utm_source=chatgpt.com)
* [MongoDB mongodump](https://www.mongodb.com/docs/database-tools/mongodump/?utm_source=chatgpt.com)
* [MongoDB createUser](https://www.mongodb.com/docs/manual/reference/method/db.createUser/?utm_source=chatgpt.com)

[1]: https://www.mongodb.com/docs/v7.0/core/databases-and-collections/?utm_source=chatgpt.com "Databases and Collections in MongoDB - Database Manual v7.0 - MongoDB Docs"
[2]: https://www.mongodb.com/docs/v8.0/reference/sql-comparison/?utm_source=chatgpt.com "SQL to MongoDB Mapping Chart - Database Manual v8.0 - MongoDB Docs"
[3]: https://www.mongodb.com/docs/database-tools/mongodump/mongodump-examples/?utm_source=chatgpt.com "mongodump Examples - Database Tools - MongoDB Docs"
[4]: https://www.mongodb.com/docs/manual/reference/method/db.createUser?utm_source=chatgpt.com "Database Manual - MongoDB Docs"
[5]: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server?view=sql-server-ver17 "What is an Always On Availability Group? - SQL Server Always On | Microsoft Learn"
[6]: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/prereqs-restrictions-recommendations-always-on-availability?view=sql-server-ver17 "Availability Group: Prerequisites, Restrictions, and ..."
[7]: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/getting-started-with-always-on-availability-groups-sql-server?view=sql-server-ver17 "Getting Started with availability groups - SQL Server Always On | Microsoft Learn"
[8]: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/enable-and-disable-always-on-availability-groups-sql-server?view=sql-server-ver17 "Enable or disable the Always On availability group feature"
[9]: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/configure-distributed-availability-groups?view=sql-server-ver17 "Configure a distributed Always On availability group"
[10]: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/automatically-initialize-always-on-availability-group?view=sql-server-ver17 "Initialize an availability group using automatic seeding"
[11]: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/basic-availability-groups-always-on-availability-groups?view=sql-server-ver17 "Basic Always On availability groups for a single database"
[12]: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-hadr-availability-replica-states-transact-sql?view=azuresqldb-current "sys.dm_hadr_availability_replica_states (Transact-SQL)"
[13]: https://learn.microsoft.com/en-us/sql/relational-databases/performance/execution-plans?view=sql-server-ver17 "Execution Plan Overview - SQL Server"
[14]: https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store?view=sql-server-ver17 "Monitor Performance by Using the Query Store - SQL Server | Microsoft Learn"
[15]: https://learn.microsoft.com/en-us/sql/t-sql/functions/stats-date-transact-sql?view=sql-server-ver17 "STATS_DATE (Transact-SQL) - SQL Server | Microsoft Learn"
[16]: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-objects/sys-dm-db-index-physical-stats-transact-sql?view=sql-server-ver17 "sys.dm_db_index_physical_stats (Transact-SQL) - SQL Server | Microsoft Learn"
[17]: https://learn.microsoft.com/en-us/sql/relational-databases/showplan-logical-and-physical-operators-reference?view=sql-server-ver17 "Logical and Physical Showplan Operator Reference - SQL Server | Microsoft Learn"
[18]: https://learn.microsoft.com/en-us/sql/relational-databases/performance/parameter-sensitive-plan-optimization?view=sql-server-ver17 "Parameter Sensitive Plan Optimization - SQL Server"
[19]: https://learn.microsoft.com/en-us/sql/relational-databases/performance/manage-the-query-store?view=sql-server-ver17 "Best practices for managing the Query Store - SQL Server | Microsoft Learn"
[20]: https://learn.microsoft.com/en-us/sql/relational-databases/performance/tune-performance-with-the-query-store?view=sql-server-ver17 "Tune performance with the Query Store - SQL Server | Microsoft Learn"
[21]: https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described?view=sql-server-ver17 "Clustered and Nonclustered Indexes - SQL Server"
[22]: https://learn.microsoft.com/en-us/sql/relational-databases/indexes/indexes?view=sql-server-ver17 "Indexes - SQL Server | Microsoft Learn"
[23]: https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-indexes-with-included-columns?view=sql-server-ver17 "Create Indexes with Included Columns - SQL Server | Microsoft Learn"
[24]: https://learn.microsoft.com/en-us/sql/t-sql/statements/truncate-table-transact-sql?view=sql-server-ver17 "TRUNCATE TABLE (Transact-SQL) - SQL Server"
[25]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver17 "Recovery Models (SQL Server) - SQL Server | Microsoft Learn"
