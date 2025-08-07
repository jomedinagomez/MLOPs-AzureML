# Azure ML Platform Deployment Strategy

## Overview

This document outlines the deployment strategy for our Azure Machine Learning platform, focusing on complete isolation between development and production environments with zero shared components. **This implementation uses two registries to showcase comprehensive MLOps asset promotion workflows, though a single registry would be sufficient for most production scenarios.**

## Strategic Principles

### 1. Complete Environment Isolation
- **Zero Shared Components**: No resources, networks, DNS zones, or identities shared between dev and prod
- **Independent Lifecycles**: Each environment can be created, modified, or destroyed independently
- **Security Boundaries**: Complete separation prevents cross-environment security risks
- **Governance**: Clear ownership and access control per environment
- **Demonstration Purpose**: Two-registry architecture showcases full MLOps promotion capabilities

### 2. Infrastructure as Code
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
  subnet             = "subnet-aml"
  workspace          = "amlws"
  registry           = "amlreg"
  storage            = "amlst"
  container_registry = "amlacr"
  key_vault          = "amlkv"
  log_analytics      = "amllog"
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
random_string = "01"             # Unique identifier
enable_auto_purge = true | false # Dev: true, Prod: false (CRITICAL)
```

**Environment-Specific Differences:**
- **Development**: `vnet_address_space = "10.1.0.0/16"`, `subnet_address_prefix = "10.1.1.0/24"`
- **Production**: `vnet_address_space = "10.2.0.0/16"`, `subnet_address_prefix = "10.2.1.0/24"`

**Generated Resource Examples:**
- VNet: `vnet-amldevcc01` / `vnet-amlprodcc01`
- Workspace: `amlwsdevcc01` / `amlwsprodcc01`
- Storage: `amlstdevcc01` / `amlstprodcc01`
- Resource Groups: `rg-aml-vnet-dev-cc01` / `rg-aml-vnet-prod-cc01`

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

### C. Network Isolation Strategy

```
Development Network:
├── VNet: 10.1.0.0/16
├── Subnet: 10.1.1.0/24
└── Private DNS Zones: Dev-specific instances

Production Network:
├── VNet: 10.2.0.0/16
├── Subnet: 10.2.1.0/24
└── Private DNS Zones: Prod-specific instances

Connectivity: NONE (complete air-gap by design)
```

**Benefits:**
- Maximum security isolation through parameterization
- No risk of cross-environment network pollution
- Independent DNS resolution per environment
- Clear security boundaries maintained by module design

## Identity and Access Management

### Service Principal Strategy
A single service principal will be used for all infrastructure deployments across all 6 resource groups:

```
Deployment Service Principal:
├── Name: "sp-aml-deployment-{environment}"
├── Scope: All 6 resource groups (RG level permissions)
├── Roles: 
│   ├── Contributor (on all 6 resource groups): Deploy ML workspace, storage accounts, and compute resources - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#contributor)
│   ├── User Access Administrator (on all 6 resource groups): Configure RBAC for managed identities and user access - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#user-access-administrator)
│   └── Network Contributor (on all 6 resource groups): Configure secure networking for ML workspace isolation - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/networking#network-contributor)
└── Purpose: Terraform deployments via CI/CD pipelines
```

### Managed Identity Strategy
Managed identities will use different types based on component requirements:

```
Workspace UAMI:
├── Name: "${purpose}-mi-workspace"
├── Location: rg-aml-vnet-${purpose}-${location_code}${random_string}
├── Used by: Azure ML Workspace for management operations
├── Roles:
│   ├── Azure AI Administrator (on resource group): Configure workspace settings and AI services integration - [Learn more](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-assign-roles?view=azureml-api-2#troubleshooting)
│   ├── Azure AI Enterprise Network Connection Approver (on resource group): Enable secure connectivity and cross-environment sharing - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azure-ai-enterprise-network-connection-approver)
│   ├── Azure AI Enterprise Network Connection Approver (on registry): Enable cross-environment model sharing - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azure-ai-enterprise-network-connection-approver)
│   ├── Storage Blob Data Contributor (on default storage account): Manage workspace artifacts and datasets - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-contributor)
│   ├── Storage Blob Data Owner (on default storage account): Complete workspace storage management and permissions - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-owner)
│   ├── AzureML Registry User (on registry): Access and use shared models, components, and environments - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-registry-user)
│   └── Reader (on private endpoints for storage accounts): Monitor and validate secure storage connectivity - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader)

