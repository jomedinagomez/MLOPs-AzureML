# Azure Deployment Plan

> **Status:** Validated

Generated: 2026-09-30

---

## 1. Project Overview

**Goal:** Replace the failed `cc-02` Azure ML demo with a fresh `cc-03`
single-workspace deployment that supports serverless Spark, customer-managed keys,
selected-IP local access, and the existing approved FQDN rules. In parallel, deploy
one public/non-managed-network workspace from the same single-workspace template.
Add a dedicated ADLS Gen2 filesystem for serverless Spark input/output after Spark
diagnostics confirmed the original HNS-disabled workspace storage did not meet the
documented quickstart architecture.

**Mode:** Modify the existing repository and replace a disposable POC deployment.

**Execution requirement:** All Terraform and Azure CLI deployment commands run in
visible VS Code task terminals. The `cc-02` destroy and `cc-03` phase-one create run
in parallel from isolated local Terraform states.

---

## 2. Requirements

| Attribute | Value |
|---|---|
| Classification | POC / disposable demo |
| Subscription | `5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25` |
| Region | Canada Central |
| Terraform root | `infra/single-workspace` |
| Replacement suffix | `03` |
| Required tag | `SecurityControl=Ignore` |
| Managed network | `AllowOnlyApprovedOutbound` |
| Internet policy | No unrestricted internet outbound |
| FQDN rules | Retain the original approved FQDN rules |
| Inbound access | Workspace and linked services use deny-by-default selected-IP access |
| Encryption | Workspace and default Storage use CMK |
| Spark | Serverless Spark, provisioned manually with `az ml workspace provision-network --include-spark` |
| Spark data | Dedicated HNS-enabled ADLS Gen2 account and `spark` filesystem using ABFSS URIs |
| Local execution | Spark notebook submitted from the user's local Windows computer |
| Public variant | One workspace, no Azure ML registry, managed networking disabled |

### Serverless Spark constraint

Microsoft documents that FQDN rules are not propagated into serverless Spark sessions.
Spark jobs that need additional Python packages must therefore use self-contained
wheels stored behind an approved private endpoint and pass them through `py_files`.
The workshop Spark example does not install external packages at runtime.

---

## 3. Repository Components

| Component | Technology | Path |
|---|---|---|
| Single workspace infrastructure | Terraform / AzureRM / AzAPI | `infra/single-workspace` |
| Managed-network CLI phase | PowerShell + Azure ML CLI | `infra/single-workspace/scripts/configure-spark-network.ps1` |
| Spark workshop job | Azure ML Spark YAML + PySpark | `workshop/notebooks/06_spark_jobs_pipelines` |
| Existing two-workspace MLOps | Terraform | `infra/mlops` |
| Existing non-networking variant | Terraform | `infra/non-networking` |

The repository contains one single-workspace Terraform template. The `cc-02` state is
copied to session storage only so destruction can run independently; this is an
operational state copy, not another repository template.

---

## 4. Deployment Recipe

**Recipe:** Terraform for infrastructure plus Azure ML CLI for the documented
post-create managed-network operation.

`includeSpark` is not a workspace-creation property. It belongs to the post-create
`provisionManagedNetwork` operation exposed by:

```powershell
az ml workspace provision-network `
  --subscription <subscription-id> `
  --resource-group <resource-group> `
  --name <workspace-name> `
  --include-spark
```

The storage Blob outbound rule is defined before provisioning with:

```powershell
az ml workspace outbound-rule set `
  --workspace-name <workspace-name> `
  --rule SparkStorageBlob `
  --type private_endpoint `
  --service-resource-id <storage-resource-id> `
  --subresource-target blob `
  --spark-enabled true
```

This preserves the existing FQDN rules because the CLI updates one named outbound
rule rather than replacing the workspace's complete outbound-rule collection.

---

## 5. Architecture and Naming

### Deployment being removed

| Resource | Name |
|---|---|
| Resource group | `rg-aml-ws-spark-cc-02` |
| Workspace | `mlwsparkcc02` |
| Storage | `stsparkcc02` |
| ACR | `acrsparkcc02` |
| Workspace Key Vault | `kvsparkcc02` |
| CMK Key Vault | `kvcmksparkcc02` |

### Fresh replacement

| Resource | Name |
|---|---|
| Resource group | `rg-aml-ws-spark-cc-03` |
| Workspace | `mlwsparkcc03` |
| Storage | `stsparkcc03` |
| ACR | `acrsparkcc03` |
| Workspace Key Vault | `kvsparkcc03` |
| CMK Key Vault | `kvcmksparkcc03` |
| Log Analytics | `log-aml-spark-cc03` |
| Application Insights | `mlwinsparkcc03` |
| Workspace UAMI | `spark-mi-workspace` |
| Cluster UAMI | `spark-mi-compute` |
| Compute-instance UAMI | `spark-mi-compute-instance` |
| Endpoint UAMI | `spark-mi-online-endpoint` |
| AML cluster | `aml-cluster-spark-cc03` |
| AML compute instance | `aml-instance-spark-cc03` |

