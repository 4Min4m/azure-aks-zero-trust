-- Layer 1 of the tamper-evidence story: PREVENTION, not just detection.
-- Ledger doesn't just notice tampering after the fact — for the most
-- direct attempt (editing history via ordinary T-SQL, even as db_owner),
-- SQL Server's engine refuses the statement outright. Run each of these
-- and note the error; every one should FAIL.

-- 1) Try to directly edit the auto-generated history table.
--    Expect: "Cannot update rows in a table which is enabled for
--    SYSTEM_VERSIONING and is currently in the state ON..." (or the
--    ledger-specific variant of that error).
UPDATE dbo.transaction_audit_log_history
SET amount_minor_units = 1
WHERE transaction_ref = 'TXN-2026-0001';
GO

-- 2) Try to turn SYSTEM_VERSIONING / LEDGER off to "unlock" the table.
--    Expect: an explicit error that ledger tables cannot have ledger
--    disabled once enabled.
ALTER TABLE dbo.transaction_audit_log SET (SYSTEM_VERSIONING = OFF);
GO

-- 3) Try to drop the history table directly.
--    Expect: an error that the history table is owned by a
--    system-versioned/ledger table and cannot be dropped independently.
DROP TABLE dbo.transaction_audit_log_history;
GO

-- Take a screenshot or paste the three error messages into the README /
-- study guide's "Ledger tamper-evidence" section — THIS is your "I tried
-- to break it and it refused" artifact for Phase 2, item 3, layer 1.