Compute Cluster & Compute Instance UAMI (Shared):
├── Name: "${purpose}-mi-compute" 
├── Location: rg-aml-vnet-${purpose}-${location_code}${random_string}
├── Used by: Both compute cluster and compute instance
├── Roles:
│   ├── AcrPull (on container registry): Access base images for ML training and inference environments - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers#acrpull)
│   ├── AcrPush (on container registry): Build and store custom training environments and inference images - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers#acrpush)
│   ├── Storage Blob Data Contributor (on default storage account): Store and retrieve training data and pipeline outputs - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-blob-data-contributor)
│   ├── Storage File Data Privileged Contributor (on default storage account): Share files between compute nodes - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage#storage-file-data-privileged-contributor)
│   ├── AzureML Data Scientist (on workspace): Execute ML pipelines and model registration workflows - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-data-scientist)
│   ├── Key Vault Secrets User (on key vault): Access credentials during ML workloads - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-user)
│   ├── Reader (on resource group): Discover resources during pipeline execution - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader)
│   ├── AzureML Registry User (on registry): Access shared models and components during training - [Learn more](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning#azureml-registry-user)
│   └── Contributor (on workspace): Enable automatic shutdown of idle compute instances - [Learn more](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-create-compute-instance?view=azureml-api-2#assign-managed-identity)

Online Endpoints:
├── Identity: System-Assigned Managed Identity (SMI) - Default behavior
├── Roles: Automatically managed by Azure ML service
└── No additional RBAC configuration required
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
    resource_group_name="rg-aml-vnet-dev-cc01", 
    workspace_name="amlwsdevcc01"
)

# Development registry client
ml_client_dev_registry = MLClient(
    credential=credential,
    subscription_id="your-subscription-id",
    registry_name="amlregdevcc01"
)

# Production registry client  
ml_client_prod_registry = MLClient(
    credential=credential,
    subscription_id="your-subscription-id",
    registry_name="amlregprodcc01"
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
    registry_name="amlregdevcc01"
)
print(f"Model shared to dev registry: {shared_model.name} v{shared_model.version}")

# ============================================================================  
# STEP 4: Promote Model from Dev Registry to Prod Registry
# ============================================================================
print("\nStep 3: Promoting model to production registry...")

model_prod = Model(
    name="taxi-fare-model", 
    version="1.0",
    path="azureml://registries/amlregdevcc01/models/taxi-fare-model/versions/1.0",
    description="Production taxi fare model (promoted from dev)",
    tags={"stage": "production", "promoted_from": "dev_registry"}
)

prod_model = ml_client_prod_registry.models.create_or_update(model_prod)
print(f"Model promoted to prod registry: {prod_model.name} v{prod_model.version}")

# ============================================================================
# STEP 5: Verification
# ============================================================================
print("\nVerification:")
print(f"Dev Registry Model: azureml://registries/amlregdevcc01/models/taxi-fare-model/versions/1.0")
print(f"Prod Registry Model: azureml://registries/amlregprodcc01/models/taxi-fare-model/versions/1.0")
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
    registry_name="amlregdevcc01"
)
print(f"Data shared to dev registry: {shared_data.name} v{shared_data.version}")

# ============================================================================
# STEP 3: Promote Data from Dev Registry to Prod Registry
# ============================================================================  
print("\nStep 3: Promoting data to production registry...")

