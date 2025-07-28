# Azure ML Operations (MLOps) Project

## Overview

This project demonstrates a complete Azure Machine Learning (ML) operations setup with Infrastructure as Code (IaC) using Terraform and a comprehensive ML pipeline for taxi fare classification. The implementation follows Azure ML best practices with secure networking, managed identities, and automated CI/CD capabilities.

## Architecture

### Infrastructure Components

The infrastructure is deployed using Terraform with a modular approach consisting of three main components:

1. **Networking Foundation** (`aml-vnet`)
   - Virtual Network with private subnets
   - Private DNS zones for Azure ML services
   - Managed identities for secure access

2. **Azure ML Workspace** (`aml-managed-smi`)
   - ML workspace with managed virtual network
   - Supporting services (Storage, Key Vault, Container Registry, Application Insights)
   - Private endpoints for secure communication
   - Compute cluster with user-assigned managed identity

3. **Azure ML Registry** (`aml-registry-smi`)
   - ML registry for model sharing and versioning
   - Private endpoint connectivity

### Security Features

- **Network Isolation**: Managed virtual network with `allow_only_approved_outbound` mode
- **Private Endpoints**: All Azure services accessible via private endpoints only
- **Managed Identities**: User-assigned managed identities for compute resources
- **RBAC**: Proper role assignments following least privilege principle
- **IP Whitelisting**: Workspace and storage account access restricted to specific IPs

## Deployment Guide

### Prerequisites

- Azure CLI installed and configured
- Terraform >= 1.0
- Azure subscription with appropriate permissions
- Azure ML CLI extension: `az extension add --name ml`

```json
{
  "azure-cli": "2.75.0",
  "azure-cli-core": "2.75.0",
  "azure-cli-telemetry": "1.1.0",
  "extensions": {
    "azure-firewall": "1.2.2",
    "k8s-extension": "1.6.3",
    "ml": "2.38.0"
  }
}
```

```bash
pip install --pre --upgrade azure-ai-ml azure-identity
```

### Infrastructure Deployment

The infrastructure deployment follows a three-step process:

#### Step 1: Deploy Network Foundation

```bash
cd infra/aml-vnet
terraform init
terraform plan
terraform apply
```

**Resources Created:**
- Virtual Network
- Private subnet
- User-assigned managed identities (workspace and compute)
- 9 Private DNS zones for Azure ML services
- VNet links for DNS resolution

#### Step 2: Deploy Azure ML Workspace

```bash
cd ../aml-managed-smi
terraform init
terraform plan
terraform apply
```

**Resources Created:**
- Azure ML Workspace
- Storage Account
- Key Vault
- Container Registry
- Application Insights
- Compute Cluster
- 7 Private endpoints
- Role assignments for managed identities

#### Step 3: Deploy Azure ML Registry

```bash
cd ../aml-registry-smi
terraform init
terraform plan
terraform apply
```

**Resources Created:**
- Azure ML Registry
- Log Analytics Workspace
- Private endpoint for registry access

### Role Assignments

The following RBAC roles are configured:

**User Account:**
- `Azure AI Developer` (Workspace level)
- `AzureML Compute Operator` (Workspace level)
- `AzureML Data Scientist` (Workspace level)
- `Storage Blob Data Contributor` (Storage account level)

**Managed Identity (Compute Cluster):**
- `AzureML Data Scientist` (Resource group level)
- `Storage Blob Data Contributor` (Resource group level)
- `Key Vault Secrets User` (Resource group level)

## ML Pipeline

### Pipeline Overview

The project includes a comprehensive ML pipeline (`taxi-fare-train-pipeline.yaml`) that demonstrates end-to-end machine learning operations:

```
Data Merge → Transform → Train → Predict → Compare/Score → Register → Deploy
```

### Pipeline Components

1. **Merge Job** (`merge_job`)
   - Combines green and yellow taxi datasets
   - Input: Raw CSV files
   - Output: Merged dataset

2. **Transform Job** (`transform_job`)
   - Data preprocessing and feature engineering
   - Train/test split (70/30)
   - Output: Training and testing datasets

3. **Train Job** (`train_job`)
   - Model training using sklearn
   - MLflow integration for experiment tracking
   - Output: Trained model artifacts

4. **Predict Job** (`predict_job`)
   - Generate predictions on test data
   - Input: Trained model and test dataset
   - Output: Prediction results

5. **Compare Job** (`compare_job`)
   - Model performance evaluation
   - Comparison with baseline models
   - Output: Performance metrics

6. **Score Job** (`score_job`)
   - Model scoring and evaluation
   - Generate performance reports
   - Output: Scoring results

7. **Register Job** (`register_job`)
   - Model registration in Azure ML
   - Version management
   - Output: Registered model reference

8. **Deploy Job** (`deploy_job`)
   - Model deployment to managed endpoint
   - Real-time inference setup
   - Output: Deployed endpoint

### Running the Pipeline

#### Method 1: Azure CLI

```bash
az ml job create \
  --file pipelines/taxi-fare-train-pipeline.yaml \
  --workspace-name <workspace-name> \
  --resource-group <resource-group> \
  --subscription <subscription-id>
```

#### Method 2: Python SDK

