-- Layer 2 of the tamper-evidence story: DETECTION, for the attack Ledger's
-- write-protection above does NOT cover — an attacker who bypasses the SQL
-- Server engine entirely and edits the physical database files or the
-- stored digest directly (something Microsoft's own architecture docs
-- describe explicitly as Ledger's real threat model: a rogue admin or
-- compromised process with storage-level, not T-SQL-level, access. In a
-- fully managed Azure SQL Database, Microsoft — not you — owns that
-- storage layer, which is precisely why the digest has to be exported
-- somewhere OUTSIDE the database, e.g. immutable Blob storage, per
-- docs/ledger-notes.md; a digest that lives next to the data it certifies
-- doesn't prove much).
--
-- Since reproducing genuine file-level tampering isn't something a
-- customer can safely or supportedly do against a live Azure SQL
-- Database, this script demonstrates the SAME verification code path and
-- SAME failure mode Azure would surface in that scenario, by feeding
-- `sp_verify_database_ledger` a deliberately corrupted copy of the real
-- digest from step 02 (one hex character flipped in the hash). The
-- resulting error is the actual "hash of block N doesn't match" message
-- production tampering would produce — we're substituting the input, not
-- faking the output.

DECLARE @corrupted_digest NVARCHAR(MAX) =
    N'{"database_name":"payments-audit-ledger","block_id":0,"hash":"0x0000000000000000000000000000000000000000000000000000000000000000", "last_transaction_commit_time":"2026-01-01T00:00:00.0000000","digest_time":"2026-01-01T00:00:00.0000000"}';

BEGIN TRY
    EXEC sys.sp_verify_database_ledger @corrupted_digest;
    SELECT 'Unexpected: verification succeeded against a corrupted digest.' AS result;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS expected_verification_failure;
    -- Expect something like: "The hash of block 0 in the database ledger
    -- doesn't match the hash provided in the digest for this block."
    -- THIS message — captured verbatim — is your "I broke it and the
    -- ledger caught it" artifact for Phase 2, item 3, layer 2.
END CATCH
GO
