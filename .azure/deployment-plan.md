# Azure Deployment Plan

> **Status:** Deployed

Generated: 2026-10-05
Updated: 2026-10-29

---

## Approved Storage 07 Selected-IP Access (2026-10-29)

The user explicitly requested matching Storage 06's access configuration and
confirmed the scoped change to **`stprivatencus07` only**. The inherited
`StorageAccount_PublicNetwork_Modify` definition was read first: it explicitly
supports `SecurityControl=Ignore` on either the resource or resource group.
The narrow resource-level exclusion was selected; no other resource was tagged.

Applied through scoped Azure CLI operations:

- Merged `SecurityControl=Ignore` onto Storage 07, preserving existing tags.
- Enabled its public endpoint with default deny and the existing single approved
  IPv4 rule, matching Storage 06's selected-IP access posture.
- Kept shared-key authentication and anonymous Blob access disabled, TLS 1.2,
  trusted-service bypass, and existing resource-instance rules unchanged.

Verified at `2026-10-29T19:30:11Z`: the tag and public-access setting persisted;
all eight existing private endpoint connections retained their states; and
authenticated laptop container listing succeeded. The workspace managed network
and registry outbound rule remain `Active`. The resource group, workspace,
registry, ACR, and Key Vault were not given the tag. No registry identity,
preauthorization, RBAC, or data asset was changed.

This resolves the Storage network blocker, not proof of a completed notebook
registration. Rerun its registration cell to create and verify the data asset.
As with the existing 06 manual ingress exception, Terraform retains the private
baseline and a future apply can reset this account tag/access exception.

## Active: Approver-Only Registry Connectivity Experiment

The user approved a second workspace, `mlwprivatencus07`, in
`rg-aml-private-ncus-07`, subscription
`5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25`, region `northcentralus`.
Duplicate the existing workspace's supporting resources, managed-network
configuration, compute cluster, and compute instance. Retain both environments.
The existing `06` environment remains deployed and must not be replaced,
destroyed, imported into new state, or updated by this experiment.

Use an independent Terraform root and state. Reuse the existing workspace
module, with a fresh workspace UAMI, separate Storage/Key Vault/ACR, and matching
V1 `AllowOnlyApprovedOutbound` networking. Match the existing restricted
selected-IP ingress, not unrestricted public access. Inspect the live compute
configuration and regional capacity before provisioning.

The only approved change to the existing registry `mlrprivatencus06` is an
`Azure AI Enterprise Network Connection Approver` assignment for the new
workspace identity at registry scope. Do not add that identity to
`managedResourceGroupSettings.assignedIdentities`, grant it Azure AI Administrator
on the registry-managed resource group, change deny assignments, modify registry
backends, or create policy exemptions. Do not copy policy opt-out tags without
separate approval.

Recipe: Terraform for the new environment, followed by a scoped CLI
managed-private-endpoint experiment against the existing registry. Validate
before applying. Record role propagation, the actual outbound-rule and endpoint
states, and any exact denied action; do not broaden permissions to force success.
No automatic cleanup or deletion is authorized.

Implementation: `infra/RegistryConnectivityTest`, using the existing workspace
module and provider versions with an independent local Terraform state. No
registry module is instantiated. The registry outbound rule is deliberately a
post-deployment experiment so its expected authorization failure cannot interrupt
creation of the requested workspace and computes.

Read-only preflight confirmed the source cluster and instance both use
`Standard_F8s_v2`, no node public IPs, and user-assigned identities. Cluster
scaling is zero to four nodes with a two-minute idle timeout. Regional FSv2
dedicated quota is 100 vCPUs with 8 currently used; the duplicate requires at
most 40 more. Regional dedicated quota is 1,000 with 24 used; cluster count is
4 of 200. Capacity is not guaranteed by quota.

The new resource group does not exist. Storage, ACR, and Key Vault names ending
in `07` are available. The approved registry-scoped role resolves to built-in
definition `b556d68e-0be0-4f35-a333-ad7ee1ce17ea`.

### Experiment Validation Proof

Verified at `2026-10-29T17:04:58Z`:

- `terraform init -input=false -no-color`: passed for the independent root.
- `terraform fmt -check`: passed.
- `terraform validate -no-color`: passed, including AzAPI workspace schema.
- `terraform plan -input=false -no-color -out=tfplan`: **101 additions, zero
  updates, zero deletions**.
- Structured inspection of that exact saved plan confirmed two F8s v2 computes
  without node public IPs, no new AML registry, no writes to the original
  workspace, and exactly one existing-registry role: Network Connection Approver.
- `python -m pytest -q tests/test_private_aml_configuration.py`: **15 passed**.
  Missing pytest was restored only under the session directory; installed
  environment packages were not changed.
- The new root's local state is initially absent, as expected before its first
  apply. The original root and state were not imported, selected, or modified.
- Template-variable scan passed; no JSON variable file is used.
- Static role review confirmed normal workspace permissions remain scoped to
  the new workspace RG. No registry-managed-RG assignment or exemption exists.
- Subscription policy assignments were inspected. Activity-log investigation
  later identified an additional parent-management-group modify policy, recorded
  below. No policy exemptions or opt-out tags were introduced.
- Registry authorized identities and backing-resource IDs were snapshotted
  before the experiment. Public access remains disabled.

The supplied preflight wrapper invoked Terraform without subcommands because of
its PowerShell argument handling. Equivalent native checks above were run
explicitly and passed; the wrapper and unrelated infrastructure were not changed.

Saved plan SHA-256:
`8005DF6A41B58008B9277A3277388F15B5CD06B07CD4E67B17B06757871EFF95`.

### Experiment Validation Checklist

- [x] All validation checks pass:
  - [x] Terraform and Azure CLI installed; Azure authentication confirmed.
  - [x] Initialize the independent root and check Terraform formatting.
  - [x] Validate configuration and generate a saved plan.
  - [x] Confirm the local backend is independent and initially empty.
  - [x] Check unresolved template variables and applicable JSON inputs.
  - [x] Verify the plan creates only new resources and the approved scoped role.
  - [x] Verify matched compute sizing, scaling, and available quota.
  - [x] Run the focused private-workspace regression checks.
  - [x] Review roles and policy requirements without adding exemptions.

### Experiment Deployment and Result

The exact validated plan applied successfully: **101 resources added, zero
changed, zero destroyed**. The new workspace `mlwprivatencus07` and both
`ccncus07` and `cincus07` report `Succeeded`. The instance reports `Running`
and incurs ongoing charges. The cluster retains the source's zero-to-four-node
F8s v2 configuration. Both computes have node public IPs disabled. Workspace
image-build compute is `ccncus07`; managed network V1 is `Active`.

The approver-only managed-private-endpoint experiment **passed**:

- CLI outbound-rule creation completed successfully with
  `AllowExternalRegistry-approver-only` in `Active` state.
- The target registry's backing Blob and ACR private endpoint connections both
  report `Approved`.
- Live post-test RBAC shows the new workspace UAMI has only
  `Azure AI Enterprise Network Connection Approver` at registry scope, and no
  role assignment inherited or direct on the registry-managed resource group.
- Registry `assignedIdentities` is unchanged and does not contain the new UAMI.
  Registry-managed-group Azure AI Administrator was not required for this
  workspace identity's connection in this run.
- Normal Azure AI Administrator remains on the **new workspace RG**, not the
  registry-managed RG. The initiating operator's existing permissions were not
  reduced; this was not a least-privileged deployment-principal experiment.
- The original workspace still reports an `Active` managed network and original
  registry rule, with its existing restricted-IP/default-deny ingress intact.

The new workspace's selected-IP/default-deny ingress was copied and verified.
Initially its Storage account kept the approved IP rule, default deny, and shared
keys disabled, but public network access remained **Disabled**. Both CLI and direct
ARM updates requesting `Enabled` were modified back to `Disabled`. Activity-log
events at `2026-10-29T18:12:12Z` identify the inherited
`StorageAccount_PublicNetwork_Modify` policy under `MCAPSGovDeployPolicies`.
Authenticated laptop container listing was therefore blocked at that stage.
The later explicitly approved Storage-only tag and selected-IP access change,
recorded above, resolved this blocker without changing registry permissions or
using a default-allow firewall.

This verifies managed-endpoint creation and approval, not registry asset
authorization or application/job traffic. Both environments are retained.
Infrastructure, local state, and variable values for the new environment are
independent of the original root. No cleanup is authorized or performed.

## Applied CLI Computer IP Allowlist

The user requests interactive notebook execution, one cell at a time, rather
than PowerShell helper scripts or batch runners. Stop the automated notebook
workflow. They also request inbound access from their computer's public IP to
the existing workspace and its Storage account.

The user approved the detected single-host address and existing subscription
and region, then explicitly requested Azure CLI rather than Terraform for this
temporary exception. The proposed allowlist Terraform changes were removed
before any apply. Terraform remains the private-only baseline; a later apply can
remove the manual exception. No allowlist variables or address remain in Terraform.
The existing 22 focused regression tests still pass.

Microsoft's private-link documentation confirms selected-IP workspace ingress:
publicNetworkAccess Enabled with networkAcls.defaultAction Deny and explicit
IPv4 ipRules. These ACLs can be configured after initial workspace creation;
this workspace already exists. The shared SDK confirms the ARM rule uses a
value field, not a Storage-style action field.

Direct visible CLI commands added the single approved Storage IP while its
public endpoint was disabled, then enabled selected-IP access with default deny.
The workspace CLI update enabled public access with one /32 rule and default deny.
Live ARM readback confirms the workspace ACL, user-assigned identity, Active
managed network, AllowOnlyApprovedOutbound isolation, and Active outbound rules.
Storage readback confirms one allowed IP, default deny, and shared keys disabled.
An independent authenticated `az storage container list --auth-mode login` now
succeeds from the computer; the previous upload-connectivity blocker is resolved.

