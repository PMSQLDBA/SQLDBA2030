The best way to learn **SQL Server recovery models** is not just to memorize *Simple / Full / Bulk-logged*, but to understand how they control the **transaction log, backups, restore options, RPO/RTO, and real production recovery scenarios**.

The explanation below follows Microsoft SQL Server documentation and is structured from **beginner → intermediate → advanced DBA level**. ([Microsoft Learn][1])

---

# SQL Server Recovery Models — End-to-End DBA Guide

## 1. What is a Recovery Model?

A **recovery model is a database-level setting** that controls:

* How transactions are logged.
* Whether transaction-log backups are supported.
* How the transaction log is managed.
* What type of recovery is possible.
* Whether point-in-time recovery is available.
* How much data can potentially be lost during a failure.
* Which SQL Server high-availability/disaster-recovery features can be used.

SQL Server has **three recovery models**:

| Recovery Model  | Log Backups | Point-in-Time Recovery | Typical Usage                                |
| --------------- | ----------: | ---------------------: | -------------------------------------------- |
| **Simple**      |        ❌ No |                   ❌ No | Dev/test, staging, non-critical databases    |
| **Full**        |       ✅ Yes |                  ✅ Yes | Production OLTP, financial, critical systems |
| **Bulk-logged** |       ✅ Yes |             ⚠️ Limited | Temporary high-volume bulk operations        |

Microsoft describes recovery models as a database property that controls transaction-log maintenance and available restore operations. ([Microsoft Learn][1])

---

# 2. First Understand the Transaction Log

Before understanding recovery models, you need to understand the **SQL Server transaction log**.

Imagine:

```text
Application
     |
     v
SQL Server
     |
     +----------------+
     | Transaction Log|
     +----------------+
             |
             v
        Data Files
        MDF / NDF
```

When SQL Server modifies data, it writes information to the transaction log.

For example:

```sql
UPDATE dbo.Customer
SET Balance = Balance - 100
WHERE CustomerID = 1001;
```

SQL Server records the required transaction information in the log.

The transaction log is critical because SQL Server uses it for:

* Transaction rollback
* Crash recovery
* Database recovery
* Transaction-log backups
* Point-in-time recovery
* Availability features such as Always On availability groups

---

# 3. The Three Recovery Models

## Simple

```text
Transactions
     |
     v
Transaction Log
     |
     v
Automatic log-space reuse
```

SQL Server automatically reuses inactive log space.

But:

> **You cannot take transaction-log backups in Simple recovery.**

Therefore, you cannot restore the database to an arbitrary point in time.

Microsoft specifically states that Simple recovery doesn't support transaction-log backups, point-in-time restores, log shipping, or Always On availability groups/database mirroring. ([Microsoft Learn][1])

---

# 4. Full Recovery Model

Full recovery is the model most important for a production DBA.

```text
Transaction
     |
     v
Transaction Log
     |
     +----> Log Backup 1
     |
     +----> Log Backup 2
     |
     +----> Log Backup 3
     |
     +----> Log Backup 4
```

The transaction log continues to grow until log backups are performed.

Microsoft states that Full recovery requires transaction-log backups. ([Microsoft Learn][1])

### Main advantage

You can recover to:

```text
10:00 AM
10:05 AM
10:07 AM
10:07:32 AM
10:07:45 AM
```

provided you have the required backup chain.

---

# 5. Bulk-Logged Recovery Model

Bulk-logged is essentially a variation of Full recovery designed for certain **high-volume operations**.

It allows certain operations to be **minimally logged**.

Examples include certain:

* `BULK INSERT`
* `SELECT INTO`
* Bulk copy operations
* Some index operations

Microsoft explains that minimal logging records only information needed to recover the operation, rather than fully logging every modification. ([Microsoft Learn][2])

---

# 6. Main Comparison

This is the table you should remember for interviews.

| Feature                       |    Simple |                               Full |                                                    Bulk-Logged |
| ----------------------------- | --------: | ---------------------------------: | -------------------------------------------------------------: |
| Transaction log backup        |         ❌ |                                  ✅ |                                                              ✅ |
| Point-in-time recovery        |         ❌ |                                  ✅ | ⚠️ Not when required bulk-logged changes are in the log backup |
| Log shipping                  |         ❌ |                                  ✅ |                                                              ✅ |
| Always On AG                  |         ❌ |                                  ✅ |                                                              ✅ |
| Minimal logging               |         ✅ |              ❌ for bulk operations |                                                              ✅ |
| Log management complexity     |       Low |                               High |                                                           High |
| Potential work loss           |    Higher |                             Lowest |                                       Depends on bulk activity |
| Suitable for critical OLTP    | Usually ❌ |                                  ✅ |                                              Usually temporary |
| Suitable for large bulk loads |   Limited | Possible but potentially large log |                                                              ✅ |
| Log backups required          |         ❌ |                                  ✅ |                                                              ✅ |

Microsoft's recovery-model comparison specifically identifies Simple as unable to perform point-in-time recovery and Full as supporting arbitrary point-in-time recovery. 

Bulk-logged can have limitations when a log backup contains minimally logged operations. ([Microsoft Learn][1])

---

# 7. What Does RPO Mean?

**RPO = Recovery Point Objective**

It answers:

> "How much data can the business afford to lose?"

Example:

```text
Failure:       10:30 AM

Last backup:   10:00 AM
```

Potential data loss:

```text
10:00 → 10:30
```

That means your RPO could be up to **30 minutes**.

---

# 8. Recovery Model vs RPO

| Recovery Model | Typical Data-Loss Exposure                         |
| -------------- | -------------------------------------------------- |
| Simple         | Changes since latest backup may be lost            |
| Full           | Can normally minimize work loss significantly      |
| Bulk-logged    | Depends on whether bulk-logged operations occurred |

Microsoft's documentation explicitly connects recovery models with RPO/work-loss exposure. ([Microsoft Learn][1])

---

# 9. What Does RTO Mean?

**RTO = Recovery Time Objective**

It answers:

> "How quickly must the application be restored?"

Example:

```text
Database failure
      |
      v
Restore starts
      |
      v
Database available
```

If business says:

> "Database must be available within 30 minutes."

Then:

```text
RTO = 30 minutes
```

---

# 10. RPO vs RTO

| Requirement | Meaning                      | Example    |
| ----------- | ---------------------------- | ---------- |
| RPO         | Maximum acceptable data loss | 5 minutes  |
| RTO         | Maximum acceptable downtime  | 30 minutes |

A DBA should never select a recovery model without understanding these business requirements.

---

# 11. Simple Recovery — Detailed

Simple recovery is designed to simplify transaction-log management.

Example:

```sql
ALTER DATABASE SalesDB
SET RECOVERY SIMPLE;
```

Check:

```sql
SELECT
    name,
    recovery_model_desc
FROM sys.databases
WHERE name = 'SalesDB';
```

Expected:

```text
SalesDB    SIMPLE
```

---

# 12. How Simple Recovery Behaves

Suppose:

```text
08:00 Full backup

08:10 INSERT
08:20 UPDATE
08:30 DELETE
08:40 UPDATE

09:00 Server failure
```

If your latest full/differential backup only contains data through 08:00 or 08:30, you cannot restore individual log backups to 08:55 because Simple recovery does not support log backups.

Microsoft explicitly states that Simple recovery can recover only to the end of a backup, rather than to an arbitrary point in time. ([Microsoft Learn][1])

---

# 13. Real-Time Simple Recovery Use Case

Imagine a development database:

```text
DEV-SQL01
    |
    +-- AdventureWorks2025
```

Developers can recreate the database if necessary.

Business requirement:

```text
RPO = 24 hours
RTO = several hours
```

You might use:

```text
SIMPLE
```

with:

```text
Daily Full Backup
```

This keeps backup administration simple.

---

# 14. Advantages of Simple

| Advantage                     | Explanation                                  |
| ----------------------------- | -------------------------------------------- |
| Easy administration           | No log-backup schedule                       |
| Automatic log-space reuse     | SQL Server manages inactive log space        |
| Lower backup complexity       | Full/differential strategy can be sufficient |
| Good for disposable databases | Dev/test environments                        |
| Reduced operational overhead  | Fewer backup jobs                            |

---

# 15. Disadvantages of Simple

| Disadvantage                                        | Impact                                 |
| --------------------------------------------------- | -------------------------------------- |
| No log backups                                      | Cannot restore transaction log backups |
| No point-in-time recovery                           | Cannot recover to 10:31:45 AM          |
| Higher possible data loss                           | Depends on last available backup       |
| Not suitable for many critical production workloads | Recovery granularity is limited        |
| Not supported for Log Shipping                      | DR architecture limitation             |
| Not supported for Always On AG                      | HA/DR limitation                       |

These limitations are documented by Microsoft. ([Microsoft Learn][1])

---

# 16. Full Recovery — Detailed

Set it:

```sql
ALTER DATABASE SalesDB
SET RECOVERY FULL;
```

But there is an important DBA rule:

> **Changing the database from Simple to Full does not by itself establish the usable log-backup chain.**

After switching from Simple to Full, take a full or differential database backup to start the log chain. ([Microsoft Learn][3])

Example:

```sql
ALTER DATABASE SalesDB
SET RECOVERY FULL;
GO

BACKUP DATABASE SalesDB
TO DISK = 'D:\SQLBackups\SalesDB_FULL.bak'
WITH INIT, COMPRESSION;
GO
```

Then:

```sql
BACKUP LOG SalesDB
TO DISK = 'D:\SQLBackups\SalesDB_LOG_001.trn'
WITH COMPRESSION;
```

---

# 17. Typical Production Backup Strategy

A common production pattern could look like:

```text
Sunday
   |
   +-- Full Backup

Monday
   |
   +-- Differential
   +-- Log
   +-- Log
   +-- Log

Tuesday
   |
   +-- Differential
   +-- Log
   +-- Log
   +-- Log
```

For example:

| Backup          | Frequency          |
| --------------- | ------------------ |
| Full            | Weekly             |
| Differential    | Daily              |
| Transaction Log | Every 5–15 minutes |

**Important:** The exact schedule must be based on the application's RPO, transaction volume, backup infrastructure, and recovery testing—not a universal "best" interval.

Microsoft recommends frequent log backups for Full/Bulk-logged databases to reduce work-loss exposure and help truncate inactive log space. ([Microsoft Learn][4])

---

# 18. Why Does the Transaction Log Keep Growing?

This is one of the most important DBA interview questions.

Suppose:

```text
Recovery Model = FULL
```

and:

```text
Full backup = Sunday
Log backup = NEVER
```

Transactions continue:

```text
Monday
Tuesday
Wednesday
Thursday
Friday
```

The log can continue growing because log backups are not occurring.

Microsoft explicitly states that under Full and Bulk-logged recovery, the transaction log continues to grow until a transaction-log backup is performed. ([Microsoft Learn][1])

---

# 19. Important: Log Truncation ≠ Shrinking

These two are completely different.

### Log truncation

Makes inactive portions of the log available for reuse.

### Shrink

Reduces the physical `.ldf` file size.

Example:

```text
Before:

LDF = 500 GB
Active = 50 GB
Inactive = 450 GB
```

A successful log backup may allow the inactive portion to be reused.

It does **not necessarily mean**:

```text
LDF automatically becomes 50 GB
```

Shrinking is a separate physical file operation and should not be used as routine log-space management.

---

# 20. Why Is My Full Recovery Log Not Truncating?

This is a classic production DBA problem.

Check:

```sql
SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc
FROM sys.databases
WHERE name = 'SalesDB';
```

Possible values include things such as:

```text
LOG_BACKUP
ACTIVE_TRANSACTION
DATABASE_MIRRORING
AVAILABILITY_REPLICA
REPLICATION
```

The exact reason matters.

For example:

```text
log_reuse_wait_desc = LOG_BACKUP
```

Strong indication:

> Log backup is required.

But:

```text
log_reuse_wait_desc = ACTIVE_TRANSACTION
```

means an active transaction may be preventing log reuse.

---

# 21. Full Recovery Real-Time Example

Imagine a banking database:

```text
Database:
BankingDB

Recovery:
FULL

Business RPO:
5 minutes
```

Backup schedule:

```text
Sunday 01:00
FULL

Every day:
01:00 Differential

Every 5 minutes:
Transaction Log
```

At:

```text
14:37:20
```

a bad deployment executes:

```sql
DELETE FROM dbo.CustomerTransactions;
```

The DBA discovers the problem at:

```text
14:39
```

The objective is:

> Restore the database to just before the accidental DELETE.

Full recovery makes this possible, assuming the required backup chain is intact and the required log backup containing the target point is available. 

Microsoft documents point-in-time recovery using transaction-log backups and `STOPAT`. ([Microsoft Learn][5])

---

# 22. Point-in-Time Recovery

Conceptually:

```text
FULL
  |
  +-- Full Backup
  |
  +-- Log 1
  |
  +-- Log 2
  |
  +-- Log 3
  |
  +-- Log 4
           |
           +---- Bad DELETE
```

You can restore:

```text
Full
  ↓
Differential
  ↓
Log 1
  ↓
Log 2
  ↓
Log 3
  ↓
STOPAT
```

Example:

```sql
RESTORE DATABASE SalesDB
FROM DISK = 'D:\Backup\SalesDB_FULL.bak'
WITH NORECOVERY;
```

Then:

```sql
RESTORE DATABASE SalesDB
FROM DISK = 'D:\Backup\SalesDB_DIFF.bak'
WITH NORECOVERY;
```

Then log backups in sequence:

```sql
RESTORE LOG SalesDB
FROM DISK = 'D:\Backup\SalesDB_LOG_001.trn'
WITH NORECOVERY;
```

Finally:

```sql
RESTORE LOG SalesDB
FROM DISK = 'D:\Backup\SalesDB_LOG_002.trn'
WITH STOPAT = '2026-09-14T14:37:00',
     RECOVERY;
```

Microsoft states that the required full/differential backup must be restored first, followed by the transaction logs in sequence. ([Microsoft Learn][6])

---

# 23. Why `NORECOVERY`?

During a restore sequence:

```text
FULL
 ↓
NORECOVERY

DIFF
 ↓
NORECOVERY

LOG 1
 ↓
NORECOVERY

LOG 2
 ↓
NORECOVERY

LOG 3
 ↓
RECOVERY
```

`NORECOVERY` tells SQL Server:

> "I am not finished restoring yet. Keep the database in a state where another backup can be applied."

At the end:

```sql
RESTORE DATABASE SalesDB
WITH RECOVERY;
```

The database becomes available.

---

# 24. What Is a Backup Chain?

Think of it as a sequence:

```text
FULL
 |
 +--> LOG 001
       |
       +--> LOG 002
              |
              +--> LOG 003
                     |
                     +--> LOG 004
```

You cannot randomly choose:

```text
FULL
+
LOG 004
```

and expect SQL Server to reconstruct everything.

The required log backups must form a valid restore sequence.

---

# 25. Differential Backup vs Log Backup

This distinction is extremely important.

| Feature                      | Differential              | Transaction Log                        |
| ---------------------------- | ------------------------- | -------------------------------------- |
| Captures                     | Changes since full backup | Log records since previous log backup  |
| Depends on                   | Full backup               | Previous log backup in chain           |
| Point-in-time restore        | No by itself              | Yes, with appropriate full/diff + logs |
| Frequency                    | Usually daily/periodic    | Frequently                             |
| File extension commonly used | `.bak`                    | `.trn`                                 |

Microsoft recommends that differential backups can reduce the number of log backups that need to be restored during recovery. ([Microsoft Learn][7])

---

# 26. Bulk-Logged — Why Does It Exist?

Imagine a 2-TB database.

You need to load:

```text
500 GB
```

of data.

With full recovery:

```text
Bulk operation
       |
       v
Extensive logging
       |
       v
Large transaction log
```

This can create significant log activity.

Bulk-logged can reduce log space usage for supported bulk operations through minimal logging. ([Microsoft Learn][2])

---

# 27. Real-Time Bulk-Logged Use Case

Suppose your company performs a nightly ETL:

```text
01:00 AM
|
+-- Load 500 million rows
|
+-- Rebuild indexes
|
+-- Data warehouse processing
|
05:00 AM
|
+-- OLTP workload starts
```

You might consider:

```text
FULL
   ↓
BULK_LOGGED
   ↓
Bulk processing
   ↓
FULL
```

But this must be carefully planned.

---

# 28. Important Bulk-Logged Warning

This is where many DBAs make mistakes.

Suppose:

```text
FULL
 ↓
BULK_LOGGED
 ↓
Large minimally logged operation
 ↓
Failure
```

If the transaction-log backup contains bulk-logged operations, **point-in-time recovery within that log backup isn't available**.

Microsoft specifically warns that when minimally logged operations are present, you cannot recover to an arbitrary point within that log backup. ([Microsoft Learn][1])

So don't think:

> "Bulk-logged is just Full recovery but faster."

That's not accurate.

---

# 29. Bulk-Logged Advantages

| Advantage                                            | Explanation                            |
| ---------------------------------------------------- | -------------------------------------- |
| Less log generation for supported operations         | Reduces logging overhead               |
| Useful for bulk loads                                | Good for ETL/data warehouse operations |
| Helps prevent huge log growth during bulk operations | Less logging                           |
| Still supports log backups                           | Unlike Simple                          |

Microsoft states that minimal logging can reduce the possibility of a large bulk operation filling the available transaction log. ([Microsoft Learn][2])

---

# 30. Bulk-Logged Disadvantages

| Disadvantage                                   | Explanation                                                   |
| ---------------------------------------------- | ------------------------------------------------------------- |
| Point-in-time recovery limitation              | Bulk-logged changes may prevent it within affected log backup |
| More operational complexity                    | DBA must carefully manage model switching                     |
| Log backup can be large                        | Minimally logged changes are captured in the log backup       |
| Recovery planning becomes more complicated     | Need to understand bulk operation timing                      |
| Not ideal as a permanent default for most OLTP | Full is usually preferable                                    |

Microsoft notes that log backups can be large because minimally logged operations are captured in them. ([Microsoft Learn][1])

---

# 31. Switching Full → Bulk-Logged

Example:

```sql
ALTER DATABASE SalesDB
SET RECOVERY BULK_LOGGED;
```

Perform the planned bulk operation.

Then:

```sql
ALTER DATABASE SalesDB
SET RECOVERY FULL;
```

And importantly:

```sql
BACKUP LOG SalesDB
TO DISK = 'D:\Backup\SalesDB_PostBulk.trn'
WITH COMPRESSION;
```

Microsoft recommends switching back to Full immediately after the bulk operations and taking a log backup. ([Microsoft Learn][3])

---

# 32. Switching Simple → Full

This is another common production scenario.

Initially:

```text
SIMPLE
```

Then:

```sql
ALTER DATABASE SalesDB
SET RECOVERY FULL;
```

Immediately establish the backup strategy.

Microsoft recommends taking a full or differential database backup after switching from Simple to Full/Bulk-logged to start the log chain, followed by regular log backups. ([Microsoft Learn][3])

---

# 33. Switching Full → Simple

Example:

```sql
ALTER DATABASE SalesDB
SET RECOVERY SIMPLE;
```

Now:

```text
Transaction log backups
        ↓
STOP
```

