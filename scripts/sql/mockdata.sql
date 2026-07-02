/* =============================================================================
   SQL Audit PoC — synthetic mock data generator (idempotent).
   Row volumes are supplied as sqlcmd variables so the same file drives both
   Azure SQL (large) and the VM database (small):
       CustomerCount, AccountCount, TransactionCount, PaymentInstructionCount,
       WireTransferCount, RiskScoreCount, SanctionsCount, FraudSignalCount,
       AccessProfileCount, AccessRequestCount
   Only generates when core.Customers is empty (safe to re-run).
   ALL DATA IS SYNTHETIC. NO real personal data.
   ============================================================================= */
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM core.Customers)
BEGIN
    PRINT 'Mock data already present — skipping generation (idempotent).';
    RETURN;
END

DECLARE @Customers          INT = $(CustomerCount);
DECLARE @Accounts           INT = $(AccountCount);
DECLARE @Transactions       INT = $(TransactionCount);
DECLARE @PaymentInstr       INT = $(PaymentInstructionCount);
DECLARE @WireTransfers      INT = $(WireTransferCount);
DECLARE @RiskScores         INT = $(RiskScoreCount);
DECLARE @Sanctions          INT = $(SanctionsCount);
DECLARE @FraudSignals       INT = $(FraudSignalCount);
DECLARE @AccessProfiles     INT = $(AccessProfileCount);
DECLARE @AccessRequests     INT = $(AccessRequestCount);

/* ---- lookup pools -------------------------------------------------------- */
DECLARE @first TABLE (i INT IDENTITY, v NVARCHAR(40));
INSERT @first (v) VALUES (N'Emma'),(N'Liam'),(N'Olivia'),(N'Noah'),(N'Ava'),(N'Elias'),
 (N'Sofia'),(N'Lucas'),(N'Maja'),(N'Hugo'),(N'Alice'),(N'Oliver'),(N'Ella'),(N'William'),
 (N'Astrid'),(N'Leo'),(N'Wilma'),(N'Adam'),(N'Freja'),(N'Axel');

DECLARE @last TABLE (i INT IDENTITY, v NVARCHAR(40));
INSERT @last (v) VALUES (N'Andersson'),(N'Johansson'),(N'Karlsson'),(N'Nilsson'),(N'Eriksson'),
 (N'Larsson'),(N'Olsson'),(N'Persson'),(N'Svensson'),(N'Gustafsson'),(N'Lindberg'),(N'Berg'),
 (N'Lundqvist'),(N'Holm'),(N'Sandberg'),(N'Nyström'),(N'Falk'),(N'Ek'),(N'Dahl'),(N'Blom');

DECLARE @country TABLE (i INT IDENTITY, v NVARCHAR(40));
INSERT @country (v) VALUES (N'Sweden'),(N'Norway'),(N'Denmark'),(N'Finland'),(N'Germany'),
 (N'Netherlands'),(N'France'),(N'Poland'),(N'Estonia'),(N'Ireland');

DECLARE @city TABLE (i INT IDENTITY, v NVARCHAR(40));
INSERT @city (v) VALUES (N'Stockholm'),(N'Gothenburg'),(N'Malmö'),(N'Oslo'),(N'Copenhagen'),
 (N'Helsinki'),(N'Berlin'),(N'Amsterdam'),(N'Paris'),(N'Warsaw');

/* ---- core.Branches (25) -------------------------------------------------- */
INSERT core.Branches (BranchCode, BranchName, Country, City, OpenedDate)
SELECT CONCAT('BR', FORMAT(value, '0000')),
       CONCAT(N'Branch ', value),
       (SELECT v FROM @country WHERE i = (value % 10) + 1),
       (SELECT v FROM @city    WHERE i = (value % 10) + 1),
       DATEADD(DAY, -(value * 37 % 6000), CAST(SYSUTCDATETIME() AS DATE))
FROM GENERATE_SERIES(1, 25) g;

/* ---- core.Customers ------------------------------------------------------ */
INSERT core.Customers (CustomerNumber, FirstName, LastName, DateOfBirth, Country, City,
                       Email, PhoneNumber, KycStatus, CustomerSegment, IsPoliticallyExposedPerson, CreatedDate)