No registry, Key Vault, ACR, private endpoint, identity, compute, or outbound
network setting was changed. No new environment, endpoint deployment, or asset
sharing was performed. Notebook mutation switches remain false.
Continue in the actual notebook editor one cell at a time. Its kernel starts,
but the cell execution tool returned a selected-model-unavailable error; do not
silently substitute batch scripts. The user can execute a cell with Shift+Enter.

## Pending Expanded Foundations Notebook Scope

The user intentionally enabled all foundation mutation switches and requested a
review before further execution. Pause mutations until the following choices
are confirmed. Interactive notebook 01 output and notebook 02's upload/readback
of `workshop-taxi-data:1` are verified. The user chose to reuse environment
version 1 rather than create another version.

- Finish notebook 04 model registration and notebook 05's managed-identity
  command job, one notebook cell at a time.
- Notebook 06 deploys `blue`; notebook 07 deploys `collector` under the same
  endpoint. Each configures one Standard_DS3_v2 replica, so running both incurs
  two continuously billable replicas. Quota, name availability, and configured
  endpoint identity permissions require preflight before creation.
- The configured collector datastore is now `workspaceblobstore`. Microsoft
  supports workspace Blob Storage for collection; no new ADLS account or
  datastore is required for this choice.
- The endpoint is currently configured with public access disabled, so laptop
  scoring is not enabled by the workspace/Storage exceptions alone. Choose
  either selected-IP endpoint ingress using the workspace ACL or execution from
  an approved privately connected host. Do not silently enable endpoint ingress.
- Both promotion flags are currently true: notebook 06 promotes blue to 100%;
  notebook 07 subsequently promotes collector to 100%. Confirm the intended
  traffic behavior instead of treating the two flags as independent outcomes.
- Notebook 08 needs the exact registry resource-instance rule on source Storage.
  The existing workspace/data-scanner rules do not include this registry.
  A read-only registry model-list operation succeeds from the computer; this
  does not prove that asset sharing will succeed. Keep the registry and its
  backing resources private and verify each immutable shared version.

No endpoint exists in the target workspace at review time. No expanded-scope
deployment, traffic promotion, or sharing rule has been applied by the assistant.
Keep existing Terraform unchanged and use direct scoped CLI operations only for
approved access changes. Do not restore batch runners or PowerShell helpers.

## AzureMLManagedVnet Development Deployment (2026-10-28)

The user approved the session plan to rename only the infrastructure root to
`infra/AzureMLManagedVnet` and retain one private workspace, external registry,
compute instance, and compute cluster. The user then clarified that this is a
single development project: all user-managed resources now share
`rg-aml-private-ncus-06`, not three separate groups. Azure ML still creates its
required registry backing-resource group automatically.
Use managed identities and AML-managed networking, not customer-VNet injection.

The new workspace Key Vault must have purge protection disabled and the required
seven-day soft-delete retention. Keep Microsoft-managed encryption and omit CMK.
Remove implicit workspace permanent deletion; retain explicit scoped teardown
approval and provider resource-group safeguards.

Keep all relevant endpoints private. Do not add NSPs, policy-exemption resources,
ineffective laptop IP exceptions, or source-storage exceptions for native registry
sharing. The user explicitly requested the development-only
`SecurityControl=Ignore` tag, which is now supplied through the local/example
variable file for the new project group and Terraform-managed resources.
This intentionally opts out of applicable tag-conditioned policies; it is not
silently treated as a cosmetic label or applied to existing environments.
Private settings and keyless access remain explicit in Terraform.
Native sharing and private-host SDK/job smoke tests remain deferred.

Implementation and local validation are approved. Reconfirm Azure target/names,
policy, quotas, permissions, and costs, then obtain approval of a fresh saved
Terraform plan before provisioning. No commits, CI/CD, online endpoint deployment,
automatic workshop registration, or changes to other live environments.

### Private Baseline Deployment Proof (Before CLI Exception)

The approved platform deployment completed through visible VS Code terminals.
The manual selected-IP exception above supersedes this section's private-only
ingress and no-drift observations; a new Terraform plan will see that exception.
The final full Terraform plan reports **no changes**, and its exact-plan checker
confirms zero additions, removals, updates, or replacements.
Final plan SHA-256:
`EB51817F248BEA4D9C7F1E8392E74705CBFC9D16C877FCFDD81A8890AD8CAA65`.

| Live check | Verified result |
|---|---|
| Project layout | One workspace `mlwprivatencus06` and one registry `mlrprivatencus06` in `rg-aml-private-ncus-06`; registry backing group remains Azure-managed |
| Workspace | Succeeded, public access Disabled, user-assigned identity, identity-based system datastores |
| Managed network | Active, V1, AllowOnlyApprovedOutbound |
| Registry connection | One Active registry-target rule; Azure created Active blob and ACR Dependency rules linked to it |
| Registry backends | Public access Disabled, Storage shared keys disabled, ACR admin authentication disabled, managed private connections Approved |
| Compute | Instance and cluster Succeeded, UAMIs, public node IPs disabled; instance owner matches requested human and SSO is false; cluster scales 0-4 |
| Workspace dependencies | Storage, ACR, and Key Vault public access Disabled; Storage shared keys/anonymous blobs and ACR admin disabled; no Storage IP rules |
| Vault lifecycle | Purge protection not enabled in Azure and false in Terraform state; mandatory seven-day soft delete retained |
| Customer private endpoints | All ten Succeeded and Approved; API/ACR private DNS A records use the project subnet |
| Scoped access | All 39 Terraform-managed role assignments match their live principal, scope, and role definition |
| Local checks | 22 focused tests pass; formatting checks and both affected Terraform roots validate |

The one-time outbound-rule migration required an additional live-state check:
the two concurrent removals reported success, but Azure still returned the
original blob rule. Removing only that same approved rule sequentially and
confirming its absence allowed the registry-target rule to succeed. The exact
internal Azure cause is not claimed. No workspace, registry, compute, or customer
private endpoint was replaced during this correction.

### Foundations Notebook Trial

The user approved running foundations notebooks 01-05 against this deployment,
without online endpoints, traffic promotion, or registry sharing. The previous
workshop configuration was backed up before updating only the deployed Azure ML
identifiers and foundation switches. Unrelated settings and source notebooks
were preserved. Execution ran visibly in local VS Code task terminals, with
separate executed copies under ignored workshop outputs.

- Notebook 01 completed its read-only workspace/compute/asset tour.
- Notebook 03 registered and retrieved `workshop-taxi-environment:1`.
  The only resulting Azure job, `imgbldrun_694999f`, reports Completed.
- Notebooks 02, 04, and 05 failed during Blob upload with `AuthorizationFailure`.
  No workshop data/model asset or submitted workshop command job was found in
  readback. No online endpoint was created.
- The client resolves the workspace Storage hostname to public addresses instead
  of its approved private Blob address, `10.30.1.6`. Storage public access is
  Disabled and the caller already has Storage Blob Data Contributor. An
  independent authenticated Azure CLI Blob read fails under the same network
  restriction. This is a private client connectivity blocker, not evidence that
  broadening RBAC or enabling keys/public access is required.
- All foundation mutation switches were returned to false after the attempts.
  Notebook 06-08 operations were not run.

Private-client routing/Studio access, private-host command-job execution, and
native workspace-to-registry asset sharing remain deferred. No CI/CD, NSP, CMK,
online endpoint, automatic asset promotion, or deny-assignment bypass was added.
The foundations sharing notebook remains available for later use.

### Implementation and Recovery History

- The staged deployment has now provisioned the workspace, registry, cluster,
  and instance. The managed network is Active and the instance is Running with
  private connectivity. Full post-deployment verification is not complete yet.
- Azure's activity log confirmed the remaining error: the registry-target
  outbound rule resolves its backing endpoints, and the separately declared
  blob/ACR rules caused duplicate-destination validation. The root now declares
  only the registry target.
- The user approved replacing only those two registry-specific managed outbound
  rules with one registry-target rule. Apply is staged: remove just the two
  duplicates, then inspect a fresh full plan and add only the registry rule.
  The workspace, registry, compute, and customer private endpoints must not change.
- All 22 focused regressions pass, both Terraform roots validate, and the
  transition plan has exactly one addition and two approved removals.
  Transition SHA-256:
  `87AE6BE316F20F060F84D84FD688224C996784D130D66BC1ED5369573F9CDE00`.
  Full live verification and a final no-drift plan are still required.

Earlier staged/recovery evidence:

- Earlier Azure result: the eager managed-network operation returned a service-side
  404 after workspace metadata briefly existed; Azure then rolled the workspace
  record back. The registry remains private and provisioned. The exact internal
  Azure cause is not available from the client error and is not claimed as known.
- The new root now uses Azure ML's documented automatic network provisioning on
  the first compute: create workspace, create its private endpoint, then create
  compute. `provision_network_now=false` only in this root; shared defaults remain
  true. Compute creation has a bounded extended timeout for first-network setup.
- All subsequent shell commands now run in visible VS Code task terminals,
  with command tracing and unredirected output, as explicitly requested.
- Visible validation and saved-plan checks pass: the staged plan adds 26 remaining
  resources, with no updates, replacements or deletions. The existing private
  registry and one-project layout are unchanged.
- Staged plan SHA-256:
  `F93E9E1032EB61733504F7C0500E948EAC370955803C833D5C7322AABED9B2EF`.
- This is a documented alternative provisioning sequence, not a claim that the
  Azure service-side failure is resolved. Apply and live readiness verification
  are still required; no destructive recovery is authorized.
- First `ncus06` apply partially succeeded: the single project group, private
  registry, identities, workspace dependencies and their private endpoints exist.
  Workspace/compute did not complete.
- Two concrete template errors were found: AzAPI 2.3 could not validate the
  workspace API at apply, and redundant writes to registry-managed resources
  were denied by its service-owned deny assignment.
