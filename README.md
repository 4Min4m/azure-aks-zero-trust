# Zero-Trust AKS Platform with Tamper-Evident Audit & Multi-IaC Parity

A private, identity-first Azure Kubernetes Service platform with a
cryptographically tamper-evident audit trail — built as the Azure
counterpart to a multi-region AWS DR project and a GCP internal developer
platform, each demonstrating a different senior-platform-engineering story
rather than repeating the same one three times.

## What this demonstrates

| Area | What's here | Why it's here |
|---|---|---|
| Zero-trust cluster access | Private AKS API server, `local_account_disabled`, Entra ID–only RBAC | No static kubeconfig anywhere; every access path is identity-based and audited |
| Practical private-cluster access | `az aks command invoke` from Codespaces/CI (`docs/access.md`) | A private API server is a checkbox; day-to-day access is the actual engineering problem |
| Pod-to-Azure auth | Azure AD Workload Identity, federated credential, zero stored secrets (`terraform/identity.tf`, `k8s/workload-identity-demo/`) | Replaces connection-strings-in-a-Secret with short-lived, auto-rotated tokens |
| Policy enforcement | Azure Policy Add-on (built-in initiatives) + one custom Gatekeeper ConstraintTemplate (`terraform/policy.tf`, `k8s/policies/`) | Same rule *list* as the AWS project's Kyverno policies, different engine — a real trade-off to be able to discuss |
| Tamper-evident audit trail | Azure SQL Database with Ledger, engine-level tamper rejection + digest-based tamper detection (`sql/`, `docs/ledger-notes.md`) | The standout differentiator — ties directly to PCI DSS 4.0 Requirement 10 and Amin's SADAD PSP background |
| Private data services | Private Endpoints (SQL, Storage, Key Vault), no public network access anywhere (`terraform/data-services.tf`) | Nothing PaaS-based in this project has a public IP, full stop |
| Multi-IaC parity | Bicep re-implementation of the network + cluster shell (`bicep/`) | Some employers specifically want Bicep; demonstrates transferable IaC knowledge, not tool-specific memorization |

## Architecture

```
                         ┌───────────────────────────────────────────┐
                         │           Azure Subscription               │
                         │                                             │
   Codespaces / CI ──ARM──▶  az aks command invoke (no VNet needed)   │
   (no VNet access)      │           │                                 │
                         │           ▼                                 │
                         │   ┌─────────────────────────────┐          │
                         │   │   AKS — PRIVATE cluster       │          │
                         │   │  (no public API endpoint)      │          │
                         │   │                                 │          │
                         │   │  namespace: apps                │          │
                         │   │   └─ nginx (stateless, WI-off)  │          │
                         │   │      internal LB only            │          │
                         │   │                                   │          │
                         │   │  namespace: data                  │          │
                         │   │   └─ mysql (stateful, Premium SSD)│          │
                         │   │      ClusterIP only, NetPol-gated  │          │
                         │   │                                     │          │
                         │   │  namespace: workload-identity-demo   │          │
                         │   │   └─ Job using Workload Identity      │          │
                         │   │      (no secrets, federated token)     │          │
                         │   └──────────────┬──────────────────────────┘          │
                         │        Private Endpoints (VNet-only, no public IP)      │
                         │        ┌──────────┼──────────────┬─────────────────┐   │
                         │        ▼          ▼              ▼                 │   │
                         │   ┌─────────┐ ┌─────────┐  ┌────────────┐          │   │
                         │   │ Key     │ │ Storage │  │ Azure SQL   │          │   │
                         │   │ Vault   │ │ Account │  │ (Ledger DB) │          │   │
                         │   └─────────┘ └─────────┘  └────────────┘          │   │
                         └───────────────────────────────────────────────────┘
```

## Zero-trust posture summary

- **No public API server** — `private_cluster_enabled = true`, and
  `command invoke` (not a VPN) is the access path (`docs/access.md`).
- **No static cluster credentials** — `local_account_disabled = true`;
  access is Entra ID RBAC or the ARM-mediated `command invoke` path only.
- **No public data-plane endpoints** — SQL, Storage, and Key Vault all have
  `public_network_access_enabled = false` and are reached exclusively
  through Private Endpoints in the VNet.
- **No long-lived secrets for pod-to-Azure auth** — Workload Identity issues
  short-lived, automatically rotated tokens; the one demo Job that talks to
  Storage does so with zero Kubernetes Secrets involved.
- **No un-pinned or ungoverned container images** — Azure Policy (built-in
  initiatives) plus one custom Gatekeeper rule jointly enforce non-root,
  resource limits, an allowed-registry list, and no `:latest` tags.
- **Tamper-evident, not just tamper-logged, audit data** — see
  [`docs/ledger-notes.md`](./docs/ledger-notes.md) for exactly what Ledger
  does and doesn't protect against, and how that maps to PCI DSS 4.0.

## Repo layout

```
terraform/          Primary IaC — VNet, private AKS, Workload Identity,
                     Azure Policy assignments, SQL Ledger, Storage, Key Vault
bicep/               Phase 3 parity subset (network + AKS only) — see bicep/README.md
helm/                nginx (stateless) and mysql (stateful) Helm charts/values
k8s/                 Plain manifests: Premium SSD StorageClass, custom
                     Gatekeeper policy, Workload Identity demo Job
sql/                 Ledger table creation + the two-layer tamper-evidence walkthrough
scripts/             deploy.sh / destroy.sh / verify-*.sh — the reference
                     run-through, all private-cluster-aware
docs/                access.md (private cluster access model) and
                     ledger-notes.md (threat model + PCI DSS mapping)
.gitlab-ci.yml       Same 5-stage shape as the AWS project's pipeline,
                     Azure-flavored, command-invoke-aware
```

## Deploying

Prerequisites: Azure CLI (`az`), Terraform ≥ 1.6, and `az login` with
Contributor + User Access Administrator (or equivalent) on the target
subscription. No local `kubectl`/`helm` install is required — every
cluster interaction goes through `az aks command invoke`
(see [`docs/access.md`](./docs/access.md)).

```bash
# 1. One-time: create the Terraform remote state backend
az group create -n rg-tfstate -l westeurope
az storage account create -n <globally-unique-name> -g rg-tfstate --sku Standard_LRS --encryption-services blob
az storage container create -n tfstate --account-name <globally-unique-name>
# fill the backend "azurerm" block in terraform/versions.tf with the above

# 2. Provision infrastructure
cd terraform
terraform init
export TF_VAR_mysql_admin_password="..."       # never commit real values
export TF_VAR_sql_admin_password="..."
export TF_VAR_allowed_object_id_for_key_vault="$(az ad signed-in-user show --query id -o tsv)"
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
cd ..

# 3. Deploy the Kubernetes-level pieces (storage class, policies, MySQL, nginx, Workload Identity demo)
./scripts/deploy.sh

# 4. Verify
./scripts/verify-private-access.sh
./scripts/verify-ledger.sh   # see the script's comments re: network path options

# 5. Tear down when done
./scripts/destroy.sh
```