SELECT CONCAT('CUST', FORMAT(value, '0000000')),
       (SELECT TOP 1 v FROM @first ORDER BY CHECKSUM(NEWID(), value)),
       (SELECT TOP 1 v FROM @last  ORDER BY CHECKSUM(NEWID(), value)),
       DATEADD(DAY, -(6570 + (value * 7 % 18000)), CAST(SYSUTCDATETIME() AS DATE)),
       (SELECT v FROM @country WHERE i = (value % 10) + 1),
       (SELECT v FROM @city    WHERE i = (value % 10) + 1),
       CONCAT('customer', value, '@example.test'),
       CONCAT('+46-70-', FORMAT(ABS(CHECKSUM(NEWID())) % 10000000, '0000000')),
       CASE value % 10 WHEN 0 THEN 'Pending' WHEN 1 THEN 'Review' ELSE 'Verified' END,
       CASE value % 5 WHEN 0 THEN 'Private' WHEN 1 THEN 'Premium' WHEN 2 THEN 'Business' WHEN 3 THEN 'Corporate' ELSE 'Retail' END,
       CASE WHEN value % 97 = 0 THEN 1 ELSE 0 END,
       DATEADD(DAY, -(value % 1400), SYSUTCDATETIME())
FROM GENERATE_SERIES(1, @Customers) g;

/* ---- core.Accounts ------------------------------------------------------- */
INSERT core.Accounts (CustomerId, AccountNumber, Iban, AccountType, Currency, Balance, Status, OpenDate, BranchId)
SELECT ((value - 1) % @Customers) + 1,
       CONCAT('ACC', FORMAT(value, '00000000')),
       CONCAT('SE', FORMAT(ABS(CHECKSUM(NEWID())) % 100, '00'), '000', FORMAT(value, '0000000000')),
       CASE value % 4 WHEN 0 THEN 'Checking' WHEN 1 THEN 'Savings' WHEN 2 THEN 'Credit' ELSE 'Investment' END,
       CASE value % 3 WHEN 0 THEN 'EUR' WHEN 1 THEN 'SEK' ELSE 'USD' END,
       CAST((ABS(CHECKSUM(NEWID())) % 5000000) / 100.0 AS DECIMAL(18,2)),
       CASE WHEN value % 50 = 0 THEN 'Frozen' WHEN value % 33 = 0 THEN 'Closed' ELSE 'Active' END,
       DATEADD(DAY, -(value % 3000), CAST(SYSUTCDATETIME() AS DATE)),
       (ABS(CHECKSUM(NEWID())) % 25) + 1
FROM GENERATE_SERIES(1, @Accounts) g;

/* ---- auditdemo.SensitiveCustomerData (one per customer) ------------------ */
INSERT auditdemo.SensitiveCustomerData (CustomerId, NationalIdentifier, TaxIdentifier, PassportNumber,
                                        CreditScore, SalaryBand, InternalRiskComment, VIPFlag, DataClassification)
SELECT c.CustomerId,
       CONCAT('SSN-', FORMAT(c.CustomerId, '00000000')),
       CONCAT('TAX-', FORMAT(c.CustomerId, '00000000')),
       CONCAT('P', FORMAT(ABS(CHECKSUM(NEWID())) % 100000000, '00000000')),
       300 + (ABS(CHECKSUM(NEWID())) % 550),
       CASE c.CustomerId % 6 WHEN 0 THEN 'A' WHEN 1 THEN 'B' WHEN 2 THEN 'C' WHEN 3 THEN 'D' WHEN 4 THEN 'E' ELSE 'F' END,
       CASE WHEN c.CustomerId % 40 = 0 THEN N'Flagged for enhanced due diligence'
            WHEN c.CustomerId % 15 = 0 THEN N'High net worth — priority handling'
            ELSE N'No adverse notes' END,
       CASE WHEN c.CustomerId % 25 = 0 THEN 1 ELSE 0 END,
       CASE WHEN c.CustomerId % 25 = 0 THEN 'Restricted' ELSE 'Confidential' END
FROM core.Customers c;

/* ---- risk.CustomerRiskScores -------------------------------------------- */
INSERT risk.CustomerRiskScores (CustomerId, RiskScore, RiskBand, LastReviewed)
SELECT ((value - 1) % @Customers) + 1,
       ABS(CHECKSUM(NEWID())) % 100,
       CASE (ABS(CHECKSUM(NEWID())) % 100) / 34 WHEN 0 THEN 'Low' WHEN 1 THEN 'Medium' ELSE 'High' END,
       DATEADD(DAY, -(value % 365), SYSUTCDATETIME())
FROM GENERATE_SERIES(1, @RiskScores) g;