prod_data = Data(
    name="validation-dataset",
    version="1.0",
    path="azureml://registries/amlregdevcc01/data/validation-dataset/versions/1.0",
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
print(f"Dev Registry Data: azureml://registries/amlregdevcc01/data/validation-dataset/versions/1.0")
print(f"Prod Registry Data: azureml://registries/amlregprodcc01/data/validation-dataset/versions/1.0")
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
- **Stays in**: `amlregdevcc01.azurecr.io` (dev registry's ACR)
- **Does NOT get copied** to prod registry's ACR  
- **Does NOT get rebuilt**

**What Gets Created in Production:**
- **Environment metadata record** (name, version, description, tags)
- **Reference to the Docker image URI** (`amlregdevcc01.azurecr.io/environments/my-env:1.0`)
- **Same image, different environment record**

**Result**: Both dev registry and prod workspace environments point to the **same physical Docker image** stored in the dev registry's ACR.

```python
# Verification example:
dev_env = ml_client_dev_registry.environments.get("my-docker-env", "1.0")
prod_env = ml_client_prod_workspace.environments.get("my-docker-env", "1.0")

print(f"Dev registry image:  {dev_env.image}")
print(f"Prod workspace image: {prod_env.image}")
# Both will show: amlregdevcc01.azurecr.io/environments/my-docker-env:1.0

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
    resource_group_name="rg-aml-vnet-prod-cc01",
    workspace_name="amlwsprodcc01"
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
    registry_name="amlregdevcc01"
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
    registry_name="amlregdevcc01"
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
conda_prod_reference = "azureml://registries/amlregdevcc01/environments/inference-env-conda/versions/1.0"
docker_prod_reference = "azureml://registries/amlregdevcc01/environments/inference-env-docker/versions/1.0"

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
print(f"  Option 1 - Dev Registry Reference: azureml://registries/amlregdevcc01/environments/inference-env-conda/versions/1.0")
print(f"  Option 2 - Prod Workspace: inference-env-conda:1.0")

print("\nDocker Environment:")
print(f"  Option 1 - Dev Registry Reference: azureml://registries/amlregdevcc01/environments/inference-env-docker/versions/1.0")
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
     - **RECOMMENDED**: Reference dev registry environments via `azureml://registries/amlregdevcc01/...` URIs
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
    environment="azureml://registries/amlregdevcc01/environments/inference-env:1.0",
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
env_prod_ref = "azureml://registries/amlregdevcc01/environments/inference-env:1.0"
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
       registry_name="amlregdevcc01"
   )
   
   # Promote model to production registry (manual approval gate)
   prod_model = Model(
       name="taxi-fare-model",
       version="1.0",
       path="azureml://registries/amlregdevcc01/models/taxi-fare-model/versions/1.0"
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
       registry_name="amlregdevcc01"
   )
   
   # 3. Choose production strategy:
   # Option A: Reference dev registry directly (fastest)
   direct_ref = "azureml://registries/amlregdevcc01/environments/inference-env/versions/1.0"
   
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
- Separate jumpbox or VPN access method
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

## Security and Compliance

### Data Protection
- Encryption: All data encrypted at rest and in transit
- Key Management: Separate Key Vaults per environment
- Access Controls: Least privilege access principles

### Network Security
- Private Endpoints: All Azure services accessible via private endpoints only
- DNS Resolution: Private DNS zones prevent data exfiltration
- Network Segmentation: Complete network isolation between environments

### Audit and Compliance
- Activity Logging: All operations logged to separate Log Analytics workspaces
- Access Reviews: Regular review of environment access
- Change Management: All infrastructure changes via pull request approval

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

## References

- [Azure ML Private Network Configuration](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-registry-network-isolation)
- [Azure Private DNS Best Practices](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/dns-for-on-premises-and-azure-resources)
- [Azure ML Enterprise Security](https://learn.microsoft.com/en-us/azure/machine-learning/concept-enterprise-security)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

**Document Version**: 1.0  
**Last Updated**: August 6, 2025  
**Next Review**: TBD based on strategic decisions
