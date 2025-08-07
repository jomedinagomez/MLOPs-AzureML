# Azure ML Platform Deployment Strategy

## Overview

This document outlines the deployment strategy for our Azure Machine Learning platform, focusing on **complete isolation** between development and production environments with **zero shared components**.

## Strategic Principles

### 1. Complete Environment Isolation
- **Zero Shared Components**: No resources, networks, DNS zones, or identities shared between dev and prod
- **Independent Lifecycles**: Each environment can be created, modified, or destroyed independently
- **Security Boundaries**: Complete separation prevents cross-environment security risks
- **Governance**: Clear ownership and access control per environment

### 2. Infrastructure as Code
- **Terraform Modules**: Reusable modules for consistent deployment across environments
- **Environment-Specific Configurations**: Separate terraform.tfvars for each environment
- **Version Control**: All infrastructure changes tracked and reviewed
- **Automated Deployment**: Infrastructure provisioned through CI/CD pipelines

## Current State Analysis

### Development Environment (Deployed)
```
Terraform Configuration:
├── purpose = "dev"
├── location = "canadacentral" 
├── location_code = "cc"
├── random_string = "01"
├── vnet_address_space = "10.1.0.0/16"
├── subnet_address_prefix = "10.1.1.0/24"
└── enable_auto_purge = true

Generated Resource Groups:
├── rg-aml-vnet-dev-cc01 (VNet module) 
├── rg-aml-workspace-dev-cc01 (Workspace module)
└── rg-aml-registry-dev-cc01 (Registry module)

Generated Key Resources:
├── VNet: vnet-amldevcc01 (10.1.0.0/16)
├── Subnet: subnet-amldevcc01 (10.1.1.0/24)
├── Workspace: amldevcc01
├── Registry: amlrdevcc01
├── Storage: stamldevcc01
├── Container Registry: acrdevcc01
├── Key Vault: kvdevcc01
└── Log Analytics: log-amldevcc01

Access Method: Windows jumpbox via Azure Bastion
Cost: ~$290/month (with optimization potential)
```

### Production Environment (Parameterized Strategy)
```
Confirmed Terraform Configuration:
├── purpose = "prod"
├── location = "canadacentral" ✅ DECIDED: Same region as dev
├── location_code = "cc" ✅ DECIDED: Same location code
├── random_string = "01" ✅ DECIDED: Same as dev (separation by purpose)
├── vnet_address_space = "10.2.0.0/16" (different CIDR for isolation)
├── subnet_address_prefix = "10.2.1.0/24" 
└── enable_auto_purge = false (NEVER true for prod)

Generated Resource Groups (using same modules, same subscription):
├── rg-aml-vnet-prod-cc01 (VNet module)
├── rg-aml-workspace-prod-cc01 (Workspace module) 
└── rg-aml-registry-prod-cc01 (Registry module)

Generated Key Resources (using same naming convention):
├── VNet: vnet-amlprodcc01 (10.2.0.0/16)
├── Subnet: subnet-amlprodcc01 (10.2.1.0/24)
├── Workspace: amlprodcc01
├── Registry: amlrprodcc01
├── Storage: stamlprodcc01
├── Container Registry: acrprodcc01
├── Key Vault: kvprodcc01 (with auto-purge DISABLED)
└── Log Analytics: log-amlprodcc01
```

## Parameterized Infrastructure Approach

### Terraform Module Architecture ✅ **IMPLEMENTED**

Your infrastructure uses a **fully parameterized approach** with reusable Terraform modules:

```
Root Orchestration (main.tf):
├── Module: aml-vnet (networking foundation)
├── Module: aml-managed-smi (workspace)  
└── Module: aml-registry-smi (registry)

Parameters Passed to All Modules:
├── purpose (environment: dev/prod/test)
├── location (Azure region)
├── location_code (region abbreviation)
├── random_string (unique identifier)
├── vnet_address_space (network CIDR)
├── subnet_address_prefix (subnet CIDR)
├── tags (resource tagging)
└── enable_auto_purge (Key Vault setting)
```

### Dynamic Resource Naming ✅ **IMPLEMENTED**

All resources use consistent, parameterized naming conventions:

