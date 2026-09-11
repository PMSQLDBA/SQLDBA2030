# SQL Server Always On – Automated Health Monitoring and Alerting Every Two Hours

## Introduction

SQL Server Always On Availability Groups are widely used to provide **High Availability (HA)** and **Disaster Recovery (DR)** for business-critical databases.

One of the most common production issues a DBA may encounter is an availability database moving into:

**NOT SYNCHRONIZING**

However, monitoring only the synchronization state is not enough.

A database can still show `SYNCHRONIZED` or `SYNCHRONIZING` while other problems are developing, such as:

* Growing Log Send Queue
* Growing Redo Queue
* Slow redo processing
* Replica disconnection
* Suspended data movement
* HADR endpoint problems
* Network interruptions
* Low disk space
* Transaction log growth
* Secondary replica lag
* WSFC or quorum problems
* Repeated HADR connection errors

For this reason, a production Always On monitoring solution should continuously examine the complete health of the Availability Group rather than checking only whether a database says `SYNCHRONIZED`.

This article explains a monitoring framework that performs an **Always On health check every two hours** and sends email notifications for both healthy and unhealthy conditions.

---

# 1. Objective

The goal is to automatically answer these questions every two hours:

**Is my Availability Group healthy?**

If not:

**What is wrong, where is the problem, how serious is it, and what should the DBA investigate?**

The monitoring framework classifies the result into three levels:

### HEALTHY

No significant problem has been detected.

### WARNING

The AG is operational, but one or more conditions require DBA attention.

Examples include:

* Increasing Log Send Queue
* Increasing Redo Queue
* Low disk space
* Secondary lag
* Recent replica connection errors
* `PARTIALLY_HEALTHY` synchronization health

### CRITICAL

An immediate HA/DR problem has been detected.

Examples include:

* `NOT SYNCHRONIZING`
* Replica `DISCONNECTED`
* Data movement suspended
* HADR endpoint stopped
* Replica failed
* Database `SUSPECT`
* Database `RECOVERY_PENDING`
* Severe secondary lag
* Critically low disk space

---

# 2. Why NOT SYNCHRONIZING Happens

When a secondary database enters `NOT SYNCHRONIZING`, the database is no longer receiving or processing changes normally from its primary replica.

The synchronization state itself tells us the symptom.

It does not necessarily tell us the root cause.

A DBA therefore needs to investigate several layers.

```text
NOT SYNCHRONIZING
        |
        +--> Is replica connected?
        |
        +--> Is HADR endpoint running?
        |
        +--> Is data movement suspended?
        |
        +--> Is network communication working?
        |
        +--> Is SQL Server running on secondary?
        |
        +--> Is disk/storage healthy?
        |
        +--> Is transaction log transport working?
        |
        +--> Are HADR errors present?
        |
        +--> Is WSFC healthy?
        |
        +--> Is the database itself healthy?
```

Restarting SQL Server should therefore not be the first troubleshooting action.

The correct approach is to identify the failing component first.

---

# 3. Overall Monitoring Architecture

The monitoring solution runs through SQL Server Agent.

```text
                 SQL Server Agent
                        |
                        |
                  Every 2 Hours
                        |
                        v
             Always On Health Check
                        |
        +---------------+---------------+
        |               |               |
        v               v               v
     Replica         Database         Server
      Health          Health           Health
        |               |               |
        +---------------+---------------+
                        |
                        v
                 Analyze Findings
                        |
             +----------+----------+
             |          |          |
             v          v          v
          HEALTHY    WARNING    CRITICAL
             |          |          |
             +----------+----------+
                        |
                        v
                 HTML Email Report
                        |
                        v
                    DBA Team
```

The framework also writes monitoring information into history tables so the DBA can investigate previous incidents and analyze queue and lag trends.

---

# 4. Why Monitor Every Two Hours?

Many monitoring solutions notify DBAs only when something fails.

For critical HA/DR environments, a regular heartbeat is also useful.

A healthy email confirms that:

* Monitoring is running
* SQL Server Agent is running
* Database Mail is functioning
* The monitoring procedure executed
* AG health was successfully evaluated
* No configured warning or critical condition was detected

This means that the absence of an alert is not the only indication of health.

The monitoring framework actively confirms health.