- Recovery corrects AzAPI to 2.13 in this root, retains shared validation defaults
  for other roots, and replaces protected writes with read-only private-access
  postconditions. The deny assignment is untouched.
- Live reads prove registry-managed Storage and ACR already have public access
  disabled. The registry service already granted the workspace UAMI Azure AI
  Administrator, which covers their reads and private-endpoint approvals.
- Recovery tests pass: 20 focused tests. Both affected roots validate, and the
  fresh recovery plan has 27 additions, no changes or deletions. No duplicate
  project group, workspace, or registry is added.
- Latest correction: one workspace and one registry in one project resource
  group. Redundant owner Reader and workspace network-approval role assignments
  were removed so shared scopes do not produce duplicate RBAC writes.
- The previous three-group 128-create plan is obsolete and must not be applied.
  A fresh single-group plan and fingerprint are required.
- Updated focused regressions pass: 18 tests. The single-group root validates.
- The infrastructure root is now `infra/AzureMLManagedVnet`; its ignored inputs
  and empty state were preserved, and provider/module metadata was reinitialized.
- New Key Vault purge protection is false; seven-day soft delete remains.
  The unconditional workspace permanent-delete provisioner was removed.
- Laptop and registry source-storage public-access exceptions are disabled.
  The customer-subnet NSG and association are managed in Terraform.
- The pinned provider's supported `storage.data_plane_available=false` feature
  is enabled in this root. Legacy queue data-plane logging is disabled only for
  this root; Azure Monitor diagnostics remain enabled. Other roots keep their
  previous legacy-logging default, with a state-address move for the counted
  resource.
- The documented `managedNetwork.managedNetworkKind` placement was corrected
  and workspace API schema validation enabled.
- All 16 focused tests pass. Both the renamed root and existing private dev/prod
  root validate. The retained notebook schema and renamed documentation links
  validate. No unrelated H2O remediation was performed.
- The user reconfirmed subscription
  `5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25`, North Central US, suffix `06`, the existing
  human compute owner, and current Azure CLI deployment authentication.
- Proposed names are `mlwprivatencus06`, `mlrprivatencus06`,
  `stprivatencus06`, `acrprivatencus06`, and `kvprivatencus06`. Storage/ACR/Key Vault
  names are available, and no matching target resource groups exist.
- Refreshed ML quota has 100 FSv2 dedicated vCPUs available, 1,000 regional
  dedicated vCPUs, and 200 clusters/instances; F8s v2 is offered. Required peak
  compute is 40 vCPUs. Capacity is not guaranteed by quota.
- The examined purge-protection deny applies to Managed HSM, not the associated
  workspace Key Vault. No policy change or exemption is authorized.
- Next: generate and inspect the fresh private-only saved plan, record current
  validation proof, and obtain its explicit apply approval.

### Earlier Validation Steps and Proof

**Current recovery plan:** verified at `2026-10-28T15:01:51Z`.
The registry and its private backing resources already exist. The supported
AzAPI 2.13 provider now validates the workspace API, and recovery adds only the
27 remaining resources with no updates, replacements, or deletions.
All 20 focused tests and both affected root validations pass.
The registry service's live Azure AI Administrator grant covers the backing
resource reads and private-endpoint approval; redundant denied human-user writes
were removed, not bypassed.
Both read-only backend privacy postconditions pass against live `Disabled`
values. No deny assignment, registry backend, or managed-group role is changed.

Current recovery plan SHA-256:
`6363E192FD3FA9170AC06F98DBCA22D40903737D4C50ABA9DEBF5DAB3856BCD7`.

All prior full-creation plans below are historical and must not be reapplied.

**Latest single-project plan:** verified at `2026-10-28T14:25:53Z`:
124 creations, no changes or deletions; exactly one workspace and one registry
wired to the single project group `rg-aml-private-ncus-06`.
All 18 focused tests pass and Terraform validation passes.
The requested `SecurityControl=Ignore` tag is present on the new project group
and applicable Terraform-managed resources. Private access and purge protection
off remain explicit. Duplicate Reader/network-approval role scopes were removed.

Current saved plan SHA-256:
`E9B5AFBA7F2CA947D36A72B2522F56344DA1187EA9F3FBF19DD3D8D1207D02E8`.

The registry parent ID is computed because its module obtains subscription
context during apply; its group input references the shared project group.
Verify that actual parent ID and backing resources after apply.
The three-group evidence below is superseded and is retained only as history.

Validation evidence recorded at `2026-10-28T14:01:11Z`:

| Check | Result |
| --- | --- |
| Authenticated context and permissions | Confirmed target subscription and current CLI user; Owner and User Access Administrator remain available |
| Formatting and initialization | Passed for the renamed root and modified shared files; real variables and plan remain ignored |
| Terraform validation | New managed-VNet root and existing private dev/prod root pass |
| Focused regressions | 16 passed; newly added lifecycle, private provisioning, subnet ownership, and API-placement tests first reproduced their failures |
| Notebook and documentation | Retained notebook schema and all renamed stack links pass |
| Fresh live plan | 128 to add, 0 to change, 0 to destroy; target state is still empty |
| Exact plan inspection | Purge protection false and seven-day soft delete; public access disabled on workspace/registry/dependencies; no CMK, NSP, exemptions, auto-purge resources, legacy data-plane queue logging, or changes to other stacks |
| Compute/network/identity inspection | V1 approved-outbound managed network, identity system datastores, private compute, explicit human owner, SSO disabled, 0-4 cluster, ten private endpoints, Terraform-owned customer subnet NSG |
| Registry identity inspection | No human principal embedded in registry creation; known role scopes target only new ncus06 groups |
| Review | Direct source and saved-plan review completed with no blocking code findings; simplification made no additional changes |

Saved plan SHA-256:
`4B64BE8FB7C5EEBFCEF01D9F11D368FDE5C3CF273F0B04A61DB1EBF4DBEF780C`.

The provider marks empty Storage IP-rule fields as computed; actual empty
IP rules must be verified after apply, not assumed from the plan.
Public access is explicitly disabled regardless. Live resource states, private
endpoint approval, managed-network readiness, effective policy controls, and RBAC
remain post-apply checks. SDK/job connectivity and registry sharing are not
reported as tested.

Historical deployment and cleanup evidence follows; it does not authorize
reusing a stale plan or changing the old protected vault.

---

## Private Azure ML Workspace and External Registry (2026-10-27)

### Current Authorization: Cleanup Only

**Result:** Cleanup completed. Direct Azure checks confirm that all three
approved resource groups are absent, and the isolated Terraform state is empty.
The Key Vault remains protected and soft-deleted, with scheduled purge at
`2026-11-04T13:12:08Z` as reported by Azure. No purge was requested.

The initial teardown removed all tracked resources except the network resource
group, where Terraform's deletion safeguard found a policy-created NSG. Direct
inspection confirmed the NSG belonged to the approved failed-deployment network
and had no subnet or NIC attachments. Only that detached NSG was removed, then
a reviewed one-delete saved plan removed the remaining network group. The
provider's resource-group deletion safeguard was not disabled.

The obsolete creation plan was removed; the state backup and cleanup evidence
remain in the session workspace. Repository templates and workshop assets are
retained. No other deployments were changed, no NSPs were added, and no new
deployment was performed.

The user explicitly approved deleting only these failed-deployment resource
groups in subscription `5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25`:

- `rg-aml-private-ncus-05-workspace`
- `rg-aml-private-ncus-05-registry`
- `rg-aml-private-ncus-05-network`

The saved destroy preview contains 50 deletions and no creations or updates.
Programmatic inspection verified that every Azure resource ID is scoped to
one of these three groups. A pre-cleanup state backup is retained in the session
workspace. The protected Key Vault will be soft-deleted, never purged.

The user selected **cleanup only** after clarification: do not redeploy, add
NSPs, add policy-ignore tags or exemptions, or change existing deployments and
workshop assets. Earlier deployment and proposed rebuild sections below are
historical and do not authorize any new provisioning.

Destroy plan SHA-256:
`5BB7F7EEBCAA51826E48791E87AF1D61622F71A755E885E6F1B3393C9E8E6710`.

#### Cleanup Validation Checks

- Confirm the subscription and all three group-specific deletion approvals.
- Preserve the current isolated Terraform state before cleanup.
- Run Terraform validation and a refreshed `plan -destroy`.
- Inspect the saved plan: deletes only, limited to the exact approved groups;
  no creation, replacement, update, purge, or external scope.
- Verify the saved-plan fingerprint immediately before applying it.
- After cleanup, check each resource group directly, confirm empty managed
  Terraform state, and confirm the Key Vault is soft-deleted rather than purged.
- Region capacity and build/deployment checks are not applicable: this operation
  creates no resources and does not run workshop assets.

**Goal:** Add an independently deployed Terraform stack with one private Azure ML
workspace, one private Azure ML registry, one compute instance, and one compute
cluster. Retain the workspace Key Vault and use Microsoft-managed encryption;
do not provision CMK resources or change CI/CD.

**Implementation:** Reuse the existing private Azure ML modules without changing
existing deployment defaults. Make the compute instance's human owner explicit
so infrastructure can be deployed using a managed identity. Add a foundations
notebook based on `notebooks/asset_sharing/sharing_assets_registries_workspaces.ipynb`
for registering workspace assets in the external registry.

**Approved networking:** Create a customer VNet and private DNS for inbound
private endpoints, separate from the AML-managed VNet used by compute and
approved outbound traffic. Keep the workspace, registry, and registry-managed
storage/ACR private. Add optional, selected-public-IP access to workspace
Storage, Key Vault, and ACR for laptop testing; this does not provide direct
laptop access to the private workspace or registry. Enable only the exact
registry resource-instance storage exception needed for native asset sharing.
Service firewalls remain deny-by-default.

**Approved notebook:** Add `08_register_assets_to_registry.ipynb` to
`workshop/notebooks/01_foundations`. Use existing registered models, environments,
and data assets, resolve immutable source versions, require an explicit mutation
switch, refuse existing destination versions, and verify destination readback.