```
Resource Group Pattern:
├── VNet Module: "rg-aml-vnet-${purpose}-${location_code}${random_string}"
├── Workspace Module: "rg-aml-workspace-${purpose}-${location_code}${random_string}"
└── Registry Module: "rg-aml-registry-${purpose}-${location_code}${random_string}"

Resource Naming Pattern:
├── VNet: "vnet-aml${purpose}${location_code}${random_string}"
├── Subnet: "subnet-aml${purpose}${location_code}${random_string}"
├── Workspace: "aml${purpose}${location_code}${random_string}"
├── Registry: "amlr${purpose}${location_code}${random_string}"
├── Storage: "staml${purpose}${location_code}${random_string}"
├── Container Registry: "acr${purpose}${location_code}${random_string}"
├── Key Vault: "kv${purpose}${location_code}${random_string}"
└── Log Analytics: "log-aml${purpose}${location_code}${random_string}"

Identity Naming:
├── Compute Cluster: "${purpose}-mi-cluster"
└── Online Endpoints: "${purpose}-mi-endpoint"
```

### Environment Configuration Strategy ✅ **IMPLEMENTED**

Each environment uses separate `terraform.tfvars` files with environment-specific parameters:

## Architecture Decisions

### A. Parameterized Deployment Strategy ✅ **IMPLEMENTED**

Your current approach uses **fully parameterized Terraform modules** that can deploy identical architecture to any environment by changing only the terraform.tfvars file:

```
Development (terraform.tfvars):
purpose = "dev"
location = "canadacentral"
location_code = "cc"
random_string = "01"
vnet_address_space = "10.1.0.0/16"
subnet_address_prefix = "10.1.1.0/24"
enable_auto_purge = true

Production (terraform-prod.tfvars):
purpose = "prod"
location = "canadacentral"  ✅ Same region as dev
location_code = "cc"        ✅ Same location code as dev
random_string = "01"       ✅ Same as dev (separation by purpose parameter)
vnet_address_space = "10.2.0.0/16"    # Different CIDR for network isolation
subnet_address_prefix = "10.2.1.0/24"  # Different subnet for network isolation
enable_auto_purge = false   # CRITICAL: never true for prod
```

**Benefits of This Approach:**
- ✅ Same modules, different configurations
- ✅ Consistent architecture across environments  
- ✅ Zero shared components (different resource instances)
- ✅ Environment-specific parameter validation
- ✅ Easy to add new environments (staging, test, etc.)

### B. Subscription Strategy ✅ **DECIDED: Single Subscription**

Based on your constraint of having only one subscription available, we'll use **single subscription with complete resource group isolation**:

**Selected Approach: Single Subscription with Resource Group Isolation**
**Pros:**
- ✅ **Practical**: Works with your current subscription setup
- ✅ **Simplified management**: Single subscription to manage and monitor
- ✅ **Shared quotas**: Dev and prod can share subscription quotas efficiently
- ✅ **Cost tracking**: Use resource group tags for cost allocation
- ✅ **Complete isolation**: Still achieves zero shared components through different resource groups

**Mitigation Strategies for Single Subscription:**
- ✅ **Strong RBAC**: Use resource group-level permissions for access control
- ✅ **Resource tagging**: Clear environment tagging for cost allocation and governance
- ✅ **Naming conventions**: Clear separation through parameterized naming (devcc01 vs prodcc01)
- ✅ **Network isolation**: Different VNet CIDR ranges prevent any network connectivity
- ✅ **Monitoring separation**: Separate Log Analytics workspaces for each environment

**Subscription Configuration:**
```
Subscription: 5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25
├── Development Resource Groups (rg-aml-*-dev-*)
├── Production Resource Groups (rg-aml-*-prod-*)
├── Complete network isolation (10.1.x.x vs 10.2.x.x)
└── Independent DNS zones per environment
```

### C. Geographic Strategy ✅ **DECIDED: Same Region**

Your decision to use the same region for both environments is practical and cost-effective:

**Selected Configuration:**
```
Both Dev and Prod:
├── location = "canadacentral"
├── location_code = "cc"
└── Same Azure region benefits
```