You should also remove/disable scheduled transaction-log backup jobs for that database.

Microsoft explicitly recommends discontinuing scheduled transaction-log backups after switching to Simple. ([Microsoft Learn][3])

---

# 34. Important Production Scenario

Imagine:

```text
ProductionDB
Recovery = FULL
```

Someone says:

> "The log file is 800 GB. Let's change it to Simple."

This may make the log appear easier to manage, but it changes the recovery capability.

Before doing that, ask:

1. Why did the log grow?
2. Is a log backup job failing?
3. Is there an active transaction?
4. Is Always On holding log truncation?
5. Is replication holding the log?
6. Is there another `log_reuse_wait_desc` reason?
7. What is the business RPO?
8. Is point-in-time recovery required?

**Never change recovery model merely to solve log growth without understanding the cause.**

---

# 35. Recovery Model and Always On

For an Always On availability group database, the database must use:

```text
FULL
```

Recovery.

Simple recovery does not support Always On availability groups. Microsoft explicitly lists Always On availability groups among features unavailable under Simple recovery. ([Microsoft Learn][1])

For a typical AG:

```text
Primary
  |
  | transaction log
  v
Secondary
```

The transaction log is essential to the synchronization process.

---

# 36. Recovery Model and Log Shipping

Log shipping also requires:

```text
FULL
```

or appropriate log-backup-compatible recovery.

Architecture:

```text
PRIMARY
   |
   | LOG BACKUP
   v
Backup Share
   |
   | COPY
   v
SECONDARY
   |
   | RESTORE
   v
Standby Database
```

Simple recovery cannot support Log Shipping. ([Microsoft Learn][1])

---

# 37. Recovery Model and Database Mirroring

Database mirroring also depends on transaction-log-based synchronization and isn't supported under Simple recovery. ([Microsoft Learn][1])

---

# 38. Recovery Model and Replication

Don't confuse:

```text
Recovery Model
```

with:

```text
Replication
```

They solve different problems.

| Technology         | Primary Purpose           |
| ------------------ | ------------------------- |
| Recovery model     | Controls logging/recovery |
| Backup             | Disaster recovery         |
| Always On AG       | HA/DR                     |
| Log Shipping       | DR                        |
| Replication        | Data distribution         |
| Database Mirroring | HA/DR legacy technology   |

A production architecture may use several of these technologies together.

---

# 39. Recovery Model Does NOT Mean Backup Strategy

This is another important DBA concept.

Choosing:

```text
FULL
```

doesn't mean:

```text
"Database is protected."
```

You still need:

```text
Full backup
+
Differential backup
+
Transaction-log backups
+
Backup retention
+
Off-server/off-site copies
+
Restore testing
```

Microsoft emphasizes that after selecting the recovery model, you must design a matching backup strategy based on business requirements. ([Microsoft Learn][8])

---

# 40. Full Recovery Does NOT Automatically Mean Zero Data Loss

This is a common interview trap.

Full recovery gives you the ability to recover to a point in time **if the required backups are available**.

For example:

```text
Full backup       01:00
Log backup        01:15
Log backup        01:30
Log backup        01:45
Server failure    01:50
```

If the latest successful log backup is:

```text
01:45
```

and you cannot obtain the active log through a tail-log backup, some transactions after 01:45 may be lost.

Microsoft recommends a tail-log backup when possible before restoring after a failure. ([Microsoft Learn][9])

---

# 41. What Is a Tail-Log Backup?

Suppose:

```text
Last log backup = 10:00
Failure = 10:17
```

There may be transactions between:

```text
10:00 → 10:17
```

still in the active transaction log.

A **tail-log backup** captures the active part of the log before recovery.

Conceptually:

```text
Regular log backup
       |
       v
10:00
       |
       | Transactions
       |
       v
10:17 Failure
       |
       v
TAIL LOG BACKUP
```

Microsoft recommends taking the tail-log backup when possible during point-of-failure recovery. ([Microsoft Learn][9])

---

# 42. Advanced: Why Can Full Recovery Still Lose Data?

Because Full recovery does not protect you from:

* Failed backup jobs
* Missing log backups
* Corrupted backup files
* Lost backup storage
* Broken backup chain
* Failure to capture the tail of the log
* Incorrect restore procedures
* Human error
* Unrecoverable storage failure

Therefore:

> **Recovery model + backup strategy + tested restore process = actual recoverability.**

---

# 43. How to Check Recovery Model

Use:

```sql
SELECT
    name AS DatabaseName,
    recovery_model_desc
FROM sys.databases
ORDER BY name;
```

Example:

```text
DatabaseName       Recovery_Model
-------------------------------
master              SIMPLE
tempdb              SIMPLE
model               FULL
msdb                SIMPLE
SalesDB             FULL
ReportingDB         SIMPLE
```

---

# 44. Check One Database

```sql
SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc
FROM sys.databases
WHERE name = 'SalesDB';
```

This is a very useful production health query.

---

# 45. Find All Databases Not Using Full

```sql
SELECT
    name AS DatabaseName,
    recovery_model_desc
FROM sys.databases
WHERE database_id > 4
  AND recovery_model_desc <> 'FULL';
```

This is useful for identifying databases that may not meet your production recovery standard.

But don't blindly change them to Full. First determine the business requirement.

---

# 46. Find All Production Databases Using Simple

```sql
SELECT
    name,
    recovery_model_desc
FROM sys.databases
WHERE recovery_model_desc = 'SIMPLE'
  AND database_id > 4;
```

Then review each database individually.

---

# 47. Recovery Model Decision Matrix

Use this in real DBA architecture discussions.

| Business Requirement                            | Recommended Model                                       |
| ----------------------------------------------- | ------------------------------------------------------- |
| Database can be recreated                       | Simple                                                  |
| Dev/test                                        | Usually Simple                                          |
| Reporting DB where some data loss is acceptable | Simple or Full depending on requirements                |
| Critical OLTP                                   | Full                                                    |
| Financial transactions                          | Usually Full                                            |
| Need point-in-time recovery                     | Full                                                    |
| Need Always On AG                               | Full                                                    |
| Need Log Shipping                               | Full                                                    |
| Large controlled bulk operation                 | Consider Bulk-logged temporarily                        |
| Data warehouse bulk load                        | Consider Bulk-logged depending on recovery requirements |
| Mission-critical database                       | Usually Full                                            |

---

# 48. A Real Production Example

Let's take:

```text
Database:
CustomerDB

Size:
2 TB

Business:
Financial Services

RPO:
5 minutes

RTO:
30 minutes

HA:
Always On AG

DR:
Log Shipping
```

Recommended:

```text
Recovery Model = FULL
```

Backup:

```text
FULL
Weekly

DIFFERENTIAL
Daily

LOG
Every 5 minutes
```

Architecture:

```text
                 +----------------+
                 |   CustomerDB   |
                 |      FULL      |
                 +----------------+
                         |
                         v
                  Transaction Log
                         |
          +--------------+--------------+
          |                             |
          v                             v
    Always On AG                 Log Shipping
      Secondary                    DR Server
```

This is a realistic enterprise configuration.

---

# 49. Another Real-Time Example — Development

```text
Database:
DeveloperDB

RPO:
24 hours

RTO:
Several hours

HA:
None

DR:
None

Can recreate:
YES
```

Possible choice:

```text
SIMPLE
```

Backup:

```text
Full backup
Daily
```

Much simpler operationally.

---

# 50. Data Warehouse Example

Suppose:

```text
DW
 |
 +-- Nightly ETL
 |
 +-- 800 GB load
 |
 +-- Index maintenance
```

A carefully controlled strategy might be:

```text
FULL
   ↓
BULK_LOGGED
   ↓
ETL
   ↓
LOG BACKUP
   ↓
FULL
```

But before using this, verify:

* Whether operations are actually minimally logged.
* Whether point-in-time recovery is required during the operation.
* Whether the bulk process can be rerun.
* Whether users are allowed during the bulk processing.
* Whether the backup/restore plan has been tested.

Microsoft recommends caution when switching to Bulk-logged and says it should be used under controlled conditions when maximizing recoverability. ([Microsoft Learn][3])

---

# 51. Very Important: Minimal Logging Doesn't Mean No Logging

This is a common misconception.

Incorrect:

> Bulk-logged means SQL Server doesn't log the operation.

Correct:

> SQL Server uses **minimal logging** for eligible operations.

It still records information needed for recovery.

Microsoft describes minimal logging as logging only information required to recover the transaction without supporting point-in-time recovery for the affected minimally logged operation. ([Microsoft Learn][2])

---

# 52. Full vs Bulk-Logged

Suppose:

```text
500 million rows
```

are loaded.

### Full

```text
Bulk operation
      ↓
Full logging
      ↓
Large log activity
```

### Bulk-logged

```text
Bulk operation
      ↓
Minimal logging
      ↓
Less log activity
```

But:

```text
Bulk-logged
      ↓
Potential point-in-time recovery limitation
```

Therefore:

> **Performance benefit comes with recovery trade-offs.**

---

# 53. Interview Question: Which Recovery Model Should I Use?

A strong DBA answer:

> "I don't select a recovery model based only on database size. I first understand the business RPO/RTO, point-in-time recovery requirement, HA/DR architecture, transaction volume, and backup strategy. For critical production databases requiring point-in-time recovery or Always On/log shipping, I normally use Full recovery. Simple is appropriate when point-in-time recovery isn't required. Bulk-logged can be used temporarily for controlled bulk operations when its recovery limitations are acceptable."

That is much stronger than:

> "Production = Full, Dev = Simple."

---

# 54. Interview Question: Why Is My Log File Growing in Full Recovery?

Good answer:

> "Full recovery requires regular transaction-log backups.
If log backups aren't occurring, the inactive log cannot be reused as expected and the physical log can continue growing.
I would first check the last successful log backup and `sys.databases.log_reuse_wait_desc`, then investigate active transactions, AG/replication/mirroring dependencies, backup failures, or other blockers.
> I would not simply shrink the log."

This demonstrates real DBA thinking.

---

# 55. Interview Question: Can I Take a Log Backup in Simple?

Answer:

**No.**

Transaction-log backups are supported for:

```text
FULL
BULK_LOGGED
```

not Simple. ([Microsoft Learn][4])

---

# 56. Interview Question: Does Full Recovery Automatically Back Up the Log?

**No.**

This is extremely important.

Setting:

```sql
ALTER DATABASE SalesDB
SET RECOVERY FULL;
```

doesn't automatically create:

```text
5-minute log backups
```

You need a SQL Agent job, maintenance solution, or another backup mechanism.

---

# 57. Interview Question: Can I Restore a Full Backup to a Point in Time?

Not by itself.

A full database backup gives you the database state contained in that backup.

For point-in-time recovery, you normally need:

```text
FULL
+
appropriate DIFF if used
+
LOG backups
```

Microsoft documents point-in-time recovery as a restore sequence involving the full backup and subsequent transaction-log backups. ([Microsoft Learn][5])

---

# 58. Interview Question: Can I Restore a Differential Without Full?

**No.**

The differential is based on a full backup.

Typical sequence:

```text
FULL
 ↓
DIFF
 ↓
LOG
 ↓
LOG
 ↓
LOG
```

---

# 59. Interview Question: Can I Restore Log Backup Directly?

Normally:

**No.**

You need the appropriate base data backup first:

```text
FULL
```

and optionally:

```text
DIFF
```

Then:

```text
LOG 1
LOG 2
LOG 3
```

Microsoft states that the immediately previous full or differential database backup must be restored before applying transaction-log backups. ([Microsoft Learn][6])

---

# 60. Production DBA Recovery Flow

This is the flow I recommend you memorize:

```text
                 BUSINESS REQUIREMENTS
                         |
                         v
                   RPO / RTO
                         |
                         v
                  RECOVERY MODEL
                         |
            +------------+------------+
            |            |            |
          SIMPLE        FULL      BULK-LOGGED
            |            |            |
            |            |            |
            v            v            v
         Backup       Full/Diff/Log  Controlled
         Strategy       Strategy      Bulk Ops
            |            |            |
            +------------+------------+
                         |
                         v
                  RESTORE TESTING
                         |
                         v
                  RECOVERY PLAN
```

---

# 61. Production Backup Architecture

For a Full recovery database:

```text
                   SQL SERVER
                       |
                       v
                  Production DB
                       |
                       v
                Transaction Log
                       |
             +---------+---------+
             |                   |
             v                   v
       Log Backup             Full Backup
       Every 5 min            Weekly
             |                   |
             +---------+---------+
                       |
                       v
                 Backup Storage
                       |
              +--------+--------+
              |                 |
              v                 v
          Local copy        Offsite copy
```

The exact design depends on the organization's RPO/RTO, retention, storage, security, and DR requirements.

---

# 62. Backup Verification Is Not Enough

A successful backup job does not automatically prove that recovery will work.

You should periodically:

```text
Backup
 ↓
Restore
 ↓
DBCC CHECKDB
 ↓
Validate database
 ↓
Application validation
```

The real test is:

> **Can I actually restore the database within the required RTO?**

---

# 63. Recovery Model Best Practices

### 1. Select based on business requirements

Don't choose Full merely because:

> "It's production."

Understand RPO/RTO first.

### 2. For Full recovery, schedule frequent log backups

Example:

```text
5 minutes
```

if business RPO requires it.

### 3. Monitor log backup failures

A failed log backup job can become a production incident.

### 4. Monitor log growth

Track:

```text
LDF size
Used %
Growth events
log_reuse_wait_desc
```

### 5. Don't routinely shrink the log

Fix the underlying reason for growth.

### 6. Test restores

Backup without restore testing is an unproven recovery strategy.

### 7. Document recovery procedures

DBAs should have:

```text
Backup location
Backup retention
Restore sequence
Credentials/access
RPO
RTO
Escalation contacts
Application validation
```

---

# 64. My Recommended DBA Cheat Sheet

| Question                                                 | Answer                                                       |
| -------------------------------------------------------- | ------------------------------------------------------------ |
| How many recovery models?                                | 3                                                            |
| Names?                                                   | Simple, Full, Bulk-logged                                    |
| Which supports log backups?                              | Full, Bulk-logged                                            |
| Which supports point-in-time recovery?                   | Full                                                         |
| Which doesn't support log backups?                       | Simple                                                       |
| Which supports Always On AG?                             | Full/Bulk-logged, not Simple                                 |
| Which supports Log Shipping?                             | Full/Bulk-logged, not Simple                                 |
| Which is simplest?                                       | Simple                                                       |
| Which gives strongest point-in-time recovery capability? | Full                                                         |
| Which reduces logging for eligible bulk operations?      | Bulk-logged                                                  |
| Does Full automatically take log backups?                | No                                                           |
| Does Full automatically prevent log growth?              | No                                                           |
| Does log backup shrink the physical `.ldf`?              | No                                                           |
| Can Bulk-logged always do point-in-time recovery?        | No                                                           |
| What establishes the log chain after Simple → Full?      | Full/differential data backup                                |
| What should be done after Bulk-logged → Full?            | Take a log backup                                            |
| What should you check for unexplained log growth?        | `log_reuse_wait_desc` and backup/transaction/HA dependencies |

---

# 65. The Most Important Concept

If you remember only one thing, remember this:

```text
Recovery Model
      ↓
Controls Transaction Log Behavior
      ↓
Controls Log Backup Capability
      ↓
Controls Recovery Options
      ↓
Influences RPO
      ↓
Must Match Business Requirements
```

And the three models:

```text
                 SQL SERVER
                     |
        +------------+------------+
        |            |            |
        v            v            v
      SIMPLE        FULL      BULK-LOGGED
        |            |            |
        |            |            |
   No Log Backup   Log Backup   Log Backup
        |            |            |
   No PITR         PITR         Limited PITR
        |            |            |
   Simple          Best         Bulk Operations
   Operations      Recovery      / ETL
```

---

# 66. Official Microsoft Documentation

These are the Microsoft Learn references I recommend keeping as your primary reference set:

* **Recovery Models (SQL Server)** — overview, RPO/RTO and model comparison. [Microsoft Learn — Recovery Models](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver17)
* **View or Change the Recovery Model** — changing models and important transition rules. [Microsoft Learn — View or Change Recovery Model](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/view-or-change-the-recovery-model-of-a-database-sql-server?view=sql-server-ver17)
* **The Transaction Log** — logging, truncation and minimally logged operations. [Microsoft Learn — The Transaction Log](https://learn.microsoft.com/en-us/sql/relational-databases/logs/the-transaction-log-sql-server?view=sql-server-ver17)
* **Transaction Log Backups** — log-backup strategy and requirements. [Microsoft Learn — Transaction Log Backups](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/transaction-log-backups-sql-server?view=sql-server-ver17)
* **Back Up and Restore SQL Server Databases** — designing a backup strategy around business requirements. [Microsoft Learn — Back Up and Restore SQL Server Databases](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/back-up-and-restore-of-sql-server-databases?view=sql-server-ver17)
* **Point-in-Time Restore** — detailed `STOPAT` restore process. [Microsoft Learn — Point-in-Time Restore](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model?view=sql-server-ver17)
* **Complete Database Restore — Full Recovery** — full restore sequence and tail-log recovery. [Microsoft Learn — Complete Database Restores](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/complete-database-restores-full-recovery-model?view=sql-server-ver16)

---

[1]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver17 "Recovery Models (SQL Server) - SQL Server | Microsoft Learn"
[2]: https://learn.microsoft.com/en-us/sql/relational-databases/logs/the-transaction-log-sql-server?view=sql-server-ver17 "The Transaction Log - SQL Server | Microsoft Learn"
[3]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/view-or-change-the-recovery-model-of-a-database-sql-server?view=sql-server-ver17 "Set database recovery model - SQL Server | Microsoft Learn"
[4]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/transaction-log-backups-sql-server?view=sql-server-ver17 "Transaction log backups - SQL Server | Microsoft Learn"
[5]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model?view=sql-server-ver17 "Restore a SQL Server Database to a Point in Time (Full Recovery Model) - SQL Server | Microsoft Learn"
[6]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/apply-transaction-log-backups-sql-server?view=sql-server-ver17 "Apply Transaction Log Backups (SQL Server) - SQL Server | Microsoft Learn"
[7]: https://learn.microsoft.com/sl-si/sql/relational-databases/backup-restore/complete-database-restores-full-recovery-model?view=sql-server-ver15 "Complete Database Restores (Full Recovery Model) - SQL Server | Microsoft Learn"
[8]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/back-up-and-restore-of-sql-server-databases?view=sql-server-ver17 "Back up and Restore of SQL Server Databases - SQL Server | Microsoft Learn"
[9]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/complete-database-restores-full-recovery-model?view=sql-server-ver16 "Complete Database Restores (Full Recovery Model) - SQL Server | Microsoft Learn"

## Hands-on Recovery Model Lab: 

```text
LAB-01  Understand transaction log
LAB-02  SIMPLE recovery
LAB-03  FULL recovery
LAB-04  Full + Differential + Log backups
LAB-05  Restore complete backup chain
LAB-06  Point-in-time recovery
LAB-07  Accidental DELETE recovery
LAB-08  Tail-log backup
LAB-09  Log growth troubleshooting
LAB-10  BULK_LOGGED recovery
LAB-11  Minimal logging demonstration
LAB-12  FULL → BULK_LOGGED → FULL
LAB-13  Broken log-chain scenario
LAB-14  Always On + recovery model
LAB-15  Log Shipping + recovery model
LAB-16  Production recovery drill
LAB-17  RPO/RTO design exercise
LAB-18  Automated recovery-model health check
```

Above progression will take us from **basic understanding to the level expected from a senior SQL Server DBA**, rather than just memorizing the three recovery models.

Below is the **complete sequential hands-on lab series — LAB 01 through LAB 18**. 

Practical enough to run in your SQL Server lab, while keeping destructive exercises isolated from your normal databases.

Microsoft defines the recovery model as a database property controlling transaction logging, log-backup requirements, and available restore operations. 

The three models are **Simple, Full, and Bulk-logged**. ([Microsoft Learn][1])

> **Lab safety:**
Run these labs only on a non-production SQL Server instance.
Do not experiment with recovery models, restore operations, `DBCC SHRINKFILE`, AG configuration, or log-shipping configuration against a production database.

# SQL Server Recovery Models — Complete 18-Lab Practical Course

## Lab Roadmap

| Lab | Topic                                  | Level                 |
| --- | -------------------------------------- | --------------------- |
| 01  | Understand the transaction log         | Beginner              |
| 02  | Simple recovery model                  | Beginner              |
| 03  | Full recovery model                    | Beginner              |
| 04  | Full + Differential + Log backups      | Beginner/Intermediate |
| 05  | Restore a complete backup chain        | Intermediate          |
| 06  | Point-in-time recovery                 | Intermediate          |
| 07  | Accidental DELETE recovery             | Intermediate          |
| 08  | Tail-log backup                        | Intermediate/Advanced |
| 09  | Transaction-log growth troubleshooting | Intermediate          |
| 10  | Bulk-logged recovery                   | Advanced              |
| 11  | Minimal logging demonstration          | Advanced              |
| 12  | FULL → BULK_LOGGED → FULL              | Advanced              |
| 13  | Broken log-chain scenario              | Advanced              |
| 14  | Always On + recovery model             | Advanced              |
| 15  | Log Shipping + recovery model          | Advanced              |
| 16  | Production recovery drill              | Advanced              |
| 17  | RPO/RTO design exercise                | Architecture          |
| 18  | Automated recovery-model health check  | DBA Automation        |

---

# 0. Lab Environment Preparation

We will create a dedicated database:

```text
RecoveryModelLab
```

and a backup directory such as:

```text
C:\SQLRecoveryLab\Backup
```

If your SQL Server service account cannot write to `C:\SQLRecoveryLab\Backup`, use a directory where the SQL Server service account has write permissions.

## Create the Lab Database

```sql
USE master;
GO

IF DB_ID(N'RecoveryModelLab') IS NULL
BEGIN
    CREATE DATABASE RecoveryModelLab;
END
GO

ALTER DATABASE RecoveryModelLab
SET RECOVERY SIMPLE;
GO

SELECT
    name,
    recovery_model_desc,
    state_desc
FROM sys.databases
WHERE name = N'RecoveryModelLab';
GO
```

Expected:

| Database         | Recovery | State  |
| ---------------- | -------- | ------ |
| RecoveryModelLab | SIMPLE   | ONLINE |

---

# LAB 01 — Understand the Transaction Log

## Objective

Understand:

* MDF/NDF
* LDF
* VLFs
* Active log
* Inactive log
* Log reuse
* Log truncation
* Physical log size

---

## Step 1 — Find database files

```sql
USE RecoveryModelLab;
GO

SELECT
    DB_NAME(database_id) AS DatabaseName,
    name AS LogicalName,
    type_desc,
    physical_name,
    size * 8 / 1024 AS SizeMB
FROM sys.master_files
WHERE database_id = DB_ID(N'RecoveryModelLab');
GO
```

You should see something similar to:

```text
RecoveryModelLab
    RecoveryModelLab       ROWS   ...\RecoveryModelLab.mdf
    RecoveryModelLab_log   LOG    ...\RecoveryModelLab_log.ldf
```

---

## Step 2 — Check log space

```sql
DBCC SQLPERF(LOGSPACE);
GO
```

Look for:

```text
RecoveryModelLab
```

---

## Step 3 — Generate transactions

```sql
USE RecoveryModelLab;
GO

IF OBJECT_ID('dbo.RecoveryTest','U') IS NOT NULL
    DROP TABLE dbo.RecoveryTest;
GO

CREATE TABLE dbo.RecoveryTest
(
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Description VARCHAR(200),
    CreatedDate DATETIME2 DEFAULT SYSDATETIME()
);
GO

INSERT INTO dbo.RecoveryTest (Description)
SELECT TOP (10000)
       CONCAT('Test row ', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)))
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;
GO
```

Check:

```sql
SELECT COUNT(*)
FROM dbo.RecoveryTest;
```

---

## Step 4 — Examine log information

```sql
SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc
FROM sys.databases
WHERE name = N'RecoveryModelLab';
```

---

## Key learning

The transaction log is not simply an "undo file."

SQL Server uses it for:

```text
Transaction recovery
Crash recovery
Rollback
Log backups
Database restore
HA/DR synchronization
Point-in-time recovery
```

Microsoft's transaction-log documentation explains the relationship between logging, recovery, truncation, and minimally logged operations. ([Microsoft Learn][2])

---

# LAB 02 — Simple Recovery Model

## Objective

Understand:

* SIMPLE
* No log backups
* Automatic log-space reuse
* No point-in-time restore

---

## Step 1

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY SIMPLE;
GO
```

Verify:

```sql
SELECT
    name,
    recovery_model_desc
FROM sys.databases
WHERE name = N'RecoveryModelLab';
```

Expected:

```text
RecoveryModelLab
SIMPLE
```

---

# Step 2 — Try a log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\Simple_Log.trn';
GO
```

This should fail because Simple recovery doesn't support transaction-log backups.

Microsoft explicitly states that Simple recovery does not support transaction-log backups or point-in-time restores. ([Microsoft Learn][2])

---

# Step 3 — Full backup

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\Simple_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

# Step 4 — Generate more changes

```sql
INSERT INTO dbo.RecoveryTest (Description)
VALUES
('Simple recovery test 1'),
('Simple recovery test 2'),
('Simple recovery test 3');
GO
```

---

# Step 5 — Understand the limitation

You cannot do:

```text
FULL
+
LOG
+
STOPAT
```

because Simple recovery does not maintain a log-backup chain.

### Microsoft-supported capability

| Capability             | SIMPLE |
| ---------------------- | -----: |
| Full backup            |    Yes |
| Differential backup    |    Yes |
| Log backup             |     No |
| Point-in-time recovery |     No |
| Log Shipping           |     No |
| Always On AG           |     No |

Microsoft documents these Simple-recovery restrictions. ([Microsoft Learn][2])

---

# LAB 03 — Full Recovery Model

## Objective

Learn the foundation of production recovery.

---

## Step 1 — Change recovery model

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY FULL;
GO
```

---

## Step 2 — Establish the log chain

Immediately take a full backup:

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\Full_01.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

Microsoft specifically recommends taking a full or differential database backup after changing from Simple to Full/Bulk-logged to establish the log chain. ([Microsoft Learn][1])

---

## Step 3 — Generate activity

```sql
INSERT INTO dbo.RecoveryTest (Description)
SELECT TOP (5000)
       CONCAT('Full recovery ', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)))
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;
GO
```

---

## Step 4 — Take log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\Log_01.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 5 — Another transaction

```sql
UPDATE dbo.RecoveryTest
SET Description = 'Updated under FULL recovery'
WHERE ID <= 1000;
GO
```

---

## Step 6 — Another log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\Log_02.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Important observation

You now have:

```text
FULL_01
   |
   +--- LOG_01
           |
           +--- LOG_02
```

This is the beginning of your recovery chain.

Microsoft recommends frequent log backups under Full recovery both to reduce work-loss exposure and to help truncate the inactive log. ([Microsoft Learn][3])

---

# LAB 04 — Full + Differential + Log Backups

## Objective

Understand the three major backup types together.

---

## Step 1 — Full

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB04_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 2 — Generate changes

```sql
INSERT INTO dbo.RecoveryTest (Description)
VALUES ('Change after full');
GO
```

---

## Step 3 — Differential

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB04_DIFF.bak'
WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 4 — More changes

```sql
INSERT INTO dbo.RecoveryTest (Description)
VALUES ('Change after differential');
GO
```

---

## Step 5 — Log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB04_LOG01.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Backup structure

```text
FULL
 |
 +------ DIFF
          |
          +------ LOG 01
          |
          +------ LOG 02
          |
          +------ LOG 03
```

The differential is based on the full backup, while log backups follow the log chain. Microsoft recommends differential backups as a way to reduce the number of log backups required during recovery. ([Microsoft Learn][4])

---

# LAB 05 — Restore a Complete Backup Chain

## Objective

Perform a real restore sequence.

We'll restore as:

```text
RecoveryModelLab_Restore
```

---

## Step 1 — Create backup set

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB05_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

Generate change:

```sql
INSERT INTO dbo.RecoveryTest (Description)
VALUES ('LAB05 Change 1');
GO
```

Log backup:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB05_LOG01.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

Generate another change:

```sql
INSERT INTO dbo.RecoveryTest (Description)
VALUES ('LAB05 Change 2');
GO
```

Log backup:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB05_LOG02.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

# Step 2 — Restore full

```sql
USE master;
GO

