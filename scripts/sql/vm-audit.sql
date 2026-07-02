/* =============================================================================
   SQL Audit PoC — SQL Server Audit configuration for the VM instance.
   Writes audit records to the Windows APPLICATION log so the Azure Monitor
   Agent + DCR forward them to the Event table in Log Analytics.
   Idempotent. Run against the VM's SQL Server (master + PocBankingAuditDbOnVm).
   sqlcmd variable: DbName (e.g. PocBankingAuditDbOnVm)
   ============================================================================= */
USE master;
GO
SET NOCOUNT ON;
GO

/* ---- Server Audit -> Application log ------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'SqlAudit_PoC')
BEGIN
    CREATE SERVER AUDIT SqlAudit_PoC
        TO APPLICATION_LOG
        WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
END
GO
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'SqlAudit_PoC' AND is_state_enabled = 0)
    ALTER SERVER AUDIT SqlAudit_PoC WITH (STATE = ON);
GO

/* ---- Server Audit Specification ------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = 'SqlAuditSpec_Server_PoC')
BEGIN
    CREATE SERVER AUDIT SPECIFICATION SqlAuditSpec_Server_PoC
        FOR SERVER AUDIT SqlAudit_PoC
        ADD (SUCCESSFUL_LOGIN_GROUP),
        ADD (FAILED_LOGIN_GROUP),
        ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
        ADD (SERVER_PERMISSION_CHANGE_GROUP),
        ADD (DATABASE_CHANGE_GROUP)
        WITH (STATE = ON);
END
GO

/* ---- Database Audit Specification ---------------------------------------- */
USE [$(DbName)];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'SqlAuditSpec_DB_PoC')
BEGIN
    CREATE DATABASE AUDIT SPECIFICATION SqlAuditSpec_DB_PoC
        FOR SERVER AUDIT SqlAudit_PoC
        ADD (SELECT ON SCHEMA::core BY public),
        ADD (SELECT ON SCHEMA::payments BY public),
        ADD (SELECT ON SCHEMA::risk BY public),
        ADD (SELECT ON SCHEMA::auditdemo BY public),
        ADD (SELECT ON SCHEMA::hr BY public),
        ADD (SELECT ON SCHEMA::admin BY public),
        ADD (INSERT ON SCHEMA::payments BY public),
        ADD (UPDATE ON SCHEMA::payments BY public),
        ADD (DELETE ON SCHEMA::payments BY public),
        ADD (INSERT ON SCHEMA::core BY public),
        ADD (UPDATE ON SCHEMA::core BY public),
        ADD (DELETE ON SCHEMA::core BY public),
        ADD (DATABASE_PERMISSION_CHANGE_GROUP),
        ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
        ADD (SCHEMA_OBJECT_CHANGE_GROUP)
        WITH (STATE = ON);
END
GO

PRINT 'SQL Server Audit (SqlAudit_PoC) configured to Application log.';