---

# 5. Primary and Secondary Monitoring Strategy

The solution should be deployed on **every SQL Server instance participating in the Availability Group**.

However, allowing every replica to send the same healthy report could create duplicate emails.

For example:

```text
PMSQL01 --> Healthy email
PMSQL02 --> Healthy email
PMSQL03 --> Healthy email
PMSQL04 --> Healthy email
```

Receiving four identical emails every two hours would create unnecessary noise.

A better design is:

```text
PRIMARY
   |
   +--> HEALTHY  --> Send email
   +--> WARNING  --> Send email
   +--> CRITICAL --> Send email


SECONDARY
   |
   +--> HEALTHY  --> No duplicate heartbeat
   +--> WARNING  --> Send email
   +--> CRITICAL --> Send email
```

This provides both centralized reporting and secondary-side fail-safe monitoring.

It is especially useful because if the primary SQL Server itself becomes unavailable, it cannot send an email saying that it is unavailable.

A secondary replica may still be able to detect the connection failure.

---

# 6. Availability Replica Health

The first monitoring layer examines the availability replicas.

Important information comes from Always On DMVs such as:

`sys.availability_groups`

`sys.availability_replicas`

`sys.dm_hadr_availability_replica_states`

The framework checks:

* Replica role
* Operational state
* Connection state
* Synchronization health
* Availability mode
* Failover mode
* Last connection error
* HADR endpoint information

A healthy synchronous replica may look conceptually like:

```text
AG Name        : AGAlpha
Replica        : PMSQL02
Role           : SECONDARY
Commit Mode    : SYNCHRONOUS_COMMIT
Connected      : CONNECTED
Sync Health    : HEALTHY
```

---

# 7. Detecting a Disconnected Replica

One of the most important conditions is:

```text
connected_state_desc = DISCONNECTED
```

This is treated as **CRITICAL**.

Possible causes include:

* Secondary SQL Server stopped
* Network interruption
* Firewall problem
* DNS problem
* HADR endpoint unavailable
* Endpoint authentication issue
* TCP port blocked
* Server restart
* Infrastructure outage

The email should not merely report:

> Replica disconnected.

It should provide an investigation direction:

> Check SQL Server service, HADR endpoint, DNS, TCP connectivity, firewall, endpoint authentication, network path, and SQL Server error log.

This turns the monitoring email into an initial troubleshooting guide.

---

# 8. Replica Operational State

The monitor also checks for serious operational states such as:

```text
FAILED
FAILED_NO_QUORUM
OFFLINE
```

These conditions require immediate investigation.

For example, `FAILED_NO_QUORUM` may indicate that the Windows Server Failover Cluster does not currently have the quorum required to maintain normal cluster operations.

Investigation may include:

* WSFC status
* Cluster nodes
* Quorum configuration
* Witness availability
* Windows Failover Clustering events
* Network communication
* SQL Server service status

---

# 9. Synchronization Health

The synchronization state and synchronization health should not be treated as the same thing.

The monitor examines values such as:

```text
HEALTHY
PARTIALLY_HEALTHY
NOT_HEALTHY
```

A practical classification is:

```text
HEALTHY
   |
   +--> Normal

PARTIALLY_HEALTHY
   |
   +--> WARNING

NOT_HEALTHY
   |
   +--> CRITICAL
```

This is particularly important because **`SYNCHRONIZING` does not automatically mean a problem**.

An asynchronous-commit secondary commonly operates in `SYNCHRONIZING`.

Therefore, a poorly designed monitoring script such as:

```sql
IF synchronization_state_desc <> 'SYNCHRONIZED'
    SEND ALERT;
```

can generate false alerts.

The monitoring logic should consider synchronization health, availability mode, connectivity, queues, lag, and related conditions together.

---

# 10. Availability Database Health

Database-level information is collected from:

`sys.dm_hadr_database_replica_states`

This DMV provides several critical Always On indicators, including:

* Synchronization state
* Synchronization health
* Database state
* Data movement status
* Suspend reason
* Log Send Queue
* Log Send Rate
* Redo Queue
* Redo Rate
* Secondary lag
* Last sent time
* Last received time
* Last hardened time
* Last redone time
* Last commit time

This gives the DBA a much more complete picture than checking SSMS Dashboard alone.

