# Azure ML Platform - Network Architecture & RBAC Reference

## 🏗️ Network Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                        Azure Subscription: 5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25        │
├─────────────────────────────────────┬───────────────────────────────────────────────────┤
│           DEVELOPMENT ENVIRONMENT   │              PRODUCTION ENVIRONMENT              │
│              canadacentral          │                 canadacentral                    │
└─────────────────────────────────────┴───────────────────────────────────────────────────┘

┌─────────────────────────────────────┐ ┌───────────────────────────────────────────────────┐
│         DEV RESOURCE GROUPS         │ │            PROD RESOURCE GROUPS                   │
├─────────────────────────────────────┤ ├───────────────────────────────────────────────────┤
│  rg-aml-vnet-dev-cc004             │ │  rg-aml-vnet-prod-cc001                          │
│  ├── vnet-amldevcc004              │ │  ├── vnet-amlprodcc001                           │
│  │   └── 10.1.0.0/16               │ │  │   └── 10.2.0.0/16                            │
│  │   └── subnet-amldevcc004         │ │  │   └── subnet-amlprodcc001                     │
│  │       └── 10.1.1.0/24            │ │  │       └── 10.2.1.0/24                         │
│  ├── kvdevcc004 (Key Vault)        │ │  ├── kvprodcc001 (Key Vault)                     │
│  ├── Private DNS Zones              │ │  ├── Private DNS Zones                           │
│  └── dev-mi-workspace (UAMI)       │ │  └── prod-mi-workspace (UAMI)                    │
│      dev-mi-compute (UAMI)          │ │      prod-mi-compute (UAMI)                      │
├─────────────────────────────────────┤ ├───────────────────────────────────────────────────┤
│  rg-aml-ws-dev-cc                  │ │  rg-aml-ws-prod-cc                               │
│  ├── amlwsdevcc004 (Workspace)     │ │  ├── amlwsprodcc001 (Workspace)                  │
│  ├── stdevcc004 (Storage)          │ │  ├── stprodcc001 (Storage)                       │
│  ├── acrdevcc004 (ACR)             │ │  ├── acrprodcc001 (ACR)                          │
│  └── Private Endpoints             │ │  └── Private Endpoints                           │
├─────────────────────────────────────┤ ├───────────────────────────────────────────────────┤
│  rg-aml-reg-dev-cc                 │ │  rg-aml-reg-prod-cc                              │
│  └── amlregdevcc004 (Registry)     │ │  └── amlregprodcc001 (Registry)                  │
│      ├── Microsoft-managed ACR     │ │      ├── Microsoft-managed ACR                   │
│      └── Microsoft-managed Storage │ │      └── Microsoft-managed Storage               │
└─────────────────────────────────────┘ └───────────────────────────────────────────────────┘

                                    ┌───────────────────┐
                                    │   CROSS-ENV       │
                                    │   CONNECTIVITY    │
                                    │                   │
                                    │ Prod Workspace    │
                                    │      ↓            │
                                    │ Outbound Rule     │
                                    │      ↓            │
                                    │ Private Endpoint  │
                                    │      ↓            │
                                    │ Dev Registry      │
                                    └───────────────────┘

═══════════════════════════════════════════════════════════════════════════════════════════

🔐 NETWORK SECURITY FEATURES:

├── Complete Air-Gap Isolation
│   ├── No VNet Peering between environments
│   ├── Different CIDR ranges (10.1.x.x vs 10.2.x.x)
│   └── Independent DNS resolution
│
├── Managed VNet with Private Endpoints
│   ├── isolationMode: "AllowOnlyApprovedOutbound"
│   ├── Automatic private endpoint creation
│   └── No public internet access
│
├── Cross-Environment Access (Controlled)
│   ├── Production → Dev Registry (Read-Only)
│   ├── Automatic private endpoint creation
│   └── Asset promotion workflow support
│
└── Microsoft-Managed Resources
    ├── Registry ACR (automatically managed)
    ├── Registry Storage (automatically managed)
    └── Workspace-managed compute and storage
