# Azure SQL Ledger — what it actually protects against, and the PCI DSS link

## The threat model, precisely

Ledger does **not** stop every kind of tampering — it can't, and Microsoft's
own docs are explicit about this. What it guarantees is *detection*:

> "An attacker or system administrator who has control of the machine can
> bypass all system checks and directly tamper with the data... Ledger can't
> prevent such attacks but guarantees that any tampering will be detected
> when the ledger data is verified." — Microsoft Learn, Ledger Overview

Two separate layers, demonstrated separately in `sql/`:

1. **Write-time prevention** (`sql/05_engine_level_tamper_attempt.sql`) — for
   the everyday case of someone with plain T-SQL access (even `db_owner`)
   trying to edit history directly, the SQL Server *engine itself* refuses
   the statement. No detection needed; it never happens.
2. **After-the-fact detection via cryptographic digests**
   (`sql/06_verify_with_corrupted_digest.sql`) — for the harder case: someone
   with access *below* the SQL engine (raw storage, backup files) who edits
   committed data directly. This is only reproducible against a real
   scenario on infrastructure you fully control (e.g. a local SQL Server
   container with raw file access) — not something you can or should attempt
   against a live, fully managed Azure SQL Database. The script instead
   feeds the verification procedure a deliberately corrupted digest to
   surface the *exact* failure mode ("hash of block N doesn't match") that
   real tampering would produce, using the real verification code path.

## Why the digest can't just live next to the data

If the digest were stored in the same database it's certifying, an attacker
capable of the storage-level tampering in layer 2 could simply rewrite the
digest to match their edit — the whole scheme collapses. That's why
production Ledger deployments use **automatic digest storage** pointing at:

- Azure immutable Blob storage (a storage account with an **immutability
  policy**, ideally **locked** — this project's `audit` storage account has
  a `ledger-digests` container reserved for exactly this, see
  `terraform/data-services.tf`), or
- Azure Confidential Ledger, which Microsoft's own docs describe as safe
  even from Microsoft's own operators.

This project generates digests manually for the walkthrough
(`sql/02_insert_rows_and_capture_digest.sql`) to keep the demo simple and
inspectable; wiring up automatic digest storage against the
`ledger-digests` container is the natural "next step" to mention if asked
how you'd run this for real.

## The PCI DSS connection (the part that should come from experience, not the docs)

PCI DSS 4.0 Requirement 10 is built almost entirely around this exact
property: audit logs must be protected such that unauthorized modification
is either prevented or reliably detectable, and log integrity must be
verifiable on a defined schedule — not just "logged and hoped."

At SADAD PSP, that requirement was met with **Utimaco HSM-backed integrity
controls** on the transaction/settlement path — hardware-rooted keys signing
or sealing records so that tampering downstream is cryptographically
evident, verified independently of the application that wrote the data.

Azure SQL Ledger is the *same shape of control*, implemented differently:
- HSM: a hardware root of trust signs/protects data; verification is a
  cryptographic check against that root.
- Ledger: a per-block SHA-256 hash chain plays the same role; verification
  (`sp_verify_database_ledger[_from_digest_storage]`) is the equivalent
  cryptographic check, and the *external, immutable digest* plays the role
  the HSM's isolation plays — evidence that no one, not even someone with
  database-admin rights, can silently rewrite.

The honest comparison to draw in an interview isn't "Ledger is as strong as
an HSM" (it isn't — an HSM protects a hardware boundary; Ledger protects a
software/cryptographic one, and Microsoft's own PaaS storage layer is
outside a customer's control either way). The honest comparison is that
**both solve the same PCI DSS 10.x problem — tamper-evident, independently
verifiable audit trails — at different points in the stack and different
cost/complexity levels**, and knowing when a software-only control is
sufficient vs. when you actually need HSM-backed integrity is itself the
senior-level judgment call.