RESTORE DATABASE RecoveryModelLab_Restore
FROM DISK = 'C:\SQLRecoveryLab\Backup\LAB05_FULL.bak'
WITH
    MOVE 'RecoveryModelLab'
    TO 'C:\SQLRecoveryLab\Data\RecoveryModelLab_Restore.mdf',
    MOVE 'RecoveryModelLab_log'
    TO 'C:\SQLRecoveryLab\Data\RecoveryModelLab_Restore_log.ldf',
    NORECOVERY,
    REPLACE;
GO
```

---

# Step 3 — Restore LOG01

```sql
RESTORE LOG RecoveryModelLab_Restore
FROM DISK = 'C:\SQLRecoveryLab\Backup\LAB05_LOG01.trn'
WITH NORECOVERY;
GO
```

---

# Step 4 — Restore LOG02

```sql
RESTORE LOG RecoveryModelLab_Restore
FROM DISK = 'C:\SQLRecoveryLab\Backup\LAB05_LOG02.trn'
WITH RECOVERY;
GO
```

---

## Step 5 — Validate

```sql
SELECT *
FROM RecoveryModelLab_Restore.dbo.RecoveryTest
ORDER BY ID DESC;
```

The restore sequence is:

```text
FULL
 ↓
NORECOVERY
 ↓
LOG01
 ↓
NORECOVERY
 ↓
LOG02
 ↓
RECOVERY
```

Microsoft documents this restore-sequence pattern. ([Microsoft Learn][5])

---

# LAB 06 — Point-in-Time Recovery

This is one of the most important labs.

## Objective

Recover a database to a specific time.

---

## Step 1 — Full backup

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB06_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 2 — Record time

```sql
SELECT SYSDATETIME() AS BeforeBadChange;
```

Save the output.

Example:

```text
2026-09-14 21:10:00
```

---

## Step 3 — Perform valid transaction

```sql
INSERT INTO dbo.RecoveryTest (Description)
VALUES ('Valid transaction');
GO
```

---

## Step 4 — Log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB06_LOG01.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 5 — Record another timestamp

```sql
SELECT SYSDATETIME() AS BeforeBadChange;
```

---

## Step 6 — Simulate bad transaction

```sql
DELETE FROM dbo.RecoveryTest
WHERE ID <= 100;
GO
```

---

## Step 7 — Log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB06_LOG02.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 8 — Restore before DELETE

Restore full:

```sql
RESTORE DATABASE RecoveryModelLab_PITR
FROM DISK = 'C:\SQLRecoveryLab\Backup\LAB06_FULL.bak'
WITH
    MOVE 'RecoveryModelLab'
    TO 'C:\SQLRecoveryLab\Data\RecoveryModelLab_PITR.mdf',
    MOVE 'RecoveryModelLab_log'
    TO 'C:\SQLRecoveryLab\Data\RecoveryModelLab_PITR_log.ldf',
    NORECOVERY,
    REPLACE;
GO
```

Restore first log:

```sql
RESTORE LOG RecoveryModelLab_PITR
FROM DISK = 'C:\SQLRecoveryLab\Backup\LAB06_LOG01.trn'
WITH NORECOVERY;
GO
```

Then restore second log with `STOPAT`.

Use the timestamp you recorded immediately before the DELETE.

```sql
RESTORE LOG RecoveryModelLab_PITR
FROM DISK = 'C:\SQLRecoveryLab\Backup\LAB06_LOG02.trn'
WITH
    STOPAT = '2026-09-14T21:15:00',
    RECOVERY;
GO
```

**Replace the example timestamp with your actual recorded timestamp.**

Microsoft documents `STOPAT` point-in-time recovery under Full recovery. ([Microsoft Learn][5])

---

# LAB 07 — Accidental DELETE Recovery

This is the production-style version of Lab 06.

## Scenario

Business reports:

> "Someone accidentally deleted customer transactions."

Timeline:

```text
14:00 Full backup

14:05 Log backup
14:10 Log backup
14:15 Log backup

14:17 Accidental DELETE

14:20 DBA discovers problem
```

---

## Step 1 — Create business table

```sql
CREATE TABLE dbo.CustomerTransactions
(
    TransactionID INT IDENTITY PRIMARY KEY,
    CustomerID INT,
    Amount DECIMAL(18,2),
    TransactionDate DATETIME2 DEFAULT SYSDATETIME()
);
GO
```

---

## Step 2 — Insert data

```sql
INSERT INTO dbo.CustomerTransactions
(
    CustomerID,
    Amount
)
VALUES
(101,100.00),
(102,250.00),
(103,500.00),
(104,750.00),
(105,900.00);
GO
```

---

## Step 3 — Full backup

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB07_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 4 — Log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB07_LOG01.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 5 — Record timestamp

```sql
SELECT SYSDATETIME();
```

---

## Step 6 — Simulate DELETE

```sql
DELETE FROM dbo.CustomerTransactions
WHERE CustomerID IN (103,104);
GO
```

---

## Step 7 — Log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB07_LOG02.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Recovery strategy

Do **not** immediately overwrite production.

Normally you should:

```text
Restore backup
       ↓
PITR to safe time
       ↓
Validate rows
       ↓
Extract missing data
       ↓
Repair production
```

This is often safer than replacing the whole production database.

---

# LAB 08 — Tail-Log Backup

This is a very important senior DBA skill.

Microsoft recommends backing up the active tail of the log before beginning a restore when possible, because it can prevent additional work loss. ([Microsoft Learn][6])

## Scenario

```text
Last regular log backup:
10:00

Failure:
10:17
```

Transactions between:

```text
10:00 → 10:17
```

may exist in the active log.

---

## Tail-log backup

The database normally must be in Full or Bulk-logged recovery and the active log must still be accessible.

Example:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB08_TAIL.trn'
WITH
    NORECOVERY,
    CHECKSUM,
    COMPRESSION;
GO
```

`NORECOVERY` leaves the database in a restoring state for the subsequent restore sequence.

Microsoft specifically documents this use of tail-log backups. ([Microsoft Learn][7])

---

## Recovery sequence

```text
TAIL LOG
   ↓
FULL
   ↓
DIFFERENTIAL
   ↓
LOG 01
   ↓
LOG 02
   ↓
TAIL LOG
   ↓
RECOVERY
```

---

# LAB 09 — Transaction Log Growth Troubleshooting

This is one of the most valuable production DBA labs.

## Step 1 — Check recovery model

```sql
SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc
FROM sys.databases
WHERE database_id > 4;
```

---

# Step 2 — Check log usage

```sql
DBCC SQLPERF(LOGSPACE);
GO
```

---

# Step 3 — Check log file

```sql
SELECT
    DB_NAME(database_id) AS DatabaseName,
    name AS LogicalName,
    physical_name,
    size * 8.0 / 1024 AS SizeMB
FROM sys.master_files
WHERE type_desc = 'LOG';
```

---

# Step 4 — Investigate reuse reason

Possible examples:

| `log_reuse_wait_desc`      | Typical investigation                    |
| -------------------------- | ---------------------------------------- |
| `NOTHING`                  | No current blocker                       |
| `LOG_BACKUP`               | Check log-backup job                     |
| `ACTIVE_TRANSACTION`       | Investigate long transaction             |
| `AVAILABILITY_REPLICA`     | Check AG synchronization                 |
| `REPLICATION`              | Check replication                        |
| `DATABASE_MIRRORING`       | Check mirroring                          |
| `ACTIVE_BACKUP_OR_RESTORE` | Check backup/restore                     |
| `OLDEST_PAGE`              | Investigate database recovery conditions |

Do not treat every log-growth incident as a reason to shrink the log.

---

# Step 5 — Check open transaction

```sql
DBCC OPENTRAN('RecoveryModelLab');
GO
```

If an old transaction exists, investigate it.

---

# Step 6 — Check AG-related blocking

For an AG database:

```sql
SELECT
    DB_NAME(database_id) AS DatabaseName,
    log_reuse_wait_desc
FROM sys.databases
WHERE name = 'RecoveryModelLab';
```

If:

```text
AVAILABILITY_REPLICA
```

appears, investigate the availability replica rather than blindly shrinking the log.

---

# LAB 10 — Bulk-Logged Recovery

## Objective

Understand:

* BULK_LOGGED
* Minimal logging
* Log backups
* Point-in-time limitation

---

## Step 1 — Full recovery

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY FULL;
GO
```

---

## Step 2 — Establish backup

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB10_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 3 — Switch to Bulk-logged

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY BULK_LOGGED;
GO
```

Verify:

```sql
SELECT
    name,
    recovery_model_desc
FROM sys.databases
WHERE name = 'RecoveryModelLab';
```

---

## Step 4 — Perform controlled bulk operation

For example:

```sql
SELECT TOP (100000)
       *
INTO dbo.BulkTest
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;
GO
```

This is a lab demonstration, not a guarantee that every operation will be minimally logged under every condition.

The exact logging behavior depends on operation, database state, indexes, recovery model, and other prerequisites.

---

## Step 5 — Log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB10_BULK_LOG.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 6 — Switch back

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY FULL;
GO
```

Then:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB10_POST_BULK_LOG.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

Microsoft recommends switching back to Full immediately after the controlled bulk operation and backing up the log. ([Microsoft Learn][1])

---

# LAB 11 — Minimal Logging Demonstration

The purpose here is not simply to prove that an operation is "fast."

We want to compare logging behavior.

## Step 1

Record current log space:

```sql
DBCC SQLPERF(LOGSPACE);
GO
```

---

## Step 2 — Full recovery test

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY FULL;
GO
```

Create table:

```sql
CREATE TABLE dbo.FullLoadTest
(
    ID INT,
    Description VARCHAR(200)
);
GO
```

Load data:

```sql
INSERT INTO dbo.FullLoadTest
SELECT TOP (50000)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
       'Full recovery test'
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;
GO
```

Check log usage:

```sql
DBCC SQLPERF(LOGSPACE);
GO
```

---

## Step 3 — Bulk-logged comparison

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY BULK_LOGGED;
GO
```

Create another table:

```sql
CREATE TABLE dbo.BulkLoadTest
(
    ID INT,
    Description VARCHAR(200)
);
GO
```

Run a controlled bulk-style operation:

```sql
SELECT TOP (50000)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ID,
       'Bulk logged test' AS Description
INTO dbo.BulkLoadTest
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;
GO
```

Check:

```sql
DBCC SQLPERF(LOGSPACE);
GO
```

---

## Important lesson

Do **not** conclude:

> "BULK_LOGGED always produces X% less logging."

There is no universal percentage.

Microsoft documents Bulk-logged as a variant of Full that permits minimal logging for qualifying operations. ([Microsoft Learn][2])

---

# LAB 12 — FULL → BULK_LOGGED → FULL

This is the standard controlled maintenance scenario.

## Step 1

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY FULL;
GO
```

Take log backup:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB12_PRE_BULK.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 2

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY BULK_LOGGED;
GO
```

---

## Step 3

Perform controlled bulk operation.

```sql
SELECT TOP (100000)
       *
INTO dbo.LargeBulkTable
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;
GO
```

---

## Step 4

Immediately return to Full:

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY FULL;
GO
```

---

## Step 5

Take log backup:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB12_POST_BULK.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Recovery rule

During a Bulk-logged period:

```text
Point-in-time recovery
        ↓
Potentially restricted
```

If a log backup contains bulk-logged changes, you cannot perform point-in-time recovery within that backup. Microsoft explicitly documents this limitation. ([Microsoft Learn][8])

---

# LAB 13 — Broken Log Chain

This is an excellent interview and troubleshooting lab.

## Objective

Understand why log backups must be restored in sequence.

---

## Step 1

Create:

```text
FULL
LOG01
LOG02
LOG03
```

Example:

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB13_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

Then:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB13_LOG01.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

Then:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB13_LOG02.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

Then:

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\LAB13_LOG03.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 2

Attempt:

```text
FULL
+
LOG02
```

instead of:

```text
FULL
+
LOG01
+
LOG02
```

You should encounter a restore-sequence problem.

---

## Lesson

The correct model is:

```text
FULL
 ↓
LOG01
 ↓
LOG02
 ↓
LOG03
```

not:

```text
FULL
 ↓
LOG03
```

Microsoft states that log backups must be restored in sequence from the appropriate point in the backup chain. ([Microsoft Learn][6])

---

# LAB 14 — Always On + Recovery Model

This lab requires:

```text
SQL Server Instance 1
SQL Server Instance 2
```

and a properly configured Windows/SQL Server Always On lab.

Do not attempt this against your existing AG until you have verified the environment.

---

## Requirement

The database must use:

```text
FULL
```

recovery.

Microsoft states that Simple recovery doesn't support Always On availability groups. ([Microsoft Learn][2])

---

## Step 1

Check:

```sql
SELECT
    name,
    recovery_model_desc
FROM sys.databases
WHERE name = 'RecoveryModelLab';
```

Must be:

```text
FULL
```

---

## Step 2

Take full backup

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\AG_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 3

Take log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = 'C:\SQLRecoveryLab\Backup\AG_LOG.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 4 — AG validation

After joining the database to the AG:

```sql
SELECT
    DB_NAME(database_id) AS DatabaseName,
    synchronization_state_desc,
    synchronization_health_desc,
    is_primary_replica
FROM sys.dm_hadr_database_replica_states
WHERE database_id = DB_ID('RecoveryModelLab');
```

---

## Key architecture lesson

```text
FULL Recovery
      |
      v
Transaction Log
      |
      +--------> AG Secondary
      |
      +--------> Log backups
      |
      +--------> DR strategy
```

Recovery model is not the HA solution itself.

It enables the transaction-log-based recovery mechanisms required by these architectures.

---

# LAB 15 — Log Shipping + Recovery Model

This lab requires:

```text
PRIMARY SQL Server
SECONDARY SQL Server
MONITOR optional
```

Your existing SQL Server lab can be used if you already have separate primary/secondary instances.

---

## Requirement

Database must use:

```text
FULL
```

or an appropriate log-backup-compatible model.

Simple recovery cannot support log shipping. ([Microsoft Learn][2])

---

## Step 1 — Primary

```sql
ALTER DATABASE RecoveryModelLab
SET RECOVERY FULL;
GO
```

---

## Step 2 — Full backup

```sql
BACKUP DATABASE RecoveryModelLab
TO DISK = '\\YourBackupShare\RecoveryModelLab_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 3 — Restore secondary

On secondary:

```sql
RESTORE DATABASE RecoveryModelLab
FROM DISK = '\\YourBackupShare\RecoveryModelLab_FULL.bak'
WITH
    NORECOVERY,
    REPLACE;
GO
```

---

## Step 4 — Primary log backup

```sql
BACKUP LOG RecoveryModelLab
TO DISK = '\\YourBackupShare\RecoveryModelLab_LOG.trn'
WITH INIT, COMPRESSION, CHECKSUM;
GO
```

---

## Step 5 — Copy

Copy:

```text
RecoveryModelLab_LOG.trn
```

to secondary.

---

## Step 6 — Restore log

```sql
RESTORE LOG RecoveryModelLab
FROM DISK = '\\YourBackupShare\RecoveryModelLab_LOG.trn'
WITH NORECOVERY;
GO
```

A production Log Shipping configuration automates:

```text
BACKUP
   ↓
COPY
   ↓
RESTORE
   ↓
MONITOR
```

---

# LAB 16 — Production Recovery Drill

This is where all previous labs come together.

## Scenario

Production database:

```text
CustomerDB
```

Business requirements:

| Requirement          |         Value |
| -------------------- | ------------: |
| RPO                  |     5 minutes |
| RTO                  |    30 minutes |
| Recovery             | Point-in-time |
| HA                   |           Yes |
| DR                   |           Yes |
| Business criticality |          High |

---

## Backup strategy

```text
Sunday
  FULL

Daily
  DIFFERENTIAL

Every 5 minutes
  LOG
```

---

## Simulated incident

```text
09:00 Full

09:05 Log
09:10 Log
09:15 Log
09:20 Log

09:23 Bad deployment

09:30 Incident discovered
```

---

## Recovery plan

### Step 1

Stop application writes if possible.

### Step 2

Determine exact target recovery time.

Example:

```text
09:22:59
```

### Step 3

Take tail-log backup if possible.

### Step 4

Restore full.

### Step 5

Restore latest differential.

### Step 6

Restore all required log backups.

### Step 7

Use:

```sql
STOPAT
```

### Step 8

Validate.

### Step 9

Application validation.

### Step 10

Release database.

Microsoft's documented restore process follows this same high-level sequence: tail-log backup when possible, full backup, latest differential where applicable, subsequent log backups in order, and recovery. ([Microsoft Learn][5])

---

# LAB 17 — RPO/RTO Architecture Exercise

Now stop writing SQL for a moment.

This is an architecture lab.

## Scenario A — Development

| Requirement          | Value    |
| -------------------- | -------- |
| RPO                  | 24 hours |
| RTO                  | 8 hours  |
| Database recreatable | Yes      |
| HA                   | No       |

Possible design:

```text
SIMPLE
+
Daily FULL
```

---

# Scenario B — Customer-facing OLTP

| Requirement |    Value |
| ----------- | -------: |
| RPO         |    5 min |
| RTO         |   30 min |
| HA          | Required |
| PITR        | Required |

Recommended:

```text
FULL
+
FULL backups
+
DIFF backups
+
Frequent LOG backups
+
Always On
+
DR
```

---

# Scenario C — Data Warehouse

| Requirement  |   Value |
| ------------ | ------: |
| RPO          | 4 hours |
| RTO          | 2 hours |
| Large ETL    |     Yes |
| Bulk loading |     Yes |

Potential architecture:

```text
FULL
      ↓
Controlled BULK_LOGGED period
      ↓
FULL
```

But only after confirming the recovery implications of the bulk operation.

Microsoft recommends Bulk-logged as a controlled supplement to Full rather than as a general replacement for Full. ([Microsoft Learn][1])

---

# LAB 18 — Automated Recovery-Model Health Check

This is the lab I strongly recommend keeping as a DBA utility.

## Objective

Create a health-check script that identifies:

* Recovery model
* Log reuse reason
* Log size
* Log usage
* Database state
* Last full backup
* Last differential backup
* Last log backup

---

## Step 1 — Recovery model

```sql
SELECT
    d.name AS DatabaseName,
    d.state_desc,
    d.recovery_model_desc,
    d.log_reuse_wait_desc
FROM sys.databases d
WHERE d.database_id > 4
ORDER BY d.name;
```

---

# Step 2 — Log size

```sql
SELECT
    DB_NAME(mf.database_id) AS DatabaseName,
    mf.name AS LogicalLogName,
    mf.physical_name,
    mf.size * 8.0 / 1024 AS LogSizeMB
FROM sys.master_files mf
WHERE mf.type_desc = 'LOG'
ORDER BY DB_NAME(mf.database_id);
```

---

# Step 3 — Backup history

```sql
SELECT
    d.name AS DatabaseName,
    MAX(CASE
        WHEN bs.type = 'D'
        THEN bs.backup_finish_date
    END) AS LastFullBackup,

    MAX(CASE
        WHEN bs.type = 'I'
        THEN bs.backup_finish_date
    END) AS LastDifferentialBackup,

    MAX(CASE
        WHEN bs.type = 'L'
        THEN bs.backup_finish_date
    END) AS LastLogBackup

FROM sys.databases d