**Execution boundary:** The user subsequently requested deployment and confirmed
North Central US, suffix `05`, the current Azure CLI user for Terraform
authentication, managed identities for service access, the detected laptop IP,
and the prepared network cost model. Apply only the reviewed, create-only saved
Terraform plan. Do not change existing deployments or register workshop assets.
Private client connectivity is explicitly deferred by the user.

**Verification:** Terraform formatting and validation, focused regression tests
for configuration and asset registration, notebook JSON/schema and code syntax,
and readback of registered assets when the notebook is deliberately executed
against Azure.

**Recipe:** Existing modular Terraform, with a new independent root at
`infra/private-workspace-registry`. No azd conversion, state migration, CI/CD, or
live asset registration is authorized. Real deployment identifiers and laptop IP
rules are stored only in the ignored `terraform.tfvars`.

**Confirmed Azure target:** Subscription
`5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25`, `northcentralus`, location code `ncus`,
prefix `aml`, purpose `private`, suffix `05`. Proposed workspace
`mlwprivatencus05` and registry `mlrprivatencus05`; new customer VNet
`10.30.0.0/16` does not overlap the subscription's existing VNets.

**Live quota and policy discovery:** Azure ML has 100 available FSv2 dedicated
vCPUs, 1,000 available total regional dedicated vCPUs, and 200 available compute
clusters/instances. The new instance plus maximum cluster scale requires 40
FSv2 vCPUs. F8s v2 is offered and has no subscription SKU restriction. Quota does
not guarantee physical allocation. The signed-in deployment user has Owner and
User Access Administrator permissions. The examined resource-creation deny
policies target legacy Classic resource types, not this modern resource set.
No policy exemption or policy modification is authorized.

**Cost and connectivity approval:** The user accepted continuing with the
prepared Standard Firewall / F8s v2 / two Premium ACR design after reviewing an
approximate continuously running retail cost of USD 1.3k/month before usage and
taxes. No VPN/Bastion/jumpbox is included; private endpoint access will be arranged
after deployment.

**Local verification so far:** Both the new root and the existing private
dev/prod root pass `terraform validate`. All seven new registry notebook tests
pass and the notebook schema is valid. The final focused run has 12 passing
tests with one pre-existing H2O golden-data test deselected. The full selected
suite reproduced that unrelated failure; the failing test and its target
notebook are unchanged from HEAD.

### All validation checks pass

- Terraform installed and offline provider initialization: passed.
- Terraform formatting check: passed for the new root and edited shared files.
- New root `terraform validate`: passed.
- Existing private dev/prod root `terraform validate`: passed.
- Notebook behavior, Python syntax, notebook schema, and new documentation links:
  passed.
- Static identity review: workspace/compute UAMIs and registry SMI have scoped
  data-plane/registry roles; the human owner has workspace/data/registry access;
  managed private endpoint approvals and managed-resource-group exceptions are
  wired explicitly.
- Authenticated Azure preflight, subscription/location confirmation, default
  local backend, create-only live plan, policy review, quotas, regional SKU
  eligibility, resource-group isolation, and global Storage/ACR/Key Vault name
  availability: passed.
- This is a first deployment with no existing state file; the empty inventory
  is expected, not a missing remote backend. `terraform init`, default workspace
  selection, and writing the saved plan to the backend directory passed.
- Private client routing/DNS testing is deferred by explicit user choice.
  Resource provisioning, endpoint approvals, network controls, and live RBAC
  will be verified after apply; laptop data-plane reachability is not promised.

**Azure deployment gate:** Apply requires the user's approval of the saved
128-create plan. It has no updates, replacements, deletions, or CMK resources.
No live workshop asset registration is authorized.

## 7. Validation Proof

### Latest Staged-Provisioning Proof

- The visible VS Code validation task ran focused regressions, formatting,
  validation for both affected roots, a fresh authenticated plan, and exact
  saved-plan requirement assertions.
- The plan has 26 additions and no updates, replacements or deletions; exactly
  one workspace, one existing private registry and one project group.
- Workspace creation defers managed-network provisioning; the existing compute
  dependencies require the workspace private endpoint first.
- Registry backend read-only private-access checks still pass. Private access,
  managed identities, disabled vault purge protection and seven-day soft delete
  are unchanged. No deny assignment or protected backend write is added.
- Azure's automatic-on-compute behavior is grounded in the official managed
  network guide. The previous internal 404 cause remains unconfirmed.
- No live success claim is made for the workspace, compute or managed network
  until the staged apply and live verification complete.

Current staged saved plan SHA-256:
`F93E9E1032EB61733504F7C0500E948EAC370955803C833D5C7322AABED9B2EF`.

### Current Recovery Proof

- First apply created the private registry and dependencies but stopped before
  workspace/compute completion.
- Runtime errors were reproduced and traced to unsupported embedded AzAPI 2.3
  workspace schema and redundant writes forbidden by the registry-managed-group
  deny assignment.
- AzAPI 2.13 installed with signature verification; AzureRM stayed at 4.32.
  Shared schema validation remains opt-in so other roots keep their defaults.
- Root and existing private root validate; all 20 focused tests pass.
- Fresh plan: 27 additions only, zero changes/deletions/replacements.
- Exactly one project group and one registry remain; the single workspace is
  among the remaining creations.
- Registry backend read-only postconditions pass in the plan's check results;
  actual Storage and ACR are already private. The deny assignment is untouched.
- New Key Vault provider state confirms purge protection false and private
  access; Azure retains its mandatory seven-day soft delete.

Verification timestamp: `2026-10-28T15:01:51Z`.
Current saved plan SHA-256:
`6363E192FD3FA9170AC06F98DBCA22D40903737D4C50ABA9DEBF5DAB3856BCD7`.

### Latest Single-Project Provisioning Proof

The current saved plan supersedes the earlier three-group plan:

- 124 create-only resources, exactly one Terraform project resource group,
  one workspace and one AML registry.
- Workspace parent is the new project group; the registry uses the same group
  input and its computed parent will be verified after creation.
- Purge protection false, mandatory seven-day soft delete, private public-access
  settings, managed identities, registry backing-resource network controls, and
  ten private endpoints verified in the plan.
- Explicit development tag present; no NSPs, CMK, policy-exemption resources,
  legacy queue data-plane logging, or changes to existing environments.
- Duplicate common-group RBAC assignments removed; 18 focused tests and root
  validation pass. Direct code/plan review has no blocking findings.
- Actual live readiness, endpoint approvals, network controls and roles remain
  post-apply checks; no Azure resources have been created in this attempt.

Verification timestamp: `2026-10-28T14:25:53Z`.
Current saved plan SHA-256:
`E9B5AFBA7F2CA947D36A72B2522F56344DA1187EA9F3FBF19DD3D8D1207D02E8`.

### Current AzureMLManagedVnet Provisioning Proof

The current operation is the user-approved fresh `ncus06` development deployment,
not the historical `ncus05` cleanup below. Detailed results are recorded in
**Current Validation Steps and Proof** above.

- New root `terraform init`, `fmt -check`, and `validate`: passed.
- Existing affected root `terraform validate`: passed.
- Focused regression tests: 16 passed; notebook schema and documentation links
  also passed.
- Fresh authenticated `terraform plan -input=false -no-color -out=tfplan`:
  128 creates, zero changes or deletions.
- Programmatic `terraform show -json tfplan` inspection: purge protection false,
  seven-day soft delete, private public-access settings, correct managed-network
  API shape, user-assigned compute/workspace identities, explicit human owner,
  system-assigned registry identity, scoped roles and owned subnet NSG.
- Names, quota, regional SKU availability, target isolation, current permissions,
  and relevant inherited deny policy definitions were checked.
- Actual deployment and data-plane/runtime checks are not yet claimed.

Verification timestamp: `2026-10-28T14:01:11Z`.
Current saved plan SHA-256:
`4B64BE8FB7C5EEBFCEF01D9F11D368FDE5C3CF273F0B04A61DB1EBF4DBEF780C`.

### Current Cleanup-Only Proof

Cleanup validation recorded at `2026-10-28T13:09:54Z` (execution-host UTC):

- The user confirmed each of the three exact resource-group deletions and then
  selected cleanup-only. No redeployment or NSP implementation is authorized.
- `terraform validate -no-color`: passed.
- `terraform state pull`: pre-cleanup backup retained in the session workspace.
- Refreshed `terraform plan -destroy -input=false`: passed, 50 to destroy,
  zero to add or change.
- Programmatic saved-plan verification: all managed actions are deletes, every
  Azure resource ID is in the confirmed subscription and one of the three
  approved groups, and the nine role-assignment actions only remove existing
  scoped roles.
- Direct Azure resource reads confirmed the ACR and protected Key Vault still
  exist despite incomplete generic resource-list results.
- Saved destroy-plan SHA-256 was rechecked successfully. Key Vault purge on
  destroy remains disabled; the vault has a seven-day protected soft-delete
  retention period.
- Build and regional provisioning checks are not applicable to cleanup-only.
  Final group absence, Terraform-state emptiness, and vault soft-delete readback
  will be verified after applying the approved destroy plan.

The provisioning proof below is historical; it does not authorize creation.

Validated checks recorded at `2026-10-27T16:57:26Z` for
`infra/private-workspace-registry`:

| Check | Command / evidence | Result |
| --- | --- | --- |
| Authentication | `az account show`, scoped role-assignment inspection | Confirmed target subscription; signed-in user has Owner and User Access Administrator |
| Initialization | `terraform init -input=false` | Passed; existing pinned provider versions reused |
| Formatting | `terraform fmt -check -recursive` | Passed |
| Configuration | `terraform validate -no-color` | Passed |
| Backend isolation | `terraform workspace show` and fresh-state inspection | Default workspace; no prior state, as expected for this independent root |
| Live plan | `terraform plan -input=false -no-color -out=tfplan` | 128 to add, 0 to change, 0 to destroy |
| Exact plan invariants | Programmatic inspection of `terraform show -json tfplan` | All managed actions are create-only; no CMK; private workspace/registry/backends; approved managed-network egress; identity datastores; private compute; correct human owner; scoped RBAC |
| Supporting-service access | Programmatic inspection of the saved plan | Exact laptop IP rules; deny-by-default firewalls; shared storage keys and ACR admin disabled; Key Vault purge protection enabled |
| Regional eligibility | Azure ML quotas, VM SKU restrictions, provider locations, ML size listing | North Central US supports workspace, registry, F8s v2, and the required peak 40 vCPUs within the available 100 |
| Policy | Applicable assignment/definition review | Planned modern types are not blocked by the examined Classic-resource deny policies; four-node cluster is below the enforced ten-node VMSS limit |
| Name/address isolation | Storage/ACR/Key Vault availability, resource-group and VNet inventory | New names available; no matching target groups or overlapping customer VNet CIDR |
| Notebook | Focused pytest suite and nbformat validation | Seven tests passed; notebook schema/code syntax valid |

Saved plan SHA-256:
`D6FB5D500A8E647A896DB3F2602C41503E020CA1F25803DD8ADB234B31834F45`.

The bundled PowerShell preflight wrapper dropped its Terraform arguments and
printed Terraform usage. Its reported Terraform failures were not accepted as
validation evidence: the same initialization, formatting, validation, and plan
commands were executed directly and passed. `terraform state list` reports no
state because this root has never been applied; no existing state was copied,
fabricated, or imported. Private connectivity remains explicitly out of scope
until the operator arranges it after deployment.

### First Apply and Recovery Findings

The approved apply failed during registry initialization after approximately
20 minutes. The exact activity-log error was `UnmatchedPrincipalType`: the
registry service tried to assign a human deployment user as a service principal.
The registry-managed resource group was rolled back by Azure. The private root
retains 58 state entries; existing deployments were not changed or deleted.
Workspace and compute provisioning have not completed.

The registry input has been corrected to include the workspace UAMI and only
explicitly supplied service-principal object IDs. A regression test reproduces
the original accidental human-principal inclusion.

Live governance evidence also shows that inherited modification policies force
Key Vault and Storage public access to `Disabled`, and disable Storage shared-key
authentication. Key Vault's public access was changed by policy despite the
planned laptop exception. These controls must not be bypassed with ignore tags
or unapproved exemptions. The selected laptop-access/native-sharing design needs
a policy-compliant revision before retrying.

No retry, destructive cleanup, policy change, or workshop asset registration has
been performed. A new validated saved plan and user approval are required before
the next apply; the first saved plan is stale against the partial deployment.

---

## Standalone Serverless Model Consumption Notebook (2026-10-06)

- Added `04_consume_registered_model_serverless_spark.ipynb` and standalone Spark
  job definition `titanic-serverless-model-consumption.yaml`; no pipeline wrapper,
  endpoint operations, local Spark, or infrastructure change.
- Reused checksum-verified registered model staging and shared output/runtime
  validation. Original inference notebook results and model version 1 retained.
- Verified job `titanic-model-consumption-b239a7b8fb48`, `Completed`, type `spark`,
  `_azureml.ComputeTargetType=amlspark`, E4s v3 resources, runtime 3.5.
- Manifest: actual Spark `3.5.5.5.4.20260824.232707473`, master `yarn`, application
  `application_1791321422909_0001`; registered asset ID, original URI and content
  SHA-256 matched selected model version 1.
- 891 unique predictions, valid binary classes and finite probabilities;
  parity passed against the completed inference pipeline's CSV.
- Canonical notebook has actual executed cells and prediction tables saved.
- Ignored configuration has submission disabled and the successful standalone
  job name set for reuse. Read-only attachment snapshots were not edited.
- Final focused regression suite: 27 passed. Four canonical notebook code cells
  executed successfully; prediction tables and runtime/parity evidence persisted.
  Temporary execution runner removed. Existing inference pipeline and endpoint
  default retained; AML compute cluster remains at current/target nodes `0/0`.

## Serverless Spark Inference Pipeline (2026-10-06)

**Goal:** Submit a plain Azure ML serverless Spark 3.5 inference pipeline and stop
the batch endpoint migration, as requested by the user.

**Scope:**

- Reuse `mlwpublicncus04` in North Central US and registered model
  `workshop-titanic-spark-model:1`; do not retrain or replace it.
- Replace notebook 03's endpoint workflow with
  `03_run_titanic_spark_inference_pipeline.ipynb`.
- Submit `titanic-spark-inference-pipeline.yaml` with the Python jobs SDK.
- Run exactly one `spark_score` child using managed Spark 3.5, user identity,
  serverless E4s v3 resources, and direct URI input/output.
- Resolve the immutable registered model artifact and use a unique ADLS prediction
  directory for each run.
- Save real notebook outputs and verify runtime, model ID, all 891 PassengerIds,
  finite probabilities, binary classes, and parity against the existing reference.
- Do not create, invoke, promote, update, or delete endpoints. Existing
  `titanic-spark-batch-ncus04` deployments and its `sparkml-v1` default are retained.
- No Terraform, persistent compute, storage, environment, or datastore creation is
  needed. Reset the abandoned batch switches immediately.

**Verification:**

- [x] Replace the active YAML/component and notebook endpoint flow.
- [x] Reuse native scoring and strict output/runtime verification.
- [x] Disable abandoned batch mutation switches.
- [x] Pass focused schema, notebook, runtime, and prediction tests.
- [x] Run and complete the serverless inference pipeline.
- [x] Verify actual `amlspark`/`Serverless` execution, model, counts, and parity.
- [x] Persist execution evidence, reset submission switch, and clean temporary files.

Preflight: all eight direct-inference tests passed, including the actual SDK
pipeline job schema, input proxy updates, and serialized Spark `direct` output.
The six existing training and legacy artifact checks also passed. Registered model
loading and output parity remain gated on the live managed Spark run.

First direct run `titanic-spark-inference-304bf0ba98e6` reached managed serverless
Spark, then failed reading the registered model through `stpublicncus04`'s DFS
endpoint (409: BlobStorageEvents/SoftDelete unsupported). The workspace is healthy
(`Succeeded`, North Central US). Preserve storage protections and copy the exact
registered artifact with the identity-authenticated Blob SDK into existing Spark
ADLS. Use content-addressed, checksum-verified files and a provenance manifest;
do not read the mutable training folder or modify infrastructure.

Model-copy preflight: 18 focused tests pass. Tests confirm identity-based Blob
reads without retrieving datastore secrets, content-addressed copies, no overwrite
on reuse, checksum mismatch rejection, unsafe-path rejection, saved Spark metadata,
and original registered URI/content checksum validation in the runtime manifest.

### Verified direct inference result

- Pipeline: `titanic-spark-inference-07036a90579b`, `Completed`.
- Child: `48fc24eb-61e1-4f0f-9026-c4d083d985ff`, `Completed`,
  `compute=Serverless`, `_azureml.ComputeTargetType=amlspark`.
- Actual Spark: `3.5.5.5.4.20260824.232707473`; master: `yarn`;
  application: `application_1791317656690_0001`.
- Registered model: `workshop-titanic-spark-model:1`; original artifact URI and
  model asset ID exactly match the runtime manifest.
- Verified copy SHA-256:
  `095a67b25284b45b93f3205d5c517dc4f5818a76cc87348baf6355d054e0e877`.
- Input/output: 891 rows, exact unique PassengerIds, binary classes, finite
  probabilities, and reference parity at tolerance `1e-9`.
- ADLS output:
  `abfss://spark@stpublicdlncus04.dfs.core.windows.net/pipelines/titanic-inference/titanic-spark-inference-07036a90579b/`.
- Local CSV:
  `workshop/outputs/titanic_spark_inference/titanic-spark-inference-07036a90579b/predictions.csv`.
- All four canonical notebook code cells executed; actual outputs are saved.
- Submission disabled; ignored configuration retains the successful job name for
  readback without duplicate submission. Abandoned batch switches remain disabled.
- Final focused suite: 19 passed; canonical notebook has four executed cells and
  no error outputs. Temporary runner and VS Code task removed; no runner remains.
- Registered model version 1 and existing endpoint default `sparkml-v1` unchanged.
  AML cluster stayed idle: current/target nodes `0/0`, allocation `Steady`.

## Previous Native Spark Batch Extension (superseded 2026-10-06)

This migration was abandoned at the user's request. Deployment `native-spark-v1`
and component versions 1 and 2 were created, but their first submitted pipeline
`pipelinejob-2b430a64-715f-4bde-bc27-bf8bb7a81837` failed in its native Spark child.
No default promotion occurred. The checks and contracts below are historical,
not pending work for the direct inference request.

**Goal:** Make batch endpoint `titanic-spark-batch-ncus04` invoke a managed
serverless Spark 3.5 inference job rather than a model batch worker with local
PySpark.

**Scope:**

- Reuse `mlwpublicncus04` in North Central US and registered model
  `workshop-titanic-spark-model:1`.
- Define the inference pipeline/component in checked-in YAML.
- Update the canonical batch notebook to deploy/invoke a pipeline-component batch
  deployment.
- Do not retrain or replace the registered model.
- Keep the existing `sparkml-v1` deployment until the new native Spark path has
  passed output validation.
- Verify the invoked child job is actually `type: spark`, uses runtime 3.5 and
  serverless ESv3 resources, and does not target the FSv2 AML cluster.
- Save real execution outputs in the existing notebook.

**Preparation and verification:**

- [x] Verify Spark pipeline-component support and identity/input/output contracts.
- [x] Implement YAML, native inference entry point, notebook changes, and tests.
- [x] Validate schemas, prediction contract, quota, and RBAC before deployment.
  Native model loading will be verified by the actual managed Spark invocation.
