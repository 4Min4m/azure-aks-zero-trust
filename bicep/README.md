# Bicep parity

This directory re-implements **only the networking + AKS cluster** shell
from `terraform/` in Bicep — not the SQL Ledger, Storage Account, Key
Vault, or Kubernetes-level policy objects. That scope was chosen
deliberately, not left incomplete by accident:

- The **point** of this phase is demonstrating Bicep fluency and the
  experience of keeping two IaC tools in parity on the same resource
  graph — not re-authoring the entire platform twice.
- The AKS cluster + VNet is the part most Azure-native-IaC job postings
  actually probe on ("show me you can write Bicep, not just Terraform").
- **Terraform is, and remains, the primary/maintained implementation.**
  This is a one-time demonstration of transferable IaC knowledge, not a
  commitment to keep both in sync going forward. If you extend the
  platform later (new services, policy changes), do it in Terraform only,
  and say so plainly if asked — an unmaintained parallel IaC tree that
  silently drifts is worse than not having one.

## Deploy (into its own resource group — don't point this at the Terraform-managed RG)

```bash
az deployment sub create \
  --location westeurope \
  --template-file bicep/main.bicep \
  --parameters projectPrefix=ztaks-bicep environment=demo
```

## What to compare when asked "Bicep vs Terraform" in an interview

| | Terraform | Bicep |
|---|---|---|
| State | Explicit remote state file you manage | No state file — Azure Resource Manager IS the state |
| Multi-cloud | Same tool/language across AWS/GCP/Azure (see the other two projects) | Azure-only, but zero extra moving parts for Azure-only shops |
| Drift detection | `terraform plan` diffs against state | `az deployment what-if` diffs against live ARM |
| Learning curve here | HCL, provider versioning, state locking | ARM template syntax made readable; ships with the `az` CLI already installed |