**Benefits of Same Region Strategy:**
- ✅ **Operational simplicity**: Familiar region for your team
- ✅ **Consistent performance**: Same latency and performance characteristics
- ✅ **Cost optimization**: No cross-region data transfer costs
- ✅ **Simplified monitoring**: Single region to monitor for service health
- ✅ **Easier troubleshooting**: Consistent region-specific behaviors

**Resource Naming Impact:**
- Dev: `amldevcc01`, `acrdevcc01`, `stamldevcc01`
- Prod: `amlprodcc01`, `acrprodcc01`, `stamlprodcc01`
- Clear separation through `purpose` parameter (dev vs prod) with same random_string (01)

### D. Network Isolation Strategy ✅ **DECIDED: Complete Isolation**

```
Development Network (current):
├── VNet: 10.1.0.0/16 (vnet_address_space parameter)
├── Subnet: 10.1.1.0/24 (subnet_address_prefix parameter)
└── Private DNS Zones: Dev-specific instances (created by aml-vnet module)

Production Network (parameterized):
├── VNet: 10.2.0.0/16 (different vnet_address_space parameter)
├── Subnet: 10.2.1.0/24 (different subnet_address_prefix parameter)  
└── Private DNS Zones: Prod-specific instances (same module, different deployment)

Connectivity: NONE (complete air-gap by design)
```

**Benefits:**
- Maximum security isolation through parameterization
- No risk of cross-environment network pollution
- Independent DNS resolution per environment
- Clear security boundaries maintained by module design

### E. DNS Zone Strategy ✅ **DECIDED: Separate DNS Zones**

Your `aml-vnet` module creates environment-specific DNS zones automatically:

```
Required DNS Zones (created per environment by aml-vnet module):
├── privatelink.blob.core.windows.net
├── privatelink.file.core.windows.net  
├── privatelink.table.core.windows.net
├── privatelink.queue.core.windows.net
├── privatelink.vaultcore.azure.net
├── privatelink.azurecr.io
├── privatelink.api.azureml.ms
├── privatelink.notebooks.azure.net
└── instances.azureml.ms

Implementation: Each deployment of aml-vnet module creates separate DNS zone instances
Cost Impact: ~$4.50/month per environment (minimal)
Resource Groups: All DNS zones created in rg-aml-vnet-{purpose}-{location_code}{random_string}
```

### F. Identity and Access Management ✅ **PARAMETERIZED**

#### Managed Identity Strategy ✅ **IMPLEMENTED**
Your aml-vnet module creates environment-specific managed identities:

```
Development (purpose = "dev"):
├── dev-mi-cluster (compute cluster identity)
└── dev-mi-endpoint (online endpoint identity)

Production (purpose = "prod"):  
├── prod-mi-cluster (compute cluster identity)
└── prod-mi-endpoint (online endpoint identity)

Pattern: ${purpose}-mi-{function}
Location: Created in rg-aml-vnet-{purpose}-{location_code}{random_string} resource group
```

#### RBAC Strategy Options ⭐ **DECISION NEEDED**

**Option 1: Completely Separate Teams**
- Dev team: Access only to dev subscription/resources
- Prod team: Access only to prod subscription/resources
- No shared access between environments

**Option 2: Tiered Access Model**
- Senior engineers: Access to both dev and prod
- Junior engineers: Dev access only
- Prod deployments: Require senior approval

**Recommendation:** Tiered access model with strict prod change control

### G. CI/CD and Model Promotion Strategy ⭐ **DECISION NEEDED**

#### Option 1: Air-Gapped Promotion (Recommended for Complete Isolation)
```
Model Development (Dev):
├── Train and validate in dev environment
├── Export model artifacts to neutral storage
└── Version control model metadata

Model Promotion (Prod):
├── Import model artifacts via CI/CD pipeline
├── Retrain/validate in prod environment
├── Deploy through prod-specific pipeline
```

**Benefits:**
- Complete environment isolation maintained
- Full validation in production environment
- Audit trail for all model promotions
- Compliance with air-gap requirements

**Challenges:**
- Longer promotion cycles
- Potential for environment drift
- Additional CI/CD complexity