- [x] Complete Azure validation before deployment.
- [ ] Create a separate native Spark deployment and invoke it.
- [ ] Verify runtime, model provenance, output rows, and prediction parity.
- [ ] Promote the verified deployment to the endpoint default.
- [ ] Reset mutation switches and record proof.

### Native execution contract

| Setting | Value |
|---|---|
| Recipe | Existing Python SDK notebook + checked-in pipeline component YAML |
| Endpoint | `titanic-spark-batch-ncus04` (reuse) |
| New deployment | `native-spark-v1` |
| Pipeline component | `titanic_native_spark_inference:1` |
| Component YAML | `batch/titanic-spark-inference-pipeline.yaml` |
| Child job | `spark_score`, type `spark` |
| Managed runtime | Spark 3.5 |
| Serverless size | `standard_e4s_v3` |
| Spark topology | One driver and two executors |
| Model | Resolve immutable artifact URI from `workshop-titanic-spark-model:1` |
| Input | `abfss://spark@stpublicdlncus04.dfs.core.windows.net/data/titanic.csv` |
| Outputs | Unique ADLS directory per invocation: predictions CSV + runtime manifest |
| Identity | Invoking user's identity; verified Blob access to both Storage accounts |
| Promotion | Explicit switch; only after completed Spark run and output checks |
| Rollback | Existing `sparkml-v1` retained; no destructive operations |

### Native provisioning preflight

- North Central US Compute ESv3: limit 100, usage 0.
- Azure ML ESv3 limit: 1,000; total dedicated usage: 8 before this request.
- The three E4s v3 nodes require 12 VM vCPUs, within current capacity.
- Existing AML compute cluster is idle and is not the Spark job's compute target.
- Input and model pointers use explicit direct-mode bindings.
- Pipeline-component YAML loaded successfully with the installed SDK as a Spark 3.5
  serverless child with no AML compute assignment.
- The caller has Storage Blob Data Contributor on registered-model Storage and
  Storage Blob Data Owner on Spark ADLS.
- Managed Spark provides its runtime and JVM; no custom conda image build or
  `master("local[...]")` is required.

### Native validation evidence

- Focused tests: 17 passed, including Azure ML component loading and deployment
  serialization, native job-marker
  checks, Spark runtime/model manifest checks, strict prediction validation, and
  PassengerId-keyed parity.
- Python scorer/helpers and every notebook code cell parse successfully.
- The native pipeline YAML has exactly one `spark` child with runtime 3.5,
  `standard_e4s_v3`, direct URI IO, user identity, and no AML cluster assignment.
- Existing model version and legacy deployment are unchanged.
- First deployment succeeded; invocation was prevented by an SDK 1.28 readback
  class mismatch. The notebook now checks the REST-derived
  `deployment_configuration_type=PipelineComponent` property. No inference job was
  launched by the failed guard, and the legacy default remained unchanged.
- The next invocation was stopped locally because SDK 1.28 treated a raw
  `abfss://` input as an asset ID. Use a credentialless datastore reference to
  the existing Spark ADLS filesystem and its supported Azure ML input URI.
  No new storage, compute, or secrets are introduced.
- Batch API validation rejects output delivery mode `direct`; it accepts
  `upload` or `rw_mount`. Component version 2 explicitly keeps the Spark child's
  output in `direct` mode while the batch API uses `upload`. The previous component
  version remains immutable and no inference job had started before this rejection.

### Native validation checklist

- [x] Confirm subscription, workspace, region, endpoint, and model version.
- [x] Verify ESv3 quota and existing data-plane permissions.
- [x] Validate YAML and SDK pipeline-component deployment serialization.
- [x] Parse every new Python source and notebook code cell.
- [x] Pass focused native runtime/output and existing training tests.
- [x] Scan active native path for secrets and forbidden local Spark master settings.
- [x] Confirm existing endpoint default and deployment remain unchanged.
- [x] Complete the official Azure validation workflow.
- [ ] Deploy/invoke, verify native runtime and model loading, and promote after parity.

---

## Previous Batch Extension Request (2026-10-06)

**Goal:** Clarify the Titanic Spark training graph and add a managed Azure ML batch
deployment for registered model `workshop-titanic-spark-model:1`.

**Approved architecture pending user confirmation:**

- Rename pipeline job `evaluate_model` to `score_test_data`; keep
  `validate_model` as the only explicit registration gate.
- Add one SDK-only notebook that creates/reuses a batch endpoint and batch deployment,
  invokes the deployment with Titanic input data, streams the batch job, downloads
  predictions, and verifies the output.
- Use existing workspace `mlwpublicncus04`, compute cluster
  `aml-cluster-public-ncus04`, registered model version 1, UAMI-based Azure resources,
  and North Central US.
- Keep endpoint/deployment creation and invocation behind separate false-by-default
  switches in `.env.example`.

### Batch resource names and settings

| Resource / setting | Value |
|---|---|
| Batch endpoint | `titanic-spark-batch-ncus04` |
| Batch deployment | `sparkml-v1` |
| Environment | `workshop-titanic-spark-batch:2` |
| Registered model | `workshop-titanic-spark-model:1` |
| Compute | `aml-cluster-public-ncus04` |
| Batch instances | 1 |
| Max concurrency | 1 |
| Mini-batch size | 1 input file |
| Output action | Append rows to `predictions.csv` |
| Input | Local workshop `data/titanic.csv`, uploaded as URI folder |
| Scoring runtime | Python 3.10, OpenJDK 17, PySpark 3.5.8 |

### Scoring and verification contract

- `init()` discovers and loads the registered native Spark ML pipeline from
  `AZUREML_MODEL_DIR`.
- `run(mini_batch)` reads Titanic CSV files, reproduces the training feature schema,
  generates class/probability rows, and returns a pandas DataFrame.
- The notebook creates/reuses the endpoint, named environment, and deployment.
- The notebook sets the deployment as the endpoint default, invokes a batch job,
  streams it, downloads the `score` output, and verifies row count, PassengerId
  uniqueness, prediction domain, and probability bounds.
- The compute instance is not used. The existing cluster remains minimum zero and
  uses one `Standard_F8s_v2` node only while the batch job runs.

### Provisioning limits

| Resource | Current | Planned | Limit / capacity | Result |
|---|---:|---:|---:|---|
| Batch endpoints in workspace | 0 | 1 | No blocking quota exposed | PASS |
| Batch deployments | 0 | 1 | No blocking quota exposed | PASS |
| FSv2 vCPUs during invocation | 0 | 8 | 100 | PASS |
| Total regional vCPUs during invocation | 0 | 8 | 100 | PASS |
| Registered model versions | 1 | Reuse version 1 | Existing asset | PASS |

**Blocking extension steps:**

- [x] Confirm supported Azure ML batch deployment contract for a native Spark ML
  custom model.
- [x] Define scoring environment, scoring contract, endpoint/deployment names, and
  batch input/output behavior.
- [x] Add tests before implementation.
- [x] Implement notebook, scoring source, environment, configuration, and docs.
- [x] Validate locally and through Azure ML SDK schemas.
- [x] Obtain approval for Azure batch endpoint/deployment creation.
- [x] Invoke Azure validation and deployment workflows.
- [x] Verify endpoint, deployment, invocation job, predictions, and cost controls.

### Batch extension validation proof

| Check | Result |
|---|---|
| Focused tests | PASS: 8 |
| Spark graph | PASS: `prepare_data`, `train_model`, `score_test_data`, `validate_model` |
| Validation-node uniqueness | PASS: exactly one `validate_model` job |
| Scoring script syntax | PASS |
| Conda environment schema | PASS |
| Notebook Python syntax | PASS |
| Azure ML SDK entities | PASS: environment, endpoint, deployment |
| Registered model | PASS: `workshop-titanic-spark-model:1` |
| Existing compute | PASS: `aml-cluster-public-ncus04`, `Standard_F8s_v2` |
| Compute capacity | PASS: 8 planned vCPUs, 100 available |
| Existing endpoints | PASS: zero batch endpoints before deployment |
| Security | AAD endpoint auth, AzureCliCredential, managed compute identity, no secrets |

**Batch compute role verification:** `public-mi-compute` has AzureML Data Scientist
and workspace Contributor, Storage Blob/File/Queue/Table data roles, Key Vault
Secrets User, ACR Pull/Push, resource-group Reader, and Managed Identity Operator.
The batch extension introduces no new identity or role assignment.

### Batch extension validation checklist

- [x] Deployment plan loaded and Azure context confirmed.
- [x] Focused tests pass.
- [x] Python, notebook, YAML, and conda syntax checks pass.
- [x] Azure ML SDK endpoint/deployment/environment entities construct successfully.
- [x] Registered model version 1 exists and is validated.
- [x] Existing compute is healthy and has sufficient quota.
- [x] Endpoint/deployment names do not conflict with existing resources.
- [x] Endpoint uses AAD authentication.
- [x] Endpoint, deployment, and environment include `SecurityControl=Ignore`.
- [x] No passwords, keys, connection strings, or client secrets are embedded.
- [x] Compute UAMI live roles include workspace, Storage, Key Vault, and ACR access.
- [x] Azure batch deployment and invocation complete successfully.
- [x] Predictions contract passes and cluster returns to zero nodes.

---

## 1. Project Overview

**Goal:** Deploy a new open/public Azure Machine Learning single-workspace stack in
North Central US.

**Path:** Modify and reuse the existing `infra/single-workspace` Terraform root.

The new deployment is intentionally isolated from the retained Canada Central
resources and state. It will use purpose `public`, region code `ncus`, suffix `04`,
and a new local state lineage.

---

## 2. Requirements