### Public single-workspace variant

| Resource | Name |
|---|---|
| Resource group | `rg-aml-ws-public-cc-03` |
| Workspace | `mlwpubliccc03` |
| Storage | `stpubliccc03` |
| ACR | `acrpubliccc03` |
| Workspace Key Vault | `kvpubliccc03` |
| CMK Key Vault | `kvcmkpubliccc03` |
| AML cluster | `aml-cluster-public-cc03` |
| AML compute instance | `aml-instance-public-cc03` |

The public variant uses an isolated local state copied from the same template. It sets
`managedNetwork.isolationMode=Disabled`, enables public access on linked services,
creates one workspace and no Azure ML registry, and retains CMK, UAMIs, compute, and
`SecurityControl=Ignore`.

Global-name checks confirm that Storage, ACR, and both Key Vault names are available,
and the replacement resource group does not exist.

---

## 6. Ordered Deployment

### Workstream A: destroy failed `cc-02`

1. Use the copied `cc-02` local state in session storage.
2. Remove only the CMK key resource from copied state because the Key Vault ARM key
   resource does not support DELETE; deleting the containing vault removes it.
3. Run `terraform destroy -auto-approve` in a visible terminal.
4. Verify `rg-aml-ws-spark-cc-02` no longer exists.

### Workstream B: create `cc-03` phase one

1. Apply the saved `cc-03` Terraform plan in a second visible terminal.
2. Create the resource group first with `SecurityControl=Ignore`.
3. Create Storage, ACR, Key Vaults, CMK resources, UAMIs, RBAC, monitoring, and the
   AML workspace.
4. Create the workspace with:
   - `publicNetworkAccess = Disabled`
   - `managedNetworkKind = V1`
   - `isolationMode = AllowOnlyApprovedOutbound`
   - Azure Firewall Standard and the original FQDN rules
   - `provisionNetworkNow = false`
5. Do not create AML compute during phase one.

Workstreams A and B use different resource groups and isolated local state and can run
in parallel.

### Visible CLI network phase

1. Keep workspace public access disabled.
2. Add/update the `SparkStorageBlob` storage Blob PE rule with
   `spark_enabled=true`.
3. Add/update the `WorkspaceSelf` `amlworkspace` PE rule required before restoring
   selected-IP workspace access.
4. Run `az ml workspace provision-network --include-spark` in the visible terminal.
   This operation provisions the managed VNet and the previously defined private
   endpoints.
5. Require managed-network `status=Active` and `sparkReady=true`.
6. Restore selected-IP workspace access using the configured CIDRs.

### Terraform compute phase

1. Set `create_compute_resources=true`.
2. Apply Terraform again in a visible terminal.
3. Create the AML cluster and compute instance only after Spark networking is ready.
4. Configure the AML cluster as image-build compute.

### Workstream C: public single workspace

1. Use an isolated operational copy of `infra/single-workspace`.
2. Select purpose `public`, suffix `03`, managed-network isolation `Disabled`, and
   `create_compute_resources=true`.
3. Apply the validated saved plan in a separate visible terminal while Workstreams A
   and B continue.
4. Persist the public profile back into the single repository template after the active
   cc-03 saved-plan apply releases the source directory.

### Workstream D: Spark ADLS Gen2 recovery

1. Create `stpublicdlcc03` with hierarchical namespace enabled and shared-key access
   disabled.
2. Create filesystem `spark` and upload `data/titanic.csv`.
3. Grant the workspace UAMI `Contributor` and `Storage Blob Data Contributor`.
4. Grant the local submitter `Storage Blob Data Owner`.
5. Use `abfss://spark@stpublicdlcc03.dfs.core.windows.net/...` input/output paths and
   user-identity passthrough for the public-workspace diagnostic.
6. Apply only the seven ADLS resources so unrelated runtime scaling/storage drifts are
   not overwritten.

---

## 7. Validation Proof

### Validation checklist

- [x] All validation checks pass
  - [x] Terraform and Azure CLI are installed
  - [x] Azure CLI is authenticated to the confirmed subscription
  - [x] Terraform initialization succeeds
  - [x] Terraform formatting check succeeds
  - [x] Terraform validation succeeds
  - [x] Terraform plan is create-only for cc-03
  - [x] Terraform state is empty for the cc-03 root before deployment
  - [x] No unresolved Go-style environment templates exist
  - [x] Terraform role assignments satisfy the workspace, Spark Storage, CMK, compute, and user access requirements
  - [x] The visible Spark-network PowerShell script parses successfully

