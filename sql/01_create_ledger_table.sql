-- Run against the `payments-audit-ledger` database (Terraform already
-- enabled Ledger at the database level via ledger_enabled=true; this
-- script creates the actual ledger table inside it).
--
-- Modeled loosely on the kind of transaction/audit-event log Amin worked
-- with at SADAD PSP: one row per settlement event, with enough fields to
-- make "someone edited a settled amount after the fact" a meaningful,
-- payments-relevant thing to catch.

CREATE TABLE dbo.transaction_audit_log
(
    audit_id           BIGINT IDENTITY(1,1) PRIMARY KEY,
    transaction_ref     NVARCHAR(64)     NOT NULL,
    merchant_id         NVARCHAR(32)     NOT NULL,
    amount_minor_units   BIGINT           NOT NULL,   -- amount in cents, avoids float rounding
    currency            CHAR(3)          NOT NULL,
    status               NVARCHAR(20)     NOT NULL,     -- e.g. AUTHORIZED, SETTLED, REVERSED
    recorded_at_utc      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    recorded_by          NVARCHAR(64)     NOT NULL
)
WITH
(
    SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.transaction_audit_log_history),
    LEDGER = ON (APPEND_ONLY = OFF)   -- updatable ledger: this table models
                                       -- a record whose STATUS legitimately
                                       -- changes over its lifecycle
                                       -- (AUTHORIZED -> SETTLED), which an
                                       -- append-only table can't represent
                                       -- directly. Every UPDATE still lands
                                       -- in the history table automatically.
);
GO

-- Sanity check: this view should show LEDGER='ON' and the paired history
-- table name.
SELECT name, ledger_type_desc, history_table_id
FROM sys.tables
WHERE name = 'transaction_audit_log';
GO
