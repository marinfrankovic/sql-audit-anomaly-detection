/* =============================================================================
   SQL Audit PoC — schema & tables (idempotent).
   Works on Azure SQL Database (PocBankingAuditDb) and SQL Server on VM
   (PocBankingAuditDbOnVm). Safe to re-run.
   Synthetic banking model only — NO real personal data.
   ============================================================================= */

/* ---- Schemas ------------------------------------------------------------- */
IF SCHEMA_ID('core')      IS NULL EXEC('CREATE SCHEMA core');
IF SCHEMA_ID('payments')  IS NULL EXEC('CREATE SCHEMA payments');
IF SCHEMA_ID('risk')      IS NULL EXEC('CREATE SCHEMA risk');
IF SCHEMA_ID('auditdemo') IS NULL EXEC('CREATE SCHEMA auditdemo');
IF SCHEMA_ID('hr')        IS NULL EXEC('CREATE SCHEMA hr');
IF SCHEMA_ID('admin')     IS NULL EXEC('CREATE SCHEMA admin');
GO

/* ---- core.Branches ------------------------------------------------------- */
IF OBJECT_ID('core.Branches') IS NULL
CREATE TABLE core.Branches (
    BranchId      INT IDENTITY(1,1) PRIMARY KEY,
    BranchCode    VARCHAR(12)  NOT NULL,
    BranchName    NVARCHAR(100) NOT NULL,
    Country       NVARCHAR(60)  NOT NULL,
    City          NVARCHAR(60)  NOT NULL,
    OpenedDate    DATE          NOT NULL
);
GO