---

# 11. NOT SYNCHRONIZING Detection

The most important database-level critical condition is:

```text
NOT SYNCHRONIZING
```

The monitoring framework immediately classifies this as:

**CRITICAL**

But the DBA should then determine why synchronization stopped.

Typical investigation flow:

```text
NOT SYNCHRONIZING
        |
        v
Replica Connected?
        |
     NO +------> Network / SQL Service / Endpoint
        |
       YES
        |
        v
Data Movement Suspended?
        |
     YES +------> Check Suspend Reason
        |
       NO
        |
        v
Check Send Queue
        |
        v
Check Redo Queue
        |
        v
Check SQL ERRORLOG
        |
        v
Check Storage / Network / WSFC
```

This is much safer than restarting SQL Server without understanding the cause.

---

# 12. Suspended Data Movement

The monitor checks:

```text
is_suspended = 1
```

When data movement is suspended, the framework also collects:

```text
suspend_reason_desc
```

This is valuable because suspension may occur for different reasons.

The alert therefore reports something similar to:

```text
Severity:
CRITICAL

Category:
Data Movement Suspended

Database:
ProductionDB

Observation:
Data movement is suspended.

Suspend Reason:
<reason reported by SQL Server>
```

The DBA should investigate the underlying cause before executing a resume command.

Blindly issuing:

```sql
ALTER DATABASE [DatabaseName]
SET HADR RESUME;
```

may temporarily clear the symptom without fixing the real problem.

---

# 13. Log Send Queue

The Log Send Queue represents transaction log records that still need to be sent to a secondary replica.

The monitor captures:

```text
log_send_queue_size
log_send_rate
```

Queue size is reported in KB by the DMV.

A growing send queue can indicate:

* Network throughput problems
* High transaction-log generation
* Secondary hardening delays
* Storage latency
* Replica connectivity problems
* Resource pressure

However, **queue size alone should not determine severity**.

Consider two cases.

### Scenario A

```text
Send Queue = 10 GB
Send Rate  = 100 MB/sec
```

The queue may drain relatively quickly.

### Scenario B

```text
Send Queue = 2 GB
Send Rate  = 100 KB/sec
```

The smaller queue may represent a much worse operational condition.

Therefore, the monitoring framework evaluates both size and rate.

---

# 14. Estimated Log Send Delay

A useful operational calculation is:

```text
Estimated Send Drain Time
        =
Log Send Queue KB
        /
Log Send Rate KB/sec
```

Conceptually:

```sql
log_send_queue_size /
NULLIF(log_send_rate, 0)
```

Example:

```text
Log Send Queue = 1,048,576 KB
Log Send Rate  = 10,240 KB/sec

Estimated drain time
= 1,048,576 / 10,240
≈ 102 seconds
```

This tells the DBA more than queue size alone.

It answers:

**If the current send rate continues, approximately how long would the current backlog take to drain?**

It is an estimate, not a guaranteed recovery time, because workload and throughput continuously change.

---

# 15. Detecting Log Transport Stalls

A particularly serious condition is:

```text
Log Send Queue > 0
AND
Log Send Rate = 0
AND
Synchronization State = NOT SYNCHRONIZING
```

This suggests log transport may have stalled.

The framework treats this as **CRITICAL**.

The DBA should investigate:

* Replica connectivity
* SQL Server service
* HADR endpoint
* Network
* Firewall
* Remote storage
* HADR errors
* Infrastructure outages

---

# 16. Redo Queue

Receiving log blocks is only one part of Always On synchronization.

The secondary must also redo the received changes.

The monitor therefore captures:

```text
redo_queue_size
redo_rate
```

A growing Redo Queue can indicate that the secondary is receiving changes faster than it can replay them.

Possible causes include:

* Slow secondary storage
* High CPU utilization
* Heavy read-only workload
* I/O latency
* Resource contention
* Large transaction workload
* Redo processing pressure

This is why a replica can be connected while still falling behind.

---

# 17. Estimated Redo Delay

The same principle used for log transport can be applied to redo.

```text
Estimated Redo Drain Time
        =
Redo Queue KB
        /
Redo Rate KB/sec
```

For example:

```text
Redo Queue = 2,000,000 KB
Redo Rate  = 20,000 KB/sec

Estimated redo time
≈ 100 seconds
```

This helps distinguish between:

**Large but rapidly clearing backlog**

and:

**Smaller but slowly processing backlog**

---

# 18. Secondary Lag

Where supported and applicable, the framework also tracks:

```text
secondary_lag_seconds
```

This gives another view of how far the secondary may be behind.

Example thresholds can be:

```text
< 5 minutes       Normal
>= 5 minutes      WARNING
>= 15 minutes     CRITICAL
```

These are monitoring-policy examples, not universal Microsoft limits.

A financial transaction system may require much tighter thresholds, while a remote DR replica across a slower WAN may intentionally tolerate greater lag.

Thresholds should therefore match the organization's:

* RPO
* RTO
* Workload
* Network architecture
* Commit mode
* Business requirements

---

# 19. HADR Endpoint Monitoring

Always On replicas communicate using database mirroring endpoints.

The monitoring framework examines:

`sys.database_mirroring_endpoints`

and the associated TCP endpoint information.

A normal endpoint should generally be:

```text
STARTED
```

Example:

```text
Endpoint : Hadr_endpoint
State    : STARTED
Port     : 5022
```

If the endpoint becomes:

```text
STOPPED
```

the condition is treated as **CRITICAL**.

The DBA should investigate:

* Endpoint configuration
* Endpoint permissions
* Authentication
* TCP port
* Firewall
* Network reachability
* SQL Server service
* Certificates where certificate authentication is used

---

# 20. Last Replica Connection Error

One extremely useful troubleshooting capability is collecting:

* Last connection error number
* Last connection error description
* Last connection error timestamp

For example:

```text
Replica:
PMSQL02

Last Connection Error:
<SQL Server reported error>

Timestamp:
2026-09-11 12:10:31
```

This can quickly point the DBA toward a network, endpoint, authentication, or remote-server issue.

Instead of receiving:

```text
Replica DISCONNECTED
```

the DBA receives both the current condition and recent connection evidence.

---

# 21. Database State Monitoring

Availability Group monitoring should also check the underlying database state.

Critical examples include:

```text
RECOVERY_PENDING
SUSPECT
EMERGENCY
OFFLINE
```

If an availability database itself is unhealthy, synchronization troubleshooting alone is insufficient.

The DBA must investigate:

* SQL Server ERRORLOG
* Storage
* Data files
* Transaction log
* I/O errors
* Database recovery
* Operating system events

---

# 22. Disk Space Monitoring

Always On problems are sometimes secondary symptoms of storage problems.

The framework therefore uses:

`sys.dm_os_volume_stats`

to monitor volumes containing SQL Server database files.

Example:

```text
Drive       E:\
Total       2 TB
Available   80 GB
Free        3.9%
Status      CRITICAL
```

Example starting thresholds:

```text
Free > 15%      Normal
Free <= 15%     WARNING
Free <= 5%      CRITICAL
```

Again, these values should be adjusted according to database size, autogrowth configuration, workload, and storage-management policies.

For a multi-terabyte volume, percentage alone may not always be sufficient. Enterprise monitoring may additionally use absolute free-space thresholds.

---

# 23. Transaction Log Reuse Monitoring

The monitor checks:

```text
log_reuse_wait_desc
```

A particularly relevant value for Always On is:

```text
AVAILABILITY_REPLICA
```

This indicates transaction-log truncation is waiting on Availability Group-related progress.

Possible reasons include:

* Disconnected secondary
* Lagging secondary
* Large send queue
* Suspended data movement
* Secondary performance problems

If this condition continues, the transaction log may continue growing.

This connects an HA/DR problem with a potential storage incident.

---

# 24. SQL Server ERRORLOG Monitoring

DMVs show current state.

The SQL Server ERRORLOG provides historical evidence about what recently happened.

The framework therefore examines recent entries using:

```sql
sys.sp_readerrorlog
```

and searches for HADR/Availability-related problems.

Examples include:

```text
HADR
availability
error
failed
disconnect
timeout
suspend
lease
not synchronizing
terminated
```

This is extremely useful because a replica may reconnect before the next scheduled monitoring cycle.

Without error-log analysis, the current DMV might say:

```text
CONNECTED
```

