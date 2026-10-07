# Single Azure ML Workspace

This Terraform root supports two isolated profiles:

- `managed`: `AllowOnlyApprovedOutbound`, selected-IP ingress, and a post-create
  managed-network/Spark provisioning phase.
- `public`: open public connectivity with AML managed-network isolation disabled.

Different deployments use separate local state, tfvars, and saved plans. Never reuse
one deployment's state file for another profile or region.

## North Central US public profile

The current public deployment uses:

```powershell
$env:TF_DATA_DIR = (
  Resolve-Path infra\single-workspace
).Path + "\.terraform-public-ncus"
terraform -chdir=infra\single-workspace init `
  -input=false
terraform -chdir=infra\single-workspace workspace select `
  -or-create public-ncus
terraform -chdir=infra\single-workspace plan `
  -var-file=public.ncus.tfvars `
  -out=public-ncus.tfplan

.\infra\single-workspace\scripts\validate-plan.ps1 `
  -PlanPath public-ncus.tfplan `
  -ExpectedLocation northcentralus `
  -ExpectedLocationCode ncus `
  -ExpectedPurpose public `
  -ExpectedSuffix 04 `
  -ExpectedNetworkProfile public `
  -ExpectedCreateCompute $true
```

Expected names:

| Resource | Name |
|---|---|
| Resource group | `rg-aml-ws-public-ncus-04` |
| Azure ML workspace | `mlwpublicncus04` |
| Storage account | `stpublicncus04` |
| Spark ADLS Gen2 | `stpublicdlncus04` |
| Container registry | `acrpublicncus04` |
| Workspace Key Vault | `kvpublicncus04` |
| CMK Key Vault | `kvcmkpublicncus04` |
| Log Analytics workspace | `log-aml-public-ncus04` |
| Application Insights | `mlwinpublicncus04` |
| Compute cluster | `aml-cluster-public-ncus04` |
| Compute instance | `ci-public-ncus04` |

Apply only the validated saved plan. Post-deployment validation uses:

```powershell
.\infra\single-workspace\scripts\validate-public-deployment.ps1 `
  -StatePath terraform.tfstate.d\public-ncus\terraform.tfstate
```

## Managed Canada Central profile

The existing managed profile retains its separate Canada Central state and names.
The network sequence below applies only to that profile.

## Historical managed-profile resources

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

## Configure a profile

```powershell
Set-Location infra\single-workspace
Copy-Item public.ncus.tfvars.example public.ncus.tfvars
```

Replace the documentation IP with an approved public IPv4 CIDR. A single address must
use `/32`. Keep the confirmed subscription and `SecurityControl=Ignore`. The public
profile does not apply selected-IP firewalls, but the validated CIDR remains available
if the stack is later converted to the managed profile.

## Local validation

```powershell
terraform fmt -check -recursive
terraform init -input=false
terraform validate
```

No Azure access is required for these checks.

## Plan review

Planning is a later, explicitly approved step:

```powershell
terraform init -input=false
terraform workspace select -or-create <workspace-name>
terraform plan -var-file=<tfvars-file> -out=<plan-file>
.\scripts\validate-plan.ps1 -PlanPath <plan-file> <expected-profile-parameters>
```

The validator requires all resources to be create-only with no deletes or
replacements, exact names, mandatory tags, CMK, UAMIs, profile-specific networking,
and the expected compute phase. Review the saved plan before applying it.

## Post-deployment validation

After a separately approved deployment:

```powershell
.\scripts\validate-public-deployment.ps1 `
  -StatePath terraform.tfstate.d\public-ncus\terraform.tfstate
```

The public validator checks exact names, North Central US locations, tags, CMK,
UAMIs, public connectivity, compute security, ADLS Gen2, and a smoke job. It stops
the compute instance and waits for the cluster to scale to zero.

## State and generated files

Local state is intentionally isolated to this root. These files must remain untracked:

- `.terraform\`
- `terraform.tfstate*`
- `.terraform.tfstate.lock.info`
- `terraform.tfvars`
- `tfplan` and other saved plans

The provider lock file is source-controlled for repeatable initialization.
