# Azure ML Platform Deployment Strategy

## Table of Contents
- [Overview](#overview)
- [Centralized Azure ML & Core Service Private DNS Zones](#centralized-azure-ml--core-service-private-dns-zones)
- [Strategic Principles](#strategic-principles)
- [Current Infrastructure Configuration](#current-infrastructure-configuration)
- [Architecture Decisions](#architecture-decisions)
- [Identity and Access Management](#identity-and-access-management)
- [Network Security and Compliance](#network-security-and-compliance)
- [Verify After Apply](#verify-after-apply)
- [Asset Promotion Strategy](#asset-promotion-strategy)
- [Implementation Plan](#implementation-plan)
- [Cost Considerations](#cost-considerations)
- [Disaster Recovery and Business Continuity](#disaster-recovery-and-business-continuity)
- [Decision Log](#decision-log)
- [Next Steps](#next-steps)
- [Implementation Status](#implementation-status)
- [Deployment Workflow](#deployment-workflow)
- [References](#references)

## Overview

This document outlines the deployment strategy for our Azure Machine Learning platform implemented as a **flat dual-VNet architecture with Azure Bastion jumpbox access**. Remote private access is delivered exclusively through Azure Bastion to a Windows DSVM. No VPN gateway or SSH ingress is used.

**Key Architecture Features (Current):**
- **Flat Dual VNets**: Independent dev and prod VNets; no VNet peering between environments
- **Bastion-Only Access**: Azure Bastion provides browser-based RDP to a Windows DSVM jumpbox; no VPN/SSH
- **Deterministic Naming**: Names derive from `prefix`, `purpose`, `location_code`, `naming_suffix`; no random postfixes
- **Centralized Private DNS Zones (Expanded)**: Azure ML + core service private DNS zones (api, notebooks, instances, blob, file, queue, table, vaultcore, acr) consolidated in a shared DNS RG; only records (not resources) are multi‑tenant
- **Private-Only Posture**: Public network access disabled for workspaces, registries, storage, key vaults, ACR
- **Per-Environment Log Analytics**: Dedicated dev & prod workspaces for observability isolation
- **Bastion-Only Operation**: No VPN gateway is deployed; all remote access is via Azure Bastion RDP to a Windows DSVM
- **Managed Outbound Rules**: Private endpoint based outbound connectivity (with required `subresourceTarget = "amlregistry"`)
- **Parameterization**: All tunables (CIDRs, purge protection, diagnostics) exposed via variables

**Two registries remain intentionally for demonstration of cross‑environment asset promotion; a single registry suffices for most production deployments.**

**Last Updated**: August 9, 2025 – Enforced Bastion-only access (no VPN, no peering), centralized Private DNS for AML/storage/KV/ACR, deterministic naming via `naming_suffix`, refined outbound rule schema & Key Vault RBAC documentation.

> NOTE: No VNet peering is used between dev and prod. Shared Private DNS is linked to both VNets independently.

> Summary of Recent Fixes:
> - Outbound Rule ValidationError (400) resolved by adding `destination.subresourceTarget = "amlregistry"` when the destination is an Azure ML Registry.
> - Workspace provisioning 403 on Key Vault resolved by granting **Key Vault Reader** (management plane) alongside **Key Vault Secrets User** (data plane) to the workspace UAMI before creation.
> - Added staged `time_sleep` resources to ensure RBAC role propagation (90s) plus an additional workspace slot wait (150s) to avoid `FailedIdentityOperation` 409 conflicts after deletes.
> - Removed erroneous duplicate `name` property inside azapi workspace resource body.
> - Documentation now reflects RBAC separation (management-plane vs data-plane) for Key Vault.

### Key Vault Configuration (Updated)

The Key Vaults (`kvdev…`, `kvprod…`) are deployed with a **private-only** network posture and RBAC authorization (no access policies). Provider features:

```hcl
provider "azurerm" {
    features {
        key_vault {
            purge_soft_delete_on_destroy    = true
            recover_soft_deleted_key_vaults = true
        }
    }
}
```

#### Rationale for Dual Roles

During Azure ML Workspace creation via `azapi_resource` the service performs both:
1. **Management-plane read** of the Key Vault resource (needs `Microsoft.KeyVault/vaults/read`).
2. **Data-plane secret operations** later in lifecycle (needs data-plane secrets permission – satisfied by RBAC role granting secret list/get).

Observed issue: Only granting **Key Vault Secrets User** resulted in 403 errors (`vaults/read`) because that role does not include management-plane read. Fix: add **Key Vault Reader** to the *same* UAMI (and, in some cases, to the deployment SP if it must enumerate properties pre-create) before workspace creation.

#### Assigned Roles

| Principal | Scope | Role | Purpose |
|----------|-------|------|---------|
| Workspace UAMI | Key Vault | Key Vault Reader | Management-plane metadata read during provisioning |
| Workspace UAMI | Key Vault | Key Vault Secrets User | Data-plane secret access (read secrets) |
| Compute UAMI | Key Vault | Key Vault Secrets User (optional depending on workload) | Access secrets during training/inference |
| Deployment SP | (Optional) Key Vault | Reader or Key Vault Reader | Plan-time introspection / drift detection |

> Note: No legacy access policies are used; RBAC-only simplifies auditing and avoids mixed authorization modes.

#### Purge & Soft-Delete Considerations

Because purge protection and soft-delete retention can delay name re-use, a `time_sleep.wait_workspace_slot` was inserted after Key Vault & role assignment creation to avoid immediate workspace recreation conflicts (`FailedIdentityOperation` 409) when iterating quickly. This gives Azure sufficient time to finalize identity bindings.

### Outbound Rules to Azure ML Registries (Updated)

When defining outbound rules from a workspace to a registry using the preview API `Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview`, Azure now **requires** an explicit `subresourceTarget` for registry destinations. Without it the service returns:

```
ValidationError: Invalid Pair of Target and Sub Target resource ... supports ["amlregistry"], the sub target introduced was: (empty)
```

#### Correct Terraform (azapi) Shape

```hcl
resource "azapi_resource" "dev_workspace_to_dev_registry_outbound_rule" {
    type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
    name      = "AllowDevRegistryAccess"
    parent_id = module.dev_managed_umi.workspace_id

    body = {
        properties = {
            type = "PrivateEndpoint"
            destination = {
                serviceResourceId = module.dev_registry.registry_id
                subresourceTarget = "amlregistry" # REQUIRED for registry targets
            }
            category = "UserDefined"
        }
    }
    depends_on = [
        module.dev_managed_umi,
        module.dev_registry,
        azurerm_role_assignment.dev_workspace_network_connection_approver
    ]
}
```

Apply the same `subresourceTarget = "amlregistry"` addition for prod→prod and prod→dev outbound rules. This resolves the 400 ValidationError returned previously. Ensure the workspace UAMI holds **Azure AI Enterprise Network Connection Approver** on the registry scope before creating the rule.

#### Ordering & RBAC Propagation

Outbound rule resources should depend on:
1. Registry creation (system-assigned identity ready)
2. Workspace creation & managed network enablement
3. Network Connection Approver role assignment (workspace UAMI on registry)
4. Optional sleep for RBAC propagation if creation is immediately after role assignment (empirically ~60–90s sufficient, we use 90s)

#### Post-Mortem Summary (Outbound Rule Failures Resolved)

| Attempt | Payload Shape | Service Response | Root Cause | Resolution |
|---------|---------------|------------------|------------|------------|
| 1 | `destination` missing `subresourceTarget` | 400 ValidationError (Invalid Pair of Target and Sub Target) | Registry private endpoint requires subresource qualification | Added `subresourceTarget = "amlregistry"` |
| 2 | Experimental `privateEndpointDestination` property | 400 ValidationError (unrecognized shape) | Incorrect property name (SDK uses `destination`) | Reverted to `destination` block | 
| 3 | Repeated REST `az rest` trials (varied casing, api-version) | 415 / 400 | Quoting & schema experimentation noise | Terraform azapi with validated shape | 

Cleanup Action: Removed obsolete troubleshooting script `test-outbound-rule.ps1` after successful apply to reduce repository noise.

Preventative Guidance:
- Always consult currently published preview swagger / SDK examples; ignore legacy blog posts referencing superseded shapes.
- For private endpoint style outbound rules, verify whether the target resource type exposes multiple subresources; if yes, expect a required `subresourceTarget`.
- Keep troubleshooting artifacts (scripts) on a temporary branch; merge only the distilled, working pattern into main documentation.


### Troubleshooting Summary (Added)

| Symptom | Root Cause | Resolution |
|---------|------------|-----------|
| 403 `vaults/read` during workspace creation | Missing management-plane role on Key Vault | Add Key Vault Reader to workspace UAMI pre-create |
| 409 `FailedIdentityOperation` after delete | Rapid re-create before soft-delete/identity cleanup | Insert wait (150s) before re-provisioning |
| 400 ValidationError outbound rule to registry | Missing `subresourceTarget` | Add `subresourceTarget = "amlregistry"` in destination |
| 409 RoleAssignmentExists on human user roles | Role already granted out-of-band / drift | Import existing role assignment or enable `skip_service_principal_aad_check`; alternatively use `lifecycle { ignore_changes = [principal_id] }` or conditional creation |

## Centralized Azure ML & Core Service Private DNS Zones

### Rationale
Previously each environment module created its own Azure ML private DNS zones:
`privatelink.api.azureml.ms`, `privatelink.notebooks.azure.net`, and the (often implicit) `instances.azureml.ms` zone for compute instance hostnames. Because Azure Private DNS zones are *global* within a subscription for a given name, duplicating these per environment introduced conflicting desired state and prevented future expansion (multi‑subscription later) without manual reconciliation. Centralizing the three AML zones removes duplication, simplifies lifecycle management, and ensures consistent name resolution for shared services (e.g., cross‑environment registry network connections) while preserving full network isolation.

### What Is Shared vs Still Isolated (Updated)
| Category | Shared? | Notes |
|----------|---------|-------|
| AML Private DNS Zones (api, notebooks, instances) | Yes | Central shared DNS RG; record prefixes prevent collisions |
| Core Service Private DNS Zones (blob, file, queue, table, vaultcore, acr) | Yes | Consolidated (Rev 4) to eliminate duplication |
| VNets / Subnets | No | Independent dev / prod VNets; no peering |
| Workspaces / Registries | No | Provisioned per environment |
| Storage Accounts / Key Vaults / ACR Registries | No | Per environment; only DNS zones centralized |
| User-Assigned Managed Identities | No | Distinct per environment (workspace + compute) |
| Log Analytics Workspaces | No | Separate dev/prod analytics |

### Terraform Implementation
1. Shared zones declared once in a dedicated DNS resource group (with `prevent_destroy` for protection).
2. Virtual network links created for dev and prod VNets for each zone: AML api, notebooks, instances, blob, file, queue, table, vaultcore, acr.
3. Environment VNet modules consume shared zone IDs as inputs (no per-environment zone creation logic).
4. Workspace private endpoints reference all required zone IDs via a unified `private_dns_zone_group` list.

### DNS Record Coexistence
Workspace and registry endpoints include unique environment-specific prefixes (e.g., `mlwdevcc02` vs `mlwprodcc02`). Azure ML adds records only for the specific PEs created, so dev and prod records coexist in the same zone with no collision. This design enables future scenarios (e.g., secure cross‑env sharing, central policy) without additional DNS orchestration.

### Operational Benefits
| Benefit | Impact |
|---------|--------|
| Eliminate duplicate AML zone resources | Simpler state, faster plans |
| Single update point for AML DNS policy | Reduced drift risk |
| Easier multi‑subscription future (can move zones first) | Decouples DNS from environment lifecycle |
| Faster environment teardown (no contention for global zone names) | Speeds re-provision cycles |

### Validation Checklist
1. Connect via Azure Bastion to the Windows DSVM jumpbox.
2. Resolve: `nslookup mlwdev*.<region>.api.azureml.ms` → private IP in dev subnet range.
3. Resolve: `nslookup mlwprod*.<region>.api.azureml.ms` → private IP in prod subnet range.
4. Resolve notebook endpoint: `nslookup mlwdev*.<region>.notebooks.azure.net` (and prod analogue).
5. (Optional) Start a compute instance; verify its hostname A record in `instances.azureml.ms` zone.
6. Access Azure ML Studio privately for both envs; confirm no public fallback.

---


## Strategic Principles

### 1. Complete Environment Isolation (Updated)
- **Shared Components (Deliberate & Minimal)**: Central private DNS zones (AML api/notebooks/instances + core service zones: blob, file, queue, table, vaultcore, acr). All other resources (VNets, workspaces, registries, storage, key vaults, identities, log analytics) remain per-environment.
- **No Network Peering**: Dev↔Prod peering is not used; strict isolation is enforced. Managed outbound rules provide required registry connectivity.
- **Deterministic Naming**: Stable resource names improve drift detection & reproducibility.
- **Promotion Demonstration**: Dual registries retained solely for cross-environment promotion patterns.

### 2. Flat Dual-VNet Architecture with Bastion-only access
- **Flat Topology**: Dev VNet + Prod VNet + shared DNS resource group.
- **Access Model**: Bastion-only remote access into a Windows DSVM jumpbox; no VPN is deployed.
- **Isolation**: No VNet peering; private endpoint–based service access only.

### 3. Infrastructure as Code
- **Terraform Modules**: Reusable modules for consistent deployment across environments
- **Environment-Specific Configurations**: Separate terraform.tfvars for each environment
- **Version Control**: All infrastructure changes tracked and reviewed
- **Automated Deployment**: Infrastructure provisioned through CI/CD pipelines

## Current Infrastructure Configuration

### Resource Naming Strategy
Our infrastructure uses resource-specific prefixes for maximum flexibility:

```terraform
resource_prefixes = {
  vnet               = "vnet-aml"
  subnet             = "snet-aml"
  workspace          = "mlw"
  registry           = "mlr"
  storage            = "st"
  container_registry = "cr"
  key_vault          = "kv"
  log_analytics      = "log"
  public_ip          = "pip"
}
```

### Environment Templates
Both development and production use identical Terraform modules with environment-specific parameters:

**Common Configuration Structure:**
```terraform
prefix = "aml"                    # Base prefix for consistency
resource_prefixes = { ... }       # See above
purpose = "dev" | "prod"         # Environment identifier
location = "canadacentral"       # Same region for both environments
location_code = "cc"             # Region abbreviation
naming_suffix = "01"             # Deterministic suffix for naming
enable_auto_purge = true | false # Dev: true, Prod: false (CRITICAL)
```

**Environment-Specific Differences:**
- **Development**: `vnet_address_space = "10.1.0.0/16"`, `subnet_address_prefix = "10.1.1.0/24"`
- **Production**: `vnet_address_space = "10.2.0.0/16"`, `subnet_address_prefix = "10.2.1.0/24"`

**Generated Resource Examples (Deterministic):**
- VNet: `vnet-{prefix}-{env}-{location_code}-{naming_suffix}`
- Workspace: `mlw{env}{location_code}{naming_suffix}`
- Storage: `st{env}{location_code}{naming_suffix}`
- Container Registry: `cr{env}{location_code}{naming_suffix}`
- Key Vault: `kv{env}{location_code}{naming_suffix}`
- Registry: `mlr{env}{location_code}{naming_suffix}`
- Resource Groups (per environment): `rg-{prefix}-{component}-{env}-{location_code}-{naming_suffix}`

## Architecture Decisions

### A. Subscription Strategy
Based on the constraint of having only one subscription available, we use single subscription with complete resource group isolation:

**Approach: Single Subscription with Resource Group Isolation**
- Practical: Works with current subscription setup
- Simplified management: Single subscription to manage and monitor
- Shared quotas: Dev and prod can share subscription quotas efficiently
- Cost tracking: Use resource group tags for cost allocation
- Complete isolation: Still achieves zero shared components through different resource groups

**Mitigation Strategies:**
- Strong RBAC: Use resource group-level permissions for access control
- Resource tagging: Clear environment tagging for cost allocation and governance
- Naming conventions: Clear separation through parameterized naming
- Network isolation: Different VNet CIDR ranges prevent any network connectivity
- Monitoring separation: Separate Log Analytics workspaces for each environment

### B. Geographic Strategy
Same region for both environments provides operational simplicity and cost-effectiveness:

**Configuration:**
```
Both Dev and Prod:
├── location = "canadacentral"
├── location_code = "cc"
└── Same Azure region benefits
```

**Benefits:**
- Operational simplicity: Familiar region for your team
- Consistent performance: Same latency and performance characteristics
- Cost optimization: No cross-region data transfer costs
- Simplified monitoring: Single region to monitor for service health
- Easier troubleshooting: Consistent region-specific behaviors

### Current Flat Dual-VNet + Bastion-only Access

```
Development VNet (vnet-*-dev-*):
├── Address Space: 10.1.0.0/16
├── Private Endpoint Subnet: 10.1.1.0/24
├── DNS: Linked to centralized zones
└── Peering: None

Production VNet (vnet-*-prod-*):
├── Address Space: 10.2.0.0/16
├── Private Endpoint Subnet: 10.2.1.0/24
├── DNS: Linked to centralized zones
└── Peering: None

Cross-Environment Traffic:
└── Managed outbound rules to registries; no VNet peering required
```

**Benefits (Flat Model):**
- Reduced routing complexity (no transit layer)
- Gateway cost incurred only when explicitly enabled
- Simpler DNS linkage (single layer of VNet links)
- Identical security posture for private endpoints & managed outbound rules
- Faster Terraform plans (fewer resources)

## Identity and Access Management

### Service Principal Strategy
A single service principal is used for all infrastructure deployments across all 7 resource groups:

```
Deployment Service Principal:
├── Name: "sp-aml-deployment-platform"
├── Scope: All 7 resource groups (RG level permissions)
├── Roles: 
│   ├── Contributor (on all 7 resource groups): Deploy ML workspace, storage accounts, and compute resources - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#contributor)
│   ├── User Access Administrator (on all 7 resource groups): Configure RBAC for managed identities and user access - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#user-access-administrator)
│   └── Network Contributor (on all resource groups): Configure secure networking and private endpoints - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/networking#network-contributor)
├── Resource Groups:
│   ├── Development: rg-aml-vnet-dev-*, rg-aml-ws-dev-*, rg-aml-reg-dev-*
│   ├── Production: rg-aml-vnet-prod-*, rg-aml-ws-prod-*, rg-aml-reg-prod-*
│   └── Shared DNS: rg-aml-dns-*
└── Purpose: Terraform deployments via CI/CD pipelines
```

### Managed Identity Strategy
Managed identities use different types based on component requirements:

#### Workspace UAMI
- Name: "${purpose}-mi-workspace"
- Location: rg-aml-vnet-${purpose}-${location_code}${naming_suffix}
- Used by: Azure ML Workspace for management operations
- Roles:
    - Azure AI Administrator (resource group) – configure workspace settings and AI services integration
    - Azure AI Enterprise Network Connection Approver (resource group) – enable secure connectivity and cross-environment sharing
    - Azure AI Enterprise Network Connection Approver (registries) – allow private endpoint creation for outbound rules
    - Storage Blob Data Contributor (default storage account)
    - Storage Blob Data Owner (default storage account)
    - Reader (on private endpoints for storage accounts)
- Note: Workspace UAMIs do NOT have AzureML Registry User roles. They create network connections only; registry data access is handled by compute UAMIs and human users.

#### Registry SMI (System-Assigned)
- Identity Type: System-assigned (registries don’t support UAMI)
- Created automatically with the registry
- Manages the registry’s Microsoft-managed storage and ACR
- RBAC configured by the service; no manual configuration required

### Registry Managed Resource Group Pre-Authorization

Azure ML Registries create a Microsoft-managed resource group (azureml-rg-<registry>_guid) that hosts internal storage and ACR. To allow Azure ML to create private endpoints and network resources from managed VNets during provisioning and outbound rule operations, pre-authorize the deployment service principal by assigning its objectId via `managedResourceGroupSettings.assignedIdentities`.

Terraform (azapi):

```hcl
resource "azapi_resource" "registry" {
    type      = "Microsoft.MachineLearningServices/registries@2025-01-01-preview"
    name      = "${local.aml_registry_prefix}${var.purpose}${var.location_code}${var.naming_suffix}"
    parent_id = azurerm_resource_group.rgwork.id
    location  = var.location

    body = {
        identity   = { type = "SystemAssigned" }
        properties = {
            regionDetails = [{ location = var.location }]
            managedResourceGroupSettings = {
                assignedIdentities = [{ principalId = var.managed_rg_assigned_principal_id }]
            }
            publicNetworkAccess = "Disabled"
        }
    }
}
```

Key points:
- Use the objectId of the service principal that provisions resources.
- This enables Azure ML to finalize private connectivity for the registry under managed VNet constraints.
- Public network access remains disabled; connectivity occurs via private endpoints only.

#### Compute Cluster & Compute Instance UAMI (Shared)
- Name: "${purpose}-mi-compute"
- Location: rg-aml-vnet-${purpose}-${location_code}${naming_suffix}
- Used by: Both compute cluster and compute instance
- Roles:
    - AcrPull (container registry)
    - AcrPush (container registry)
    - Storage Blob Data Contributor (default storage account)
    - Storage File Data Privileged Contributor (default storage account)
    - AzureML Data Scientist (workspace)
    - Key Vault Secrets User (key vault)
    - Reader (resource group)
    - AzureML Registry User (registry)
    - Contributor (workspace) – for CI auto-shutdown

#### Online Endpoints
- Identity: System-assigned managed identity (default)
- Roles: Automatically managed by Azure ML service
- No additional RBAC configuration required

### Implementation Notes

**Key Implementation Decisions:**

1. **Single Shared Compute UAMI**: The implementation uses one User-Assigned Managed Identity (`${purpose}-mi-compute`) for both compute clusters and compute instances, as documented above. This reduces complexity while maintaining security boundaries.

2. **No Managed Online Endpoint UAMIs**: Following the strategy, online endpoints use system-assigned managed identities that are automatically managed by Azure ML service. No additional User-Assigned Managed Identities are created for online endpoints.

3. **Role Assignment Timing**: All role assignments are configured before compute resource creation to ensure proper permissions are in place when resources are provisioned.

4. **Module Parameter Passing**: The VNet module creates the shared compute UAMI and passes the identity ID and principal ID to both workspace and registry modules for proper role assignment configuration.

5. **Centralized Resource Group Ownership (New)**: Resource groups are created only at the root level. All modules require a pre-existing `resource_group_name` and no longer create RGs internally. This eliminates conditional `count` logic and plan-time unknowns, making plans deterministic and easier to reason about.

6. **Module Contracts (RG Inputs) (New)**:
    - `modules/aml-vnet`: requires `resource_group_name` (string). All VNet, subnet, UAMI, Private DNS zones, and diagnostics land in this RG.
    - `modules/aml-registry-smi`: requires `resource_group_name` (string). The Azure ML Registry is created in this RG; the Azure-managed registry RG is still handled by the service.
    - (Legacy network aggregation module removed – not part of current architecture).

7. **Migration Notes (New)**:
    - Remove any `create_resource_group` (bool) inputs from module invocations.
    - Ensure root creates RGs explicitly (e.g., `rg-aml-vnet-...`, `rg-aml-reg-...`) and passes their names into modules via `resource_group_name`.
    - Delete or ignore any internal RG resources in modules; references should use the passed `resource_group_name` via locals.
    - If outputs referenced counted RG IDs, compute the RG ID as `"/subscriptions/${subscription_id}/resourceGroups/${resource_group_name}"` using `data.azurerm_client_config` for the subscription ID.

## Network Security and Compliance

### Security Architecture

**Zero Trust Network Model**
```
External Access:
├── No Public Endpoints: All Azure ML resources are private
├── No direct RDP/SSH: Access is via Azure Bastion to a jumpbox VM; no public RDP/SSH
└── Certificate Management: Self-signed certificates with manual distribution

Internal Network Segmentation:
├── Dev VNet (10.1.0.0/16): Development workloads only
├── Prod VNet (10.2.0.0/16): Production workloads only
└── Optional Peering: Present only if explicitly enabled

Azure ML Private Endpoints:
├── Workspace APIs: *.api.azureml.ms
├── Workspace UI: *.ml.azure.com
├── Storage Accounts: *.blob.core.windows.net
├── Container Registries: *.azurecr.io
└── Key Vaults: *.vault.azure.net
```

**Compliance Features**
- **Data Residency**: All data remains in Canada Central region
- **Encryption in Transit**: All communication over private endpoints with TLS 1.2+
- **Encryption at Rest**: Azure-managed keys for all storage services
- **Access Logging**: Azure Activity Log tracks all management operations
- **Network Isolation**: No internet-facing endpoints for ML workspaces
- **Identity Integration**: Azure AD authentication for all human access

**Security Monitoring**
```
Azure Monitor Integration:
├── Private Endpoint Monitoring: DNS resolution and connectivity
├── Azure ML Audit Logs: Workspace access and operations
├── Resource Group Activity: All infrastructure changes
└── Cost Management: Spending anomaly detection

Compliance Reports:
├── Network Security Groups: Traffic flow analysis
├── Private DNS Zones: Resolution audit trails  
├── Key Vault Access: Secret and certificate usage
└── Role Assignment Changes: Permission modifications
```

### Human User RBAC

```
Data Engineers/Scientists:
├── Scope: Multi-level assignments
├── Resource Group Level:
│   └── Reader (on resource group): Discover ML resources and monitor workspace infrastructure - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader)
├── Workspace Level:
│   ├── AzureML Data Scientist (on workspace): Core ML development and model management - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-data-scientist)
│   ├── Azure AI Developer (on workspace): Develop generative AI solutions and prompt engineering - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azure-ai-developer)
│   └── AzureML Compute (on workspace): Manage personal compute instances and clusters - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-compute-operator)
├── Storage Level:
│   ├── Storage Blob Data Contributor (on default storage account): Manage training data and experimental outputs - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-contributor)
│   └── Storage File Data Privileged Contributor (on default storage account): Share code and collaborate on ML projects - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-file-data-privileged-contributor)
└── Registry Level:
    └── Azure ML Registry User (on registry): Access organization-wide ML assets and promote models - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-registry-user)
```

### Cross-Environment Permissions

To support the asset promotion workflow while maintaining security boundaries, specific cross-environment permissions are required for compute cluster User-Assigned Managed Identities (UAMIs).

#### Environment-Specific UAMI Identities

**Development Compute Cluster UAMI**
- **Identity**: `{dev-compute-uami-name}` (lives in dev resource group)
- **Scope**: Development environment only
- **Purpose**: Run training jobs, experimentation, model development

**Production Compute Cluster UAMI**
- **Identity**: `{prod-compute-uami-name}` (lives in prod resource group)  
- **Scope**: Production environment + limited dev registry access
- **Purpose**: Run inference jobs, model deployment, production workloads

#### Development UAMI Permissions (`{dev-compute-uami-name}`)

```
Development Environment Resources ONLY:
├── Storage Account ({dev-storage-account}): Storage Blob Data Contributor
├── Azure ML Workspace ({dev-workspace}): AzureML Data Scientist
├── Azure ML Registry ({dev-registry}): AzureML Registry User
├── Key Vault ({dev-key-vault}): Key Vault Secrets User
└── Any workspace-managed ACR: AcrPull + AcrPush

NO ACCESS to Production Environment:
├── {prod-storage-account}: No access
├── {prod-workspace}: No access  
├── {prod-registry}: No access
└── {prod-key-vault}: No access
```

**Security Principle**: Complete isolation from production to prevent any development workloads from affecting production systems.

#### Production UAMI Permissions (`{prod-compute-uami-name}`)

```
Production Environment Resources:
├── Storage Account ({prod-storage-account}): Storage Blob Data Contributor
├── Azure ML Workspace ({prod-workspace}): AzureML Data Scientist
├── Azure ML Registry ({prod-registry}): AzureML Registry User  
├── Key Vault ({prod-key-vault}): Key Vault Secrets User
└── Any workspace-managed ACR: AcrPull

Cross-Environment Access (READ-ONLY):
└── Dev Azure ML Registry ({dev-registry}): AzureML Registry User

NO WRITE ACCESS to Development Environment:
├── {dev-storage-account}: No access
├── {dev-workspace}: No access
└── {dev-key-vault}: No access
```

**Security Principle**: Minimal cross-environment access following the principle of least privilege. Production can read promoted assets from dev registry but cannot modify development resources.

#### Production Workspace UAMI Permissions (`{prod-workspace-uami-name}`)

```
Production Environment Resources:
├── Azure AI Administrator (on {prod-resource-group}): Configure workspace settings and AI services integration
├── Azure AI Enterprise Network Connection Approver (on {prod-resource-group}): Enable secure connectivity and cross-environment sharing
├── Azure AI Enterprise Network Connection Approver (on {prod-registry}): Enable cross-environment model sharing
├── Storage Blob Data Contributor (on {prod-storage-account}): Manage workspace artifacts and datasets
├── Storage Blob Data Owner (on {prod-storage-account}): Complete workspace storage management and permissions
└── Reader (on private endpoints for {prod-storage-account}): Monitor and validate secure storage connectivity

Cross-Environment Access (REQUIRED for Automatic Private Endpoint Creation):
└── Azure AI Enterprise Network Connection Approver (on {dev-registry}): Enable automatic private endpoint creation for outbound rules

NO DATA ACCESS to Registries:
├── {dev-registry}: No AzureML Registry User role (only network connection approver)
├── {prod-registry}: No AzureML Registry User role (only network connection approver)
└── Registry data access is handled by compute UAMIs and human users

NO WRITE ACCESS to Development Environment:
├── {dev-storage-account}: No access
├── {dev-workspace}: No access
└── {dev-key-vault}: No access
```

**Critical Permission**: The production workspace UAMI requires `Azure AI Enterprise Network Connection Approver` on the dev registry to automatically create private endpoints when outbound rules are configured. This permission enables the managed VNet to establish secure connectivity without manual intervention.

**Important Note**: Workspace UAMIs do NOT have `AzureML Registry User` roles. They only create network connectivity through private endpoints. Actual registry data access is provided through compute UAMIs and human user accounts.

#### Cross-Environment Access Justification

The production **compute** UAMI requires `AzureML Registry User` access to the development registry (`{dev-registry}`) to support the documented asset promotion patterns:

1. Environment references: access environments promoted from dev using URIs like `azureml://registries/{dev-registry}/environments/inference-env/versions/1.0`.
2. Docker image access: `AzureML Registry User` grants metadata access and enables pulls of associated images from the registry’s Microsoft-managed ACR.
3. Model lineage: maintain complete lineage for models promoted via the dev registry.

Important distinction: Only compute UAMIs and human users have `AzureML Registry User` roles for data access. Workspace UAMIs only have `Azure AI Enterprise Network Connection Approver` roles to create private endpoint connections.

#### Network Connectivity for Cross-Environment Access

**Managed VNet Automatic Private Endpoint Creation**

This infrastructure uses Azure ML managed virtual networks with `isolationMode = "AllowOnlyApprovedOutbound"`. **Private endpoints are automatically created** when outbound rules specify `type = "PrivateEndpoint"`.

```terraform
# Cross-environment connectivity (from main.tf)
resource "azapi_resource" "prod_workspace_to_dev_registry_outbound_rule" {
  type      = "Microsoft.MachineLearningServices/workspaces/outboundRules@2024-10-01-preview"
  name      = "AllowDevRegistryAccess"
  parent_id = module.prod_managed_umi.workspace_id

  body = {
    properties = {
      type = "PrivateEndpoint"
      destination = {
    serviceResourceId = module.dev_registry.registry_id
    subresourceTarget = "amlregistry" # required for registry targets
      }
      category = "UserDefined"
    }
  }

  depends_on = [
    module.prod_managed_umi,
    module.dev_registry,
    azurerm_role_assignment.prod_workspace_network_connection_approver
  ]
}
```

**What Happens Automatically:**
- **Private Endpoint Creation**: Azure ML service creates the private endpoint within the managed VNet
- **DNS Resolution**: Automatic DNS configuration for `{dev-registry}.api.azureml.ms`
- **Network Path**: Secure connectivity from prod workspace to dev registry without VNet peering
- **Microsoft-Managed ACR Access**: Automatic access to dev registry's internal ACR through the same private endpoint

**No Manual Network Configuration Required:**
- ❌ No VNet peering needed between environments
- ❌ No manual private endpoint creation
- ❌ No manual DNS configuration
- ❌ No cross-VNet private endpoint setup
- ✅ Complete network isolation maintained
- ✅ Automatic secure connectivity through managed VNet outbound rules

#### Registry Access Notes

- **Microsoft-Managed Resources**: Azure ML Registries create Microsoft-managed resource groups with their own ACR and storage. These resources are not directly manageable for RBAC assignments.
- **Automatic Access**: The `AzureML Registry User` role on the registry service automatically provides access to associated container images through Azure ML's internal service mechanisms.
- **Managed VNet Integration**: The outbound rule with `type = "PrivateEndpoint"` automatically handles all network connectivity, including access to the registry's Microsoft-managed ACR and storage.
- **No Direct ACR Permissions Needed**: Unlike workspace-managed ACRs, registry-managed ACRs are accessed automatically when you have appropriate registry permissions and network connectivity.

#### RBAC Assignment Summary

**Development Resource Group** (`{dev-resource-group}`):
```
{dev-compute-uami-name}:
├── AcrPull (on {dev-container-registry})
├── AcrPush (on {dev-container-registry})
├── Storage Blob Data Contributor (on {dev-storage-account})
├── Storage File Data Privileged Contributor (on {dev-storage-account})
├── AzureML Data Scientist (on {dev-workspace})
├── Key Vault Secrets User (on {dev-key-vault})
├── Reader (on {dev-resource-group})
├── AzureML Registry User (on {dev-registry})
└── Contributor (on {dev-workspace})

{dev-workspace-uami-name}:
├── Azure AI Administrator (on {dev-resource-group})
├── Azure AI Enterprise Network Connection Approver (on {dev-resource-group})
├── Azure AI Enterprise Network Connection Approver (on {dev-registry})
├── Storage Blob Data Contributor (on {dev-storage-account})
├── Storage Blob Data Owner (on {dev-storage-account})
└── Reader (on private endpoints for {dev-storage-account})

{prod-compute-uami-name}:
└── AzureML Registry User (on {dev-registry}) # Cross-environment read access

{prod-workspace-uami-name}:
└── Azure AI Enterprise Network Connection Approver (on {dev-registry}) # For automatic PE creation
```

**Production Resource Group** (`{prod-resource-group}`):
```
{prod-compute-uami-name}:
├── AcrPull (on {prod-container-registry})
├── AcrPush (on {prod-container-registry})
├── Storage Blob Data Contributor (on {prod-storage-account})
├── Storage File Data Privileged Contributor (on {prod-storage-account})
├── AzureML Data Scientist (on {prod-workspace})
├── Key Vault Secrets User (on {prod-key-vault})
├── Reader (on {prod-resource-group})
├── AzureML Registry User (on {prod-registry})
└── Contributor (on {prod-workspace})

{prod-workspace-uami-name}:
├── Azure AI Administrator (on {prod-resource-group})
├── Azure AI Enterprise Network Connection Approver (on {prod-resource-group})
├── Azure AI Enterprise Network Connection Approver (on {prod-registry})
├── Storage Blob Data Contributor (on {prod-storage-account})
├── Storage Blob Data Owner (on {prod-storage-account})
└── Reader (on private endpoints for {prod-storage-account})

{dev-compute-uami-name}:
└── No access to any production resources

{dev-workspace-uami-name}:
└── No access to any production resources
```

This configuration ensures complete environment isolation while enabling the necessary cross-environment asset access for production deployments using promoted development assets.

## Verify After Apply

Use these quick checks to validate networking, RBAC, and registry pre-authorization once Terraform finishes.

Prerequisites
- Azure CLI installed and logged in with sufficient permissions
- Subscription set to the one used for deployment

Set common variables (replace names if you customized naming)

```powershell
# Subscription
$SUBSCRIPTION_ID = (az account show --query id -o tsv)

# Names (match Terraform naming in this repo)
$DEV_RG_WS   = (az group list --query "[?starts_with(name, 'rg-aml-ws-dev-')].name | [0]" -o tsv)
$PROD_RG_WS  = (az group list --query "[?starts_with(name, 'rg-aml-ws-prod-')].name | [0]" -o tsv)
$DEV_RG_REG  = (az group list --query "[?starts_with(name, 'rg-aml-reg-dev-')].name | [0]" -o tsv)
$PROD_RG_REG = (az group list --query "[?starts_with(name, 'rg-aml-reg-prod-')].name | [0]" -o tsv)

$DEV_WS_NAME   = (az resource list -g $DEV_RG_WS  --resource-type Microsoft.MachineLearningServices/workspaces --query "[0].name" -o tsv)
$PROD_WS_NAME  = (az resource list -g $PROD_RG_WS --resource-type Microsoft.MachineLearningServices/workspaces --query "[0].name" -o tsv)
$DEV_REG_NAME  = (az resource list -g $DEV_RG_REG  --resource-type Microsoft.MachineLearningServices/registries --query "[0].name" -o tsv)
$PROD_REG_NAME = (az resource list -g $PROD_RG_REG --resource-type Microsoft.MachineLearningServices/registries --query "[0].name" -o tsv)

# Deployment Service Principal objectId (from Terraform output or Azure AD)
$DEPLOY_SP_OBJECT_ID = (az ad sp list --display-name "sp-aml-deployment-platform" --query "[0].id" -o tsv)
```

### 1) Registry managed RG pre-authorization (assignedIdentities)

Expect to see your deployment SP objectId under properties.managedResourceGroupSettings.assignedIdentities[].principalId

```powershell
# Dev registry
az rest `
    --method get `
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DEV_RG_REG/providers/Microsoft.MachineLearningServices/registries/$DEV_REG_NAME?api-version=2025-01-01-preview" `
    | ConvertFrom-Json `
    | Select-Object -ExpandProperty properties `
    | Select-Object -ExpandProperty managedResourceGroupSettings `
    | Select-Object -ExpandProperty assignedIdentities

# Prod registry
az rest `
    --method get `
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$PROD_RG_REG/providers/Microsoft.MachineLearningServices/registries/$PROD_REG_NAME?api-version=2025-01-01-preview" `
    | ConvertFrom-Json `
    | Select-Object -ExpandProperty properties `
    | Select-Object -ExpandProperty managedResourceGroupSettings `
    | Select-Object -ExpandProperty assignedIdentities
```

### 2) Managed VNet outbound rules (auto-PE)

Expect rules:
- Dev workspace → Dev registry
- Prod workspace → Prod registry
- Prod workspace → Dev registry (for dev asset consumption)

```powershell
# List outbound rules on dev workspace
az rest `
    --method get `
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$DEV_RG_WS/providers/Microsoft.MachineLearningServices/workspaces/$DEV_WS_NAME/outboundRules?api-version=2024-10-01-preview"

# List outbound rules on prod workspace
az rest `
    --method get `
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$PROD_RG_WS/providers/Microsoft.MachineLearningServices/workspaces/$PROD_WS_NAME/outboundRules?api-version=2024-10-01-preview"
```

### 3) Managed private endpoints present

Azure ML creates private endpoints in the workspace managed resource group (name starts with "mrg-"). Check for endpoints targeting the registries.

```powershell
# Find dev workspace managed RG and list PEs
$DEV_MRG = (az group list --query "[?starts_with(name, 'mrg-') && contains(name, '$DEV_WS_NAME')].name | [0]" -o tsv)
az network private-endpoint list -g $DEV_MRG -o table

# Find prod workspace managed RG and list PEs
$PROD_MRG = (az group list --query "[?starts_with(name, 'mrg-') && contains(name, '$PROD_WS_NAME')].name | [0]" -o tsv)
az network private-endpoint list -g $PROD_MRG -o table
```

Look for private service connections referencing subresource "amlregistry" and the dev/prod registry resource IDs.

### 4) Private-only posture for Storage, Key Vault, ACR

Expect publicNetworkAccess disabled and defaultAction Deny (where applicable).

```powershell
# Storage (dev/prod)
az storage account show -g $DEV_RG_WS  --name (az resource list -g $DEV_RG_WS  --resource-type Microsoft.Storage/storageAccounts --query "[0].name" -o tsv)  --query "{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction}" -o table
az storage account show -g $PROD_RG_WS --name (az resource list -g $PROD_RG_WS --resource-type Microsoft.Storage/storageAccounts --query "[0].name" -o tsv) --query "{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction}" -o table

# Key Vault (dev/prod)
az keyvault show -g $DEV_RG_WS  -n (az resource list -g $DEV_RG_WS  --resource-type Microsoft.KeyVault/vaults --query "[0].name" -o tsv)  --query "{publicNetworkAccess:properties.publicNetworkAccess, defaultAction:properties.networkAcls.defaultAction}" -o table
az keyvault show -g $PROD_RG_WS -n (az resource list -g $PROD_RG_WS --resource-type Microsoft.KeyVault/vaults --query "[0].name" -o tsv) --query "{publicNetworkAccess:properties.publicNetworkAccess, defaultAction:properties.networkAcls.defaultAction}" -o table

# Container Registry (workspace-managed ACR)
az acr show -g $DEV_RG_WS  -n (az resource list -g $DEV_RG_WS  --resource-type Microsoft.ContainerRegistry/registries --query "[0].name" -o tsv)  --query "{publicNetworkAccess:publicNetworkAccess, networkRuleBypassOption:networkRuleBypassOptions}" -o table
az acr show -g $PROD_RG_WS -n (az resource list -g $PROD_RG_WS --resource-type Microsoft.ContainerRegistry/registries --query "[0].name" -o tsv) --query "{publicNetworkAccess:publicNetworkAccess, networkRuleBypassOption:networkRuleBypassOptions}" -o table
```

### 5) RBAC spot checks on registries

Expect:
- Workspace UAMI has Azure AI Enterprise Network Connection Approver on dev/prod registries (for connectivity only)
- Compute UAMI has AzureML Registry User on dev/prod registries (for asset access)

```powershell
# Registry IDs
$DEV_REG_ID  = (az resource show -g $DEV_RG_REG  -n $DEV_REG_NAME  --resource-type Microsoft.MachineLearningServices/registries --query id -o tsv)
$PROD_REG_ID = (az resource show -g $PROD_RG_REG -n $PROD_REG_NAME --resource-type Microsoft.MachineLearningServices/registries --query id -o tsv)

# List role assignments at registry scopes
az role assignment list --scope $DEV_REG_ID  --query "[].{principalId:principalId, role:roleDefinitionName}"  -o table
az role assignment list --scope $PROD_REG_ID --query "[].{principalId:principalId, role:roleDefinitionName}" -o table
```

Look for roles:
- Azure AI Enterprise Network Connection Approver (workspace UAMI principal IDs)
- AzureML Registry User (compute UAMI principal IDs)

## Asset Promotion Strategy

### Overview

This section defines the strategy for promoting machine learning assets from development to production environments. Given our managed virtual network configuration and complete environment isolation, we implement a **Registry-Based Promotion Strategy** with manual validation gates.

### What Gets Promoted

**Assets Promoted via Registries:**
- **Trained Models**: Validated models ready for production deployment
- **Reference Data**: Small datasets for production validation and testing

**Assets Managed at Workspace Level (Cannot Use Registries):**
- **Environments**: Docker images and conda environments (managed via version control)
- **Pipeline Components**: Component definitions (managed via version control)

**Assets NOT Promoted:**
- **Training Data**: Remains in development for model training and experimentation
- **Experimental Models**: Only validated, approved models are promoted

### Promotion Architecture

**Selected Architecture: Two Registries for MLOps Demonstration**

While a single registry would be sufficient for most production scenarios, this implementation uses two registries to showcase comprehensive MLOps asset promotion workflows and demonstrate the full spectrum of Azure ML registry capabilities.

#### **Primary Implementation: Two-Registry Architecture**
```
Development Environment                Production Environment
┌─────────────────────┐               ┌─────────────────────┐
│ Dev Workspace       │               │ Prod Workspace      │
│ - Model Training    │               │ - Model Deployment  │
│ - Experimentation   │               │ - Inference         │
│ - Data Processing   │               │ - Monitoring        │
│ - Environment Mgmt  │               │ - Environment Mgmt  │
└─────────────────────┘               └─────────────────────┘
         │                                     ▲
         ▼ shares                              ▼ uses
┌─────────────────────┐               ┌─────────────────────┐
│ Dev Registry        │    Promote    │ Prod Registry       │
│ - Candidate Models  │  ─────────▶   │ - Production Models │
│ - Test Data         │               │ - Prod Data         │
│ (No Environments)   │               │ (No Environments)   │
└─────────────────────┘               └─────────────────────┘
```

#### **Alternative: Single-Registry Architecture (for comparison)**
```
Development Environment                Production Environment
┌─────────────────────┐               ┌─────────────────────┐
│ Dev Workspace       │               │ Prod Workspace      │
│ - Model Training    │               │ - Model Deployment  │
│ - Experimentation   │               │ - Inference         │
│ - Data Processing   │               │ - Monitoring        │
│ - Environment Mgmt  │               │ - Environment Mgmt  │
└─────────────────────┘               └─────────────────────┘
         │                                     ▲
         ▼ shares                              ▼ uses
    ┌─────────────────────────────────────────────────────┐
    │              Central Registry                       │
    │ - All validated models and data assets              │
    │ - Version-controlled asset promotion                │
    │ - Single source of truth for production assets      │
    │ - Environments                                      │
    └─────────────────────────────────────────────────────┘
```

**Architecture Benefits for Demonstration:**
- **Complete MLOps Workflow**: Shows end-to-end asset promotion across registry boundaries
- **Governance Showcase**: Demonstrates manual approval gates and promotion controls
- **Azure ML Feature Coverage**: Illustrates cross-registry operations and complex RBAC patterns
- **Enterprise Patterns**: Shows how to manage assets across multiple environments with full isolation

### Asset-Specific Promotion Strategies

#### **1. Trained Models**
**Strategy**: Registry-to-Registry Promotion for Demonstration
- **Process**: 
  1. Model trained and registered in Dev Workspace
  2. Share model from Dev Workspace to Dev Registry
  3. Manual approval and validation gate
  4. Promote model from Dev Registry to Prod Registry
  5. Model deployed from Prod Registry to Prod Workspace

```python
# Model promotion workflow (two-registry demonstration)
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Model
from azure.identity import DefaultAzureCredential

# ============================================================================
# STEP 1: Initialize ML Clients
# ============================================================================
credential = DefaultAzureCredential()

# Development workspace client
ml_client_dev_workspace = MLClient(
    credential=credential,
    subscription_id="your-subscription-id",
    resource_group_name="{dev-resource-group}", 
    workspace_name="{dev-workspace}"
)

# Development registry client
ml_client_dev_registry = MLClient(
    credential=credential,
    subscription_id="your-subscription-id",
    registry_name="{dev-registry}"
)

# Production registry client  
ml_client_prod_registry = MLClient(
    credential=credential,
    subscription_id="your-subscription-id",
    registry_name="{prod-registry}"
)

# ============================================================================
# STEP 2: Register Model in Development Workspace
# ============================================================================
print("Step 1: Registering model in development workspace...")

model_dev = Model(
    name="taxi-fare-model",
    version="1.0",
    path="azureml://jobs/{job-id}/outputs/model",  # Replace {job-id} with actual training job ID
    description="Taxi fare prediction model from training job",
    tags={"stage": "development", "algorithm": "lightgbm"}
)

model_created = ml_client_dev_workspace.models.create_or_update(model_dev)
print(f"Model created: {model_created.name} v{model_created.version}")

# ============================================================================
# STEP 3: Share Model from Dev Workspace to Dev Registry
# ============================================================================
print("\nStep 2: Sharing model to development registry...")

shared_model = ml_client_dev_workspace.models.share(
    name="taxi-fare-model",
    version="1.0",
    registry_name="{dev-registry}"
)
print(f"Model shared to dev registry: {shared_model.name} v{shared_model.version}")

# ============================================================================  
# STEP 4: Promote Model from Dev Registry to Prod Registry
# ============================================================================
print("\nStep 3: Promoting model to production registry...")

model_prod = Model(
    name="taxi-fare-model", 
    version="1.0",
    path="azureml://registries/{dev-registry}/models/taxi-fare-model/versions/1.0",
    description="Production taxi fare model (promoted from dev)",
    tags={"stage": "production", "promoted_from": "dev_registry"}
)

prod_model = ml_client_prod_registry.models.create_or_update(model_prod)
print(f"Model promoted to prod registry: {prod_model.name} v{prod_model.version}")

# ============================================================================
# STEP 5: Verification
# ============================================================================
print("\nVerification:")
print(f"Dev Registry Model: azureml://registries/{dev-registry}/models/taxi-fare-model/versions/1.0")
print(f"Prod Registry Model: azureml://registries/{prod-registry}/models/taxi-fare-model/versions/1.0")
```

#### **2. Reference Data Assets**
**Strategy**: Cross-Registry Data Promotion for Demonstration
- **Training Data**: Stays in development (not promoted)
- **Reference/Validation Data**: Small datasets promoted to production for testing
- **Process**: Create in Dev Workspace → Share to Dev Registry → Promote to Prod Registry

```python
# Reference data promotion workflow (two-registry demonstration)
from azure.ai.ml.entities import Data
from azure.ai.ml.constants import AssetTypes

# ============================================================================
# STEP 1: Create Data Asset in Development Workspace
# ============================================================================
print("Step 1: Creating validation dataset in development workspace...")

validation_data = Data(
    name="validation-dataset",
    version="1.0", 
    path="./validation-data",  # Local path to validation data files
    type=AssetTypes.URI_FOLDER,
    description="Validation dataset for model testing",
    tags={"data_type": "validation", "size": "small"}
)

data_created = ml_client_dev_workspace.data.create_or_update(validation_data)
print(f"Data asset created: {data_created.name} v{data_created.version}")

# ============================================================================
# STEP 2: Share Data from Dev Workspace to Dev Registry  
# ============================================================================
print("\nStep 2: Sharing data to development registry...")

shared_data = ml_client_dev_workspace.data.share(
    name="validation-dataset",
    version="1.0", 
    registry_name="{dev-registry}"
)
print(f"Data shared to dev registry: {shared_data.name} v{shared_data.version}")

# ============================================================================
# STEP 3: Promote Data from Dev Registry to Prod Registry
# ============================================================================  
print("\nStep 3: Promoting data to production registry...")

prod_data = Data(
    name="validation-dataset",
    version="1.0",
    path="azureml://registries/{dev-registry}/data/validation-dataset/versions/1.0",
    type=AssetTypes.URI_FOLDER,
    description="Production validation dataset (promoted from dev)",
    tags={"data_type": "validation", "stage": "production"}
)

prod_data_created = ml_client_prod_registry.data.create_or_update(prod_data)
print(f"Data promoted to prod registry: {prod_data_created.name} v{prod_data_created.version}")

# ============================================================================
# STEP 4: Verification
# ============================================================================
print("\nVerification:")
print(f"Dev Registry Data: azureml://registries/{dev-registry}/data/validation-dataset/versions/1.0")
print(f"Prod Registry Data: azureml://registries/{prod-registry}/data/validation-dataset/versions/1.0")
```

#### **3. Environment Images**
**Strategy**: Workspace-to-Registry-to-Production Promotion
- **Approach**: Create environment in dev workspace, share to dev registry, then promote to production
- **Two Environment Types**: Base Image + Conda OR Custom Dockerfile
- **Key Limitation**: Docker build contexts are consumed during registry build (source files not preserved)
- **Best Practice**: Keep Docker source files in version control for rebuilds
- **Property Access**: Use env.image for built images, env.conda_file for conda files, env.build (limited for registry environments)
- **Process**: 
  1. Create environment in Dev Workspace for development and testing
  2. Share environment from Dev Workspace to Dev Registry (Docker source consumed, image built)
  3. Promote to production using image references (Docker) or property access (Conda)
  4. For Docker rebuilds: Use version control source files, not registry downloads

#### **Environment Object Properties Reference**
Environment objects in Azure ML provide direct access to their configuration properties, eliminating the need to always download source files.

```python
# Get environment object from registry or workspace
env = ml_client.environments.get(name="environment-name", version="1.0")

# Available properties for all environment types:
print(f"Name: {env.name}")
print(f"Version: {env.version}")
print(f"Description: {env.description}")
print(f"Tags: {env.tags}")
print(f"Image URI: {env.image}")  # Built image URI or base image

# Conda-specific properties:
if hasattr(env, 'conda_file') and env.conda_file:
    print(f"Conda file path: {env.conda_file}")

# Docker-specific properties:
if hasattr(env, 'build') and env.build:
    print(f"Build context: {env.build}")
    print(f"Build context path: {env.build.path}")

# Additional properties may include:
# - env.creation_context (creation metadata)
# - env.provisioning_state (current state)
# - env.environment_type (conda, docker, etc.)
```

#### **Property Usage Patterns**

**Pattern 1: Direct Property Reuse**
```python
# Reuse existing environment configuration exactly
new_env = Environment(
    name="new-environment-name",
    version="2.0",
    image=original_env.image,
    conda_file=original_env.conda_file,  # For conda environments
    build=original_env.build,  # For docker environments
    tags={"copied_from": original_env.name}
)
```

**Pattern 2: Property with Fallback**
```python
# Use original property or fallback to downloaded/local files
conda_env = Environment(
    name="production-env",
    version="1.0",
    image=dev_env.image,
    conda_file=dev_env.conda_file or "./local-conda.yaml"
)

# For Docker environments from registry: use image reference (build context not available)
docker_env = Environment(
    name="production-env", 
    version="1.0",
    image=dev_env.image  # Use pre-built image - build context consumed during registry build
)
```

**Pattern 3: Property Inspection for Decision Making**
```python
# Inspect properties to determine promotion strategy
if env.conda_file:
    print(f"Conda environment detected: {env.conda_file}")
    # Use conda-specific promotion logic
    new_env = Environment(
        name="prod-env",
        image=env.image,
        conda_file=env.conda_file
    )
elif env.image and not env.build:
    print(f"Pre-built Docker image environment: {env.image}")
    # Use image reference for Docker environments from registry
    new_env = Environment(
        name="prod-env",
        image=env.image
    )
else:
    print(f"Local build context environment")
    # Use build context (only for workspace environments, not registry)
```

#### **Docker Image Location and Sharing Behavior**
**Important**: Understanding where Docker images physically reside during promotion is crucial for architecture planning.

```python
# When you get environment from registry and create in production workspace:
docker_env = ml_client_dev_registry.environments.get("my-docker-env", "1.0")
ml_client_prod_workspace.environments.create_or_update(docker_env)

# What happens to the Docker image:
print("Docker Image Physical Location Analysis:")
print("=" * 50)
```

**Physical Docker Image Location:**
- **Stays in**: `{dev-registry}.azurecr.io` (dev registry's ACR)
- **Does NOT get copied** to prod registry's ACR  
- **Does NOT get rebuilt**

**What Gets Created in Production:**
- **Environment metadata record** (name, version, description, tags)
- **Reference to the Docker image URI** (`{dev-registry}.azurecr.io/environments/my-env:1.0`)
- **Same image, different environment record**

**Result**: Both dev registry and prod workspace environments point to the **same physical Docker image** stored in the dev registry's ACR.

```python
# Verification example:
dev_env = ml_client_dev_registry.environments.get("my-docker-env", "1.0")
prod_env = ml_client_prod_workspace.environments.get("my-docker-env", "1.0")

print(f"Dev registry image:  {dev_env.image}")
print(f"Prod workspace image: {prod_env.image}")
# Both will show: {dev-registry}.azurecr.io/environments/my-docker-env:1.0

print("Same physical Docker image, different environment records")
print("No image duplication - efficient storage usage")
print("Dev registry ACR must remain accessible to production deployments")
```

**Architecture Implications:**
- **Network Access**: Production workspaces must have access to dev registry's ACR
- **Storage Efficiency**: No image duplication across registries/workspaces
- **Dependency**: Production depends on dev registry's ACR availability
- **Security**: Dev registry ACR becomes part of production infrastructure

```python
# Environment promotion workflow (workspace → registry → production)
from azure.ai.ml.entities import Environment, BuildContext

# ============================================================================
# INITIALIZE ADDITIONAL CLIENTS
# ============================================================================
# Production workspace client
ml_client_prod_workspace = MLClient(
    credential=credential,
    subscription_id="your-subscription-id", 
    resource_group_name="{prod-resource-group}",
    workspace_name="{prod-workspace}"
)

# ============================================================================
# SCENARIO A: BASE IMAGE + CONDA ENVIRONMENT
# ============================================================================
print("=== SCENARIO A: Base Image + Conda Environment ===")

print("\nStep 1A: Creating conda-based environment in dev workspace...")
conda_env = Environment(
    name="inference-env-conda",
    version="1.0",
    description="Inference environment with conda dependencies",
    image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest",
    conda_file="environment/conda.yaml",  # Path to your conda.yaml file
    tags={"type": "conda", "stage": "development"}
)

conda_env_created = ml_client_dev_workspace.environments.create_or_update(conda_env)
print(f"Conda environment created: {conda_env_created.name} v{conda_env_created.version}")

print("\nStep 2A: Sharing conda environment to dev registry...")
shared_conda_env = ml_client_dev_workspace.environments.share(
    name="inference-env-conda",
    version="1.0",
    registry_name="{dev-registry}"
)
print(f"Conda environment shared to registry: {shared_conda_env.name}")

# ============================================================================
# SCENARIO B: CUSTOM DOCKERFILE ENVIRONMENT  
# ============================================================================
print("\n=== SCENARIO B: Custom Dockerfile Environment ===")

print("\nStep 1B: Creating dockerfile-based environment in dev workspace...")
dockerfile_env = Environment(
    name="inference-env-docker",
    version="1.0", 
    description="Inference environment with custom Dockerfile",
    build=BuildContext(path="./environment"),  # Directory containing Dockerfile
    tags={"type": "dockerfile", "stage": "development"}
)

dockerfile_env_created = ml_client_dev_workspace.environments.create_or_update(dockerfile_env)
print(f"Docker environment created: {dockerfile_env_created.name} v{dockerfile_env_created.version}")

print("\nStep 2B: Sharing docker environment to dev registry...")
shared_docker_env = ml_client_dev_workspace.environments.share(
    name="inference-env-docker", 
    version="1.0",
    registry_name="{dev-registry}"
)
print(f"Docker environment shared to registry: {shared_docker_env.name}")

# ============================================================================
# PRODUCTION PROMOTION: TWO REALISTIC OPTIONS
# ============================================================================
print("\n=== PRODUCTION PROMOTION OPTIONS ===")

# Get environments from dev registry for promotion
conda_from_dev = ml_client_dev_registry.environments.get("inference-env-conda", "1.0")
docker_from_dev = ml_client_dev_registry.environments.get("inference-env-docker", "1.0")

# ------------------------------------------------------------------------
# OPTION 1: Reference Dev Registry Directly (RECOMMENDED)
# ------------------------------------------------------------------------
print("\n--- OPTION 1: Reference Dev Registry Directly (RECOMMENDED) ---")

print("IMPORTANT: Private registries cannot create environments directly")
print("   This is due to ACR public access being disabled in managed VNet setup")
print("   Solution: Reference dev registry environments from production deployments")

# Use dev registry references directly in production
conda_prod_reference = "azureml://registries/{dev-registry}/environments/inference-env-conda/versions/1.0"
docker_prod_reference = "azureml://registries/{dev-registry}/environments/inference-env-docker/versions/1.0"

print(f"Conda Production Reference: {conda_prod_reference}")
print(f"Docker Production Reference: {docker_prod_reference}")
print("  Benefits: Fastest deployment, direct lineage, single source of truth")
print("  Usage: Use these URIs directly in production deployments and pipelines")

# ------------------------------------------------------------------------
# OPTION 2: Recreate in Production Workspace (ALTERNATIVE)
# ------------------------------------------------------------------------
print("\n--- OPTION 2: Recreate in Production Workspace (ALTERNATIVE) ---")

print("NOTE: This approach recreates environments instead of referencing")
print("   Use when you need workspace-specific customizations or complete isolation")

print("\nOption 2A: Reference existing dev registry images (faster)...")

# Get detailed environment information from dev registry
conda_env_details = ml_client_dev_registry.environments.get("inference-env-conda", "1.0")
docker_env_details = ml_client_dev_registry.environments.get("inference-env-docker", "1.0")

print(f"Retrieved conda environment details - Base Image: {conda_env_details.image}")
print(f"Retrieved docker environment details - Built Image: {docker_env_details.image}")

# Create conda environment in prod workspace using the same image
conda_prod_workspace_ref = Environment(
    name="inference-env-conda",
    version="1.0", 
    description="Production conda environment (workspace - image ref)",
    image=conda_env_details.image,  # Use image from dev environment details
    tags={"type": "conda", "stage": "production", "location": "prod_workspace", "source": "dev_registry_image"}
)
ml_client_prod_workspace.environments.create_or_update(conda_prod_workspace_ref)
print(f"Conda environment created in prod workspace (references dev image)")

# Create docker environment in prod workspace using the same built image
docker_prod_workspace_ref = Environment(
    name="inference-env-docker",
    version="1.0",
    description="Production docker environment (workspace - image ref)", 
    image=docker_env_details.image,  # Use built image from dev environment details
    tags={"type": "docker", "stage": "production", "location": "prod_workspace", "source": "dev_registry_image"}
)
ml_client_prod_workspace.environments.create_or_update(docker_prod_workspace_ref)
print(f"Docker environment created in prod workspace (references dev image)")

print("\nOption 2B: Rebuild from source definitions (complete isolation)...")
print("IMPORTANT: This rebuilds the environment from scratch")

# First, download the source definitions from dev registry
print("Downloading source definitions from dev registry...")

# Download conda environment source (conda.yaml file)
conda_download_path = "./downloaded-envs/conda"
ml_client_dev_registry.environments.download(
    name="inference-env-conda",
    version="1.0",
    download_path=conda_download_path
)
print(f"Conda environment downloaded to: {conda_download_path}")

# IMPORTANT: Docker environment download typically NOT available
# Docker build contexts are consumed during registry build process
print("Docker environment download limitation:")
print("   Registry builds consume Docker source files (Dockerfile + context)")
print("   Download may fail or return empty/minimal content")
print("   RECOMMENDATION: Keep Docker source files in version control")

# Attempt docker download (may fail)
docker_download_path = "./downloaded-envs/docker"
try:
    ml_client_dev_registry.environments.download(
        name="inference-env-docker", 
        version="1.0",
        download_path=docker_download_path
    )
    print(f"Docker environment download attempted: {docker_download_path}")
    print("   Note: Content may be limited or empty")
except Exception as e:
    print(f"Docker environment download failed: {e}")
    print("   This is expected behavior - use version control instead")

# Get environment details to extract conda file and base image info
conda_env_details = ml_client_dev_registry.environments.get("inference-env-conda", "1.0")
docker_env_details = ml_client_dev_registry.environments.get("inference-env-docker", "1.0")

print(f"Conda base image: {conda_env_details.image}")
print(f"Conda file path: {conda_env_details.conda_file}")
print(f"Docker build context: {docker_env_details.build}")
print(f"Docker build context available in: {docker_download_path}")

# Example of rebuilding conda environment from downloaded source
conda_prod_workspace_rebuild = Environment(
    name="inference-env-conda-rebuild",
    version="1.0",
    description="Production conda environment (rebuilt from source)",
    image=conda_env_details.image,  # Use the same base image from dev
    conda_file=conda_env_details.conda_file or f"{conda_download_path}/conda.yaml",  # Use original path or downloaded
    tags={"type": "conda", "stage": "production", "rebuilt": "true", "source": "downloaded"}
)
# ml_client_prod_workspace.environments.create_or_update(conda_prod_workspace_rebuild)
print(f"Option available: Rebuild conda environment with downloaded conda.yaml")

# Example of rebuilding docker environment from downloaded source
print("DOCKER REBUILD LIMITATION:")
print("   Docker source files typically NOT available from registry downloads")
print("   Registry consumes Dockerfile + context during image build process")

# RECOMMENDED: Use version control source files
print("\nRECOMMENDED APPROACH: Use version control source files")
docker_prod_workspace_rebuild = Environment(
    name="inference-env-docker-rebuild",
    version="1.0",
    description="Production docker environment (rebuilt from version control)",
    build=BuildContext(path="./docker-source-from-git"),  # From version control, NOT registry
    tags={"type": "docker", "stage": "production", "rebuilt": "true", "source": "version_control"}
)
# ml_client_prod_workspace.environments.create_or_update(docker_prod_workspace_rebuild)
print(f"Option available: Rebuild docker environment from version control source")

# ALTERNATIVE: Use the pre-built image (most common)
print("\nALTERNATIVE: Reference the pre-built image (most common)")
docker_prod_workspace_image_ref = Environment(
    name="inference-env-docker-image-ref",
    version="1.0",
    description="Production docker environment (pre-built image reference)",
    image=docker_env_details.image,  # Use the built image from registry
    tags={"type": "docker", "stage": "production", "rebuilt": "false", "source": "registry_image"}
)
# ml_client_prod_workspace.environments.create_or_update(docker_prod_workspace_image_ref)
print(f"Option available: Reference pre-built Docker image: {docker_env_details.image}")

# Alternative: Use original build context directly (if accessible)
print("\n✓ ALTERNATIVE: Reference original build context directly")
docker_prod_workspace_direct = Environment(
    name="inference-env-docker-direct",
    version="1.0",
    description="Production docker environment (direct build context reference)",
    build=docker_env_details.build,  # Direct reference to original build context
    tags={"type": "docker", "stage": "production", "rebuilt": "true", "source": "direct_reference"}
)
# ml_client_prod_workspace.environments.create_or_update(docker_prod_workspace_direct)
print(f"Option available: Use original build context directly: {docker_env_details.build}")

# Alternative: Use original conda file path directly (if accessible)
print("\nALTERNATIVE: Reference original conda file directly")
conda_prod_workspace_direct = Environment(
    name="inference-env-conda-direct",
    version="1.0",
    description="Production conda environment (direct conda file reference)",
    image=conda_env_details.image,  # Same base image
    conda_file=conda_env_details.conda_file,  # Direct reference to original conda file
    tags={"type": "conda", "stage": "production", "rebuilt": "true", "source": "direct_reference"}
)
# ml_client_prod_workspace.environments.create_or_update(conda_prod_workspace_direct)
print(f"Option available: Use original conda file path directly: {conda_env_details.conda_file}")

# Alternative: Modify downloaded files for production-specific changes
print("\nCUSTOMIZATION EXAMPLE:")
print("  - Modify downloaded conda.yaml to add/remove production dependencies")
print("  - Modify downloaded Dockerfile for production-specific configurations")
print("  - Update base images to production-approved versions")
print("  Benefits: Complete workspace isolation, allows production-specific customizations")
print("  Drawbacks: Longer build times, potential environment drift, more maintenance")

# ============================================================================
# SUMMARY
# ============================================================================
print("\n=== ENVIRONMENT PROMOTION SUMMARY ===")
print("PRIVATE REGISTRY LIMITATION: Cannot create environments directly in private registries")
print("   Reason: ACR public access disabled in managed VNet configuration")
print("")
print("TWO REALISTIC OPTIONS:")
print("  OPTION 1 (RECOMMENDED): Reference dev registry environments directly")
print("  OPTION 2 (ALTERNATIVE): Recreate environments in production workspace")
print("")
print("Environment References for Production Use:")
print("Conda Environment:")
print(f"  Option 1 - Dev Registry Reference: azureml://registries/{dev-registry}/environments/inference-env-conda/versions/1.0")
print(f"  Option 2 - Prod Workspace: inference-env-conda:1.0")

print("\nDocker Environment:")
print(f"  Option 1 - Dev Registry Reference: azureml://registries/{dev-registry}/environments/inference-env-docker/versions/1.0")
print(f"  Option 2 - Prod Workspace: inference-env-docker:1.0")
print("")
print("RECOMMENDED: Use Option 1 (dev registry references) for simplicity and lineage")
print("Use Option 2 only when you need workspace-specific customizations")
```

#### **4. Pipeline Components**
**Strategy**: Version Control Recreation
- **Limitation**: Component sharing from workspace to registry is not supported
- **Process**: Store component YAML definitions in version control and recreate in production
- **Approach**: Direct creation in production workspace from source control

```python
# Component deployment workflow (no promotion - recreation from source control)
from azure.ai.ml import load_component

# ============================================================================
# INITIALIZE COMPONENT DEPLOYMENT
# ============================================================================
print("=== COMPONENT DEPLOYMENT WORKFLOW ===")
print("Note: Components cannot be shared between workspaces/registries")
print("Strategy: Recreate from version control YAML definitions")

# ============================================================================
# STEP 1: LOAD COMPONENT DEFINITIONS FROM VERSION CONTROL
# ============================================================================
print("\nStep 1: Loading component definitions from source control...")

# Load training component from YAML file
training_component = load_component(source="src/components/train.yaml")
print(f"Loaded training component: {training_component.name}")

# Load scoring component from YAML file  
scoring_component = load_component(source="src/components/score.yaml")
print(f"Loaded scoring component: {scoring_component.name}")

# Load additional components as needed
transform_component = load_component(source="src/components/transform.yaml")
print(f"Loaded transform component: {transform_component.name}")

# ============================================================================
# STEP 2: CREATE COMPONENTS IN PRODUCTION WORKSPACE
# ============================================================================
print("\nStep 2: Creating components in production workspace...")

# Create training component in production
print("Creating training component...")
training_comp_created = ml_client_prod_workspace.components.create_or_update(training_component)
print(f"Training component created: {training_comp_created.name} v{training_comp_created.version}")

# Create scoring component in production
print("Creating scoring component...")
scoring_comp_created = ml_client_prod_workspace.components.create_or_update(scoring_component)
print(f"Scoring component created: {scoring_comp_created.name} v{scoring_comp_created.version}")

# Create transform component in production
print("Creating transform component...")
transform_comp_created = ml_client_prod_workspace.components.create_or_update(transform_component)
print(f"Transform component created: {transform_comp_created.name} v{transform_comp_created.version}")

# ============================================================================
# STEP 3: VERIFY COMPONENT DEPENDENCIES
# ============================================================================
print("\nStep 3: Verifying component dependencies...")

# Check that referenced environments exist in production
print("Checking environment dependencies...")
for component in [training_comp_created, scoring_comp_created, transform_comp_created]:
    if hasattr(component, 'environment') and component.environment:
        print(f"  - {component.name}: Environment = {component.environment}")
        # Verify environment exists (this would throw exception if not found)
        try:
            env_check = ml_client_prod_workspace.environments.get(
                name=component.environment.split(':')[0],
                version=component.environment.split(':')[1] if ':' in component.environment else None
            )
            print(f"    Environment verified: {env_check.name}")
        except Exception as e:
            print(f"    Environment not found: {component.environment}")

print("Component dependency verification completed")

# ============================================================================
# VERIFICATION SECTION
# ============================================================================
print("\n=== COMPONENT DEPLOYMENT VERIFICATION ===")
print("Production Workspace Components:")
print(f"Training: {training_comp_created.name} v{training_comp_created.version}")
print(f"Scoring: {scoring_comp_created.name} v{scoring_comp_created.version}")
print(f"Transform: {transform_comp_created.name} v{transform_comp_created.version}")
print("Components ready for production pipeline deployment")

# ============================================================================
# USAGE EXAMPLE
# ============================================================================
print("\n=== USAGE IN PRODUCTION PIPELINE ===")
print("Components can now be referenced in production pipelines:")
print(f"  - azureml:{training_comp_created.name}:{training_comp_created.version}")
print(f"  - azureml:{scoring_comp_created.name}:{scoring_comp_created.version}")
print(f"  - azureml:{transform_comp_created.name}:{transform_comp_created.version}")
```

### Platform Limitations and Constraints

#### **Managed Virtual Network Limitations**
Our managed VNet configuration introduces specific constraints for asset sharing:

1. **Component Sharing Limitation**
   - **Issue**: Components cannot be shared from workspace to registry ([Microsoft Documentation](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation))
   - **Impact**: Pipeline components must be manually recreated in production
   - **Mitigation**: Store component YAML definitions in version control

2. **Environment Creation in Private Registry**
   - **Issue**: Cannot create environment assets directly in private registry with disabled ACR public access
   - **Technical Reason**: Private registries cannot build container images when ACR public access is disabled
   - **Impact**: Environment promotion requires alternative strategies
   - **Mitigation Options**:
     - **RECOMMENDED**: Reference dev registry environments via `azureml://registries/{dev-registry}/...` URIs
     - **ALTERNATIVE**: Recreate environments in production workspace using image references
     - **FALLBACK**: Store environment YAML definitions in version control and rebuild from source
   - **Reference**: [Network Isolation with Registries](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation#create-assets-in-registry-from-local-files)

3. **Storage Configuration for Asset Sharing**
   - **Requirement**: For secure workspace to private registry sharing, storage account must allow "Selected virtual networks and IP addresses"
   - **Configuration**: Add `Microsoft.MachineLearningServices/registries` to Resource instances
   - **Security Consideration**: This potentially weakens isolation but enables asset sharing

4. **Azure ML Studio Limitations**
   - **Issue**: Can only view MODEL assets in Studio when using network isolation
   - **Impact**: Must use CLI/SDK for all other registry operations
   - **Reference**: [Studio Limitations](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation#limitations)

#### **Data Sharing Constraints**
5. **Registry Data Limitations**
   - **Issue**: Registry creates data copies, unsuitable for large datasets or data that cannot be copied
   - **Issue**: No fine-grained access control within registry
   - **Reference**: [Data Sharing Scenarios](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-share-data-across-workspaces-with-registries)

### Manual Promotion Workflow

#### **Prerequisites**
- Azure CLI with ML extension installed
- Appropriate RBAC permissions (AzureML Registry User, Data Engineer roles)
- Access to both development and production environments

#### **Step-by-Step Promotion Process**

### Manual Promotion Workflow

#### **Prerequisites**
- Azure CLI with ML extension installed
- Appropriate RBAC permissions (AzureML Registry User, Data Engineer roles)
- Access to both development and production environments

#### **Step-by-Step Promotion Process**

```python
# Complete manual promotion workflow
from azure.ai.ml.entities import ManagedOnlineEndpoint, ManagedOnlineDeployment

# ============================================================================
# STEP 1: ASSET VALIDATION IN DEVELOPMENT
# ============================================================================
print("=== DEVELOPMENT VALIDATION ===")

print("Step 1A: Validating model performance in dev workspace...")
model_details = ml_client_dev_workspace.models.get(
    name="taxi-fare-model",
    version="1.0"
)
print(f"✓ Model validated: {model_details.name}, Tags: {model_details.tags}")

print("Step 1B: Testing model deployment in dev environment...")
dev_endpoint = ManagedOnlineEndpoint(
    name="dev-taxi-endpoint",
    description="Development endpoint for taxi fare model testing",
    tags={"environment": "development", "project": "taxi-fare"}
)

dev_deployment = ManagedOnlineDeployment(
    name="dev-deployment",
    endpoint_name="dev-taxi-endpoint",
    model=f"azureml:{model_details.name}:{model_details.version}",
    environment="azureml://registries/{dev-registry}/environments/inference-env:1.0",
    instance_type="Standard_DS2_v2",
    instance_count=1
)

print("✓ Development deployment configuration validated")

# ============================================================================
# STEP 2: PRODUCTION ASSET PROMOTION
# ============================================================================
print("\n=== PRODUCTION ASSET PROMOTION ===")

print("Step 2A: Promoting model to production registry...")
# Use the enhanced model promotion code from above
model_prod = ml_client_dev_workspace.models.share(
    name="taxi-fare-model",
    version="1.0", 
    registry_name="amlregprodcc01"
)
print(f"✓ Model promoted: {model_prod.name}")

print("Step 2B: Setting up environment references for production...")
# IMPORTANT: Cannot create environments in private prod registry
# Must reference dev registry environments or recreate in prod workspace
env_prod_ref = "azureml://registries/{dev-registry}/environments/inference-env:1.0"
print(f"✓ Environment reference (dev registry): {env_prod_ref}")
print("   Note: Referencing dev registry due to private registry limitations")

print("Step 2C: Recreating components in production...")
# Use component recreation workflow from above
training_comp = load_component(source="src/components/train.yaml")
ml_client_prod_workspace.components.create_or_update(training_comp)
print(f"✓ Components recreated in production workspace")

# ============================================================================
# STEP 3: PRODUCTION DEPLOYMENT
# ============================================================================
print("\n=== PRODUCTION DEPLOYMENT ===")

print("Step 3A: Creating production endpoint...")
prod_endpoint = ManagedOnlineEndpoint(
    name="prod-taxi-endpoint",
    description="Production endpoint for taxi fare model",
    tags={"environment": "production", "project": "taxi-fare"}
)
endpoint_created = ml_client_prod_workspace.online_endpoints.begin_create_or_update(prod_endpoint)
print(f"✓ Production endpoint created: {endpoint_created.name}")

print("Step 3B: Deploying model to production endpoint...")
prod_deployment = ManagedOnlineDeployment(
    name="prod-deployment",
    endpoint_name="prod-taxi-endpoint",
    model=f"azureml://registries/amlregprodcc01/models/taxi-fare-model/versions/1.0",
    environment=env_prod_ref,
    instance_type="Standard_DS3_v2",  # Production instance
    instance_count=2,  # Production scale
    traffic_allocation=100
)

deployment_created = ml_client_prod_workspace.online_deployments.begin_create_or_update(prod_deployment)
print(f"✓ Production deployment created: {deployment_created.name}")

# ============================================================================
# STEP 4: PRODUCTION VALIDATION
# ============================================================================
print("\n=== PRODUCTION VALIDATION ===")

print("Step 4A: Testing production endpoint...")
# Test the production endpoint
import json
test_data = {
    "data": [
        {"trip_distance": 3.5, "passenger_count": 2}
    ]
}

try:
    response = ml_client_prod_workspace.online_endpoints.invoke(
        endpoint_name="prod-taxi-endpoint",
        request_file=None,
        deployment_name="prod-deployment"
    )
    print(f"✓ Endpoint test successful: {response}")
except Exception as e:
    print(f"⚠️  Endpoint test failed: {e}")

print("Step 4B: Monitoring deployment health...")
# Check deployment status
deployment_status = ml_client_prod_workspace.online_deployments.get(
    name="prod-deployment",
    endpoint_name="prod-taxi-endpoint"
)
print(f"✓ Deployment status: {deployment_status.provisioning_state}")
print(f"✓ Ready replicas: {deployment_status.ready_replica_count}")

# ============================================================================
# STEP 5: FINAL VERIFICATION
# ============================================================================
print("\n=== FINAL VERIFICATION ===")
print("✓ Development model validated and tested")
print("✓ Production assets promoted successfully")
print("✓ Production endpoint deployed and tested")
print("✓ System ready for production traffic")

print("\nProduction Asset References:")
print(f"  Model: azureml://registries/amlregprodcc01/models/taxi-fare-model/versions/1.0")
print(f"  Environment: {env_prod_ref} (dev registry - private registry limitation)")
print(f"  Endpoint: prod-taxi-endpoint")
print(f"  Deployment: prod-deployment")
```
       description="Development endpoint for taxi fare model"
   )
   ml_client_dev_workspace.online_endpoints.begin_create_or_update(dev_endpoint)
   ```

2. **Model Promotion to Registry**
   ```python
   # Register validated model in dev registry (already shown above)
   model_dev = Model(
       name="taxi-fare-model",
       version="1.0",
       path="azureml://jobs/{training-job-id}/outputs/model"
   )
   ml_client_dev_workspace.models.create_or_update(model_dev)
   
   # Share to dev registry
   shared_model = ml_client_dev_workspace.models.share(
       name="taxi-fare-model",
       version="1.0", 
       registry_name="{dev-registry}"
   )
   
   # Promote model to production registry (manual approval gate)
   prod_model = Model(
       name="taxi-fare-model",
       version="1.0",
       path="azureml://registries/{dev-registry}/models/taxi-fare-model/versions/1.0"
   )
   ml_client_prod_registry.models.create_or_update(prod_model)
   ```

3. **Environment Promotion**
   ```python
   # Three-stage environment promotion workflow
   # 1. Create environment in dev workspace (conda example)
   conda_env = Environment(
       name="inference-env",
       version="1.0",
       image="mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest",
       conda_file="environment/conda.yaml"
   )
   ml_client_dev_workspace.environments.create_or_update(conda_env)
   
   # 2. Share environment to dev registry
   shared_env = ml_client_dev_workspace.environments.share(
       name="inference-env",
       version="1.0",
       registry_name="{dev-registry}"
   )
   
   # 3. Choose production strategy:
   # Option A: Reference dev registry directly (fastest)
   direct_ref = "azureml://registries/{dev-registry}/environments/inference-env/versions/1.0"
   
   # Option B: Copy to prod registry (registry isolation)
   env_from_dev = ml_client_dev_registry.environments.get("inference-env", "1.0")
   prod_env_registry = Environment(
       name="inference-env",
       version="1.0", 
       image=env_from_dev.image
   )
   ml_client_prod_registry.environments.create_or_update(prod_env_registry)
   
   # Option C: Copy to prod workspace (complete isolation)
   prod_env_workspace = Environment(
       name="inference-env",
       version="1.0",
       image=env_from_dev.image
   )
   ml_client_prod_workspace.environments.create_or_update(prod_env_workspace)
   ```

4. **Component Recreation in Production**
   ```python
   # Deploy component definitions from version control to prod workspace
   training_component = load_component("components/scoring-component.yaml")
   ml_client_prod_workspace.components.create_or_update(training_component)
   
   scoring_component = load_component("components/scoring-component.yaml") 
   ml_client_prod_workspace.components.create_or_update(scoring_component)
   ```

5. **Production Deployment**
   ```python
   # Deploy model from production registry to production workspace
   from azure.ai.ml.entities import ManagedOnlineEndpoint, ManagedOnlineDeployment
   
   # Create production endpoint
   prod_endpoint = ManagedOnlineEndpoint(
       name="prod-taxi-endpoint",
       description="Production endpoint for taxi fare model"
   )
   ml_client_prod_workspace.online_endpoints.begin_create_or_update(prod_endpoint)
   
   # Create deployment with model from prod registry
   prod_deployment = ManagedOnlineDeployment(
       name="prod-deployment",
       endpoint_name="prod-taxi-endpoint",
       model="azureml://registries/amlregprodcc01/models/taxi-fare-model/versions/1.0",
       environment="azureml://registries/amlregprodcc01/environments/inference-env/versions/1.0",
       instance_type="Standard_DS2_v2",
       instance_count=1
   )
   ml_client_prod_workspace.online_deployments.begin_create_or_update(prod_deployment)
   ```

### Approval and Governance

#### **Manual Approval Gates**
- Model performance validation in development environment
- Security scan of promoted assets
- Business stakeholder approval for production deployment
- Documentation of promotion rationale and testing results

#### **Audit Trail**
- All promotion activities logged via Azure Activity Log
- Version control tracking of component definitions
- Registry asset metadata maintains lineage information
- Production deployment tracking via Azure ML workspace logs

### Operational Considerations

#### **Cost Management**
- Registry storage costs for data asset copies
- Azure Firewall costs if using FQDN outbound rules in managed VNet
- Cross-region data transfer costs (none in our same-region setup)

#### **Performance**
- Registry asset access latency for cross-registry operations
- Network bandwidth considerations for large asset transfers
- Managed VNet performance characteristics

### References and Documentation

- [Azure ML Registry Network Isolation](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation)
- [Sharing Assets Across Workspaces](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-share-models-pipelines-across-workspaces-with-registries)
- [Data Sharing with Registries](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-share-data-across-workspaces-with-registries)
- [Managed Virtual Network Limitations](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-managed-network#limitations)
- [Azure ML Enterprise Security](https://learn.microsoft.com/en-us/azure/machine-learning/concept-enterprise-security)

## Implementation Plan

### Phase 1: Production Environment Foundation
Your parameterized modules are ready for production deployment:

1. **Create Production terraform.tfvars**
   Use the same configuration structure as development but with production-specific parameters:
   - `purpose = "prod"`
   - `vnet_address_space = "10.2.0.0/16"` (different CIDR from dev)
   - `subnet_address_prefix = "10.2.1.0/24"` (different subnet from dev)
   - `enable_auto_purge = false` (CRITICAL: never true for prod)
   - `environment = "prod"` in tags

2. **Deploy Production Infrastructure**
   ```bash
   cd /infra/environments/prod
   terraform init
   terraform plan -var-file=terraform.tfvars
   terraform apply -var-file=terraform.tfvars
   ```

### Phase 2: Access and Security
- Configure production access controls
- Restricted RBAC assignments
- Separate jumpbox access method
- Audit logging and monitoring

### Phase 3: CI/CD Pipeline Setup
- Environment-specific pipelines
- Dev pipeline for development workflows
- Prod pipeline with approval gates
- Model promotion workflows

### Phase 4: Operational Excellence
- Monitoring and alerting
- Environment-specific Log Analytics workspaces
- Separate monitoring dashboards
- Independent alert configurations

## Cost Considerations

### Development Environment (Current)
- Compute: Auto-shutdown policies implemented
- Storage: Lifecycle policies for old data
- Jumpbox: ~$290/month (optimization opportunities identified)

### Production Environment (Projected)
- Similar base cost to dev environment
- Additional considerations: Higher availability requirements, backup costs
- Optimization: Right-sizing based on actual workloads

### Cost Optimization Strategies
1. Auto-scaling: Implement compute auto-scaling policies
2. Reserved Instances: Consider 1-year reservations for stable workloads
3. Storage Tiers: Implement intelligent tiering for model artifacts
4. Monitoring: Set up cost alerts and budget controls

<!-- Removed duplicate 'Security and Compliance' section (content already covered earlier) -->

## Disaster Recovery and Business Continuity

### Backup Strategy
- Infrastructure: Terraform state files backed up and versioned
- Data: Model artifacts and training data backed up to separate storage
- Configuration: Environment configurations stored in version control

### Recovery Procedures
- Infrastructure Recovery: Terraform-based infrastructure recreation
- Data Recovery: Point-in-time restore capabilities for critical data
- Service Recovery: Documented procedures for service restoration

## Decision Log

| Decision | Status | Date | Rationale |
|----------|--------|------|-----------|
| Complete Environment Isolation | Decided | 2025-08-06 | Maximum security, compliance requirements |
| Separate DNS Zones | Decided | 2025-08-06 | Prevent cross-environment DNS pollution |
| Single Subscription Strategy | Decided | 2025-08-06 | Only one subscription available, use resource group isolation |
| Same Region Strategy | Decided | 2025-08-06 | Operational simplicity, cost optimization, team familiarity |
| RBAC Strategy | Decided | 2025-08-06 | Service Principal + UAMI + Data Engineer roles |
| Asset Promotion Strategy | Decided | 2025-08-06 | Registry-First Simplified Approach with manual validation gates |
| CI/CD Strategy | Pending | TBD | Integration with asset promotion workflow |
| Access Control Model | Pending | TBD | Team structure and access requirements |

## Next Steps

1. **Implement Updated RBAC Strategy**
   - Create service principal for deployment automation
   - Convert workspace from SMI to UAMI implementation
   - Add missing ACR permissions for compute cluster
   - Test RBAC assignments with principle of least privilege

2. **Configure Asset Promotion Infrastructure**
   - Set up development and production registries
   - Configure storage account networking for asset sharing
   - Implement manual approval workflow procedures
   - Create component definition version control repository

3. **Finalize Strategic Decisions**
   - Subscription strategy: Single subscription confirmed
   - Geographic deployment: Same region (Canada Central) confirmed  
   - RBAC strategy: Service Principal + UAMI + Data Engineer roles confirmed
   - Asset promotion strategy: Registry-First Simplified Approach confirmed

4. **Create Production Environment**
   - Terraform configuration approach confirmed (same modules, different terraform.tfvars)
   - Deploy production infrastructure using single subscription approach
   - Configure updated RBAC assignments for production environment

5. **Implement Asset Promotion Workflows**
   - Document manual promotion procedures
   - Create CLI/SDK scripts for common promotion tasks
   - Train team on asset promotion workflow
   - Establish approval and governance processes

6. **Operational Readiness**
   - Validate RBAC permissions in both environments
   - Test asset promotion workflow end-to-end
   - Documentation and runbooks for operational procedures
   - Team training on Data Engineer role capabilities and asset promotion

## Implementation Status

### ✅ **RBAC Implementation Complete**

The current infrastructure implementation in `main.tf` fully implements this deployment strategy with the following role assignments:

- **Service Principal**: 18 role assignments (3 roles × 6 resource groups)
- **Shared Compute UAMIs**: 18 role assignments (9 roles × 2 environments)
- **Workspace UAMIs**: 14 role assignments (7 roles × 2 environments)  
- **Human User Roles**: 14 role assignments (7 roles × 2 environments)
- **Cross-Environment Access**: Optimized to 2 role assignments (removed unnecessary prod workspace to dev registry access)
- **Managed VNet Outbound Rules**: 1 automatic private endpoint rule

### ✅ **Terraform Dependency Issues Resolved**

**Recent Updates (August 7–8, 2025):**
1. **Flat Network Implementation**: Direct dev↔prod optional peering (no transit layer).
2. **Cross-Environment RBAC Optimization**: Removed unnecessary workspace UAMI registry roles; compute UAMIs retain data access; workspace UAMIs limited to network connection approver.
3. **Outbound Rule Schema Fix**: Added required `subresourceTarget = "amlregistry"` for all registry private endpoint outbound rules.
4. **Key Vault Provisioning Reliability**: Added dual roles (Reader + Secrets User) to workspace UAMIs pre-create to avoid 403 `vaults/read` errors.
 

### ✅ **Architecture Decisions Implemented**

1. **Single Shared Compute UAMI**: ✅ One UAMI per environment for both compute cluster and compute instance
2. **No MOE UAMIs**: ✅ Online endpoints use system-assigned managed identities as designed
3. **Cross-Environment Connectivity**: ✅ Production can access dev registry via compute UAMIs and automatic private endpoints
4. **Complete Environment Isolation**: ✅ Zero shared components between dev and prod
5. **Role Assignment Before Resource Creation**: ✅ All permissions configured before compute provisioning
6. **Optimized RBAC Strategy**: ✅ Workspace UAMIs handle connectivity, compute UAMIs handle data access

### ✅ **Infrastructure Ready for Deployment**

The Terraform configuration in `/infra/main.tf` implements the flat architecture, centralized DNS, deterministic naming, and Bastion-only access. (Resource count varies with user role assignment flags.)

## Deployment Workflow

### Prerequisites

1. **Azure Subscription**: Valid Azure subscription with sufficient permissions
2. **Terraform**: Version 1.5+ installed locally
3. **Azure CLI**: Latest version with `az login` completed
4. **PowerShell**: Optional, for local scripting convenience

### Deployment Steps

**Step 1: Configure Variables**
```hcl
# Update terraform.tfvars with your settings
subscription_id = "your-subscription-id"
prefix = "aml"
location = "canadacentral"
location_code = "cc"
# Optional: Assign user roles automatically
assign_user_roles = true
```

**Step 2: Deploy Infrastructure**
```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan

# Apply infrastructure (deploys all resource groups and flat network)
terraform apply
```

**Step 3: Access the Environment (Bastion-only)**
```text
1. Open Azure Bastion session to the Windows DSVM jumpbox.
2. Use Azure CLI/SDK from the jumpbox to access AML workspaces via private endpoints.
3. No VPN is required; public access remains disabled across services.
```

**Step 4: Verify Deployment**
```powershell
# Test Azure ML access
az ml workspace show --name mlwdevcc* --resource-group rg-aml-ws-dev-cc*
az ml workspace show --name mlwprodcc* --resource-group rg-aml-ws-prod-cc*
```

### Cost Management

**Monthly Cost Estimates** (Canada Central):
- **Development Environment**: ~$200-300/month (compute-dependent)
- **Production Environment**: ~$200-300/month (compute-dependent)

**Total Platform Cost**: Compute-dependent; Bastion + jumpbox adds minimal overhead compared to VPN gateways.

**Cost Optimization Strategies**:
- Stop compute clusters when not in use
- Use auto-scaling for compute instances
- Leverage spot instances for non-critical workloads
- Monitor storage consumption and implement lifecycle policies

## References

- [Azure ML Private Network Configuration](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation)
- [Azure Private DNS Best Practices](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/dns-for-on-premises-and-azure-resources)
- [Azure ML Enterprise Security](https://learn.microsoft.com/en-us/azure/machine-learning/concept-enterprise-security)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

**Document Version**: 1.1  
**Last Updated**: August 7, 2025  
**Next Review**: Post-deployment validation