while the ERRORLOG reveals that the replica disconnected several times during the previous two hours.

---

# 25. Why Recent Errors Matter

Consider this scenario:

```text
10:15 AM --> Replica disconnected
10:18 AM --> Replica reconnected
12:00 PM --> Monitoring job runs
```

A simple current-state monitor sees:

```text
CONNECTED
HEALTHY
```

and reports no issue.

A stronger monitoring solution sees:

```text
Current State = CONNECTED

Recent Event:
Replica connection failure occurred at 10:15 AM
```

It can therefore classify the environment as requiring investigation even though the immediate condition recovered.

This is important for identifying intermittent production problems.

---

# 26. Monitoring History

The framework does not simply send an email and discard the results.

It stores execution history.

The main history areas are:

```text
AGMonitorRunHistory
AGMonitorFindingHistory
AGMonitorDatabaseSnapshot
```

This provides historical evidence for incident investigation.

For example:

```text
12:00 --> Send Queue 100 MB
14:00 --> Send Queue 450 MB
16:00 --> Send Queue 1.2 GB
18:00 --> Send Queue 3.8 GB
```

The DBA can immediately see that the queue has been progressively increasing.

That is much more useful than a single snapshot.

---

# 27. 30-Day and 90-Day Trend Analysis

Historical data can be used for:

* Capacity planning
* Incident RCA
* Network analysis
* Secondary performance analysis
* Queue-growth analysis
* Repeated connection failures
* DR readiness reviews
* SLA reporting

For example:

```sql
SELECT
    CaptureTime,
    AGName,
    DatabaseName,
    ReplicaName,
    LogSendQueueKB / 1024.0 AS LogSendQueueMB,
    LogSendRateKBps,
    EstimatedSendDelaySeconds,
    RedoQueueKB / 1024.0 AS RedoQueueMB,
    RedoRateKBps,
    EstimatedRedoDelaySeconds,
    SecondaryLagSeconds
FROM DBA_Admin.dbo.AGMonitorDatabaseSnapshot
WHERE CaptureTime >= DATEADD(DAY,-30,SYSDATETIME())
ORDER BY CaptureTime DESC;
```

The same history can be retained for 90 days or another period according to company policy.

---

# 28. HTML Email Report

Instead of sending plain-text alerts, the framework generates a structured HTML email.

Example:

```text
SQL Server Always On Health Report

SQL Server       PMSQL01
Host             PMSQL01
Report Time      2026-09-11 12:00
Overall Status   WARNING

Critical Issues  0
Warnings         2
```

The report contains several sections.

### Detected Health Findings

```text
Severity | Category | AG | Database | Replica
```

followed by:

```text
Observation
Recommendation
```

This gives the on-call DBA an immediate starting point.

---

# 29. Example Healthy Notification

A healthy notification may show:

```text
[AG HEALTHY] PMSQL01 | 2-Hour Always On Health Check

Overall Status: HEALTHY

AG:
AGAlpha

Primary:
PMSQL01

Secondary:
PMSQL02

Connectivity:
CONNECTED

Synchronization Health:
HEALTHY

Database:
AdventureWorks2025

Synchronization:
SYNCHRONIZED

Suspended:
NO

Send Queue:
0 MB

Redo Queue:
0 MB

HADR Endpoint:
STARTED

Disk:
Healthy
```

This confirms that both the Availability Group and monitoring process are operating normally.

---

# 30. Example Critical Notification

A critical report could contain:

```text
[AG CRITICAL] PMSQL01 | 2-Hour Always On Health Check

Severity:
CRITICAL

Category:
Replica Connectivity

Availability Group:
AGAlpha

Replica:
PMSQL02

Observation:
Replica is DISCONNECTED.

Last Connection Error:
<SQL Server reported connection error>

Recommendation:
Check SQL Server service,
HADR endpoint,
TCP port,
firewall,
DNS,
network connectivity,
endpoint authentication,
and SQL Server ERRORLOG.
```

Another finding could show:

```text
Severity:
CRITICAL

Category:
Database Synchronization

Database:
AdventureWorks2025

State:
NOT SYNCHRONIZING
```

This gives the DBA multiple pieces of evidence from the same incident.

---

# 31. Configurable Thresholds

Hardcoding thresholds throughout a stored procedure makes maintenance difficult.