/* ---- risk.SanctionsScreening -------------------------------------------- */
INSERT risk.SanctionsScreening (CustomerId, ListName, MatchScore, Decision, ScreenedDate)
SELECT ((value - 1) % @Customers) + 1,
       CASE value % 3 WHEN 0 THEN 'OFAC' WHEN 1 THEN 'EU-Consolidated' ELSE 'UN' END,
       ABS(CHECKSUM(NEWID())) % 100,
       CASE WHEN (ABS(CHECKSUM(NEWID())) % 100) > 85 THEN 'Escalate' ELSE 'Clear' END,
       DATEADD(DAY, -(value % 400), SYSUTCDATETIME())
FROM GENERATE_SERIES(1, @Sanctions) g;

/* ---- risk.FraudSignals --------------------------------------------------- */
INSERT risk.FraudSignals (CustomerId, SignalType, Severity, Details, DetectedDate)
SELECT ((value - 1) % @Customers) + 1,
       CASE value % 5 WHEN 0 THEN 'VelocityAnomaly' WHEN 1 THEN 'GeoMismatch' WHEN 2 THEN 'DeviceChange'
                      WHEN 3 THEN 'LargeCashOut' ELSE 'StructuredDeposits' END,
       CASE value % 3 WHEN 0 THEN 'High' WHEN 1 THEN 'Medium' ELSE 'Low' END,
       N'Automated fraud model signal (synthetic).',
       DATEADD(HOUR, -(value % 2000), SYSUTCDATETIME())
FROM GENERATE_SERIES(1, @FraudSignals) g;

/* ---- payments.Transactions ---------------------------------------------- */
INSERT payments.Transactions (AccountId, TransactionType, Amount, Currency, MerchantName, MerchantCategory,
                              CounterpartyAccount, TransactionDate, Channel, RiskFlag)
SELECT (ABS(CHECKSUM(NEWID())) % @Accounts) + 1,
       CASE value % 4 WHEN 0 THEN 'Debit' WHEN 1 THEN 'Credit' WHEN 2 THEN 'Transfer' ELSE 'Payment' END,
       CAST((ABS(CHECKSUM(NEWID())) % 1000000) / 100.0 AS DECIMAL(18,2)),
       CASE value % 3 WHEN 0 THEN 'EUR' WHEN 1 THEN 'SEK' ELSE 'USD' END,
       CASE value % 6 WHEN 0 THEN N'IKEA' WHEN 1 THEN N'Spotify' WHEN 2 THEN N'Volvo' WHEN 3 THEN N'H&M'
                      WHEN 4 THEN N'Klarna' ELSE N'SAS' END,
       CASE value % 5 WHEN 0 THEN 'Retail' WHEN 1 THEN 'Travel' WHEN 2 THEN 'Grocery' WHEN 3 THEN 'Utilities' ELSE 'Entertainment' END,
       CONCAT('SE00', FORMAT(ABS(CHECKSUM(NEWID())) % 1000000000, '000000000')),
       DATEADD(MINUTE, -(value % 500000), SYSUTCDATETIME()),
       CASE value % 4 WHEN 0 THEN 'Mobile' WHEN 1 THEN 'Web' WHEN 2 THEN 'ATM' ELSE 'Branch' END,
       CASE WHEN value % 200 = 0 THEN 'High' WHEN value % 50 = 0 THEN 'Medium' ELSE 'None' END
FROM GENERATE_SERIES(1, @Transactions) g;

/* ---- payments.PaymentInstructions --------------------------------------- */
INSERT payments.PaymentInstructions (AccountId, Amount, Currency, BeneficiaryName, BeneficiaryIban, Status, CreatedDate)
SELECT (ABS(CHECKSUM(NEWID())) % @Accounts) + 1,
       CAST((ABS(CHECKSUM(NEWID())) % 2000000) / 100.0 AS DECIMAL(18,2)),
       CASE value % 3 WHEN 0 THEN 'EUR' WHEN 1 THEN 'SEK' ELSE 'USD' END,
       CONCAT(N'Beneficiary ', value),
       CONCAT('DE', FORMAT(ABS(CHECKSUM(NEWID())) % 100, '00'), '00000', FORMAT(value, '0000000000')),
       CASE value % 4 WHEN 0 THEN 'Completed' WHEN 1 THEN 'Pending' WHEN 2 THEN 'Rejected' ELSE 'Processing' END,
       DATEADD(HOUR, -(value % 5000), SYSUTCDATETIME())
FROM GENERATE_SERIES(1, @PaymentInstr) g;