| Attribute | Value |
|---|---|
| Classification | POC / development |
| Scale | Small |
| Budget | Cost-optimized: cluster minimum 0, maximum 4 |
| Subscription | `{subscription-name}` (`{subscription-id}`) |
| Location | North Central US (`northcentralus`) |
| Network profile | Public/open; AML managed-network isolation disabled |
| Encryption | Azure ML workspace and default Storage use CMK |
| Registry | No Azure ML registry |
| Required tag | `SecurityControl=Ignore` |
| State | Local Terraform workspace `public-ncus` at `infra/single-workspace/terraform.tfstate.d/public-ncus/terraform.tfstate` |
| Terraform data | Isolated `infra/single-workspace/.terraform-public-ncus` |
| Variables | Local `public.ncus.tfvars`; tracked example `public.ncus.tfvars.example` |
| Plan | `infra/single-workspace/public-ncus.tfplan` |

### Non-destructive boundary

- Do not modify or destroy resources in `rg-aml-ws-public-cc-03`.
- Do not use `terraform.public.tfstate`, `terraform.tfstate`, or the default Terraform
  workspace.
- The deployment plan must contain zero delete or replacement actions.
- Create a new North Central US resource group and globally unique linked resources.

---

## 3. Components Detected

| Component | Type | Technology | Path |
|---|---|---|---|
| Single-workspace root | Infrastructure | Terraform / AzureRM / AzAPI | `infra/single-workspace` |
| Azure ML module | Infrastructure | Terraform / AzAPI | `infra/single-workspace/modules/aml-managed-umi` |
| Default Storage module | Infrastructure | Terraform / AzureRM | `infra/single-workspace/modules/storage-account` |
| Container Registry module | Infrastructure | Terraform / AzureRM | `infra/single-workspace/modules/container-registry` |
| Workspace Key Vault module | Infrastructure | Terraform / AzureRM | `infra/single-workspace/modules/key-vault` |
| Spark data lake | Infrastructure | Terraform / ADLS Gen2 | `infra/single-workspace/spark-data-lake.tf` |
| Plan validator | Validation | PowerShell | `infra/single-workspace/scripts/validate-plan.ps1` |
| Deployment validator | Validation | PowerShell | `infra/single-workspace/scripts/validate-deployment.ps1` |

---

## 4. Recipe Selection

**Selected:** Terraform.

**Rationale:** The repository already contains the required public workspace
architecture, CMK, UAMIs, RBAC, compute, monitoring, and ADLS Gen2 resources. Reusing
the root avoids introducing a second infrastructure implementation.

### Required preparation changes

1. Allow the existing root to accept the validated
   `northcentralus` / `ncus` region pair and a two-digit suffix while retaining the
   existing Canada Central values.
2. Use an isolated Terraform data directory and local Terraform workspace, add
   `public.ncus.tfvars.example`, and create an ignored local
   `public.ncus.tfvars`.
3. Parameterize the plan validator for the expected public profile, location, region
   code, suffix, names, public access, compute creation, and isolated state.
4. Parameterize or extend deployment validation for the new public stack.
5. Update the single-workspace README with state-isolation and North Central US
   commands.

---

## 5. Architecture

### Planned resource names

| Resource | Name |
|---|---|
| Resource group | `rg-aml-ws-public-ncus-04` |
| Azure ML workspace | `mlwpublicncus04` |
| Default Storage | `stpublicncus04` |
| Spark ADLS Gen2 | `stpublicdlncus04` |
| Container Registry | `acrpublicncus04` |
| Workspace Key Vault | `kvpublicncus04` |
| CMK Key Vault | `kvcmkpublicncus04` |
| Log Analytics | `log-aml-public-ncus04` |
| Application Insights | `mlwinpublicncus04` |
| Workspace UAMI | `public-mi-workspace` |
| Cluster UAMI | `public-mi-compute` |
| Compute-instance UAMI | `public-mi-compute-instance` |
| Endpoint UAMI | `public-mi-online-endpoint` |
| Compute cluster | `aml-cluster-public-ncus04` |
| Compute instance | `ci-public-ncus04` |

All globally scoped names above were checked and are available.

### Service mapping

| Component | Azure service / SKU |
|---|---|
| ML control plane | Azure Machine Learning workspace |
| Cluster | AML Compute, `Standard_F8s_v2`, min 0, max 4 |
| Interactive compute | Compute Instance, `Standard_F8s_v2` |
| Workspace artifacts | StorageV2 Standard LRS |
| Spark data | StorageV2 Standard LRS, HNS enabled |
| Images | Azure Container Registry Premium |
| Secrets | Key Vault Premium |
| CMK | Separate purge-protected Key Vault and RSA key |
| Monitoring | Log Analytics PerGB2018 + Application Insights |
| Identity | Four user-assigned managed identities |

### Network and security

- Workspace `publicNetworkAccess=Enabled`.
- AML managed-network `isolationMode=Disabled`.
- Default Storage, Spark ADLS, ACR, and Key Vault public endpoints enabled.
- Blob public access and shared-key Storage authentication remain disabled.
- Compute nodes use public IPs because this open profile has no workspace private
  endpoint; remote login and SSH remain disabled.
- Workspace and default Storage use customer-managed encryption.
- Terraform caller and managed identities receive scoped RBAC.
- Every taggable managed resource includes `SecurityControl=Ignore`.

---

## 6. Provisioning Limit Checklist

### Resource inventory and verified capacity

| Resource type | Number to deploy | Total after deployment | Limit / quota | Validation source |
|---|---:|---:|---:|---|
| Resource groups | 1 | 20 | 980/subscription | ARG current count + Azure ARM limit |
| AML workspaces | 1 | 1 in region | No blocking workspace-count quota reported | Azure quota CLI/provider registration |
| AML compute clusters | 1 | 1 | 200 | `azure-quotas` `TotalClusters` |
| AML dedicated cores | Max 40 | 40 | 1,000 | `azure-quotas` `TotalDedicatedCores` |
| AML FSv2-family cores | Max 40 | 40 | 100 | `azure-quotas` `standardFSv2Family` |
| Compute regional vCPUs | Max 40 | 40 | 100 | `az vm list-usage` |
| Compute FSv2-family vCPUs | Max 40 | 40 | 100 | `az vm list-usage` |
| Storage accounts | 2 | 2 | 250 | `azure-quotas` `StorageAccounts` |
| Container registries | 1 | 2 | 100/region | ARG current count + Microsoft ACR limit |
| Key Vaults | 2 | 2 | No separate vault-count quota | ARG current count + Microsoft Key Vault limits |
| User-assigned identities | 4 | 4 | 1,000/region | ARG current count + Microsoft managed-identity limit |
| Role assignments | 45 | 282 | 5,000/subscription | ARG current count + Microsoft RBAC limit |

`Standard_F8s_v2` is available in North Central US with no subscription restriction.
The stack uses at most 40% of the Compute and AML FSv2-family limits.

**Status:** All planned resources are within limits.

---

## 7. Validation Proof

| Check | Command / source | Result |
|---|---|---|
| Terraform installed | `terraform -version` | PASS: Terraform 1.10.5 |
| Azure CLI installed and authenticated | `az account show` | PASS: confirmed subscription |
| Required providers registered | `az provider show` | PASS: AML, Storage, Key Vault, ACR |
| Terraform initialization | `terraform init -input=false` | PASS |
| Terraform formatting | `terraform fmt -check -recursive` | PASS |
| Terraform syntax | `terraform validate` | PASS |
| PowerShell validators | PowerShell parser API | PASS |
| Isolated pre-apply state | `Test-Path terraform.tfstate.d/public-ncus/terraform.tfstate` | PASS: absent |
| Saved plan | `terraform plan ... -out=public-ncus.tfplan` | PASS: 91 add, 0 change, 0 destroy; SHA-256 `4BFBD02800C80260C996863A062AD50E50680B69D8683ED52BDF83A1C18C4F57` |
| Plan invariants | `scripts/validate-plan.ps1` with public/NCUS parameters | PASS: all invariants |
| Template-variable scan | `{{ .Env.* }}` scan | PASS: no unresolved values |
| tfvars JSON gate | `main.tfvars.json` check | PASS: file not present |
| Compute quota | Azure quota CLI and `az vm list-usage` | PASS: 100 FSv2 and regional vCPUs; max 40 planned |
| Azure ML quota | Azure quota CLI | PASS: 100 FSv2, 1,000 dedicated cores, 200 clusters |
| Storage quota | Azure quota CLI | PASS: 250 available; 2 planned |
| Global names | Storage, ACR, Key Vault name checks | PASS: all available |
| SKU availability | `az vm list-skus` | PASS: `Standard_F8s_v2` unrestricted |
| Static RBAC review | Terraform and saved-plan review | PASS |
| Azure Policy | Azure MCP Policy + policy-definition review | PASS: no planned type, location, or SKU conflicts |
| Apply recovery | Replan after transient ARM connection reset | PASS: 34 creates, one approved ADLS firewall convergence update, zero deletes; SHA-256 `0D3055BFE6CB6D8522AC034E3A7F4ED00741FDABC3310C87C4550BDF60212A61` |
| Compute-name recovery | Replan after Azure ML name-length validation | PASS: 13 creates, one approved ADLS firewall convergence update, zero deletes; `ci-public-ncus04`; SHA-256 `51EFCA578432AE59B47F44C7E9B5092AD76ED97232135689B84DD8CB7DF6E30A` |
| Batch extension tests | `pytest tests/test_titanic_spark_training_pipeline.py tests/test_titanic_batch_endpoint.py` | PASS: 8 |
| Batch SDK schemas | Python AST, YAML/conda parsing, Azure ML SDK entity construction | PASS |
| Batch prerequisites | Model, compute, quota, endpoint conflict, secret scan | PASS |
| Batch compute RBAC | Live role assignment review for `public-mi-compute` | PASS |
| Native Spark tests (2026-10-06) | `pytest test_native_titanic_spark_batch.py test_titanic_batch_endpoint.py test_titanic_spark_training_pipeline.py` | PASS: 17, including batch datastore URI resolution and named input/output serialization |
| Native endpoint contract | SDK component load and pipeline-component REST serialization | PASS: `PipelineComponent`, Spark child runtime 3.5, no AML compute |
| Native runtime preflight | ESv3 quota CLI, immutable model URI, direct-mode inputs/outputs, Synapse registration, user Blob roles | PASS |
| Native policy preflight | Subscription assignments and inherited governance SKU-deny initiative | PASS: no E4s v3 denial |
| Notebook execution kernel | `mlops-azureml` kernelspec | PASS: exact repository `.venv` interpreter |
| Batch environment recovery | Environment v1 failed before scoring because NumPy 1.26 conflicted with `azureml-dataset-runtime`; v2 pins NumPy 1.23.5 | Corrected |

