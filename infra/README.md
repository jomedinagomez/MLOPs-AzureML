# Terraform Infrastructure Stacks

This directory contains four independent Terraform roots. Run Terraform commands
from one stack directory at a time; each stack has its own state and variables.

| Stack | Purpose |
|---|---|
| [`mlops/`](./mlops/) | Existing private dev/prod platform with two Azure ML workspaces and two Azure ML registries. |
| [`non-networking/`](./non-networking/) | Existing public-network variant with two workspaces and two registries. |
| [`single-workspace/`](./single-workspace/) | One CMK-enabled workspace using AML-managed networking and selected public IPs. No Azure ML registry or customer-managed network. |
| [`spark-workspace/`](./spark-workspace/) | Replacement CMK/UAMI workspace with Terraform-native AzAPI Spark provisioning, selected-IP services, and `SecurityControl=Ignore`. |

## State isolation

Never share or copy a `terraform.tfstate`, `.terraform/`, plan file, or real
`terraform.tfvars` between these directories. The repository ignores these files.
Create a separate backend or state file for each stack.

## Commands

```powershell
terraform -chdir=infra\mlops init
terraform -chdir=infra\mlops validate

terraform -chdir=infra\non-networking init
terraform -chdir=infra\non-networking validate

terraform -chdir=infra\single-workspace init
terraform -chdir=infra\single-workspace validate

terraform -chdir=infra\spark-workspace init
terraform -chdir=infra\spark-workspace validate
```

See each stack's README before planning, applying, or destroying resources.