LEFT JOIN msdb.dbo.backupset bs
    ON bs.database_name = d.name

WHERE d.database_id > 4

GROUP BY d.name
ORDER BY d.name;
```

---

# Step 4 — Production-style health report

```sql
SELECT
    d.name AS DatabaseName,
    d.state_desc AS DatabaseState,
    d.recovery_model_desc AS RecoveryModel,
    d.log_reuse_wait_desc AS LogReuseWait,

    MAX(CASE
        WHEN bs.type = 'D'
        THEN bs.backup_finish_date
    END) AS LastFullBackup,

    MAX(CASE
        WHEN bs.type = 'I'
        THEN bs.backup_finish_date
    END) AS LastDifferentialBackup,

    MAX(CASE
        WHEN bs.type = 'L'
        THEN bs.backup_finish_date
    END) AS LastLogBackup

FROM sys.databases d

LEFT JOIN msdb.dbo.backupset bs
    ON bs.database_name = d.name

WHERE d.database_id > 4

GROUP BY
    d.name,
    d.state_desc,
    d.recovery_model_desc,
    d.log_reuse_wait_desc

ORDER BY d.name;
```

---

# LAB 18A — Add Recovery Policy

Now classify databases.

```sql
SELECT
    d.name AS DatabaseName,
    d.recovery_model_desc,

    CASE
        WHEN d.recovery_model_desc = 'FULL'
            THEN 'EXPECTED FOR CRITICAL PRODUCTION'

        WHEN d.recovery_model_desc = 'SIMPLE'
            THEN 'REVIEW RECOVERY REQUIREMENT'

        WHEN d.recovery_model_desc = 'BULK_LOGGED'
            THEN 'REVIEW - TEMPORARY USE EXPECTED'

        ELSE
            'UNKNOWN'
    END AS RecoveryAssessment

FROM sys.databases d

WHERE d.database_id > 4
ORDER BY d.name;
```

Microsoft's Policy-Based Management guidance recommends Full recovery for production databases and frequent transaction-log backups to support recoverability with minimal data loss. ([Microsoft Learn][9])

---

# LAB 18B — Detect Missing Log Backups

```sql
SELECT
    d.name AS DatabaseName,
    d.recovery_model_desc,

    MAX(bs.backup_finish_date) AS LastLogBackup,

    DATEDIFF
    (
        MINUTE,
        MAX(bs.backup_finish_date),
        GETDATE()
    ) AS MinutesSinceLastLogBackup

FROM sys.databases d

LEFT JOIN msdb.dbo.backupset bs
    ON bs.database_name = d.name
    AND bs.type = 'L'

WHERE d.database_id > 4
  AND d.recovery_model_desc IN
      ('FULL', 'BULK_LOGGED')

GROUP BY
    d.name,
    d.recovery_model_desc

ORDER BY
    MinutesSinceLastLogBackup DESC;
```

---

# LAB 18C — Flag Databases With No Recent Log Backup

For example, assume your policy requires a maximum 15-minute interval:

```sql
SELECT
    d.name AS DatabaseName,
    d.recovery_model_desc,

    MAX(bs.backup_finish_date) AS LastLogBackup,

    DATEDIFF
    (
        MINUTE,
        MAX(bs.backup_finish_date),
        GETDATE()
    ) AS MinutesSinceLastLogBackup,

    CASE
        WHEN MAX(bs.backup_finish_date) IS NULL
            THEN 'CRITICAL - NO LOG BACKUP FOUND'

        WHEN DATEDIFF
        (
            MINUTE,
            MAX(bs.backup_finish_date),
            GETDATE()
        ) > 15
            THEN 'WARNING - LOG BACKUP DELAYED'

        ELSE 'HEALTHY'
    END AS BackupStatus

FROM sys.databases d

LEFT JOIN msdb.dbo.backupset bs
    ON bs.database_name = d.name
    AND bs.type = 'L'

WHERE d.database_id > 4
  AND d.recovery_model_desc IN
      ('FULL', 'BULK_LOGGED')

GROUP BY
    d.name,
    d.recovery_model_desc

ORDER BY
    MinutesSinceLastLogBackup DESC;
```

**Important:** The 15-minute threshold is just a lab policy example. In production, set it from the database's actual RPO.

---

# Final Master Exercise

After completing all 18 labs, build this architecture mentally:

```text
                         BUSINESS
                            |
                            v
                       RPO / RTO
                            |
                            v
                   RECOVERY MODEL
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
          SIMPLE          FULL       BULK-LOGGED
             |              |              |
             |              |              |
             v              v              v
         FULL/DIFF      FULL/DIFF/LOG    Bulk Operations
         BACKUPS           BACKUPS           |
             |              |                |
             |              v                |
             |        POINT-IN-TIME          |
             |          RECOVERY             |
             |              |                |
             +--------------+----------------+
                            |
                            v
                       RESTORE TEST
                            |
                            v
                     RECOVERY DRILL
                            |
                            v
                       RPO / RTO
                       VALIDATED
```

# What You Should Be Able to Do After These Labs

| Skill                                | Target |
| ------------------------------------ | -----: |
| Explain all 3 recovery models        |      ✅ |
| Explain transaction-log behavior     |      ✅ |
| Configure Simple                     |      ✅ |
| Configure Full                       |      ✅ |
| Configure Bulk-logged                |      ✅ |
| Take full backups                    |      ✅ |
| Take differential backups            |      ✅ |
| Take log backups                     |      ✅ |
| Understand log chains                |      ✅ |
| Restore full + diff + log            |      ✅ |
| Use `NORECOVERY`                     |      ✅ |
| Use `RECOVERY`                       |      ✅ |
| Perform PITR with `STOPAT`           |      ✅ |
| Recover accidental DELETE            |      ✅ |
| Understand tail-log backup           |      ✅ |
| Troubleshoot log growth              |      ✅ |
| Understand `log_reuse_wait_desc`     |      ✅ |
| Understand minimal logging           |      ✅ |
| Understand Bulk-logged limitations   |      ✅ |
| Understand AG relationship           |      ✅ |
| Understand Log Shipping relationship |      ✅ |
| Design RPO/RTO                       |      ✅ |
| Build recovery health checks         |      ✅ |
| Perform a production recovery drill  |      ✅ |

## The five rules I want you to remember

**Rule 1**

> **Recovery model is not a backup strategy.**

**Rule 2**

> **FULL recovery without regular log backups is not a complete recovery solution.**

**Rule 3**

> **Never change FULL → SIMPLE merely because the `.ldf` file is large. Find the `log_reuse_wait_desc` reason first.**

**Rule 4**

> **BULK_LOGGED is a controlled recovery strategy for eligible bulk operations, not a permanent "better Full" recovery model.**

**Rule 5**

> **A backup is only useful when you have tested the restore.**

Microsoft's current documentation supports these core principles: Full/Bulk-logged require log backups; Simple does not support log backups or point-in-time recovery; Full supports point-in-time recovery when the required backup chain exists; and Bulk-logged has point-in-time limitations when the log backup contains bulk-logged changes. ([Microsoft Learn][1])

### Microsoft references

* [Recovery Models — SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver17)
* [View or Change the Recovery Model](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/view-or-change-the-recovery-model-of-a-database-sql-server?view=sql-server-ver17)
* [Transaction Log Backups](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/transaction-log-backups-sql-server?view=sql-server-ver17)
* [Complete Database Restores — Full Recovery Model](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/complete-database-restores-full-recovery-model?view=sql-server-ver16)
* [Plan and Perform Restore Sequences](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/plan-and-perform-restore-sequences-full-recovery-model?view=sql-server-ver17)
* [Apply Transaction Log Backups](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/apply-transaction-log-backups-sql-server?view=sql-server-ver17)
* [Back Up a Transaction Log](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/back-up-a-transaction-log-sql-server?view=sql-server-ver17)

**Best learning sequence:** Don't just read these labs. Run **01 → 18 in order**, record the output of every backup/restore operation, and deliberately break the backup chain in Lab 13. That will make the recovery-model concepts much easier to remember in real production troubleshooting and interviews.

[1]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/view-or-change-the-recovery-model-of-a-database-sql-server?view=sql-server-ver17 "Set database recovery model - SQL Server | Microsoft Learn"
[2]: https://learn.microsoft.com/ga-ie/sql/relational-databases/backup-restore/recovery-models-sql-server?view=sql-server-ver16 "Recovery Models (SQL Server) - SQL Server | Microsoft Learn"
[3]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/transaction-log-backups-sql-server?view=sql-server-ver17 "Transaction log backups - SQL Server | Microsoft Learn"
[4]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/plan-and-perform-restore-sequences-full-recovery-model?view=sql-server-ver17 "Restore sequences (Full Recovery Model) - SQL Server | Microsoft Learn"
[5]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/complete-database-restores-full-recovery-model?view=sql-server-ver16 "Complete Database Restores (Full Recovery Model) - SQL Server | Microsoft Learn"
[6]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/apply-transaction-log-backups-sql-server?view=sql-server-ver17 "Apply Transaction Log Backups (SQL Server) - SQL Server | Microsoft Learn"
[7]: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/back-up-a-transaction-log-sql-server?view=sql-server-ver17 "Back up a Transaction Log - SQL Server | Microsoft Learn"
[8]: https://learn.microsoft.com/ro-ro/sql/relational-databases/backup-restore/restore-and-recovery-overview-sql-server?view=sql-server-ver17&viewFallbackFrom=aps-pdw-2016 "Restore and Recovery Overview (SQL Server) - SQL Server | Microsoft Learn"
[9]: https://learn.microsoft.com/en-us/sql/relational-databases/policy-based-management/database-recovery-model?view=sql-server-ver17 "Database recovery model best practice policy - SQL Server | Microsoft Learn"