/* ---- core.Customers ------------------------------------------------------ */
IF OBJECT_ID('core.Customers') IS NULL
CREATE TABLE core.Customers (
    CustomerId                 INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNumber             VARCHAR(20)  NOT NULL,
    FirstName                  NVARCHAR(60) NOT NULL,
    LastName                   NVARCHAR(60) NOT NULL,
    DateOfBirth                DATE         NOT NULL,
    Country                    NVARCHAR(60) NOT NULL,
    City                       NVARCHAR(60) NOT NULL,
    Email                      NVARCHAR(120) NOT NULL,
    PhoneNumber                VARCHAR(30)  NULL,
    KycStatus                  VARCHAR(20)  NOT NULL,
    CustomerSegment            VARCHAR(20)  NOT NULL,
    IsPoliticallyExposedPerson BIT          NOT NULL DEFAULT 0,
    CreatedDate                DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- core.Accounts ------------------------------------------------------- */
IF OBJECT_ID('core.Accounts') IS NULL
CREATE TABLE core.Accounts (
    AccountId     INT IDENTITY(1,1) PRIMARY KEY,
    CustomerId    INT           NOT NULL,
    AccountNumber VARCHAR(24)   NOT NULL,
    Iban          VARCHAR(34)   NOT NULL,
    AccountType   VARCHAR(20)   NOT NULL,
    Currency      CHAR(3)       NOT NULL,
    Balance       DECIMAL(18,2) NOT NULL DEFAULT 0,
    Status        VARCHAR(15)   NOT NULL DEFAULT 'Active',
    OpenDate      DATE          NOT NULL,
    BranchId      INT           NULL
);
GO

/* ---- core.Employees ------------------------------------------------------ */
IF OBJECT_ID('core.Employees') IS NULL
CREATE TABLE core.Employees (
    EmployeeId  INT IDENTITY(1,1) PRIMARY KEY,
    UserName    VARCHAR(60)  NOT NULL,
    FullName    NVARCHAR(120) NOT NULL,
    Department  NVARCHAR(60) NOT NULL,
    Title       NVARCHAR(80) NULL,
    BranchId    INT          NULL,
    HireDate    DATE         NOT NULL
);
GO

/* ---- payments.Transactions ---------------------------------------------- */
IF OBJECT_ID('payments.Transactions') IS NULL
CREATE TABLE payments.Transactions (
    TransactionId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    AccountId          INT           NOT NULL,
    TransactionType    VARCHAR(20)   NOT NULL,
    Amount             DECIMAL(18,2) NOT NULL,
    Currency           CHAR(3)       NOT NULL,
    MerchantName       NVARCHAR(120) NULL,
    MerchantCategory   VARCHAR(40)   NULL,
    CounterpartyAccount VARCHAR(34)  NULL,
    TransactionDate    DATETIME2     NOT NULL,
    Channel            VARCHAR(20)   NOT NULL,
    RiskFlag           VARCHAR(10)   NOT NULL DEFAULT 'None'
);
GO

/* ---- payments.PaymentInstructions --------------------------------------- */
IF OBJECT_ID('payments.PaymentInstructions') IS NULL
CREATE TABLE payments.PaymentInstructions (
    InstructionId    BIGINT IDENTITY(1,1) PRIMARY KEY,
    AccountId        INT           NOT NULL,
    Amount           DECIMAL(18,2) NOT NULL,
    Currency         CHAR(3)       NOT NULL,
    BeneficiaryName  NVARCHAR(120) NOT NULL,
    BeneficiaryIban  VARCHAR(34)   NOT NULL,
    Status           VARCHAR(20)   NOT NULL DEFAULT 'Pending',
    CreatedDate      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- payments.WireTransfers --------------------------------------------- */
IF OBJECT_ID('payments.WireTransfers') IS NULL
CREATE TABLE payments.WireTransfers (
    WireId            BIGINT IDENTITY(1,1) PRIMARY KEY,
    AccountId         INT           NOT NULL,
    Amount            DECIMAL(18,2) NOT NULL,
    Currency          CHAR(3)       NOT NULL,
    BeneficiaryBank   NVARCHAR(120) NOT NULL,
    BeneficiaryIban   VARCHAR(34)   NOT NULL,
    Country           NVARCHAR(60)  NOT NULL,
    Status            VARCHAR(20)   NOT NULL DEFAULT 'Sent',
    IsDemoRow         BIT           NOT NULL DEFAULT 0,
    CreatedDate       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- risk.CustomerRiskScores -------------------------------------------- */
IF OBJECT_ID('risk.CustomerRiskScores') IS NULL
CREATE TABLE risk.CustomerRiskScores (
    RiskScoreId  BIGINT IDENTITY(1,1) PRIMARY KEY,
    CustomerId   INT          NOT NULL,
    RiskScore    INT          NOT NULL,
    RiskBand     VARCHAR(10)  NOT NULL,
    LastReviewed DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- risk.SanctionsScreening -------------------------------------------- */
IF OBJECT_ID('risk.SanctionsScreening') IS NULL
CREATE TABLE risk.SanctionsScreening (
    ScreeningId   BIGINT IDENTITY(1,1) PRIMARY KEY,
    CustomerId    INT          NOT NULL,
    ListName      VARCHAR(40)  NOT NULL,
    MatchScore    INT          NOT NULL,
    Decision      VARCHAR(20)  NOT NULL,
    ScreenedDate  DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- risk.FraudSignals -------------------------------------------------- */
IF OBJECT_ID('risk.FraudSignals') IS NULL
CREATE TABLE risk.FraudSignals (
    SignalId     BIGINT IDENTITY(1,1) PRIMARY KEY,
    CustomerId   INT          NOT NULL,
    SignalType   VARCHAR(40)  NOT NULL,
    Severity     VARCHAR(10)  NOT NULL,
    Details      NVARCHAR(400) NULL,
    DetectedDate DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- auditdemo.SensitiveCustomerData ------------------------------------ */
IF OBJECT_ID('auditdemo.SensitiveCustomerData') IS NULL
CREATE TABLE auditdemo.SensitiveCustomerData (
    CustomerId         INT          NOT NULL PRIMARY KEY,
    NationalIdentifier VARCHAR(30)  NOT NULL,
    TaxIdentifier      VARCHAR(30)  NOT NULL,
    PassportNumber     VARCHAR(20)  NULL,
    CreditScore        INT          NOT NULL,
    SalaryBand         VARCHAR(10)  NOT NULL,
    InternalRiskComment NVARCHAR(400) NULL,
    VIPFlag            BIT          NOT NULL DEFAULT 0,
    DataClassification VARCHAR(20)  NOT NULL DEFAULT 'Confidential'
);
GO

/* ---- auditdemo.PrivilegedOperations ------------------------------------- */
IF OBJECT_ID('auditdemo.PrivilegedOperations') IS NULL
CREATE TABLE auditdemo.PrivilegedOperations (
    OperationId   BIGINT IDENTITY(1,1) PRIMARY KEY,
    PerformedBy   VARCHAR(60)  NOT NULL,
    OperationType VARCHAR(40)  NOT NULL,
    TargetObject  NVARCHAR(120) NULL,
    PerformedAt   DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- auditdemo.DemoEvents ------------------------------------------------ */
IF OBJECT_ID('auditdemo.DemoEvents') IS NULL
CREATE TABLE auditdemo.DemoEvents (
    DemoEventId  BIGINT IDENTITY(1,1) PRIMARY KEY,
    ScenarioCode CHAR(1)      NOT NULL,
    ScenarioName NVARCHAR(120) NOT NULL,
    RunBy        VARCHAR(60)  NULL,
    Notes        NVARCHAR(400) NULL,
    RunAt        DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---- hr.EmployeeAccessProfiles ------------------------------------------ */
IF OBJECT_ID('hr.EmployeeAccessProfiles') IS NULL
CREATE TABLE hr.EmployeeAccessProfiles (
    ProfileId              INT IDENTITY(1,1) PRIMARY KEY,
    UserName               VARCHAR(60)  NOT NULL,
    RoleName               VARCHAR(40)  NOT NULL,
    Department             NVARCHAR(60) NOT NULL,
    NormalWorkingHoursStart TINYINT     NOT NULL,
    NormalWorkingHoursEnd   TINYINT     NOT NULL,
    NormalSourceIp         VARCHAR(45)  NULL,
    UsualDatabases         NVARCHAR(200) NULL,
    UsualTables            NVARCHAR(400) NULL,
    ExpectedSchemas        NVARCHAR(200) NULL,
    ExpectedTables         NVARCHAR(400) NULL,
    ExpectedActivityLevel  VARCHAR(20)  NULL,
    DataAccessJustification NVARCHAR(400) NULL,
    IsPrivileged           BIT          NOT NULL DEFAULT 0,
    ManagerName            NVARCHAR(120) NULL
);
GO

/* ---- admin.AccessRequests ----------------------------------------------- */
IF OBJECT_ID('admin.AccessRequests') IS NULL
CREATE TABLE admin.AccessRequests (
    RequestId    BIGINT IDENTITY(1,1) PRIMARY KEY,
    RequestedBy  VARCHAR(60)  NOT NULL,
    RequestedRole VARCHAR(40) NOT NULL,
    Justification NVARCHAR(400) NULL,
    Status       VARCHAR(20)  NOT NULL DEFAULT 'Pending',
    RequestedDate DATETIME2   NOT NULL DEFAULT SYSUTCDATETIME(),
    ApprovedBy   VARCHAR(60)  NULL
);
GO

/* ---- auditdemo.SensitiveObjectCatalog ----------------------------------- */
IF OBJECT_ID('auditdemo.SensitiveObjectCatalog') IS NULL
CREATE TABLE auditdemo.SensitiveObjectCatalog (
    CatalogId            INT IDENTITY(1,1) PRIMARY KEY,
    ObjectName           NVARCHAR(128) NOT NULL,
    SchemaName           NVARCHAR(64)  NOT NULL,
    SensitivityLevel     VARCHAR(20)   NOT NULL,
    BusinessOwner        NVARCHAR(120) NOT NULL,
    Reason               NVARCHAR(400) NOT NULL,
    RecommendedMonitoring NVARCHAR(400) NOT NULL
);
GO

PRINT 'Schema and tables ensured.';
