/*
===============================================================================
 SQL Server Always On Availability Groups - Production Health Monitoring
 Version      : 1.0
 Target       : SQL Server 2019 / 2022 / 2025
 Schedule     : Every 2 hours
 Purpose      : Healthy heartbeat + WARNING/CRITICAL Always On notifications
 Deployment   : Run on EACH SQL Server instance participating in an AG
===============================================================================

IMPORTANT BEFORE RUNNING
------------------------
1. Configure Database Mail first.
2. In section "CONFIGURATION VALUES", set:
      MailProfile
      Recipients
3. Deploy on every AG replica.
4. SQL Server Agent must be running.
5. Recommended permissions for the Agent job owner/execution context:
      VIEW SERVER STATE (SQL Server 2019 and earlier)
      VIEW SERVER PERFORMANCE STATE as applicable on newer versions
      VIEW ANY ERROR LOG or equivalent on SQL Server 2022+
6. Queue/disk thresholds below are STARTING VALUES. Tune them for your workload.

MAIL BEHAVIOR
-------------
Default = PRIMARY_PLUS_FAILSAFE

* A server hosting a PRIMARY replica sends the normal 2-hour heartbeat:
      HEALTHY / WARNING / CRITICAL

* A server hosting only SECONDARY replicas sends mail only when it detects
  WARNING/CRITICAL locally. This prevents duplicate healthy emails while still
  providing fail-safe notification if the primary is unavailable.

To receive an email from EVERY replica every two hours, change:
      SendHealthyFromSecondary = 1
===============================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*=============================================================================
  0. PRECHECK
=============================================================================*/

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS int) <> 1
BEGIN
    THROW 51000, 'Always On Availability Groups is not enabled on this SQL Server instance.', 1;
END;
GO

/*=============================================================================
  1. DBA DATABASE
=============================================================================*/

USE master;
GO

IF DB_ID(N'DBA_Admin') IS NULL
BEGIN
    PRINT 'Creating DBA_Admin database...';
    CREATE DATABASE DBA_Admin;
END;
GO

ALTER DATABASE DBA_Admin SET RECOVERY SIMPLE;
GO

USE DBA_Admin;
GO

/*=============================================================================
  2. CONFIGURATION TABLE
=============================================================================*/

