# Spark-Ready Azure ML Workspace Module

This module is private to `infra/spark-workspace`.

It creates linked Storage, Key Vault, Application Insights, Premium ACR, a workspace
UAMI, CMK resources, an Azure ML workspace, UAMI-backed compute, diagnostic settings,
and image-build compute configuration.

The workspace uses `AllowOnlyApprovedOutbound`, starts with public access disabled,
and sets `provisionNetworkNow=false`. An `azapi_resource_action` performs the
`provisionManagedNetwork` POST with `includeSpark=true` and a three-hour timeout.
Terraform does not define a Blob outbound rule; Azure owns the required system rule,
which the post-deployment validator checks for uniqueness and Spark readiness.

Workspace selected-IP access is enabled after Spark provisioning. Storage, ACR, and
both Key Vaults use deny-by-default selected-IP firewalls. Storage uses Entra
authentication with shared-key access disabled.

The module creates no customer VNet, subnet, private endpoint, private DNS zone,
registry, Bastion host, jump box, or virtual machine.
