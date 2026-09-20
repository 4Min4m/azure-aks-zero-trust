# ---------------------------------------------------------------------------
# Azure Policy for AKS — the same "policy list" as the Kyverno ClusterPolicy
# set in the AWS project (non-root, no privilege escalation, resource
# limits), enforced by a different engine.
#
# Mechanically the two are closer than they look: the Azure Policy Add-on
# for AKS *is* Gatekeeper (OPA) running in-cluster — Azure Policy is the
# control-plane/reporting layer on top, translating ARM policy assignments
# into Gatekeeper ConstraintTemplates + Constraints behind the scenes for
# the built-ins below. Kyverno, by contrast, has its own admission
# controller and its own (non-Rego) policy language. That distinction is a
# good senior-interview answer in itself.
# ---------------------------------------------------------------------------

data "azurerm_policy_definition_built_in" "pod_security_restricted" {
  display_name = "Kubernetes cluster pod security restricted standards for Linux-based workloads"
}

data "azurerm_policy_definition_built_in" "resource_limits" {
  display_name = "Kubernetes cluster containers CPU and memory resource limits should not exceed the specified limits"
}

data "azurerm_policy_definition_built_in" "allowed_images" {
  display_name = "Kubernetes cluster containers should only use allowed images"
}

resource "azurerm_resource_policy_assignment" "pod_security_restricted" {
  name                 = "aks-pod-security-restricted"
  resource_id          = azurerm_resource_group.main.id
  policy_definition_id = data.azurerm_policy_definition_built_in.pod_security_restricted.id
  description          = "Non-root, no privilege escalation, no hostPath/hostNetwork — mirrors the Kyverno baseline rules from the AWS project."
  display_name         = "AKS pod security — restricted standards"

  parameters = jsonencode({
    effect = { value = "deny" }
    excludedNamespaces = { value = ["kube-system", "gatekeeper-system", "azure-arc"] }
  })
}

resource "azurerm_resource_policy_assignment" "resource_limits" {
  name                 = "aks-container-resource-limits"
  resource_id          = azurerm_resource_group.main.id
  policy_definition_id = data.azurerm_policy_definition_built_in.resource_limits.id
  description          = "Every container must declare CPU/memory limits — prevents one runaway pod starving the node."
  display_name         = "AKS containers — CPU/memory limits required"

  parameters = jsonencode({
    effect       = { value = "deny" }
    cpuLimit     = { value = "1000m" }
    memoryLimit  = { value = "1Gi" }
    excludedNamespaces = { value = ["kube-system", "gatekeeper-system", "azure-arc"] }
  })
}

resource "azurerm_resource_policy_assignment" "allowed_images" {
  name                 = "aks-allowed-image-registries"
  resource_id          = azurerm_resource_group.main.id
  policy_definition_id = data.azurerm_policy_definition_built_in.allowed_images.id
  description          = "Restrict image sources to MCR + this project's registry, as a base for the custom no-:latest rule to build on."
  display_name         = "AKS containers — allowed image registries"

  parameters = jsonencode({
    effect  = { value = "deny" }
    excludedNamespaces = { value = ["kube-system", "gatekeeper-system", "azure-arc"] }
    allowedContainerImagesRegex = {
      # mcr.microsoft.com/* (AKS system components), and the two Docker Hub
      # publishers this project actually pulls from (nginxinc, bitnami),
      # whether referenced bare or with an explicit docker.io/ prefix.
      value = "^(mcr\\.microsoft\\.com/|(docker\\.io/)?(nginxinc|bitnami)/).*"
    }
  })
}

# NOTE — the fourth rule, "no :latest tag", has no built-in Azure Policy
# equivalent, so it's shipped as a hand-written Gatekeeper ConstraintTemplate
# applied directly with kubectl instead of through the ARM policy control
# plane: k8s/policies/deny-latest-tag.yaml. Since the Azure Policy Add-on
# already deploys Gatekeeper into the cluster, you can extend it with your
# own ConstraintTemplates for anything the built-in catalog doesn't cover —
# you don't have to wait for Microsoft to ship a matching built-in, and you
# don't have to duplicate the whole ruleset in Kyverno just for one rule.
# That trade-off (ARM-managed + reportable vs. directly-applied + custom) is
# worth being able to explain out loud.