IF OBJECT_ID(N'dbo.AGMonitorConfig', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AGMonitorConfig
    (
        ConfigID                        tinyint         NOT NULL
            CONSTRAINT PK_AGMonitorConfig PRIMARY KEY
            CONSTRAINT CK_AGMonitorConfig_OneRow CHECK (ConfigID = 1),

        Enabled                         bit             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_Enabled DEFAULT (1),

        MailProfile                     sysname         NOT NULL,
        Recipients                      varchar(2000)   NOT NULL,

        SendHealthyFromSecondary        bit             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_SendHealthySecondary DEFAULT (0),

        SendQueueWarningMB              bigint          NOT NULL
            CONSTRAINT DF_AGMonitorConfig_SendQueueWarning DEFAULT (512),

        SendQueueCriticalMB             bigint          NOT NULL
            CONSTRAINT DF_AGMonitorConfig_SendQueueCritical DEFAULT (2048),

        RedoQueueWarningMB              bigint          NOT NULL
            CONSTRAINT DF_AGMonitorConfig_RedoQueueWarning DEFAULT (512),

        RedoQueueCriticalMB             bigint          NOT NULL
            CONSTRAINT DF_AGMonitorConfig_RedoQueueCritical DEFAULT (2048),

        EstimatedDelayWarningSeconds    int             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_DelayWarning DEFAULT (300),

        EstimatedDelayCriticalSeconds   int             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_DelayCritical DEFAULT (900),

        SecondaryLagWarningSeconds      int             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_LagWarning DEFAULT (300),

        SecondaryLagCriticalSeconds     int             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_LagCritical DEFAULT (900),

        DiskWarningPercent              decimal(5,2)    NOT NULL
            CONSTRAINT DF_AGMonitorConfig_DiskWarning DEFAULT (15.00),

        DiskCriticalPercent             decimal(5,2)    NOT NULL
            CONSTRAINT DF_AGMonitorConfig_DiskCritical DEFAULT (5.00),

        ErrorLogLookbackHours           int             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_ErrorLookback DEFAULT (2),

        HistoryRetentionDays            int             NOT NULL
            CONSTRAINT DF_AGMonitorConfig_Retention DEFAULT (90),

        LastUpdated                     datetime2(0)    NOT NULL
            CONSTRAINT DF_AGMonitorConfig_LastUpdated DEFAULT (SYSDATETIME())
    );
END;
GO

/*=============================================================================
  CONFIGURATION VALUES - CHANGE THESE TWO VALUES
=============================================================================*/

IF NOT EXISTS (SELECT 1 FROM dbo.AGMonitorConfig WHERE ConfigID = 1)
BEGIN
    INSERT dbo.AGMonitorConfig
    (
        ConfigID,
        MailProfile,
        Recipients
    )
    VALUES
    (
        1,
        N'DBA_Mail_Profile',          -- <<< CHANGE
        'DBATeam@yourcompany.com'    -- <<< CHANGE
    );
END;
GO

/*
Example configuration update:

UPDATE dbo.AGMonitorConfig
SET MailProfile                  = N'SQL_DBA_Mail',
    Recipients                   = 'dba-team@company.com;noc@company.com',
    SendHealthyFromSecondary     = 0,
    SendQueueWarningMB           = 512,
    SendQueueCriticalMB          = 2048,
    RedoQueueWarningMB           = 512,
    RedoQueueCriticalMB          = 2048,
    EstimatedDelayWarningSeconds = 300,
    EstimatedDelayCriticalSeconds= 900,
    SecondaryLagWarningSeconds   = 300,
    SecondaryLagCriticalSeconds  = 900,
    DiskWarningPercent           = 15,
    DiskCriticalPercent          = 5,
    ErrorLogLookbackHours        = 2,
    HistoryRetentionDays         = 90,
    LastUpdated                  = SYSDATETIME()
WHERE ConfigID = 1;
GO
*/

/*=============================================================================
  3. EXECUTION HISTORY
=============================================================================*/

IF OBJECT_ID(N'dbo.AGMonitorRunHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AGMonitorRunHistory
    (
        RunID               bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_AGMonitorRunHistory PRIMARY KEY,
        ServerName          sysname              NOT NULL,
        HostName            sysname              NULL,
        RunStartTime        datetime2(0)         NOT NULL,
        RunEndTime          datetime2(0)         NULL,
        OverallStatus       varchar(10)          NULL,
        CriticalCount       int                  NOT NULL DEFAULT (0),
        WarningCount        int                  NOT NULL DEFAULT (0),
        HealthyCount        int                  NOT NULL DEFAULT (0),
        EmailAttempted      bit                  NOT NULL DEFAULT (0),
        EmailQueued         bit                  NOT NULL DEFAULT (0),
        EmailError          nvarchar(4000)       NULL,
        ProcedureError      nvarchar(4000)       NULL
    );

    CREATE INDEX IX_AGMonitorRunHistory_RunStartTime
        ON dbo.AGMonitorRunHistory(RunStartTime);
END;
GO

/*=============================================================================
  4. FINDING HISTORY
=============================================================================*/

IF OBJECT_ID(N'dbo.AGMonitorFindingHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AGMonitorFindingHistory
    (
        FindingID           bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_AGMonitorFindingHistory PRIMARY KEY,
        RunID               bigint               NOT NULL,
        CaptureTime         datetime2(0)         NOT NULL,
        Severity            varchar(10)          NOT NULL,
        Category            varchar(60)          NOT NULL,
        AGName              sysname              NULL,
        DatabaseName        sysname              NULL,
        ReplicaName         sysname              NULL,
        Observation         nvarchar(2048)       NOT NULL,
        Recommendation      nvarchar(2048)       NULL,

        CONSTRAINT FK_AGMonitorFindingHistory_Run
            FOREIGN KEY (RunID)
            REFERENCES dbo.AGMonitorRunHistory(RunID)
    );

    CREATE INDEX IX_AGMonitorFindingHistory_RunID
        ON dbo.AGMonitorFindingHistory(RunID);

    CREATE INDEX IX_AGMonitorFindingHistory_CaptureTime
        ON dbo.AGMonitorFindingHistory(CaptureTime);
END;
GO

/*=============================================================================
  5. DATABASE/REPLICA SNAPSHOT HISTORY
=============================================================================*/

IF OBJECT_ID(N'dbo.AGMonitorDatabaseSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AGMonitorDatabaseSnapshot
    (
        SnapshotID                  bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_AGMonitorDatabaseSnapshot PRIMARY KEY,
        RunID                       bigint               NOT NULL,
        CaptureTime                 datetime2(0)         NOT NULL,
        AGName                      sysname              NULL,
        IsDistributed              bit                  NULL,
        DatabaseName               sysname              NULL,
        ReplicaName                sysname              NULL,
        IsLocal                    bit                  NULL,
        RoleDesc                   nvarchar(60)         NULL,
        AvailabilityModeDesc       nvarchar(60)         NULL,
        ConnectedStateDesc         nvarchar(60)         NULL,
        SynchronizationStateDesc   nvarchar(60)         NULL,
        SynchronizationHealthDesc  nvarchar(60)         NULL,
        DatabaseStateDesc          nvarchar(60)         NULL,
        IsSuspended                bit                  NULL,
        SuspendReasonDesc          nvarchar(60)         NULL,
        LogSendQueueKB             bigint               NULL,
        LogSendRateKBps            bigint               NULL,
        EstimatedSendDelaySeconds  decimal(18,2)        NULL,
        RedoQueueKB                bigint               NULL,
        RedoRateKBps               bigint               NULL,
        EstimatedRedoDelaySeconds  decimal(18,2)        NULL,
        SecondaryLagSeconds        bigint               NULL,
        LastSentTime               datetime             NULL,
        LastReceivedTime           datetime             NULL,
        LastHardenedTime           datetime             NULL,
        LastRedoneTime             datetime             NULL,
        LastCommitTime             datetime             NULL,

        CONSTRAINT FK_AGMonitorDatabaseSnapshot_Run
            FOREIGN KEY (RunID)
            REFERENCES dbo.AGMonitorRunHistory(RunID)
    );

    CREATE INDEX IX_AGMonitorDatabaseSnapshot_Capture
        ON dbo.AGMonitorDatabaseSnapshot(CaptureTime, AGName, DatabaseName);
END;
GO

/*=============================================================================
  6. HTML ENCODING FUNCTION
=============================================================================*/

CREATE OR ALTER FUNCTION dbo.ufn_AGMonitor_HtmlEncode
(
    @Input nvarchar(max)
)
RETURNS nvarchar(max)
AS
BEGIN
    IF @Input IS NULL RETURN N'';

    RETURN
        REPLACE(
        REPLACE(
        REPLACE(
        REPLACE(
        REPLACE(@Input,
            N'&', N'&amp;'),
            N'<', N'&lt;'),
            N'>', N'&gt;'),
            N'"', N'&quot;'),
            N'''', N'&#39;');
END;
GO

/*=============================================================================
  7. MAIN HEALTH CHECK PROCEDURE
=============================================================================*/

CREATE OR ALTER PROCEDURE dbo.usp_AG_HealthCheck_Email
    @ForceEmail bit = 0,
    @Debug     bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE
        @RunID                          bigint,
        @RunStart                       datetime2(0) = SYSDATETIME(),
        @ServerName                     sysname = CAST(SERVERPROPERTY('ServerName') AS sysname),
        @HostName                       sysname = CAST(SERVERPROPERTY('MachineName') AS sysname),
        @MailProfile                    sysname,
        @Recipients                     varchar(2000),
        @Enabled                        bit,
        @SendHealthyFromSecondary       bit,
        @SendQueueWarningMB             bigint,
        @SendQueueCriticalMB            bigint,
        @RedoQueueWarningMB             bigint,
        @RedoQueueCriticalMB            bigint,
        @DelayWarningSec                int,
        @DelayCriticalSec               int,
        @LagWarningSec                  int,
        @LagCriticalSec                 int,
        @DiskWarningPct                 decimal(5,2),
        @DiskCriticalPct                decimal(5,2),
        @ErrorLookbackHours             int,
        @RetentionDays                  int,
        @HasPrimary                     bit = 0,
        @CriticalCount                  int = 0,
        @WarningCount                   int = 0,
        @HealthyCount                   int = 0,
        @OverallStatus                  varchar(10),
        @ShouldSend                     bit = 0,
        @EmailQueued                    bit = 0,
        @Subject                        nvarchar(255),
        @Body                           nvarchar(max),
        @Rows                           nvarchar(max),
        @Now                            datetime2(0) = SYSDATETIME();

    SELECT
        @Enabled                      = Enabled,
        @MailProfile                  = MailProfile,
        @Recipients                   = Recipients,
        @SendHealthyFromSecondary     = SendHealthyFromSecondary,
        @SendQueueWarningMB           = SendQueueWarningMB,
        @SendQueueCriticalMB          = SendQueueCriticalMB,
        @RedoQueueWarningMB           = RedoQueueWarningMB,
        @RedoQueueCriticalMB          = RedoQueueCriticalMB,
        @DelayWarningSec              = EstimatedDelayWarningSeconds,
        @DelayCriticalSec             = EstimatedDelayCriticalSeconds,
        @LagWarningSec                = SecondaryLagWarningSeconds,
        @LagCriticalSec               = SecondaryLagCriticalSeconds,
        @DiskWarningPct               = DiskWarningPercent,
        @DiskCriticalPct              = DiskCriticalPercent,
        @ErrorLookbackHours           = ErrorLogLookbackHours,
        @RetentionDays                = HistoryRetentionDays
    FROM dbo.AGMonitorConfig
    WHERE ConfigID = 1;

    IF @Enabled IS NULL
        THROW 51001, 'AG monitor configuration row ConfigID=1 does not exist.', 1;

    IF @Enabled = 0
    BEGIN
        PRINT 'AG monitoring is disabled in dbo.AGMonitorConfig.';
        RETURN;
    END;

    INSERT dbo.AGMonitorRunHistory
    (
        ServerName,
        HostName,
        RunStartTime
    )
    VALUES
    (
        @ServerName,
        @HostName,
        @RunStart
    );

    SET @RunID = SCOPE_IDENTITY();

    CREATE TABLE #Findings
    (
        FindingOrder      int IDENTITY(1,1) NOT NULL,
        Severity          varchar(10)        NOT NULL,
        Category          varchar(60)        NOT NULL,
        AGName            sysname            NULL,
        DatabaseName      sysname            NULL,
        ReplicaName       sysname            NULL,
        Observation       nvarchar(2048)      NOT NULL,
        Recommendation    nvarchar(2048)      NULL
    );

    BEGIN TRY

        /*---------------------------------------------------------------------
          A. BASIC AG EXISTENCE
        ---------------------------------------------------------------------*/

        IF NOT EXISTS (SELECT 1 FROM sys.availability_groups)
        BEGIN
            INSERT #Findings
            (
                Severity, Category, Observation, Recommendation
            )
            VALUES
            (
                'WARNING',
                'Availability Group',
                N'Always On is enabled on the SQL Server instance, but no availability group metadata is currently visible.',
                N'Confirm the expected AG configuration, WSFC state, and whether this instance should host an availability replica.'
            );
        END;

        /*---------------------------------------------------------------------
          B. DETERMINE WHETHER THIS INSTANCE CURRENTLY HOSTS A PRIMARY
        ---------------------------------------------------------------------*/

        IF EXISTS
        (
            SELECT 1
            FROM sys.dm_hadr_availability_replica_states
            WHERE is_local = 1
              AND role_desc = 'PRIMARY'
        )
        SET @HasPrimary = 1;

        /*---------------------------------------------------------------------
          C. REPLICA STATE
        ---------------------------------------------------------------------*/

        SELECT
            ag.group_id,
            ag.name                                           AS AGName,
            ag.is_distributed,
            ar.replica_id,
            ar.replica_server_name,
            ar.endpoint_url,
            ar.availability_mode_desc,
            ar.failover_mode_desc,
            ars.is_local,
            ars.role_desc,
            ars.operational_state_desc,
            ars.connected_state_desc,
            ars.recovery_health_desc,
            ars.synchronization_health_desc,
            ars.last_connect_error_number,
            ars.last_connect_error_description,
            ars.last_connect_error_timestamp
        INTO #Replica
        FROM sys.availability_groups AS ag
        INNER JOIN sys.availability_replicas AS ar
            ON ag.group_id = ar.group_id
        LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
            ON ar.group_id = ars.group_id
           AND ar.replica_id = ars.replica_id;

        INSERT #Findings
        SELECT
            'CRITICAL',
            'Replica Connectivity',
            AGName,
            NULL,
            replica_server_name,
            CONCAT(
                N'Replica is DISCONNECTED. Endpoint = ',
                COALESCE(endpoint_url, N'UNKNOWN'),
                N'. Last connection error = ',
                COALESCE(CONVERT(nvarchar(20), last_connect_error_number), N'UNKNOWN'),
                N' - ',
                COALESCE(last_connect_error_description, N'No description available'),
                N'.'
            ),
            N'Check SQL Server service, HADR endpoint, DNS, TCP connectivity, firewall rules, endpoint authentication/certificates, network path, and SQL Server error log.'
        FROM #Replica
        WHERE connected_state_desc = 'DISCONNECTED';

        INSERT #Findings
        SELECT
            'CRITICAL',
            'Replica Operational State',
            AGName,
            NULL,
            replica_server_name,
            CONCAT(N'Replica operational state is ', operational_state_desc, N'.'),
            N'Check WSFC/quorum, SQL Server service state, cluster events, replica connectivity, and Windows/System logs.'
        FROM #Replica
        WHERE operational_state_desc IN ('FAILED', 'FAILED_NO_QUORUM', 'OFFLINE');

        INSERT #Findings
        SELECT
            CASE
                WHEN synchronization_health_desc = 'NOT_HEALTHY' THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Replica Synchronization Health',
            AGName,
            NULL,
            replica_server_name,
            CONCAT(N'Replica synchronization health is ', synchronization_health_desc, N'.'),
            N'Check database synchronization state, suspended data movement, send/redo queues, replica connectivity, and HADR error log entries.'
        FROM #Replica
        WHERE synchronization_health_desc IN ('NOT_HEALTHY', 'PARTIALLY_HEALTHY');

        INSERT #Findings
        SELECT
            'WARNING',
            'Recent Replica Connection Error',
            AGName,
            NULL,
            replica_server_name,
            CONCAT(
                N'Error ', last_connect_error_number, N': ',
                COALESCE(last_connect_error_description, N'No description'),
                N' at ',
                CONVERT(nvarchar(19), last_connect_error_timestamp, 120),
                N'.'
            ),
            N'Validate endpoint URL, DNS, firewall, TCP port, network stability, service account permissions/certificates, and remote SQL availability.'
        FROM #Replica
        WHERE ISNULL(last_connect_error_number, 0) <> 0
          AND last_connect_error_timestamp >= DATEADD(HOUR, -@ErrorLookbackHours, @Now);

        /*---------------------------------------------------------------------
          D. DATABASE REPLICA STATE
        ---------------------------------------------------------------------*/

        SELECT
            ag.name                                           AS AGName,
            ag.is_distributed,
            DB_NAME(drs.database_id)                           AS DatabaseName,
            ar.replica_server_name,
            drs.is_local,
            ars.role_desc,
            ar.availability_mode_desc,
            ars.connected_state_desc,
            drs.synchronization_state_desc,
            drs.synchronization_health_desc,
            drs.database_state_desc,
            drs.is_suspended,
            drs.suspend_reason_desc,
            drs.log_send_queue_size,
            drs.log_send_rate,
            CAST(
                CASE
                    WHEN drs.log_send_queue_size > 0
                     AND drs.log_send_rate > 0
                    THEN drs.log_send_queue_size * 1.0 / drs.log_send_rate
                END
                AS decimal(18,2)
            ) AS EstimatedSendDelaySeconds,
            drs.redo_queue_size,
            drs.redo_rate,
            CAST(
                CASE
                    WHEN drs.redo_queue_size > 0
                     AND drs.redo_rate > 0
                    THEN drs.redo_queue_size * 1.0 / drs.redo_rate
                END
                AS decimal(18,2)
            ) AS EstimatedRedoDelaySeconds,
            drs.secondary_lag_seconds,
            drs.last_sent_time,
            drs.last_received_time,
            drs.last_hardened_time,
            drs.last_redone_time,
            drs.last_commit_time
        INTO #DBState
        FROM sys.dm_hadr_database_replica_states AS drs
        INNER JOIN sys.availability_groups AS ag
            ON drs.group_id = ag.group_id
        INNER JOIN sys.availability_replicas AS ar
            ON drs.group_id = ar.group_id
           AND drs.replica_id = ar.replica_id
        LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
            ON drs.group_id = ars.group_id
           AND drs.replica_id = ars.replica_id;

        INSERT dbo.AGMonitorDatabaseSnapshot
        (
            RunID, CaptureTime, AGName, IsDistributed, DatabaseName,
            ReplicaName, IsLocal, RoleDesc, AvailabilityModeDesc,
            ConnectedStateDesc, SynchronizationStateDesc,
            SynchronizationHealthDesc, DatabaseStateDesc, IsSuspended,
            SuspendReasonDesc, LogSendQueueKB, LogSendRateKBps,
            EstimatedSendDelaySeconds, RedoQueueKB, RedoRateKBps,
            EstimatedRedoDelaySeconds, SecondaryLagSeconds,
            LastSentTime, LastReceivedTime, LastHardenedTime,
            LastRedoneTime, LastCommitTime
        )
        SELECT
            @RunID, @Now, AGName, is_distributed, DatabaseName,
            replica_server_name, is_local, role_desc, availability_mode_desc,
            connected_state_desc, synchronization_state_desc,
            synchronization_health_desc, database_state_desc, is_suspended,
            suspend_reason_desc, log_send_queue_size, log_send_rate,
            EstimatedSendDelaySeconds, redo_queue_size, redo_rate,
            EstimatedRedoDelaySeconds, secondary_lag_seconds,
            last_sent_time, last_received_time, last_hardened_time,
            last_redone_time, last_commit_time
        FROM #DBState;

        /* NOT SYNCHRONIZING */

        INSERT #Findings
        SELECT
            'CRITICAL',
            'Database Synchronization',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Database synchronization state is ',
                COALESCE(synchronization_state_desc, N'UNKNOWN'),
                N'; synchronization health is ',
                COALESCE(synchronization_health_desc, N'UNKNOWN'),
                N'.'
            ),
            N'Check replica connectivity, HADR endpoint, transaction log transport, suspended data movement, storage health, and SQL Server error log.'
        FROM #DBState
        WHERE synchronization_state_desc = 'NOT SYNCHRONIZING';

        /* SUSPENDED */

        INSERT #Findings
        SELECT
            'CRITICAL',
            'Data Movement Suspended',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Data movement is suspended. Suspend reason = ',
                COALESCE(suspend_reason_desc, N'UNKNOWN'),
                N'.'
            ),
            N'Investigate the suspend reason and SQL Server error log first. Resume HADR only after the underlying cause is understood and corrected.'
        FROM #DBState
        WHERE is_suspended = 1;

        /* BAD DATABASE STATE */

        INSERT #Findings
        SELECT
            'CRITICAL',
            'Database State',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(N'Availability database state is ', database_state_desc, N'.'),
            N'Investigate database recovery, storage/I/O, SQL Server error log, and availability-group health immediately.'
        FROM #DBState
        WHERE database_state_desc IN
        (
            'RECOVERY_PENDING', 'SUSPECT', 'EMERGENCY', 'OFFLINE'
        );

        /* SEND QUEUE SIZE */

        INSERT #Findings
        SELECT
            CASE
                WHEN log_send_queue_size >= @SendQueueCriticalMB * 1024 THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Log Send Queue',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Log send queue = ',
                CONVERT(nvarchar(30), CAST(log_send_queue_size / 1024.0 AS decimal(18,2))),
                N' MB; send rate = ',
                COALESCE(CONVERT(nvarchar(30), log_send_rate), N'NULL'),
                N' KB/sec; estimated drain time = ',
                COALESCE(CONVERT(nvarchar(30), EstimatedSendDelaySeconds), N'N/A'),
                N' seconds.'
            ),
            N'Check log generation rate, network throughput/latency, remote replica hardening, storage latency, CPU pressure, and replica connectivity.'
        FROM #DBState
        WHERE log_send_queue_size >= @SendQueueWarningMB * 1024;

        /* SEND DELAY */

        INSERT #Findings
        SELECT
            CASE
                WHEN EstimatedSendDelaySeconds >= @DelayCriticalSec THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Estimated Send Delay',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Estimated send queue drain time = ',
                CONVERT(nvarchar(30), EstimatedSendDelaySeconds),
                N' seconds.'
            ),
            N'Investigate transaction-log generation versus send throughput. Queue size alone is not enough; trend queue size and send rate together.'
        FROM #DBState
        WHERE EstimatedSendDelaySeconds >= @DelayWarningSec;

        /* SEND STALL */

        INSERT #Findings
        SELECT
            'CRITICAL',
            'Log Transport Stalled',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Log send queue contains ',
                CONVERT(nvarchar(30), CAST(log_send_queue_size / 1024.0 AS decimal(18,2))),
                N' MB while log_send_rate is 0 KB/sec.'
            ),
            N'Check replica connectivity, HADR endpoint/network path, remote SQL service, flow control, storage, and HADR errors.'
        FROM #DBState
        WHERE log_send_queue_size > 0
          AND ISNULL(log_send_rate, 0) = 0
          AND synchronization_state_desc = 'NOT SYNCHRONIZING';

        /* REDO QUEUE SIZE */

        INSERT #Findings
        SELECT
            CASE
                WHEN redo_queue_size >= @RedoQueueCriticalMB * 1024 THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Redo Queue',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Redo queue = ',
                CONVERT(nvarchar(30), CAST(redo_queue_size / 1024.0 AS decimal(18,2))),
                N' MB; redo rate = ',
                COALESCE(CONVERT(nvarchar(30), redo_rate), N'NULL'),
                N' KB/sec; estimated drain time = ',
                COALESCE(CONVERT(nvarchar(30), EstimatedRedoDelaySeconds), N'N/A'),
                N' seconds.'
            ),
            N'Check secondary replica CPU, storage latency/throughput, read workload, blocking, and redo performance.'
        FROM #DBState
        WHERE redo_queue_size >= @RedoQueueWarningMB * 1024;

        /* REDO DELAY */

        INSERT #Findings
        SELECT
            CASE
                WHEN EstimatedRedoDelaySeconds >= @DelayCriticalSec THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Estimated Redo Delay',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Estimated redo queue drain time = ',
                CONVERT(nvarchar(30), EstimatedRedoDelaySeconds),
                N' seconds.'
            ),
            N'Investigate secondary CPU, data-file I/O latency, storage throughput, read-only workload, and redo blocking/pressure.'
        FROM #DBState
        WHERE EstimatedRedoDelaySeconds >= @DelayWarningSec;

        /* SECONDARY LAG */

        INSERT #Findings
        SELECT
            CASE
                WHEN secondary_lag_seconds >= @LagCriticalSec THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Secondary Lag',
            AGName,
            DatabaseName,
            replica_server_name,
            CONCAT(
                N'Secondary lag = ',
                CONVERT(nvarchar(30), secondary_lag_seconds),
                N' seconds.'
            ),
            N'Check log transport, network latency, log hardening, redo throughput, secondary workload, and storage performance.'
        FROM #DBState
        WHERE secondary_lag_seconds >= @LagWarningSec;

        /*---------------------------------------------------------------------
          E. HADR ENDPOINT
        ---------------------------------------------------------------------*/

        SELECT
            dme.name,
            dme.state_desc,
            dme.connection_auth_desc,
            dme.is_encryption_enabled,
            te.port
        INTO #Endpoint
        FROM sys.database_mirroring_endpoints AS dme
        LEFT JOIN sys.tcp_endpoints AS te
            ON dme.endpoint_id = te.endpoint_id;

        IF NOT EXISTS (SELECT 1 FROM #Endpoint)
        BEGIN
            INSERT #Findings
            (
                Severity, Category, Observation, Recommendation
            )
            VALUES
            (
                'CRITICAL',
                'HADR Endpoint',
                N'No database mirroring/HADR endpoint was found on this Always On enabled instance.',
                N'Validate Always On endpoint configuration and the expected AG replica configuration.'
            );
        END;

        INSERT #Findings
        SELECT
            'CRITICAL',
            'HADR Endpoint',
            NULL,
            NULL,
            @ServerName,
            CONCAT(
                N'Endpoint ', name,
                N' is ', state_desc,
                N'; TCP port = ',
                COALESCE(CONVERT(nvarchar(10), port), N'UNKNOWN'),
                N'.'
            ),
            N'The HADR endpoint should normally be STARTED. Check endpoint configuration, endpoint permissions/authentication, port binding, firewall, and network reachability.'
        FROM #Endpoint
        WHERE state_desc <> 'STARTED';

        /*---------------------------------------------------------------------
          F. LOCAL DISK SPACE FOR SQL DATABASE VOLUMES
        ---------------------------------------------------------------------*/

        SELECT
            vs.volume_mount_point,
            MAX(vs.total_bytes) AS total_bytes,
            MAX(vs.available_bytes) AS available_bytes,
            CAST(
                MAX(vs.available_bytes) * 100.0 /
                NULLIF(MAX(vs.total_bytes), 0)
                AS decimal(10,2)
            ) AS FreePct
        INTO #Disk
        FROM sys.master_files AS mf
        CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
        GROUP BY vs.volume_mount_point;

        INSERT #Findings
        SELECT
            CASE
                WHEN FreePct <= @DiskCriticalPct THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Disk Space',
            NULL,
            NULL,
            @ServerName,
            CONCAT(
                N'Volume ', volume_mount_point,
                N' has ', CONVERT(nvarchar(30), FreePct),
                N'% free space (',
                CONVERT(nvarchar(30), CAST(available_bytes / 1073741824.0 AS decimal(18,2))),
                N' GB free of ',
                CONVERT(nvarchar(30), CAST(total_bytes / 1073741824.0 AS decimal(18,2))),
                N' GB).'
            ),
            N'Free space or increase storage capacity before data/log growth, backup activity, or SQL Server operations are affected.'
        FROM #Disk
        WHERE FreePct <= @DiskWarningPct;

        /*---------------------------------------------------------------------
          G. LOG REUSE WAIT
        ---------------------------------------------------------------------*/

        INSERT #Findings
        SELECT
            'WARNING',
            'Transaction Log Reuse',
            ag.name,
            d.name,
            @ServerName,
            N'log_reuse_wait_desc = AVAILABILITY_REPLICA.',
            N'Check disconnected/lagging replicas, log-send queues, suspended movement, and replica health before the transaction log grows excessively.'
        FROM sys.databases AS d
        INNER JOIN sys.availability_databases_cluster AS adc
            ON d.name = adc.database_name
        INNER JOIN sys.availability_groups AS ag
            ON adc.group_id = ag.group_id
        WHERE d.log_reuse_wait_desc = 'AVAILABILITY_REPLICA';

        /*---------------------------------------------------------------------
          H. RECENT SQL SERVER ERRORLOG - HADR/AVAILABILITY RELATED
        ---------------------------------------------------------------------*/

        CREATE TABLE #ErrorLogRaw
        (
            LogDate       datetime,
            ProcessInfo   nvarchar(50),
            [Text]        nvarchar(max)
        );

        BEGIN TRY
            INSERT #ErrorLogRaw
            EXEC master.sys.sp_readerrorlog 0, 1, N'HADR';
        END TRY
        BEGIN CATCH
            INSERT #Findings
            (
                Severity, Category, Observation, Recommendation
            )
            VALUES
            (
                'WARNING',
                'Error Log Monitoring',
                CONCAT(N'Unable to read HADR entries from SQL Server ERRORLOG: ', ERROR_MESSAGE()),
                N'On SQL Server 2022 and later, verify VIEW ANY ERROR LOG or VIEW SERVER PERFORMANCE STATE as appropriate for the execution context.'
            );
        END CATCH;

        BEGIN TRY
            INSERT #ErrorLogRaw
            EXEC master.sys.sp_readerrorlog 0, 1, N'availability';
        END TRY
        BEGIN CATCH
            -- Avoid duplicating permission finding if first call already reported it.
        END CATCH;

        ;WITH E AS
        (
            SELECT DISTINCT
                LogDate,
                ProcessInfo,
                [Text]
            FROM #ErrorLogRaw
            WHERE LogDate >= DATEADD(HOUR, -@ErrorLookbackHours, GETDATE())
              AND
              (
                    [Text] LIKE N'%error%'
                 OR [Text] LIKE N'%fail%'
                 OR [Text] LIKE N'%disconnect%'
                 OR [Text] LIKE N'%timeout%'
                 OR [Text] LIKE N'%suspend%'
                 OR [Text] LIKE N'%lease%'
                 OR [Text] LIKE N'%not synchron%'
                 OR [Text] LIKE N'%terminated%'
              )
        )
        INSERT #Findings
        SELECT TOP (25)
            CASE
                WHEN [Text] LIKE N'%fail%'
                  OR [Text] LIKE N'%error%'
                  OR [Text] LIKE N'%lease%'
                  OR [Text] LIKE N'%terminated%'
                    THEN 'CRITICAL'
                ELSE 'WARNING'
            END,
            'Recent HADR Error Log',
            NULL,
            NULL,
            @ServerName,
            CONCAT(
                CONVERT(nvarchar(19), LogDate, 120),
                N' | ', ProcessInfo,
                N' | ', LEFT([Text], 1700)
            ),
            N'Review the surrounding SQL Server ERRORLOG entries and correlate them with replica connectivity, WSFC, network, endpoint, storage, and database-state findings.'
        FROM E
        ORDER BY LogDate DESC;

        /*---------------------------------------------------------------------
          I. HEALTHY MARKER
        ---------------------------------------------------------------------*/

        IF NOT EXISTS (SELECT 1 FROM #Findings)
        BEGIN
            INSERT #Findings
            (
                Severity, Category, Observation, Recommendation
            )
            VALUES
            (
                'HEALTHY',
                'Overall Health',
                N'No warning or critical conditions were detected by the configured SQL-visible Always On checks.',
                N'Continue normal monitoring. Review historical queue and lag trends to tune thresholds for this workload.'
            );
        END;

        /*---------------------------------------------------------------------
          J. PERSIST FINDINGS
        ---------------------------------------------------------------------*/

        INSERT dbo.AGMonitorFindingHistory
        (
            RunID,
            CaptureTime,
            Severity,
            Category,
            AGName,
            DatabaseName,
            ReplicaName,
            Observation,
            Recommendation
        )
        SELECT
            @RunID,
            @Now,
            Severity,
            Category,
            AGName,
            DatabaseName,
            ReplicaName,
            Observation,
            Recommendation
        FROM #Findings;

        SELECT
            @CriticalCount = SUM(CASE WHEN Severity = 'CRITICAL' THEN 1 ELSE 0 END),
            @WarningCount  = SUM(CASE WHEN Severity = 'WARNING'  THEN 1 ELSE 0 END),
            @HealthyCount  = SUM(CASE WHEN Severity = 'HEALTHY'  THEN 1 ELSE 0 END)
        FROM #Findings;

        SET @CriticalCount = ISNULL(@CriticalCount, 0);
        SET @WarningCount  = ISNULL(@WarningCount, 0);
        SET @HealthyCount  = ISNULL(@HealthyCount, 0);

        SET @OverallStatus =
            CASE
                WHEN @CriticalCount > 0 THEN 'CRITICAL'
                WHEN @WarningCount  > 0 THEN 'WARNING'
                ELSE 'HEALTHY'
            END;

        /*---------------------------------------------------------------------
          K. SHOULD THIS REPLICA SEND EMAIL?
        ---------------------------------------------------------------------*/

        SET @ShouldSend =
            CASE
                WHEN @ForceEmail = 1 THEN 1
                WHEN @HasPrimary = 1 THEN 1
                WHEN @SendHealthyFromSecondary = 1 THEN 1
                WHEN @OverallStatus IN ('WARNING','CRITICAL') THEN 1
                ELSE 0
            END;

        /*---------------------------------------------------------------------
          L. HTML EMAIL
        ---------------------------------------------------------------------*/

        SET @Subject =
            CONCAT(
                N'[AG ', @OverallStatus, N'] ',
                @ServerName,
                N' | 2-Hour Always On Health Check'
            );

        SET @Body =
N'<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
body{font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#222}
h2,h3{color:#17365D}
table{border-collapse:collapse;width:100%;margin-bottom:18px}
th{background:#D9EAF7;text-align:left}
th,td{border:1px solid #B7C9D6;padding:6px;vertical-align:top}
.status-HEALTHY{background:#DFF0D8;font-weight:bold}
.status-WARNING{background:#FFF3CD;font-weight:bold}
.status-CRITICAL{background:#F8D7DA;font-weight:bold}
.small{font-size:11px;color:#555}
</style>
</head>
<body>';

        SET @Body +=
            N'<h2>SQL Server Always On Health Report</h2>' +
            N'<table>' +
            N'<tr><th>SQL Server</th><td>' + dbo.ufn_AGMonitor_HtmlEncode(@ServerName) + N'</td></tr>' +
            N'<tr><th>Host</th><td>' + dbo.ufn_AGMonitor_HtmlEncode(@HostName) + N'</td></tr>' +
            N'<tr><th>Report Time</th><td>' + CONVERT(nvarchar(19), @Now, 120) + N' (server local time)</td></tr>' +
            N'<tr><th>Hosts a Primary Replica</th><td>' + CASE WHEN @HasPrimary = 1 THEN N'YES' ELSE N'NO' END + N'</td></tr>' +
            N'<tr><th>Overall Status</th><td class="status-' + @OverallStatus + N'">' + @OverallStatus + N'</td></tr>' +
            N'<tr><th>Critical / Warning</th><td>' + CONVERT(nvarchar(12), @CriticalCount) + N' / ' + CONVERT(nvarchar(12), @WarningCount) + N'</td></tr>' +
            N'</table>';

        /* Findings table */

        SELECT @Rows =
            STRING_AGG(
                CAST(
                    N'<tr>' +
                    N'<td class="status-' + Severity + N'">' + Severity + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(Category) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(AGName,N'')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(DatabaseName,N'')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(ReplicaName,N'')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(Observation) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(Recommendation,N'')) + N'</td>' +
                    N'</tr>'
                    AS nvarchar(max)
                ),
                N''
            )
        FROM #Findings;

        SET @Body +=
            N'<h3>Detected Health Findings</h3>' +
            N'<table><tr>' +
            N'<th>Severity</th><th>Category</th><th>AG</th><th>Database</th><th>Replica</th><th>Observation</th><th>Recommendation</th>' +
            N'</tr>' + ISNULL(@Rows,N'') + N'</table>';

        /* Replica details */

        SELECT @Rows =
            STRING_AGG(
                CAST(
                    N'<tr>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(AGName) + N'</td>' +
                    N'<td>' + CASE WHEN is_distributed = 1 THEN N'YES' ELSE N'NO' END + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(replica_server_name) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(role_desc,N'Not visible from this replica')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(availability_mode_desc,N'')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(connected_state_desc,N'Not visible')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(synchronization_health_desc,N'Not visible')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(endpoint_url,N'')) + N'</td>' +
                    N'</tr>'
                    AS nvarchar(max)
                ),
                N''
            )
        FROM #Replica;

        SET @Body +=
            N'<h3>Availability Replica Summary</h3>' +
            N'<table><tr>' +
            N'<th>AG</th><th>Distributed</th><th>Replica</th><th>Role</th><th>Commit Mode</th><th>Connected</th><th>Sync Health</th><th>Endpoint</th>' +
            N'</tr>' + ISNULL(@Rows,N'') + N'</table>';

        /* Database details */

        SELECT @Rows =
            STRING_AGG(
                CAST(
                    N'<tr>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(AGName) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(DatabaseName) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(replica_server_name) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(role_desc,N'')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(synchronization_state_desc,N'')) + N'</td>' +
                    N'<td>' + dbo.ufn_AGMonitor_HtmlEncode(ISNULL(synchronization_health_desc,N'')) + N'</td>' +
                    N'<td>' + CASE WHEN is_suspended = 1 THEN N'YES' ELSE N'NO' END + N'</td>' +
                    N'<td>' + COALESCE(CONVERT(nvarchar(30), CAST(log_send_queue_size/1024.0 AS decimal(18,2))),N'') + N'</td>' +
                    N'<td>' + COALESCE(CONVERT(nvarchar(30), log_send_rate),N'') + N'</td>' +
                    N'<td>' + COALESCE(CONVERT(nvarchar(30), EstimatedSendDelaySeconds),N'') + N'</td>' +
                    N'<td>' + COALESCE(CONVERT(nvarchar(30), CAST(redo_queue_size/1024.0 AS decimal(18,2))),N'') + N'</td>' +
                    N'<td>' + COALESCE(CONVERT(nvarchar(30), redo_rate),N'') + N'</td>' +
                    N'<td>' + COALESCE(CONVERT(nvarchar(30), EstimatedRedoDelaySeconds),N'') + N'</td>' +
                    N'<td>' + COALESCE(CONVERT(nvarchar(30), secondary_lag_seconds),N'') + N'</td>' +
                    N'</tr>'
                    AS nvarchar(max)
                ),
                N''
            )
        FROM #DBState;

        SET @Body +=
            N'<h3>Availability Database Details</h3>' +
            N'<table><tr>' +
            N'<th>AG</th><th>Database</th><th>Replica</th><th>Role</th><th>Sync State</th><th>Sync Health</th><th>Suspended</th>' +
            N'<th>Send Queue MB</th><th>Send KB/s</th><th>Est. Send sec</th>' +
            N'<th>Redo Queue MB</th><th>Redo KB/s</th><th>Est. Redo sec</th><th>Lag sec</th>' +
            N'</tr>' + ISNULL(@Rows,N'') + N'</table>';

        /* Disk */

        SELECT @Rows =
            STRING_AGG(
                CAST(
                    N'<tr><td>' + dbo.ufn_AGMonitor_HtmlEncode(volume_mount_point) + N'</td>' +
                    N'<td>' + CONVERT(nvarchar(30), CAST(total_bytes/1073741824.0 AS decimal(18,2))) + N'</td>' +
                    N'<td>' + CONVERT(nvarchar(30), CAST(available_bytes/1073741824.0 AS decimal(18,2))) + N'</td>' +
                    N'<td>' + CONVERT(nvarchar(30), FreePct) + N'</td></tr>'
                    AS nvarchar(max)
                ),
                N''
            )
        FROM #Disk;

        SET @Body +=
            N'<h3>SQL Database Volume Space</h3>' +
            N'<table><tr><th>Volume</th><th>Total GB</th><th>Free GB</th><th>Free %</th></tr>' +
            ISNULL(@Rows,N'') + N'</table>';

        SET @Body +=
            N'<p class="small">Note: SYNCHRONIZING can be the expected healthy state for an asynchronous-commit secondary. The monitor therefore evaluates synchronization health, role/commit mode, queues, lag, and related symptoms rather than treating every SYNCHRONIZING state as a failure.</p>' +
            N'<p class="small">Run ID: ' + CONVERT(nvarchar(30), @RunID) + N'</p>' +
            N'</body></html>';

        /*---------------------------------------------------------------------
          M. SEND MAIL
        ---------------------------------------------------------------------*/

        IF @ShouldSend = 1
        BEGIN
            UPDATE dbo.AGMonitorRunHistory
            SET EmailAttempted = 1
            WHERE RunID = @RunID;

            BEGIN TRY
                EXEC msdb.dbo.sp_send_dbmail
                    @profile_name = @MailProfile,
                    @recipients   = @Recipients,
                    @subject      = @Subject,
                    @body         = @Body,
                    @body_format  = 'HTML';

                SET @EmailQueued = 1;
            END TRY
            BEGIN CATCH
                UPDATE dbo.AGMonitorRunHistory
                SET EmailError = ERROR_MESSAGE()
                WHERE RunID = @RunID;
            END CATCH;
        END;

        /*---------------------------------------------------------------------
          N. RETENTION
        ---------------------------------------------------------------------*/

        DELETE dbo.AGMonitorFindingHistory
        WHERE CaptureTime < DATEADD(DAY, -@RetentionDays, @Now);

        DELETE dbo.AGMonitorDatabaseSnapshot
        WHERE CaptureTime < DATEADD(DAY, -@RetentionDays, @Now);

        DELETE dbo.AGMonitorRunHistory
        WHERE RunStartTime < DATEADD(DAY, -@RetentionDays, @Now)
          AND RunID <> @RunID;

        UPDATE dbo.AGMonitorRunHistory
        SET
            RunEndTime       = SYSDATETIME(),
            OverallStatus    = @OverallStatus,
            CriticalCount    = @CriticalCount,
            WarningCount     = @WarningCount,
            HealthyCount     = @HealthyCount,
            EmailQueued      = @EmailQueued
        WHERE RunID = @RunID;

        IF @Debug = 1
        BEGIN
            SELECT
                @RunID AS RunID,
                @OverallStatus AS OverallStatus,
                @HasPrimary AS HostsPrimary,
                @ShouldSend AS ShouldSendEmail,
                @EmailQueued AS EmailQueued,
                @CriticalCount AS CriticalCount,
                @WarningCount AS WarningCount;

            SELECT *
            FROM #Findings
            ORDER BY
                CASE Severity
                    WHEN 'CRITICAL' THEN 1
                    WHEN 'WARNING'  THEN 2
                    ELSE 3
                END,
                FindingOrder;

            SELECT *
            FROM #Replica
            ORDER BY AGName, replica_server_name;

            SELECT *
            FROM #DBState
            ORDER BY AGName, DatabaseName, replica_server_name;
        END;

    END TRY
    BEGIN CATCH
        DECLARE @ProcedureError nvarchar(4000) =
            CONCAT(
                N'Error ', ERROR_NUMBER(),
                N', line ', ERROR_LINE(),
                N': ', ERROR_MESSAGE()
            );

        UPDATE dbo.AGMonitorRunHistory
        SET
            RunEndTime      = SYSDATETIME(),
            OverallStatus   = 'CRITICAL',
            ProcedureError  = @ProcedureError
        WHERE RunID = @RunID;

        /* Best-effort monitor failure email */
        BEGIN TRY
            EXEC msdb.dbo.sp_send_dbmail
                @profile_name = @MailProfile,
                @recipients   = @Recipients,
                @subject      = N'[AG MONITOR FAILURE] SQL Server Always On Health Check',
                @body         = @ProcedureError,
                @body_format  = 'TEXT';
        END TRY
        BEGIN CATCH
            -- Do not mask the original procedure exception.
        END CATCH;

        THROW;
    END CATCH;
END;
GO

/*=============================================================================
  8. REPORTING / TROUBLESHOOTING VIEWS
=============================================================================*/

CREATE OR ALTER VIEW dbo.vw_AGMonitorLatestRuns
AS
SELECT TOP (100)
    RunID,
    ServerName,
    HostName,
    RunStartTime,
    RunEndTime,
    OverallStatus,
    CriticalCount,
    WarningCount,
    HealthyCount,
    EmailAttempted,
    EmailQueued,
    EmailError,
    ProcedureError
FROM dbo.AGMonitorRunHistory
ORDER BY RunID DESC;
GO

CREATE OR ALTER VIEW dbo.vw_AGMonitorRecentProblems
AS
SELECT
    f.FindingID,
    f.RunID,
    r.ServerName,
    f.CaptureTime,
    f.Severity,
    f.Category,
    f.AGName,
    f.DatabaseName,
    f.ReplicaName,
    f.Observation,
    f.Recommendation
FROM dbo.AGMonitorFindingHistory AS f
INNER JOIN dbo.AGMonitorRunHistory AS r
    ON f.RunID = r.RunID
WHERE f.Severity IN ('WARNING','CRITICAL');
GO

/*=============================================================================
  9. SQL SERVER AGENT JOB - EVERY TWO HOURS
=============================================================================*/

USE msdb;
GO

DECLARE
    @JobName      sysname = N'DBA - Always On Health Alert - Every 2 Hours',
    @ScheduleName sysname = N'DBA - Always On Health - Every 2 Hours';

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC dbo.sp_delete_job
        @job_name = @JobName,
        @delete_unused_schedule = 1;
END;

EXEC dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Runs the DBA_Admin Always On health monitor every two hours. Primary sends heartbeat; secondary sends fail-safe warning/critical notifications by default.';

EXEC dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_name = N'Collect AG Health and Send Notification',
    @subsystem = N'TSQL',
    @database_name = N'DBA_Admin',
    @command = N'EXEC dbo.usp_AG_HealthCheck_Email @ForceEmail = 0, @Debug = 0;',
    @retry_attempts = 2,
    @retry_interval = 5,
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC dbo.sp_add_jobschedule
    @job_name = @JobName,
    @name = @ScheduleName,
    @enabled = 1,
    @freq_type = 4,              -- Daily
    @freq_interval = 1,          -- Every day
    @freq_subday_type = 8,       -- Hours
    @freq_subday_interval = 2,   -- Every 2 hours
    @active_start_time = 000000; -- 00:00 server local time

EXEC dbo.sp_add_jobserver
    @job_name = @JobName;
GO

/*=============================================================================
  10. POST-DEPLOYMENT TESTS
=============================================================================*/

USE DBA_Admin;
GO

PRINT '============================================================';
PRINT 'Always On monitor deployment completed.';
PRINT '1. Update dbo.AGMonitorConfig with the correct mail profile.';
PRINT '2. Update dbo.AGMonitorConfig with the correct recipients.';
PRINT '3. Run the forced email test below.';
PRINT '============================================================';
GO

/* Force a test email from THIS replica, even if it is secondary */
-- EXEC dbo.usp_AG_HealthCheck_Email @ForceEmail = 1, @Debug = 1;
-- GO

/* Normal production behavior */
-- EXEC dbo.usp_AG_HealthCheck_Email @ForceEmail = 0, @Debug = 1;
-- GO

/* Recent runs */
-- SELECT * FROM dbo.vw_AGMonitorLatestRuns;
-- GO

/* Recent problems */
-- SELECT TOP (100) *
-- FROM dbo.vw_AGMonitorRecentProblems
-- ORDER BY CaptureTime DESC;
-- GO

/* Queue/lag trend for the last 24 hours */
-- SELECT
--     CaptureTime,
--     AGName,
--     DatabaseName,
--     ReplicaName,
--     LogSendQueueKB / 1024.0 AS LogSendQueueMB,
--     LogSendRateKBps,
--     EstimatedSendDelaySeconds,
--     RedoQueueKB / 1024.0 AS RedoQueueMB,
--     RedoRateKBps,
--     EstimatedRedoDelaySeconds,
--     SecondaryLagSeconds
-- FROM dbo.AGMonitorDatabaseSnapshot
-- WHERE CaptureTime >= DATEADD(HOUR, -24, SYSDATETIME())
-- ORDER BY CaptureTime DESC, AGName, DatabaseName, ReplicaName;
-- GO