The monitoring framework therefore stores configuration separately.

Example:

```text
AGMonitorConfig
```

The DBA can change:

* Email profile
* Recipients
* Send Queue warning
* Send Queue critical
* Redo Queue warning
* Redo Queue critical
* Estimated-delay warning
* Estimated-delay critical
* Secondary-lag thresholds
* Disk thresholds
* ERRORLOG lookback period
* History-retention period

without rewriting the monitoring procedure.

---

# 32. Example Threshold Configuration

A starting configuration might be:

| Metric               |   Warning |   Critical |
| -------------------- | --------: | ---------: |
| Log Send Queue       |    512 MB |       2 GB |
| Redo Queue           |    512 MB |       2 GB |
| Estimated Drain Time | 5 minutes | 15 minutes |
| Secondary Lag        | 5 minutes | 15 minutes |
| Disk Free Space      |       15% |         5% |
| ERRORLOG Lookback    |   2 hours |          — |
| History Retention    |   90 days |          — |

These are operational starting points.

They must be tuned according to the environment.

---

# 33. SQL Server Agent Scheduling

A SQL Server Agent job executes:

```sql
EXEC DBA_Admin.dbo.usp_AG_HealthCheck_Email;
```

every two hours.

Conceptually:

```text
00:00
02:00
04:00
06:00
08:00
10:00
12:00
14:00
16:00
18:00
20:00
22:00
```

The job runs continuously, seven days a week.

Retries can also be configured so a temporary execution problem does not immediately cause the monitoring cycle to be lost.

---

# 34. Monitoring Failure Detection

A monitoring solution itself can fail.

For example:

* DMV permission changed
* Database Mail unavailable
* Procedure error
* DBA database inaccessible
* ERRORLOG permission denied

Therefore, the framework also records monitoring execution failures.

A monitoring failure should generate a separate message such as:

```text
[AG MONITOR FAILURE]
SQL Server Always On Health Check
```

This distinction is important.

There is a difference between:

```text
AG is unhealthy
```

and:

```text
The system responsible for checking the AG failed.
```

Both require DBA attention.

---

# 35. Database Mail Considerations

The framework uses:

```sql
msdb.dbo.sp_send_dbmail
```

to submit the HTML report through SQL Server Database Mail.

Database Mail must therefore be configured and tested before deploying the monitoring solution.

A basic validation should confirm:

```text
Database Mail enabled
        |
        v
Mail profile exists
        |
        v
SQL Agent/job execution context can use it
        |
        v
Test mail succeeds
        |
        v
AG monitoring mail enabled
```

Database Mail itself should also be monitored independently because an AG monitoring procedure cannot guarantee delivery if the mail infrastructure is unavailable.

---

# 36. Security and Permissions

The monitoring account should follow least-privilege principles.

Depending on SQL Server version and the monitoring operations being performed, permissions may be required to access server-level dynamic management information and SQL Server error logs.

Permissions should be tested using the **actual SQL Server Agent execution context**, not only through an administrator's SSMS session.

This prevents a common situation where:

```text
DBA manual test = Works
SQL Agent job   = Permission denied
```

---

# 37. Production Troubleshooting Workflow

When a CRITICAL email arrives, use a structured process.

```text
CRITICAL ALERT
      |
      v
Identify affected AG
      |
      v
Identify database/replica
      |
      v
Check replica connectivity
      |
      v
Check synchronization state
      |
      v
Check suspended state
      |
      v
Check Send Queue
      |
      v
Check Redo Queue
      |
      v
Check secondary lag
      |
      v
Check endpoint
      |
      v
Check recent HADR errors
      |
      v
Check disk/storage
      |
      v
Check WSFC/network if required
      |
      v
Identify Root Cause
      |
      v
Correct Root Cause
      |
      v
Monitor Recovery
```

Only after the underlying issue is understood should corrective actions such as restarting services, resuming data movement, or failing over replicas be considered.

---

# 38. Real-Time Scenario – Network Failure

Assume:

```text
Primary   : PMSQL01
Secondary : PMSQL02
AG        : AGAlpha
```

The network connection between the servers fails.

The monitor may detect:

```text
Replica Connectivity:
DISCONNECTED

Synchronization Health:
NOT_HEALTHY

Database:
NOT SYNCHRONIZING

Log Send Queue:
Increasing

Send Rate:
0 KB/sec

Recent HADR Error:
Connection-related error
```

These multiple signals strongly point toward connectivity rather than a database-engine synchronization problem.

The DBA then investigates:

```text
PMSQL01
   |
   X
   |
PMSQL02

DNS
Firewall
TCP 5022
Routing
NIC
Network
HADR Endpoint
SQL Service
```

---

# 39. Real-Time Scenario – Slow Secondary Storage

Now assume the network is healthy.

The monitor reports:

```text
Replica:
CONNECTED

Synchronization:
SYNCHRONIZING

Log Send Queue:
Small

Redo Queue:
Rapidly increasing

Redo Rate:
Low

Secondary Lag:
Increasing
```

This pattern points more toward the **secondary's ability to redo changes**.

Investigation should focus on:

* Secondary disk latency
* CPU pressure
* Storage throughput
* Heavy readable-secondary workload
* Resource contention
* Redo performance

Restarting the primary SQL Server would make little sense in this scenario.

---

# 40. Real-Time Scenario – Log Transport Bottleneck

Another pattern might be:

```text
Replica:
CONNECTED

Send Queue:
Increasing

Send Rate:
Low

Redo Queue:
Small
```

This suggests the bottleneck occurs before redo.

Possible areas include:

```text
Primary log generation
        |
        v
Log capture
        |
        v
Network transport   <-- investigate
        |
        v
Secondary hardening
        |
        v
Redo
```

Network throughput, latency, flow control, secondary log-disk performance, and transaction-log generation rate should be investigated.

---

# 41. Real-Time Scenario – Disk Space Problem

Suppose the secondary transaction-log volume reaches:

```text
Free Space = 4%
```

The monitor raises:

```text
CRITICAL
Disk Space
```

At the same time:

```text
Redo Queue increasing
Secondary lag increasing
```

The disk alert gives the DBA an important clue that the synchronization problem may be connected to storage capacity or storage performance.

This demonstrates why Always On monitoring should include supporting infrastructure signals rather than only AG synchronization state.

---

# 42. What This Monitoring Does Not Replace

SQL Server-based monitoring is extremely useful, but it cannot directly diagnose every external infrastructure problem.

For example:

* Failed physical network switch
* SAN controller failure
* Hypervisor problem
* Datacenter network outage
* Operating system failure
* Cluster communication issue outside SQL
* Corporate SMTP outage

SQL Server may show the resulting symptoms, such as:

```text
DISCONNECTED
NOT SYNCHRONIZING
Large Send Queue
Connection timeout
```

but infrastructure monitoring may still be required to identify the physical cause.

For enterprise environments, SQL Server Always On monitoring should therefore complement:

* Windows monitoring
* WSFC monitoring
* Network monitoring
* Storage monitoring
* VM/hypervisor monitoring
* Enterprise observability tools

---

# 43. Why Restarting Services Is Not the First Fix

A service restart can occasionally clear a symptom, but it can also destroy valuable evidence and introduce additional downtime.

Consider:

```text
NOT SYNCHRONIZING
       |
       v
DBA restarts SQL Server immediately
       |
       v
Problem temporarily disappears
       |
       v
Root cause remains unknown
       |
       v
Problem returns during production peak
```

A better approach is:

```text
Detect
  |
Analyze
  |
Correlate
  |
Identify root cause
  |
Correct
  |
Validate
  |
Monitor
```

That is the difference between reactive administration and production-grade HA/DR operations.

---

# 44. Recommended Production Deployment

Deploy the monitoring components on every participating replica.

For example:

```text
                 AGAlpha

          +------------------+
          |                  |
       PMSQL01            PMSQL02
       PRIMARY           SECONDARY
          |                  |
       Monitor            Monitor
          |                  |
          +--------+---------+
                   |
                DBA Team


                 AGBeta

          +------------------+
          |                  |
       PMSQL03            PMSQL04
       PRIMARY           SECONDARY
          |                  |
       Monitor            Monitor
          |                  |
          +--------+---------+
                   |
                DBA Team
```

This avoids depending entirely on one SQL Server for HA monitoring.

---

# 45. Recommended Alert Philosophy