#### Option 2: Direct Registry-to-Registry (Requires Connectivity)
```
Model Promotion:
├── Controlled VNet peering between environments
├── Direct model copy from dev to prod registry
├── Network-level access controls (NSGs/Firewall)
```

**Benefits:**
- Faster model promotion
- Simplified artifact management
- Direct lineage tracking

**Challenges:**
- Breaks complete isolation principle
- Additional network security complexity
- Cross-environment connectivity risks

**Recommendation:** Air-gapped promotion to maintain complete isolation

## Infrastructure Implementation Plan

## Infrastructure Implementation Plan

### Phase 1: Production Environment Foundation ✅ **READY TO DEPLOY**
Your parameterized modules are ready for production deployment:

1. **Create Production terraform.tfvars**
   ```terraform
   # /infra/environments/prod/terraform.tfvars
   purpose = "prod"
   location = "canadacentral"  ✅ Same region as dev
   location_code = "cc"        ✅ Same location code
   random_string = "01"       ✅ Same as dev (separation by purpose)
   vnet_address_space = "10.2.0.0/16"      # Different CIDR from dev
   subnet_address_prefix = "10.2.1.0/24"   # Different subnet from dev
   enable_auto_purge = false   # CRITICAL: never true for prod
   
   tags = {
     environment  = "prod"     # Different from dev
     project      = "ml-platform"
     created_by   = "terraform"
     owner        = "ml-team"
   }
   ```

2. **Deploy Production Infrastructure**
   ```bash
   cd /infra/environments/prod
   terraform init
   terraform plan -var-file=terraform.tfvars
   terraform apply -var-file=terraform.tfvars
   ```

   This creates (in same subscription, same region):
   - New VNet with 10.2.0.0/16 CIDR (completely isolated from dev 10.1.0.0/16)
   - Separate DNS zones for all services (zero shared, different resource groups)  
   - Independent managed identities (prod-mi-* vs dev-mi-*)
   - Isolated storage and container registry (amlprodcc01 vs amldevcc01 names)
   - Key Vault with auto-purge DISABLED (vs enabled in dev)
   - Complete resource group separation (rg-aml-*-prod-* vs rg-aml-*-dev-*)

### Phase 2: Access and Security
1. **Configure Production Access Controls**
   - Restricted RBAC assignments
   - Separate jumpbox or VPN access method
   - Audit logging and monitoring

### Phase 3: CI/CD Pipeline Setup
1. **Environment-Specific Pipelines**
   - Dev pipeline for development workflows
   - Prod pipeline with approval gates
   - Model promotion workflows

### Phase 4: Operational Excellence
1. **Monitoring and Alerting**
   - Environment-specific Log Analytics workspaces
   - Separate monitoring dashboards
   - Independent alert configurations

## Naming Conventions ✅ **IMPLEMENTED**

### Parameterized Pattern (Currently Deployed)
Your Terraform modules use a consistent, parameterized naming convention:

```
Format: {prefix}{purpose}{location_code}{random_string}

Current Development (purpose="dev", location_code="cc", random_string="01"):
├── amldevcc01 (workspace)
├── amlrdevcc01 (registry)  
├── stamldevcc01 (storage)
├── acrdevcc01 (container registry)
├── kvdevcc01 (key vault)
└── vnet-amldevcc01 (virtual network)

Planned Production (purpose="prod", location_code="cc", random_string="01"):
├── amlprodcc01 (workspace)
├── amlrprodcc01 (registry)
├── stamlprodcc01 (storage)
├── acrprodcc01 (container registry)
├── kvprodcc01 (key vault)
└── vnet-amlprodcc01 (virtual network)
```

### Resource Group Pattern ✅ **IMPLEMENTED**
```
Format: rg-{service}-{purpose}-{location_code}{random_string}

Development:
├── rg-aml-vnet-dev-cc01 (VNet module)
├── rg-aml-workspace-dev-cc01 (Workspace module)
└── rg-aml-registry-dev-cc01 (Registry module)

Production (with same modules):
├── rg-aml-vnet-prod-cc01 (VNet module)
├── rg-aml-workspace-prod-cc01 (Workspace module)
└── rg-aml-registry-prod-cc01 (Registry module)
```

