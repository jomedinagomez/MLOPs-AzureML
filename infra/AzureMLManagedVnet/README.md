# AzureMLManagedVnet

Independent Terraform root for one Azure ML workspace, one external AML registry,
one compute instance, and one compute cluster in **one project resource group**.
Azure ML separately creates the registry's required service-managed backing
resource group; it is not an additional user-designed environment.
The stack reuses the existing private
modules without changing the dev/prod stack's default behavior. Do not copy
state, real variable files, or `.terraform` directories from another root.

## Architecture

- **Workspace:** user-assigned managed identity, public access disabled, AML-managed
  VNet with `AllowOnlyApprovedOutbound`.
- **Compute:** one instance and one cluster, each with a separate UAMI and no node
  public IPs. Both use `Standard_F8s_v2`; the cluster scales from zero to four nodes
  and scales down after two idle minutes. The instance is assigned to the human
  `assigned_user_object_id`, not the deployment identity. Shut it down when idle.
  Compute names use `cc<region-code><suffix>` and `ci<region-code><suffix>` to
  remain within AML naming limits.
  This root defers network creation until the first compute, after the workspace
  private endpoint exists, using Azure ML's documented automatic provisioning
  flow. Compute creation has an extended timeout for that initial network setup.
- **Registry:** system-assigned identity, private AML/blob/ACR endpoints, and public
  access disabled on both registry-managed Storage and ACR.
- **Inbound network:** a new customer VNet, private-endpoint subnet, and private DNS
  zones. This is separate from the AML-managed compute/outbound VNet.
- **Subnet security:** the customer private-endpoint subnet's NSG and association
  are owned by this Terraform root, including the deterministic NSG name used by
  the observed governance deployment pattern.
- **Encryption:** Microsoft-managed encryption. The workspace Key Vault remains;
  no CMK vault, key, or encryption scope is provisioned.
- **Serving:** the reused module prepares an online-endpoint UAMI and permissions,
  but this stack does not deploy an online endpoint.
- **No CI/CD, VPN gateway, Bastion, jumpbox, or hub firewall is created.**
- **No NSPs, public-IP exceptions, or policy-exemption resources in Terraform.**

This root focuses on AML-managed networking. Future customer-VNet injection
belongs in a separate stack; do not inject this stack's compute into the
customer private-endpoint subnet.

## Development Deletion Behavior

The new workspace Key Vault has **purge protection disabled**, with Azure's
mandatory seven-day soft-delete retention. No optional deletion lock or CMK
resource is created. `enable_auto_purge` and provider Key Vault purge-on-destroy
remain disabled. Workspace deletion uses the native Terraform/Azure operation,
not an implicit permanent-delete CLI hook.

Soft delete cannot be disabled, and deleted vault names remain reserved until
recovery, expiry, or an explicitly approved authorized purge. A previously
purge-protected vault cannot be made unprotected; use a new suffix rather than
recovering that vault for this development deployment.

Review a scoped `terraform plan -destroy` before cleanup. Do not execute it or
purge resources without explicit approval. Keep the provider's resource-group
deletion safeguard enabled. Inventory any policy-created child resources before
teardown and remove only specifically approved leftovers.

The AML workspace's approved outbound rules reach the external registry and its
backing blob storage and ACR using managed private endpoints. Workspace and
compute identities, plus the human owner, receive registry permissions.
Declare one outbound rule targeting the AML registry and let Azure resolve its
backing-service endpoints. Do not also declare separate blob/ACR outbound rules
for that registry: Azure rejects the overlapping destinations.

The workspace UAMI is included in the registry's
`managedResourceGroupSettings.assignedIdentities`. This is a scoped exception to
the registry-managed resource group's deny assignment, enabling managed private
endpoint approval. This API accepts **service principals only**, including
managed identities; a human object ID fails with `UnmatchedPrincipalType`.
The signed-in deployment user is not added automatically. When deploying through
an existing UAMI that needs an exception, supply its service-principal object ID
in `registry_managed_rg_assigned_principal_ids`. Do not grant unrelated principals
or subscription-wide permissions to runtime identities.

The registry service grants its declared identities access to the managed
backing resources. The observed `Azure AI Administrator` grant covers Storage/ACR
reads and private-endpoint approval. This root does not attempt human-user RBAC
or network-setting writes inside that system-protected group. It instead reads
the backing resources and requires public access to be disabled through
postconditions. If either check fails, stop; do not remove or bypass the deny
assignment.