```

## 🔑 RBAC Permission Matrix

### Service Principal (Deployment Automation)
```
sp-aml-deployment-automation:
┌─────────────────────────────────────┬───────────────────────────────────────┐
│              SCOPE                  │                ROLE                   │
├─────────────────────────────────────┼───────────────────────────────────────┤
│ All 6 Resource Groups              │ Contributor                           │
│ All 6 Resource Groups              │ User Access Administrator             │
│ All 6 Resource Groups              │ Network Contributor                   │
└─────────────────────────────────────┴───────────────────────────────────────┘
```

### Development Environment - Managed Identities

#### dev-mi-workspace (Workspace UAMI)
```
┌─────────────────────────────────────┬───────────────────────────────────────┐
│              SCOPE                  │                ROLE                   │
├─────────────────────────────────────┼───────────────────────────────────────┤
│ rg-aml-vnet-dev-cc004              │ Azure AI Administrator                │
│ rg-aml-vnet-dev-cc004              │ Azure AI Enterprise Network          │
│                                     │ Connection Approver                   │
│ amlregdevcc004 (Registry)           │ Azure AI Enterprise Network          │
│                                     │ Connection Approver                   │
│ stdevcc004 (Storage)                │ Storage Blob Data Contributor         │
│ stdevcc004 (Storage)                │ Storage Blob Data Owner               │
│ amlregdevcc004 (Registry)           │ AzureML Registry User                 │
│ Storage Private Endpoints           │ Reader                                │
└─────────────────────────────────────┴───────────────────────────────────────┘
```

#### dev-mi-compute (Compute UAMI)
```
┌─────────────────────────────────────┬───────────────────────────────────────┐
│              SCOPE                  │                ROLE                   │
├─────────────────────────────────────┼───────────────────────────────────────┤
│ amlwsdevcc004 (Workspace)           │ AzureML Data Scientist                │
│ amlregdevcc004 (Registry)           │ AzureML Registry User                 │
│ stdevcc004 (Storage)                │ Storage Blob Data Contributor         │
│ stdevcc004 (Storage)                │ Storage File Data Privileged          │
│                                     │ Contributor                           │
│ acrdevcc004 (ACR)                   │ AcrPull                               │
│ acrdevcc004 (ACR)                   │ AcrPush                               │
│ kvdevcc004 (Key Vault)              │ Key Vault Secrets User                │
│ rg-aml-vnet-dev-cc004              │ Reader                                │
│ amlwsdevcc004 (Workspace)           │ Contributor (for auto-shutdown)       │
└─────────────────────────────────────┴───────────────────────────────────────┘
```

### Production Environment - Managed Identities

#### prod-mi-workspace (Workspace UAMI)
```
┌─────────────────────────────────────┬───────────────────────────────────────┐
│              SCOPE                  │                ROLE                   │
├─────────────────────────────────────┼───────────────────────────────────────┤
│ rg-aml-vnet-prod-cc001             │ Azure AI Administrator                │
│ rg-aml-vnet-prod-cc001             │ Azure AI Enterprise Network          │
│                                     │ Connection Approver                   │
│ amlregprodcc001 (Registry)          │ Azure AI Enterprise Network          │
│                                     │ Connection Approver                   │
│ stprodcc001 (Storage)               │ Storage Blob Data Contributor         │
│ stprodcc001 (Storage)               │ Storage Blob Data Owner               │
│ amlregprodcc001 (Registry)          │ AzureML Registry User                 │
│ Storage Private Endpoints           │ Reader                                │
│ ─────────────────────────────────── │ ───────────────────────────────────── │
│ CROSS-ENVIRONMENT ACCESS:           │                                       │
│ amlregdevcc004 (Dev Registry)       │ Azure AI Enterprise Network          │
│                                     │ Connection Approver                   │
└─────────────────────────────────────┴───────────────────────────────────────┘
```

#### prod-mi-compute (Compute UAMI)
```
┌─────────────────────────────────────┬───────────────────────────────────────┐
│              SCOPE                  │                ROLE                   │
├─────────────────────────────────────┼───────────────────────────────────────┤
│ amlwsprodcc001 (Workspace)          │ AzureML Data Scientist                │
│ amlregprodcc001 (Registry)          │ AzureML Registry User                 │
│ stprodcc001 (Storage)               │ Storage Blob Data Contributor         │
│ stprodcc001 (Storage)               │ Storage File Data Privileged          │
│                                     │ Contributor                           │
│ acrprodcc001 (ACR)                  │ AcrPull                               │
│ kvprodcc001 (Key Vault)             │ Key Vault Secrets User                │
│ rg-aml-vnet-prod-cc001             │ Reader                                │
│ amlwsprodcc001 (Workspace)          │ Contributor (for auto-shutdown)       │
│ ─────────────────────────────────── │ ───────────────────────────────────── │
│ CROSS-ENVIRONMENT ACCESS:           │                                       │
│ amlregdevcc004 (Dev Registry)       │ AzureML Registry User                 │
└─────────────────────────────────────┴───────────────────────────────────────┘
```

### Human Users

#### Data Scientists / ML Engineers
```
┌─────────────────────────────────────┬───────────────────────────────────────┐
│              SCOPE                  │                ROLE                   │
├─────────────────────────────────────┼───────────────────────────────────────┤
│ DEVELOPMENT ENVIRONMENT:            │                                       │
│ rg-aml-ws-dev-cc                   │ Reader                                │
│ amlwsdevcc004 (Workspace)           │ AzureML Data Scientist                │
│ amlwsdevcc004 (Workspace)           │ Azure AI Developer                    │
│ amlwsdevcc004 (Workspace)           │ AzureML Compute Operator              │
│ stdevcc004 (Storage)                │ Storage Blob Data Contributor         │
│ stdevcc004 (Storage)                │ Storage File Data Privileged          │
│                                     │ Contributor                           │
│ amlregdevcc004 (Registry)           │ AzureML Registry User                 │
│ ─────────────────────────────────── │ ───────────────────────────────────── │
│ PRODUCTION ENVIRONMENT:             │                                       │
│ rg-aml-ws-prod-cc                  │ Reader                                │
│ amlregprodcc001 (Registry)          │ AzureML Registry User                 │
└─────────────────────────────────────┴───────────────────────────────────────┘
```

#### MLOps Team
```
┌─────────────────────────────────────┬───────────────────────────────────────┐
│              SCOPE                  │                ROLE                   │
├─────────────────────────────────────┼───────────────────────────────────────┤
│ rg-aml-ws-dev-cc                   │ Azure AI Administrator                │
│ rg-aml-ws-prod-cc                  │ Azure AI Administrator                │
│ rg-aml-reg-dev-cc                  │ Azure AI Administrator                │
│ rg-aml-reg-prod-cc                 │ Azure AI Administrator                │
│ All Storage Accounts                │ Storage Blob Data Owner               │
│ All Key Vaults                      │ Key Vault Administrator               │
└─────────────────────────────────────┴───────────────────────────────────────┘
```

## 🌐 Network Connectivity Details

### Private Endpoint Configuration
```
Development Environment:
├── Storage Account (stdevcc004)
│   ├── blob.core.windows.net → 10.1.1.x
│   ├── file.core.windows.net → 10.1.1.x
│   └── queue.core.windows.net → 10.1.1.x
├── Key Vault (kvdevcc004)
│   └── vault.azure.net → 10.1.1.x
├── Container Registry (acrdevcc004)
│   └── azurecr.io → 10.1.1.x
└── Workspace (amlwsdevcc004)
    └── api.azureml.ms → 10.1.1.x