The official `validate-terraform.ps1` wrapper passed tool discovery,
subscription selection, Azure authentication, and template scanning. Its Terraform
subcommands returned Terraform help because the wrapper parameter named `$Args`
collides with PowerShell's automatic `$Args` variable. The same required commands
were run directly against the isolated state and saved plan and all passed.

The first apply lost its ARM connection while creating the workspace UAMI Reader
assignment. Azure did not create that assignment, while Terraform persisted every
resource that completed. The recovery plan contains only the remaining creates plus
an in-place ADLS firewall representation convergence from Azure's implicit open
default to Terraform's explicit `Allow`/`AzureServices` configuration.

The next recovery apply created the workspace and remaining RBAC but Azure rejected
the default compute-instance name because it exceeded the service's 24-character
limit. The invalid compute instance was not created. The approved replacement name is
`ci-public-ncus04`.

After deployment, the convergence check found only a representation loop on the
public Spark ADLS firewall: Azure omits an explicit firewall block for open access.
The Terraform root now emits `network_rules` only for the managed profile, preserving
the same public behavior without perpetual drift.

---

## 8. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace and retained Azure resources.
- [x] Gather deployment requirements.
- [x] Scan Terraform modules and validators.
- [x] Select the existing Terraform recipe.
- [x] Define isolated North Central US architecture and names.
- [x] Validate quotas and SKU availability.
- [x] Confirm subscription and location from the explicit deployment request.
- [x] User approves this plan.

### Phase 2: Preparation

- [x] Generalize region/suffix validation without changing existing defaults.
- [x] Add isolated Terraform data directory/workspace handling, North Central public
  tfvars example, and ignored local tfvars.
- [x] Parameterize plan and deployment validators.
- [x] Update directly related infrastructure documentation.
- [x] Run `terraform fmt -recursive`.
- [x] Run `terraform init -input=false`.
- [x] Run `terraform validate`.
- [x] Initialize/select the isolated `public-ncus` Terraform workspace and regenerate
  the saved plan after correcting legacy `-state` handling.
- [x] Prove plan is create-only, public, CMK-enabled, one workspace, no registry.
- [x] Set plan status to `Ready for Validation`.

### Phase 3: Validation and deployment

- [x] All validation checks pass
  - [x] Terraform is installed.
  - [x] Azure CLI is installed.
  - [x] Azure CLI is authenticated to the confirmed subscription.
  - [x] Terraform initialization succeeds.
  - [x] Terraform formatting check succeeds.
  - [x] Terraform configuration validation succeeds.
  - [x] Terraform saved plan succeeds.
  - [x] Terraform state check confirms the new state lineage is empty before apply.
  - [x] No unresolved Go-style environment templates exist.
  - [x] No invalid `main.tfvars.json` file exists.
  - [x] Azure Policy preflight permits the planned resources and required tags.
  - [x] Terraform plan invariants pass with 91 creates, zero changes, and zero destroys.
  - [x] Required deployment roles are present.
- [x] Invoke `azure-validate`.
- [x] Invoke `azure-deploy`.
- [x] Apply the saved plan in a visible VS Code terminal.
- [x] Verify exact names, North Central US locations, tags, UAMIs, CMK, linked
  resources, public networking, compute security, and ADLS Gen2.
- [x] Confirm cluster min nodes is zero and stop the compute instance after smoke
  validation to control cost.
- [x] Set plan status to `Deployed`.

---

## 9. Rollback

If deployment validation fails, do not touch retained Canada Central resources.
Destroy only the new North Central state lineage:

```powershell
terraform -chdir=infra\single-workspace destroy `
  -var-file=public.ncus.tfvars
```

Destruction requires separate explicit approval.

---

## 10. Role Assignment Verification

- **Status:** Verified.
- **Workspace UAMI:** Resource-group Reader, Azure AI Administrator, Azure AI
  Enterprise Network Connection Approver; Key Vault management/secrets roles;
  default-Storage Contributor plus Blob, File, Queue, and Table data roles; CMK
  Crypto User; Spark ADLS Contributor and Blob Data Contributor.
- **Cluster UAMI:** Workspace AzureML Data Scientist/Contributor; resource-group
  Reader; default-Storage Blob, File, Queue, and Table data roles; Key Vault Secrets
  User; ACR Pull and Push.
- **Compute-instance UAMI:** Workspace AzureML Data Scientist; default-Storage Blob
  and File data roles; Key Vault Secrets User; ACR Pull.
- **Online-endpoint UAMI:** ACR Pull, Storage Blob Data Reader, AzureML Metrics
  Writer; Managed Identity Operator is scoped to the compute identities for approved
  deployer principals.
- **Terraform caller:** Resource-group Reader; workspace AzureML Data Scientist,
  Azure AI Developer, and Compute Operator; Key Vault Administrator; default-Storage
  Blob, File, Queue, and Table data roles; Spark ADLS Blob Data Owner.
- **Scope review:** Data roles are scoped to their Storage, Key Vault, ACR, workspace,
  or identity resources. Resource-group roles are management-plane roles needed for
  Azure ML resource discovery and network approval.
- **Issues:** None found. Generic Reader/Contributor roles are not relied upon for
  Storage data access; explicit data-plane roles are present.

---

## 11. Deployment Results

- **Status:** Deployed and verified.
- **Terraform workspace:** `public-ncus`.
- **Terraform state:** `terraform.tfstate.d/public-ncus/terraform.tfstate`.
- **State resources:** 97.
- **Convergence:** `terraform plan -detailed-exitcode` returned no changes.
- **Azure resources:** 12 top-level resources, all in North Central US.
- **Azure ML workspace:** `mlwpublicncus04`.
- **Networking:** Public access enabled; AML managed-network isolation disabled.
- **Compute cluster:** `aml-cluster-public-ncus04`, `Standard_F8s_v2`, minimum zero,
  zero allocated nodes after validation.
- **Compute instance:** `ci-public-ncus04`, `Standard_F8s_v2`, stopped after
  validation.
- **Smoke job:** `affable_hamster_bsfgjj9527`, status `Completed`.
- **Serverless Spark job:** `icy_monkey_yv1fnc1hwf`, status `Completed`,
  `standard_e4s_v3`, Spark runtime 3.4.
- **Upgraded serverless Spark job:** `bright_market_x0hn88s7ls`, status
  `Completed`, `standard_e4s_v3`, Spark runtime 3.5, with no runtime-version
  deprecation warning.
- **Spark output:** 889 rows, 12 expected Titanic columns, no missing `Age`
  values, written to
  `abfss://spark@stpublicdlncus04.dfs.core.windows.net/output/titanic/`.
- **Titanic training pipeline:** `musing_date_ws9pfpkm52`, status `Completed`.
- **Pipeline stages:** `prepare_data`, `train_model`, `evaluate_model`, and
  `validate_model`, all Spark 3.5 and all `Completed`.
- **Model validation:** accuracy `0.8482758621`, F1 `0.8456727519`, area under ROC
  `0.9112131649`, threshold `0.70`, `validated=true`.
- **Registered model:** `workshop-titanic-spark-model:1`, custom Spark ML model.
- **Batch endpoint:** `titanic-spark-batch-ncus04`, AAD auth, provisioning succeeded.
- **Batch deployment:** `sparkml-v1`, environment
  `workshop-titanic-spark-batch:2`, model version 1, existing FSv2 cluster.
- **Batch scoring job:** `batchjob-a1db9a6c-865f-4091-b233-7ea6f0b5877b`,
  status `Completed`.
- **Batch predictions:** 891 rows; unique PassengerIds; binary prediction classes;
  probabilities in `[0, 1]`.
- **Batch compute cost control:** cluster returned to zero allocated nodes.
- **CMK:** Workspace encryption enabled; CMK Key Vault purge protection enabled.
- **Storage:** Shared-key access disabled on default Storage and Spark ADLS; Spark
  account has hierarchical namespace enabled.

### Live role verification

| Identity | Expected roles checked | Live assignments | Result |
|---|---:|---:|---|
| Workspace UAMI | 12 | 14 | PASS |
| Cluster UAMI | 10 | 11 | PASS |
| Compute-instance UAMI | 5 | 6 | PASS |
| Online-endpoint UAMI | 3 | 3 | PASS |
| Terraform caller | 9 | 67 including inherited | PASS |

### Links

- Azure ML Studio:
  `https://ml.azure.com/?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Smoke job:
  `https://ml.azure.com/runs/affable_hamster_bsfgjj9527?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Spark 3.5 job:
  `https://ml.azure.com/runs/bright_market_x0hn88s7ls?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Titanic Spark training pipeline:
  `https://ml.azure.com/runs/musing_date_ws9pfpkm52?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Titanic batch scoring job:
  `https://ml.azure.com/runs/batchjob-a1db9a6c-865f-4091-b233-7ea6f0b5877b?wsid=/subscriptions/{subscription-id}/resourcegroups/rg-aml-ws-public-ncus-04/workspaces/mlwpublicncus04&tid={tenant-id}`
- Titanic batch scoring URI:
  `https://titanic-spark-batch-ncus04.northcentralus.inference.ml.azure.com/jobs`
- Azure portal resource group:
  `https://portal.azure.com/#@{tenant-id}/resource/subscriptions/{subscription-id}/resourceGroups/rg-aml-ws-public-ncus-04/overview`
