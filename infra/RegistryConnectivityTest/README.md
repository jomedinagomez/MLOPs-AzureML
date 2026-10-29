# Registry connectivity experiment

Creates a second workspace using the same workspace module and provider versions
as [AzureMLManagedVnet](../AzureMLManagedVnet/README.md), but targets an existing
AML registry instead of creating or configuring one.

The new environment has its own resource group, workspace UAMI, Storage, Key
Vault, Premium ACR, private networking, DNS, diagnostics, F8s v2 compute instance,
and F8s v2 cluster with zero to four nodes. Its local Terraform state is separate
from the original root. Never copy or import the original environment's state.
The compute instance and private endpoints incur ongoing charges.

## Permission boundary

The only registry-side assignment created here is **Azure AI Enterprise Network
Connection Approver** for the new workspace UAMI, scoped to the existing registry.
The shared workspace module retains its normal permissions on the **new workspace
resource group**, including Azure AI Administrator there. Those permissions do
not cover the existing registry's resource group or its managed backing resources.

This root does not change registry preauthorization, deny assignments, backing
Storage/ACR, or policy exemptions. It does not grant registry asset access.
Do not broaden permissions after a failed test without separate approval.

## Verified result

On October 29, 2026, workspace `mlwprivatencus07` successfully created
`AllowExternalRegistry-approver-only` against registry `mlrprivatencus06`:

| Check | Observed result |
|---|---|
| Workspace managed network | Active |
| Registry outbound rule | Active |
| Registry backing Blob private endpoint connection | Approved |
| Registry backing ACR private endpoint connection | Approved |
| Workspace UAMI roles at the registry | Network Connection Approver only |
| Workspace UAMI roles on the registry-managed RG | None |
| Workspace UAMI added to registry preauthorization | No |
| Existing registry preauthorization | Unchanged |

Azure AI Administrator on the **registry-managed RG** was not necessary for
this connection test. The workspace UAMI retained its normal Azure AI
Administrator role on its **own, separate workspace RG**. This experiment does
not establish that workspace-local administration can be removed, nor does it
test registry asset authorization or application/job traffic. The initiating
operator's existing permissions were not reduced, so this is not a
least-privileged deployment-principal test. Do not remove existing identities or
grants from another environment based on this test alone.

Both duplicated computes provisioned successfully. The new workspace's restricted
IP ingress was also copied. Initially, an inherited modify policy kept its
Storage account's public network access disabled despite the approved IP rule.

After explicit user approval on October 29, `SecurityControl=Ignore` was applied
to **Storage `stprivatencus07` only**, using the policy's supported resource-level
exclusion. Public access is now enabled with default deny and the same single
approved IP as Storage 06. Shared keys and anonymous Blob access remain disabled;
TLS 1.2 and all eight existing private endpoint connections were preserved.
Authenticated laptop container listing succeeded after the change.

The resource group, workspace, registry, ACR, and Key Vault were not given the
tag. Registry preauthorization and the approver-only test remain unchanged.
Terraform retains the private baseline; a future apply can remove this manual
Storage tag/access exception. Review its plan before applying.

## Deploy and test

1. Copy the variable example to a local, ignored `terraform.tfvars`. Use a fresh
   suffix and the existing registry's full resource ID.
2. Run `terraform init`, `terraform validate`, and `terraform plan -out=tfplan`
   from this directory. Inspect the saved plan: only new resources and the single
   existing-registry role assignment are permitted. Apply that exact saved plan.
3. Keep the Terraform baseline private. If approved, reproduce the source
   workspace's selected-IP/default-deny exceptions on the **new workspace and
   its Storage only**, using scoped CLI operations. As in the original root,
   a subsequent Terraform apply can remove manual exceptions. Read back the live
   settings: an approved IP rule does not override an inherited policy that
   disables public network access. A policy-defined tag exclusion requires
   explicit approval at the narrowest applicable resource scope.
4. Verify the fresh workspace identity has the registry-scoped approver role
   and is absent from the registry's managed-RG authorized identities. Record
   effective roles, the original authorized identities, and current endpoint
   connections before the test.
5. After RBAC propagation, create one managed private-endpoint outbound rule
   targeting the existing AML registry with subresource `amlregistry`. Do not
   create separate rules for its backing Storage/ACR: Azure resolves them.
6. Provision/read back the managed network and inspect the outbound rule plus
   registry/backing-resource endpoint connection states. A successful rule PUT
   alone is not proof of connectivity. Capture the precise denied action and
   resource scope if creation or approval fails.
7. Verify the original workspace remains healthy and registry preauthorization
   is unchanged. Retain the new environment unless cleanup is explicitly approved.