### Benefits of Parameterized Naming
- ✅ **Consistent**: Same pattern across all environments
- ✅ **Predictable**: Easy to find resources across environments
- ✅ **Scalable**: Add new environments without naming conflicts
- ✅ **Automated**: No manual naming decisions required

## Cost Considerations

### Development Environment (Current)
- **Compute**: Auto-shutdown policies implemented
- **Storage**: Lifecycle policies for old data
- **Jumpbox**: ~$290/month (optimization opportunities identified)

### Production Environment (Projected)
- **Similar base cost** to dev environment
- **Additional considerations**: Higher availability requirements, backup costs
- **Optimization**: Right-sizing based on actual workloads

### Cost Optimization Strategies
1. **Auto-scaling**: Implement compute auto-scaling policies
2. **Reserved Instances**: Consider 1-year reservations for stable workloads
3. **Storage Tiers**: Implement intelligent tiering for model artifacts
4. **Monitoring**: Set up cost alerts and budget controls

## Security and Compliance

### Data Protection
- **Encryption**: All data encrypted at rest and in transit
- **Key Management**: Separate Key Vaults per environment
- **Access Controls**: Least privilege access principles

### Network Security
- **Private Endpoints**: All Azure services accessible via private endpoints only
- **DNS Resolution**: Private DNS zones prevent data exfiltration
- **Network Segmentation**: Complete network isolation between environments

### Audit and Compliance
- **Activity Logging**: All operations logged to separate Log Analytics workspaces
- **Access Reviews**: Regular review of environment access
- **Change Management**: All infrastructure changes via pull request approval

## Disaster Recovery and Business Continuity

### Backup Strategy
- **Infrastructure**: Terraform state files backed up and versioned
- **Data**: Model artifacts and training data backed up to separate storage
- **Configuration**: Environment configurations stored in version control

### Recovery Procedures
- **Infrastructure Recovery**: Terraform-based infrastructure recreation
- **Data Recovery**: Point-in-time restore capabilities for critical data
- **Service Recovery**: Documented procedures for service restoration

## Decision Log

| Decision | Status | Date | Rationale |
|----------|--------|------|-----------|
| Complete Environment Isolation | ✅ Decided | 2025-08-06 | Maximum security, compliance requirements |
| Separate DNS Zones | ✅ Decided | 2025-08-06 | Prevent cross-environment DNS pollution |
| Single Subscription Strategy | ✅ Decided | 2025-08-06 | Only one subscription available, use resource group isolation |
| Same Region Strategy | ✅ Decided | 2025-08-06 | Operational simplicity, cost optimization, team familiarity |
| CI/CD Strategy | ⭐ Pending | TBD | Air-gapped vs connected promotion approach |
| Access Control Model | ⭐ Pending | TBD | Team structure and access requirements |

## Next Steps

1. **Finalize Strategic Decisions**
   - ✅ Subscription strategy: Single subscription confirmed
   - ✅ Geographic deployment: Same region (Canada Central) confirmed  
   - ⭐ CI/CD and model promotion approach (air-gapped vs connected)
   - ⭐ Access control model (team structure and permissions)

2. **Create Production Environment** ✅ **READY TO IMPLEMENT**
   - ✅ Terraform configuration approach confirmed (same modules, different terraform.tfvars)
   - ⭐ Deploy production infrastructure using single subscription approach
   - ⭐ Configure resource group-level access controls

3. **Implement CI/CD Pipelines**
   - Environment-specific deployment pipelines
   - Model promotion workflows  
   - Testing and validation procedures

4. **Operational Readiness**
   - Monitoring and alerting setup with separate Log Analytics workspaces
   - Documentation and runbooks
   - Team training and procedures

## References

- [Azure ML Private Network Configuration](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation)
- [Azure Private DNS Best Practices](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/dns-for-on-premises-and-azure-resources)
- [Azure ML Enterprise Security](https://learn.microsoft.com/en-us/azure/machine-learning/concept-enterprise-security)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

**Document Version**: 1.0  
**Last Updated**: August 6, 2025  
**Next Review**: TBD based on strategic decisions