/* ---- payments.WireTransfers --------------------------------------------- */
INSERT payments.WireTransfers (AccountId, Amount, Currency, BeneficiaryBank, BeneficiaryIban, Country, Status, IsDemoRow, CreatedDate)
SELECT (ABS(CHECKSUM(NEWID())) % @Accounts) + 1,
       CAST((ABS(CHECKSUM(NEWID())) % 10000000) / 100.0 AS DECIMAL(18,2)),
       CASE value % 3 WHEN 0 THEN 'EUR' WHEN 1 THEN 'USD' ELSE 'GBP' END,
       CASE value % 4 WHEN 0 THEN N'Deutsche Bank' WHEN 1 THEN N'BNP Paribas' WHEN 2 THEN N'HSBC' ELSE N'Nordea' END,
       CONCAT('GB', FORMAT(ABS(CHECKSUM(NEWID())) % 100, '00'), 'ABCD', FORMAT(value, '0000000000')),
       (SELECT v FROM @country WHERE i = (value % 10) + 1),
       CASE value % 5 WHEN 0 THEN 'Pending' WHEN 1 THEN 'Rejected' ELSE 'Sent' END,
       1, /* mark all seed wire rows as demo rows so DELETE scenarios stay safe */
       DATEADD(HOUR, -(value % 8000), SYSUTCDATETIME())
FROM GENERATE_SERIES(1, @WireTransfers) g;

/* ---- hr.EmployeeAccessProfiles: personas first, then filler ------------- */
INSERT hr.EmployeeAccessProfiles (UserName, RoleName, Department, NormalWorkingHoursStart, NormalWorkingHoursEnd,
                                  NormalSourceIp, UsualDatabases, UsualTables, IsPrivileged, ManagerName)
VALUES
 ('normal_user',      'CustomerService', N'Retail Ops',  8, 17, '10.42.1.20', N'PocBankingAuditDb', N'core.Customers,core.Accounts', 0, N'Team Lead Retail'),
 ('app_user',         'Application',     N'Digital',     0, 23, '10.42.1.30', N'PocBankingAuditDb', N'payments.Transactions',        0, N'Platform Owner'),
 ('reporting_user',   'Reporting',       N'Finance',     8, 18, '10.42.1.40', N'PocBankingAuditDb', N'core.Customers,payments.Transactions', 0, N'Head of Finance'),
 ('payments_analyst', 'PaymentsAnalyst', N'Payments',    8, 18, '10.42.1.50', N'PocBankingAuditDb', N'payments.Transactions,payments.PaymentInstructions,payments.WireTransfers', 0, N'Payments Manager'),
 ('fraud_analyst',    'FraudAnalyst',    N'Financial Crime', 8, 18, '10.42.1.60', N'PocBankingAuditDb', N'risk.FraudSignals,risk.CustomerRiskScores', 0, N'Head of Financial Crime'),
 ('dba_user',         'DBA',             N'IT Ops',      8, 18, '10.42.1.70', N'PocBankingAuditDb', N'ALL', 1, N'IT Operations Manager'),
 ('privileged_admin', 'PrivilegedAdmin', N'IT Ops',      8, 18, '10.42.1.71', N'PocBankingAuditDb', N'ALL', 1, N'CISO'),
 ('suspicious_user',  'Contractor',      N'External',    9, 17, '10.42.1.99', N'PocBankingAuditDb', N'core.Customers', 0, N'Vendor Manager'),
 ('breakglass_admin', 'BreakGlass',      N'Security',    0, 23, '10.42.1.10', N'PocBankingAuditDb', N'admin.AccessRequests', 1, N'CISO');

INSERT hr.EmployeeAccessProfiles (UserName, RoleName, Department, NormalWorkingHoursStart, NormalWorkingHoursEnd,
                                  NormalSourceIp, UsualDatabases, UsualTables, IsPrivileged, ManagerName)
SELECT CONCAT('employee_', value),
       CASE value % 4 WHEN 0 THEN 'CustomerService' WHEN 1 THEN 'Reporting' WHEN 2 THEN 'PaymentsAnalyst' ELSE 'FraudAnalyst' END,
       CASE value % 3 WHEN 0 THEN N'Retail Ops' WHEN 1 THEN N'Payments' ELSE N'Finance' END,
       8, 17,
       CONCAT('10.42.1.', 100 + (value % 150)),
       N'PocBankingAuditDb',
       N'core.Customers,core.Accounts',
       0,
       N'Team Lead'
FROM GENERATE_SERIES(1, CASE WHEN @AccessProfiles > 9 THEN @AccessProfiles - 9 ELSE 0 END) g;