Production Environment:
├── Storage Account (stprodcc001)
│   ├── blob.core.windows.net → 10.2.1.x
│   ├── file.core.windows.net → 10.2.1.x
│   └── queue.core.windows.net → 10.2.1.x
├── Key Vault (kvprodcc001)
│   └── vault.azure.net → 10.2.1.x
├── Container Registry (acrprodcc001)
│   └── azurecr.io → 10.2.1.x
├── Workspace (amlwsprodcc001)
│   └── api.azureml.ms → 10.2.1.x
└── Cross-Environment Private Endpoint
    └── amlregdevcc004.api.azureml.ms → 10.2.1.x (via outbound rule)
```

### DNS Resolution
```
Private DNS Zones (per environment):
├── privatelink.api.azureml.ms
├── privatelink.blob.core.windows.net
├── privatelink.file.core.windows.net
├── privatelink.queue.core.windows.net
├── privatelink.vault.azure.net
└── privatelink.azurecr.io

Note: Each environment has its own private DNS zones for complete isolation
```

## 🔄 Asset Promotion Flow

### Secure Promotion Workflow
```
1. Model Development (Dev Workspace)
   ├── Training on amlwsdevcc004
   ├── Model registration in dev workspace
   └── Model validation and testing

2. Share to Dev Registry
   ├── dev-mi-compute has AzureML Registry User on amlregdevcc004
   ├── Model shared from workspace to registry
   └── Model available in amlregdevcc004

3. Manual Approval Gate
   ├── MLOps team reviews model
   ├── Performance validation
   └── Security and compliance check

4. Promote to Prod Registry
   ├── Model copied from amlregdevcc004 to amlregprodcc001
   ├── prod-mi-compute has read access to dev registry
   └── Model available in amlregprodcc001

5. Production Deployment
   ├── Model deployed from amlregprodcc001
   ├── Production inference endpoints
   └── Monitoring and alerting
```

### Network Path for Asset Promotion
```
Production Workspace (amlwsprodcc001)
         ↓
Managed VNet Outbound Rule (allow-dev-registry)
         ↓
Private Endpoint (automatic creation)
         ↓
Dev Registry (amlregdevcc004)
         ↓
Microsoft-Managed ACR (automatic access)
         ↓
Docker Images & Model Artifacts
```

## 🛡️ Security Boundaries

### Environment Isolation Principles
```
✅ ALLOWED:
├── Complete resource isolation per environment
├── Independent VNet address spaces
├── Separate managed identities per environment
├── Production read-only access to dev registry
├── Automatic private endpoint creation for approved outbound rules
└── Managed VNet security controls

❌ PROHIBITED:
├── VNet peering between environments
├── Shared storage accounts
├── Shared managed identities
├── Direct network connectivity (except approved outbound rules)
├── Cross-environment write access
└── Public internet access from workspaces
```

### Critical Security Notes
```
🚨 PRODUCTION SECURITY:
├── enable_auto_purge = false (prevents Key Vault destruction)
├── No write access to development resources
├── Read-only registry access for asset promotion
├── Private endpoint only connectivity
└── Audit logging enabled for all operations

🔧 DEVELOPMENT FLEXIBILITY:
├── enable_auto_purge = true (allows infrastructure cleanup)
├── Full development environment access
├── Experimental workloads isolation
├── Cost optimization through auto-shutdown
└── Rapid prototyping capabilities
```

This network architecture ensures complete security isolation while enabling controlled asset promotion workflows between development and production environments.
