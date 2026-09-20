-- The "no tampering" case: verify the CURRENT state against the digest you
-- captured in step 02. This should succeed with return code 0.
--
-- Paste the digest JSON you saved from step 02 in place of the literal
-- below (this is `sp_verify_database_ledger`, which takes a digest
-- directly — as opposed to `sp_verify_database_ledger_from_digest_storage`,
-- which reads digests from a configured external storage location instead
-- of one you paste in by hand; use that variant if you wire up automatic
-- digest storage per docs/ledger-notes.md).

DECLARE @digest NVARCHAR(MAX) = N'{"database_name":"payments-audit-ledger","block_id":0,"hash":"0xPASTE_THE_REAL_HASH_HERE", ...}';

BEGIN TRY
    EXEC sys.sp_verify_database_ledger @digest;
    SELECT 'Ledger verification succeeded — no tampering detected.' AS result;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS verification_error;
END CATCH
GO