/* ---- admin.AccessRequests ----------------------------------------------- */
INSERT admin.AccessRequests (RequestedBy, RequestedRole, Justification, Status, RequestedDate, ApprovedBy)
SELECT CONCAT('employee_', (value % 100) + 1),
       CASE value % 4 WHEN 0 THEN 'DBA' WHEN 1 THEN 'PaymentsAnalyst' WHEN 2 THEN 'FraudAnalyst' ELSE 'Reporting' END,
       N'Access required for project work (synthetic).',
       CASE value % 3 WHEN 0 THEN 'Approved' WHEN 1 THEN 'Pending' ELSE 'Rejected' END,
       DATEADD(DAY, -(value % 200), SYSUTCDATETIME()),
       CASE WHEN value % 3 = 0 THEN 'privileged_admin' ELSE NULL END
FROM GENERATE_SERIES(1, @AccessRequests) g;

/* ---- Expected-behaviour metadata for the demo personas ------------------- */
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'core', ExpectedTables=N'core.Customers,core.Accounts', ExpectedActivityLevel='Low', DataAccessJustification=N'Front-line customer servicing' WHERE UserName='normal_user';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'payments', ExpectedTables=N'payments.Transactions', ExpectedActivityLevel='High', DataAccessJustification=N'Application service account' WHERE UserName='app_user';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'core,payments', ExpectedTables=N'core.Customers,payments.Transactions', ExpectedActivityLevel='Medium', DataAccessJustification=N'Regulatory & MI reporting' WHERE UserName='reporting_user';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'payments', ExpectedTables=N'payments.Transactions,payments.PaymentInstructions,payments.WireTransfers', ExpectedActivityLevel='Medium', DataAccessJustification=N'Payments operations analysis' WHERE UserName='payments_analyst';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'risk', ExpectedTables=N'risk.FraudSignals,risk.CustomerRiskScores', ExpectedActivityLevel='Medium', DataAccessJustification=N'Financial crime investigation' WHERE UserName='fraud_analyst';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'ALL', ExpectedTables=N'ALL (operational)', ExpectedActivityLevel='Variable', DataAccessJustification=N'Database administration & maintenance' WHERE UserName='dba_user';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'ALL', ExpectedTables=N'ALL (controlled)', ExpectedActivityLevel='Low', DataAccessJustification=N'Controlled privileged operations' WHERE UserName='privileged_admin';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'core', ExpectedTables=N'core.Customers', ExpectedActivityLevel='Low', DataAccessJustification=N'Contractor - limited scope' WHERE UserName='suspicious_user';
UPDATE hr.EmployeeAccessProfiles SET ExpectedSchemas=N'admin', ExpectedTables=N'admin.AccessRequests', ExpectedActivityLevel='None', DataAccessJustification=N'Emergency break-glass only' WHERE UserName='breakglass_admin';

/* ---- auditdemo.SensitiveObjectCatalog ------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM auditdemo.SensitiveObjectCatalog)
INSERT auditdemo.SensitiveObjectCatalog (ObjectName, SchemaName, SensitivityLevel, BusinessOwner, Reason, RecommendedMonitoring)
VALUES
 (N'SensitiveCustomerData', N'auditdemo', 'Restricted', N'Data Protection Officer', N'PII, salary, credit score, internal risk comments', N'Alert on any non-privileged access and all after-hours access'),
 (N'WireTransfers',         N'payments',  'High',       N'Head of Payments',        N'High-value money movement', N'Alert on DELETE/UPDATE and out-of-role SELECT'),
 (N'CustomerRiskScores',    N'risk',      'High',       N'Chief Risk Officer',       N'Customer risk classification', N'Alert on access by non-risk roles'),
 (N'SanctionsScreening',    N'risk',      'Restricted', N'Head of Financial Crime',  N'Sanctions match decisions', N'Alert on any out-of-role access'),
 (N'FraudSignals',          N'risk',      'High',       N'Head of Financial Crime',  N'Fraud model outputs', N'Alert on access by non-fraud roles'),
 (N'EmployeeAccessProfiles',N'hr',        'Confidential',N'HR Director',             N'Employee behavioural baselines', N'Alert on access by non-HR roles'),
 (N'AccessRequests',        N'admin',     'Confidential',N'CISO',                     N'Privileged access request workflow', N'Alert on break-glass and unusual access');

PRINT CONCAT('Mock data generated: ', @Customers, ' customers, ', @Accounts, ' accounts, ', @Transactions, ' transactions.');
