# Reaching a private AKS cluster from Codespaces

A private AKS cluster (`private_cluster_enabled = true`) has **no public API
server endpoint at all** — not "restricted by IP," genuinely absent from the
public internet. That's the whole point, but it means "how do I run
`kubectl` from Codespaces" needs a real answer, not just the checkbox.

## The three real options, and why this project uses the first one

| Option | Needs | Works from Codespaces (no VNet peering)? |
|---|---|---|
| **`az aks command invoke`** | Azure CLI + RBAC on the cluster | **Yes** — this is the one we use |
| VPN / ExpressRoute into the VNet | Persistent network infra, cost, setup | No, by design (would defeat the point of Codespaces being throwaway) |
| Jumpbox VM + Azure Bastion in the VNet | An extra VM to patch/pay for/secure | Works, but adds infrastructure just to run kubectl |

`az aks command invoke` runs your command (kubectl, helm, whatever) **inside
the cluster**, through the Azure Resource Manager API — not through the
private API server's network endpoint at all. Azure schedules a short-lived
pod, runs your command against the cluster from inside its own network
boundary, and streams the result back to you over the ARM control plane,
which *is* public (that's how `az` talks to every Azure service). Your
Codespaces box never needs line-of-sight to the VNet.

```bash
# Single command
az aks command invoke \
  --resource-group $(terraform -chdir=terraform output -raw resource_group_name) \
  --name $(terraform -chdir=terraform output -raw aks_cluster_name) \
  --command "kubectl get nodes"

# With local files attached (e.g. a whole Helm chart directory)
az aks command invoke \
  --resource-group <rg> --name <cluster> \
  --command "helm upgrade --install nginx-app ./nginx-app --values ./nginx-app/values.yaml" \
  --file helm/nginx
```

Because `local_account_disabled = true` on the cluster, there is no static
admin kubeconfig to leak, lose, or rotate — the only two doors in are
`command invoke` (RBAC-gated at the ARM layer) and interactive Entra ID
login for anyone who genuinely needs a live kubectl session from inside the
VNet (e.g. a future jumpbox). Both are identity-based, both are logged in
Azure AD sign-in logs / Activity Log, and neither is a secret sitting in a
file.

## Interview-ready version of this answer

> "The API server has no public endpoint. From CI or Codespaces — neither of
> which is on the cluster's VNet — I use `az aks command invoke`, which runs
> the command inside the cluster via the ARM control plane instead of
> connecting to the API server's network endpoint directly. It's RBAC-gated,
> it's audited the same way any other ARM operation is, and it means I never
> needed a VPN, a jumpbox, or the static admin kubeconfig — which I disabled
> outright with `local_account_disabled`."

## Caveats worth knowing (asked about in the study guide)

- `command invoke` has a 60-second ARM timeout per call and truncates output
  over 512 KB — fine for `kubectl apply`/`helm upgrade`/spot-checks, not for
  tailing logs continuously. For that, a jumpbox or Bastion session is the
  right tool, not a limitation of the private-cluster design itself.
- It needs `Microsoft.ContainerService/managedClusters/runcommand/action`
  RBAC — scope that role narrowly in a real environment, not at subscription
  level.