Preparation checks completed on 2026-09-30:

| Check | Result |
|---|---|
| `terraform fmt -recursive` | PASS |
| `terraform fmt -check -recursive` | PASS |
| `terraform init -input=false` | PASS |
| `terraform validate` | PASS |
| Fresh `cc-03` Terraform plan | `80 add, 0 change, 0 destroy` |
| `scripts/validate-plan.ps1` | PASS: all cc-03 invariants |
| Saved plan | 45,829 bytes; SHA-256 `7C876873E3FA51959C5390F09AE2043637A083D7E3C1176EF41A6692E3623601` |
| `create_compute_resources` during phase one | `false` |
| Embedded Terraform Spark action | Absent |
| Embedded Terraform workspace ACL action | Absent |
| Original FQDN rules | Present |
| Workspace initial public access | Disabled |
| Workspace `provisionNetworkNow` | `false` |
| `SecurityControl=Ignore` | Present on all validated taggable resources |
| `cc-03` resource group | Does not exist |
| `stsparkcc03` | Available |
| `acrsparkcc03` | Available |
| `kvsparkcc03` | Available |
| `kvcmksparkcc03` | Available |
| `cc-02` state isolation | SHA-256 verified before detaching from cc-03 root |
| PowerShell script parse | `configure-spark-network.ps1` recognized as an external script |
| Static RBAC review | PASS |
| Public single-workspace Terraform validation | PASS |
| Public single-workspace plan | `84 add, 0 change, 0 destroy` |
| Public focused plan validator | PASS: one workspace, no registry, networking disabled, CMK, compute, required tag |
| `rg-aml-ws-public-cc-03` | Does not exist |
| `stpubliccc03`, `acrpubliccc03`, `kvpubliccc03`, `kvcmkpubliccc03` | Available |
| Spark ADLS Terraform validation | PASS |
| Targeted public Spark ADLS plan | `7 add, 0 change, 0 destroy` |
| `stpublicdlcc03` | Available |
| Canada Central ESv3 quota | Compute: 100 vCPUs available; Azure ML family limit: 1000 |
| Supported ESv3 SKUs | E4s/E8s/E16s/E32s/E64s v3 all available with no subscription restriction |

The official `validate-terraform.ps1` wrapper passed tool installation, subscription
selection, Azure authentication, and template-variable scanning. Its Terraform
subcommands produced Terraform's top-level help because the wrapper's `Invoke-Tf`
parameter named `$Args` collides with PowerShell's automatic `$Args` variable. The same
required Terraform commands were therefore executed directly in visible VS Code task
terminals and passed. The cc-03 root intentionally has no state file before its first
apply; `terraform state list` correctly reports that no state file exists.

### Role Assignment Verification

- **Status:** Verified.
- **Workspace UAMI:** Azure AI Enterprise Network Connection Approver and Azure AI
  Administrator at the cc-03 resource-group scope; Storage Contributor plus Blob,
  File, Table, and Queue data-plane roles at the default Storage scope; required
  Key Vault roles at the workspace vault scope.
- **Compute UAMIs:** AzureML Data Scientist, Storage data-plane, Key Vault Secrets
  User, ACR pull/push, workspace management, and resource-group discovery roles.
- **Online endpoint UAMI:** ACR pull, Storage Blob Data Reader, AzureML Metrics
  Writer, and explicitly scoped Managed Identity Operator assignments.
- **Local Azure CLI identity:** Resource-group Reader; workspace data-scientist,
  AI-developer, and compute-operator roles; Key Vault Administrator; Storage Blob,
  File, Table, and Queue data roles.
- **Issues:** None found for the planned POC operations.

Azure Validate must independently validate this plan and set status to `Validated`
before either Terraform deployment task starts.

---

## 8. Post-Deployment Verification

1. Verify `rg-aml-ws-spark-cc-02` is deleted.
2. Verify exact `cc-03` resource names and `SecurityControl=Ignore`.
3. Verify workspace CMK and Storage encryption scope.
4. Verify workspace UAMI has Storage `Contributor`, Storage Blob Data Contributor,
   and network-connection approval permissions.
5. Verify `SparkStorageBlob` is unique, active, and Spark-enabled.
6. Verify managed-network `Active` and `sparkReady=true`.
7. Verify selected-IP ACLs on workspace, Storage, ACR, and both Key Vaults.
8. Verify compute uses UAMIs and no public IP/SSH.
9. Update root and workshop `.env` files to `cc-03`.
10. Submit and monitor the serverless Spark workshop job from the local machine.