```bash
python submit_pipeline.py
```

### Pipeline Configuration

- **Compute**: Managed compute cluster (Standard_DS3_v2, 2 nodes)
- **Environment**: `AzureML-sklearn-1.0-ubuntu20.04-py38-cpu@latest`
- **Experiment**: `nyc-taxi-pipeline-class`
- **Default Datastore**: `workspaceblobstore`

## Project Structure

```
MLOPs-AzureML/
├── infra/                          # Terraform Infrastructure
│   ├── aml-vnet/                   # Network foundation
│   ├── aml-managed-smi/            # ML workspace
│   ├── aml-registry-smi/           # ML registry
│   └── modules/                    # Reusable Terraform modules
├── src/                            # ML Pipeline Components
│   ├── merge_data/                 # Data merging logic
│   ├── transform/                  # Data transformation
│   ├── train/                      # Model training
│   ├── predict/                    # Prediction generation
│   ├── compare/                    # Model comparison
│   ├── score/                      # Model scoring
│   ├── register/                   # Model registration
│   ├── deploy/                     # Model deployment
│   └── components/                 # Component definitions
├── pipelines/                      # Pipeline definitions
│   └── taxi-fare-train-pipeline.yaml
├── data/                          # Training data
│   └── taxi-data/
└── notebooks/                     # Jupyter notebooks
```

## Key Features

### Infrastructure as Code
- **Modular Design**: Reusable Terraform modules
- **Environment Separation**: Support for dev/staging/prod
- **State Management**: Remote state storage capability
- **Dependency Management**: Proper resource dependencies

### Security Best Practices
- **Network Isolation**: Private networking throughout
- **Identity Management**: Managed identities for all resources
- **Access Control**: RBAC with least privilege
- **Encryption**: Data encryption at rest and in transit

### MLOps Capabilities
- **Experiment Tracking**: MLflow integration
- **Model Versioning**: Automated model registration
- **Pipeline Orchestration**: Component-based pipeline design
- **Automated Deployment**: Model-to-endpoint deployment
- **Monitoring**: Built-in logging and monitoring

## Monitoring and Observability

### Application Insights
- Real-time monitoring of ML workspace
- Custom telemetry and logging
- Performance tracking

### Azure Monitor
- Infrastructure monitoring
- Resource health tracking
- Alerting and notifications

### MLflow Tracking
- Experiment tracking and comparison
- Model metrics and parameters
- Artifact management

## Troubleshooting

### Common Issues

1. **Authorization Failures**
   - Verify RBAC role assignments
   - Check managed identity permissions
   - Ensure IP whitelisting is configured

2. **Network Connectivity**
   - Validate private endpoint connections
   - Check DNS resolution
   - Verify firewall rules

3. **Pipeline Failures**
   - Check compute cluster status
   - Validate input data paths
   - Review component logs in Azure ML Studio

### Useful Commands

```bash
# Set default configuration
az account set --subscription <subscription>
az configure --defaults workspace=<workspace-name> group=<resource-group> location=<location>

# Check compute cluster status
az ml compute list --workspace-name <workspace-name> --resource-group <resource-group>

# Monitor pipeline run
az ml job show --name <job-name> --workspace-name <workspace-name> --resource-group <resource-group>

# List registered models
az ml model list --workspace-name <workspace-name> --resource-group <resource-group>

# Check role assignments
az role assignment list --scope <resource-scope>
```

## Cost Optimization

- **Compute Auto-scaling**: Cluster scales to zero when idle
- **Reserved Instances**: Consider for production workloads
- **Storage Tiers**: Use appropriate storage tiers for data
- **Resource Tagging**: Implemented for cost tracking

## Next Steps

- [ ] Implement automated testing
- [ ] Add CI/CD pipeline with GitHub Actions
- [ ] Configure model monitoring and drift detection
- [ ] Implement A/B testing for model deployments
- [ ] Add data quality checks
- [ ] Implement automated retraining

---

## Change Log

*This section tracks changes and updates to the project.*

### Version 1.0.0 (2025-07-28)
- ✅ Initial infrastructure deployment with Terraform
- ✅ Complete ML pipeline implementation
- ✅ Security configuration with managed identities
- ✅ Private networking setup
- ✅ Documentation and README creation
- ✅ Successful pipeline execution

#### Infrastructure Deployed:
- **Networking**: VNet with private subnets and DNS zones
- **ML Workspace**: Complete workspace with supporting services
- **Compute**: Cluster with managed identity
- **Registry**: ML registry for model management
- **Security**: RBAC roles and IP whitelisting configured

#### Pipeline Features:
- **8-step ML pipeline**: From data merge to model deployment
- **MLflow integration**: Experiment tracking and model management
- **Managed compute**: Auto-scaling cluster configuration
- **Private networking**: All components using private endpoints

---

## Contributing

Please follow these guidelines when contributing to the project:

1. Use Infrastructure as Code for all Azure resources
2. Follow security best practices
3. Implement proper logging and monitoring
4. Update documentation for any changes
5. Test thoroughly before deployment

## Support

For issues and questions:
- Review the troubleshooting section
- Check Azure ML documentation
- Open an issue in the repository

---

**Authors**: Jose Medina Gomez, Matt Felton