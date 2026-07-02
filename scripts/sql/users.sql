/* =============================================================================
   SQL Audit PoC — demo principals and least-privilege(-ish) permissions.
   Idempotent. Works on Azure SQL (contained users) and SQL Server VM (logins+users).
   sqlcmd variables:
       IsAzureSql        1 = Azure SQL Database (contained users), 0 = VM (logins)
       DemoUserPassword  password applied to every demo principal
   NOTE: analysts are deliberately slightly over-permissioned to mirror real
   environments — the PoC value is DETECTING abnormal behaviour, not blocking it.
   ============================================================================= */
SET NOCOUNT ON;

DECLARE @isAzure BIT = $(IsAzureSql);
DECLARE @pwd NVARCHAR(128) = N'$(DemoUserPassword)';
DECLARE @sql NVARCHAR(MAX);

/* ---- Create principals --------------------------------------------------- */
DECLARE @users TABLE (name SYSNAME);
INSERT @users (name) VALUES
 ('normal_user'),('app_user'),('reporting_user'),('payments_analyst'),
 ('fraud_analyst'),('dba_user'),('privileged_admin'),('suspicious_user'),('breakglass_admin');

DECLARE @n SYSNAME;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @users;
OPEN cur; FETCH NEXT FROM cur INTO @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'';
    IF @isAzure = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @n)
            SET @sql = N'CREATE USER ' + QUOTENAME(@n) + N' WITH PASSWORD = ''' + REPLACE(@pwd,'''','''''') + N''';';
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @n)
            SET @sql = N'CREATE LOGIN ' + QUOTENAME(@n) + N' WITH PASSWORD = ''' + REPLACE(@pwd,'''','''''') + N''', CHECK_POLICY = OFF;';
        IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @n)
            SET @sql = @sql + N'CREATE USER ' + QUOTENAME(@n) + N' FOR LOGIN ' + QUOTENAME(@n) + N';';
    END
    IF @sql <> N'' EXEC (@sql);
    FETCH NEXT FROM cur INTO @n;
END
CLOSE cur; DEALLOCATE cur;

/* ---- Helper to add a role member only if not already a member ------------ */
DECLARE @addRole TABLE (member SYSNAME, role SYSNAME);
INSERT @addRole VALUES
 ('reporting_user','db_datareader'),
 ('dba_user','db_datareader'),
 ('dba_user','db_datawriter'),
 ('dba_user','db_ddladmin'),
 ('privileged_admin','db_owner'),
 ('breakglass_admin','db_owner');

DECLARE @m SYSNAME, @r SYSNAME;
DECLARE rc CURSOR LOCAL FAST_FORWARD FOR SELECT member, role FROM @addRole;
OPEN rc; FETCH NEXT FROM rc INTO @m, @r;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF IS_ROLEMEMBER(@r, @m) = 0
    BEGIN
        SET @sql = N'ALTER ROLE ' + QUOTENAME(@r) + N' ADD MEMBER ' + QUOTENAME(@m) + N';';
        EXEC (@sql);
    END
    FETCH NEXT FROM rc INTO @m, @r;
END
CLOSE rc; DEALLOCATE rc;

/* ---- Object / schema grants (idempotent) --------------------------------- */
-- normal_user: limited read on customer/account data (NO sensitive data).
GRANT SELECT ON OBJECT::core.Customers TO normal_user;
GRANT SELECT ON OBJECT::core.Accounts  TO normal_user;

-- app_user: read/write transactions.
GRANT SELECT, INSERT, UPDATE ON OBJECT::payments.Transactions TO app_user;

-- reporting_user: reporting-style reads (also in db_datareader above).
GRANT SELECT ON OBJECT::core.Customers TO reporting_user;
GRANT SELECT ON OBJECT::payments.Transactions TO reporting_user;

-- payments_analyst: payments tables (+ risk visibility to enable Scenario J).
GRANT SELECT ON SCHEMA::payments TO payments_analyst;
GRANT SELECT ON SCHEMA::risk     TO payments_analyst;

-- fraud_analyst: risk/fraud tables (+ hr & sensitive visibility to enable Scenario I).
GRANT SELECT ON SCHEMA::risk      TO fraud_analyst;
GRANT SELECT ON SCHEMA::hr        TO fraud_analyst;
GRANT SELECT ON SCHEMA::auditdemo TO fraud_analyst;

-- dba_user: elevated read/write across the app schemas (real DBA-style access).
GRANT SELECT ON SCHEMA::core      TO dba_user;
GRANT SELECT ON SCHEMA::payments  TO dba_user;
GRANT SELECT ON SCHEMA::risk      TO dba_user;
GRANT SELECT ON SCHEMA::auditdemo TO dba_user;
GRANT SELECT ON SCHEMA::hr        TO dba_user;
GRANT SELECT ON SCHEMA::admin     TO dba_user;
GRANT VIEW DATABASE STATE TO dba_user;

-- suspicious_user: over-permissioned contractor (realistic) used to trigger
-- volume/enumeration/out-of-role demos. Reads across core/risk/auditdemo and can
-- DELETE demo wire-transfer rows (Scenario 3 targets demo rows only).
GRANT SELECT ON SCHEMA::core      TO suspicious_user;
GRANT SELECT ON SCHEMA::risk      TO suspicious_user;
GRANT SELECT ON SCHEMA::auditdemo TO suspicious_user;
GRANT DELETE ON OBJECT::payments.WireTransfers TO suspicious_user;

PRINT 'Demo principals and permissions ensured.';
