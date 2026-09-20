-- Step 1 of the tamper-evidence demo: write some legitimate rows, then
-- capture a database digest — a cryptographic snapshot of the ledger's
-- state right now. This digest is the "known good" reference every later
-- verification is checked against.

INSERT INTO dbo.transaction_audit_log (transaction_ref, merchant_id, amount_minor_units, currency, status, recorded_by)
VALUES
    ('TXN-2026-0001', 'MERCH-001', 15000, 'EUR', 'AUTHORIZED', 'svc-gateway'),
    ('TXN-2026-0002', 'MERCH-002', 42599, 'EUR', 'AUTHORIZED', 'svc-gateway'),
    ('TXN-2026-0003', 'MERCH-001', 15000, 'EUR', 'SETTLED',    'svc-settlement');
GO

-- A legitimate, tracked change: this UPDATE is exactly what Ledger is
-- built to allow and record — the row's current value changes, and the
-- FULL history of both states is preserved automatically in
-- dbo.transaction_audit_log_history. This is NOT the tampering scenario;
-- it's the normal audit trail working as designed.
UPDATE dbo.transaction_audit_log
SET status = 'SETTLED'
WHERE transaction_ref = 'TXN-2026-0002';
GO

-- Manually generate a database digest. In production you'd point Ledger at
-- "automatic digest storage" (an immutable Blob container or Azure
-- Confidential Ledger) so this happens on a schedule without anyone having
-- to remember to run it — see docs/ledger-notes.md for why that matters.
-- For this walkthrough we generate one on demand and save it ourselves.
EXEC sys.sp_generate_database_ledger_digest;
GO
-- Copy the JSON result (one row: {"database_name":...,"block_id":...,
-- "hash":"0x...", ...}) into sql/03_known_good_digest.json — you'll need it
-- for both the clean verification and the corrupted-digest test.
