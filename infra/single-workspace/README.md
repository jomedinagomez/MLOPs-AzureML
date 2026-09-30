# Spark-Ready Azure ML Workspace

This independent Terraform root creates the Canada Central replacement workspace with
`purpose=spark` and `naming_suffix=02`. It uses local state in this directory and must
never share state, plans, `.terraform`, or `terraform.tfvars` with another root.

## Expected resources

| Resource | Name |
|---|---|
| Resource group | `rg-aml-ws-spark-cc-02` |
| Azure ML workspace | `mlwsparkcc02` |
| Storage account | `stsparkcc02` |
| Container registry | `acrsparkcc02` |
| Workspace Key Vault | `kvsparkcc02` |
| CMK Key Vault | `kvcmksparkcc02` |
| Log Analytics workspace | `log-aml-spark-cc02` |
| Application Insights | `mlwinsparkcc02` |
| Compute cluster | `aml-cluster-spark-cc02` |
| Compute instance | `aml-instance-spark-cc02` |

The root also creates workspace, cluster, compute-instance, and online-endpoint UAMIs;
an RSA customer-managed key; a Storage encryption scope; and required RBAC.

Every taggable Terraform-managed resource carries `SecurityControl=Ignore`.

## Network and Spark sequence

- Workspace creation starts with public access disabled.
- The workspace uses `AllowOnlyApprovedOutbound`.
- `provisionNetworkNow=false` prevents the non-Spark network from provisioning first.
- Terraform invokes the `provisionManagedNetwork` ARM action once with
  `includeSpark=true` and a three-hour timeout.
- Terraform does not declare a Blob outbound rule. Azure creates the required system
  rule for default Storage, avoiding duplicate destinations.
- Selected-IP workspace access is restored only after the Spark action succeeds.
- Compute creation waits for the Spark action and selected-IP restoration.
- Storage, ACR, and both Key Vaults use public access with deny-by-default firewalls
  limited to `allowed_public_ip_cidrs`. Storage shared-key access remains disabled.
- Compute nodes have no public IP and the compute instance has no public SSH.

The deployment validator requires exactly one Azure-created Blob rule targeting
`stsparkcc02`, with `spark_enabled=true`, `status=Active`, and workspace
`sparkReady=true`.

## Configure

```powershell
Set-Location infra\spark-workspace
Copy-Item terraform.tfvars.example terraform.tfvars
```

Replace the documentation IP with approved public IPv4 CIDRs. A single address must
use `/32`. Keep the confirmed subscription, Canada Central location, `spark`, `02`, and
`SecurityControl=Ignore`.

## Local validation

```powershell
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

No Azure access is required for these checks.

## Plan review

Planning is a later, explicitly approved step:

```powershell
terraform plan -out=tfplan
.\scripts\validate-plan.ps1 -PlanPath tfplan
```

The validator requires all managed resources to be create-only, no deletes or
replacements, exact names, mandatory tags, CMK, UAMIs, selected-IP services, and the
Terraform-native Spark action. Review the saved plan before applying it.

## Post-deployment validation

After a separately approved deployment:

```powershell
.\scripts\validate-deployment.ps1
```

The validator checks exact names, tags, CMK, UAMIs, selected-IP ACLs, one Azure-created
Spark Blob rule, `sparkReady`, compute security, a smoke job, and the integration
pipeline. It stops the compute instance and waits for the cluster to scale to zero.

## State and generated files

Local state is intentionally isolated to this root. These files must remain untracked:

- `.terraform\`
- `terraform.tfstate*`
- `.terraform.tfstate.lock.info`
- `terraform.tfvars`
- `tfplan` and other saved plans

The provider lock file is source-controlled for repeatable initialization.