Do not design Always On monitoring around only:

```text
Is database SYNCHRONIZED?
```

Instead ask:

```text
Is the replica connected?

Is synchronization healthy?

Is data movement active?

Is the Send Queue under control?

Is the Send Rate keeping up?

Is the Redo Queue under control?

Is Redo Rate keeping up?

Is secondary lag acceptable?

Is the endpoint healthy?

Are databases healthy?

Is disk space sufficient?

Is transaction-log truncation blocked?

Did HADR report recent errors?

Is the condition getting better or worse?
```

That provides a much stronger picture of HA/DR health.

---

# 46. Benefits

This monitoring framework provides:

* Proactive Always On monitoring
* Healthy heartbeat notifications
* Warning-level early detection
* Critical incident notification
* Primary and secondary monitoring
* Reduced duplicate healthy emails
* NOT SYNCHRONIZING detection
* Replica disconnection detection
* Suspended-data-movement detection
* Log Send Queue monitoring
* Redo Queue monitoring
* Send/redo rate monitoring
* Estimated backlog drain time
* Secondary-lag monitoring
* HADR endpoint monitoring
* Disk-space monitoring
* Transaction-log reuse monitoring
* Recent HADR ERRORLOG analysis
* Root-cause-oriented recommendations
* HTML DBA reporting
* Historical monitoring data
* Trend analysis
* Better RCA evidence

---

# 47. Key DBA Principle

The most important principle is:

> **Do not monitor only the final symptom. Monitor the complete data-movement path.**

Always On data movement can be viewed conceptually as:

```text
PRIMARY
   |
Transaction Log
   |
Log Capture
   |
Log Send Queue
   |
HADR Endpoint
   |
Network
   |
Secondary Endpoint
   |
Log Hardening
   |
Redo Queue
   |
Redo Processing
   |
SECONDARY DATABASE
```

A problem at any point in this chain can eventually appear as synchronization lag or `NOT SYNCHRONIZING`.

The monitoring system should therefore collect enough information to identify **which part of that chain is failing**.

---

# 48. Final Production Flow

The complete monitoring approach becomes:

```text
SQL Server Agent
       |
       | Every 2 Hours
       v
Always On Monitoring Procedure
       |
       +--> Replica State
       |
       +--> Connection State
       |
       +--> Synchronization Health
       |
       +--> Database State
       |
       +--> Suspended Movement
       |
       +--> Send Queue / Rate
       |
       +--> Estimated Send Delay
       |
       +--> Redo Queue / Rate
       |
       +--> Estimated Redo Delay
       |
       +--> Secondary Lag
       |
       +--> HADR Endpoint
       |
       +--> Last Connection Error
       |
       +--> Disk Space
       |
       +--> Log Reuse Wait
       |
       +--> Recent HADR ERRORLOG
       |
       v
Analyze Severity
       |
 +-----+-------+
 |     |       |
 v     v       v
Healthy Warning Critical
 |     |       |
 +-----+-------+
       |
       v
HTML Email to DBA Team
       |
       v
Store History
       |
       v
30/90-Day Trend Analysis
```

# Conclusion

SQL Server Always On monitoring should go far beyond detecting `NOT SYNCHRONIZING`.

That state is often only the visible symptom.

A production-ready monitoring solution should correlate replica connectivity, synchronization health, Log Send Queue, Send Rate, Redo Queue, Redo Rate, secondary lag, suspended data movement, endpoint health, database state, disk capacity, transaction-log reuse, connection errors, and SQL Server ERRORLOG events.

The objective is not simply to tell the DBA:

**“Always On is unhealthy.”**

The objective is to provide enough evidence to answer:

**“What is unhealthy, which replica/database is affected, how serious is it, and where should I start troubleshooting?”**

That approach reduces troubleshooting time, improves HA/DR visibility, provides better RCA evidence, and helps DBAs identify developing problems before they become major production outages.

**Reference implementation:** `SQL_Server_AlwaysOn_2Hour_Health_Monitor.sql`

**Reference standard:** Microsoft SQL Server Always On Availability Groups, Always On dynamic management views, SQL Server Agent, Database Mail, database mirroring/HADR endpoints, SQL Server ERRORLOG, and SQL Server storage DMVs.