These grants describe this root's configured baseline, not a universal
private-endpoint requirement. The separate
[approver-only experiment](../RegistryConnectivityTest/README.md#verified-result)
created an Active registry connection with approved backing endpoints and no
workspace-identity grant or preauthorization on the registry-managed group.
This root's existing configuration is unchanged.

The managed-network and registry patterns follow the existing repository modules
and [Matt Felton's Azure lab](https://github.com/mattfeltonma/azure-terraform-lab-base-azfw).
AzureRM stays on the existing 4.32 release line. This root requires AzAPI 2.13
because the old 2.3 embedded schema does not support the workspace's API version.
Workspace schema validation is explicitly enabled here; shared module consumers
retain their previous validation default and compatible 2.x constraints.

## Private Access and Governance

The workspace, registry, workspace Storage/Key Vault/ACR, and registry backing
Storage/ACR have public access disabled by default. Storage shared keys, anonymous blob
access, ACR admin credentials, and node public IPs remain disabled.
Trusted-service bypass still requires authenticated, authorized requests.

For an explicitly approved temporary computer-IP exception, use the Azure CLI
to configure workspace selected-IP access and Storage's default-deny firewall.
This adds IP-restricted public ingress; it does not create private laptop routing.
Keep registry, Key Vault, ACR, and managed outbound networking unchanged.
Terraform intentionally retains the private-only baseline, so review any later
plan: an apply can remove the manual exception. Verify effective policy and
authenticated Blob access rather than treating an accepted IP rule as proof.
See Microsoft's [selected-IP workspace guidance](https://learn.microsoft.com/azure/machine-learning/how-to-configure-private-link?view=azureml-api-2#enable-public-access-only-from-internet-ip-ranges).

To operate the private APIs from your laptop, arrange private routing and DNS
through existing VPN/peering/Bastion infrastructure, or use an approved private
host. Creating a private endpoint VNet alone does not give your laptop or browser
a route to Studio notebooks. No such client connection is provisioned here.

See Microsoft's guidance on
[registry sharing](https://learn.microsoft.com/azure/machine-learning/how-to-registry-network-isolation?view=azureml-api-2#share-assets-from-workspace-to-registry)
and [Key Vault service-side access](https://learn.microsoft.com/azure/machine-learning/how-to-secure-workspace-vnet?view=azureml-api-2#secure-azure-key-vault).

### Inherited Policy

Inherited Azure Policy can force Storage and Key Vault public network access to
`Disabled` even when Terraform requests selected-IP access. In that case, the IP
rules do not provide laptop access, and the source-storage exception required by
native registry sharing is ineffective. A saved Terraform plan alone does not
prove that Azure will retain the requested network settings.

This stack agrees with those private settings instead of requesting public
exceptions in Terraform. Any manual CLI exception must be authorized and
verified against effective policy. If policy requires purge protection, stop and resolve the conflict
before provisioning; do not enable protection silently or bypass the policy.

The current development deployment explicitly requests `SecurityControl=Ignore`
through its local/example `.tfvars` tags. This is a policy opt-out, not a cosmetic
label: apply it only where authorized. It is scoped to the new project group and
Terraform-managed resources, not existing environments, and is not forced by
the module's default tags. Explicit private access, keyless Storage, and disabled
purge protection remain configured independently of the tag.

The AzureRM provider's `storage.data_plane_available=false` feature avoids
Storage data-plane calls during account creation/read from outside the VNet.
Legacy Storage Analytics queue logging is disabled for this root; the module's
Azure Monitor queue diagnostics still collect read/write/delete events.
Other Terraform roots retain their existing legacy-logging default and state
addresses are preserved with a moved block.

## Prepare and Validate

From the repository root:

```powershell
Copy-Item infra\AzureMLManagedVnet\terraform.tfvars.example infra\AzureMLManagedVnet\terraform.tfvars
# Edit the real .tfvars: subscription, region/code, unique suffix, human owner.
terraform -chdir=infra\AzureMLManagedVnet init
terraform -chdir=infra\AzureMLManagedVnet validate
terraform -chdir=infra\AzureMLManagedVnet plan -out=tfplan
```

Confirm naming, address-space overlap, quota, regional SKU availability, effective
Azure Policy, and private client connectivity before reviewing and applying the
saved plan. This implementation does not apply Terraform.

### Managed-Identity Deployment

Run Terraform from an Azure host with an existing deployment UAMI:

```powershell
$env:ARM_USE_MSI = "true"
$env:ARM_CLIENT_ID = "<DEPLOYMENT_UAMI_CLIENT_ID>"
$env:ARM_SUBSCRIPTION_ID = "<SUBSCRIPTION_ID>"
$env:ARM_TENANT_ID = "<TENANT_ID>"
```

Both providers honor these authentication variables. The deployment identity must
already exist and be attached to the host; it is separate from the identities this
stack creates. Give it resource provisioning and role-assignment permissions at
the appropriate deployment scopes. Creating new resource groups requires
subscription-level provisioning permission. Also ensure the registry managed
resource-group exception can be assigned. Do not put secrets in `.tfvars`.

Local Azure CLI authentication is an alternative for an authorized human, not a
way to use a managed identity from an arbitrary laptop.

## Workshop Configuration and Deferred Asset Sharing

After an approved deployment, retrieve `terraform output -json workshop_environment`
and copy its identifier values into `workshop/.env`, using
[the configuration example](../../workshop/.env.example).
Do not overwrite existing behavior switches or run registration automatically.

The
[08_register_assets_to_registry.ipynb](../../workshop/notebooks/01_foundations/08_register_assets_to_registry.ipynb)
notebook is retained, but native workspace-to-registry sharing is **deferred**:
Microsoft documents that it requires selected-network public access and a registry
resource-instance exception on source Storage. This stack deliberately does not
enable that exception. Keep `SHARE_FOUNDATION_ASSETS=false`.

Verify provisioning, managed network readiness, endpoint approvals, identities,
the human compute owner, effective privacy, Key Vault purge protection, and live
RBAC first. SDK/job smoke tests and environment image builds require a confirmed
private-connected execution host. Do not report those runtime tests as passed
without actually running them.
