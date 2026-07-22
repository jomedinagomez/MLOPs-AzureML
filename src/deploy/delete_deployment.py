"""
Delete Azure ML Online Deployment Script
This script deletes a specific deployment from an online endpoint.
"""
import argparse
import os
from azure.ai.ml import MLClient
from azure.core.exceptions import ResourceNotFoundError
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azureml.core.run import Run


def _build_credential():
    """Build credential with managed identity fallback to DefaultAzureCredential"""
    msi_client_id = os.environ.get("DEFAULT_IDENTITY_CLIENT_ID")
    if msi_client_id:
        try:
            credential = ManagedIdentityCredential(client_id=msi_client_id)
            credential.get_token("https://management.azure.com/.default")
            print("Using managed identity credential")
            return credential
        except Exception as exc:
            print(f"Managed identity failed: {exc}")
    
    credential = DefaultAzureCredential()
    credential.get_token("https://management.azure.com/.default")
    print("Using DefaultAzureCredential")
    return credential


def main():
    parser = argparse.ArgumentParser(
        description="Delete an Azure ML online deployment"
    )
    parser.add_argument(
        "--endpoint_name", 
        type=str, 
        required=True, 
        help="Name of the online endpoint"
    )
    parser.add_argument(
        "--deployment_name", 
        type=str, 
        required=True, 
        help="Name of the deployment to delete"
    )
    parser.add_argument(
        "--subscription_id", 
        type=str, 
        help="Azure subscription ID (optional if running in AML context)"
    )
    parser.add_argument(
        "--resource_group", 
        type=str, 
        help="Resource group name (optional if running in AML context)"
    )
    parser.add_argument(
        "--workspace_name", 
        type=str, 
        help="Workspace name (optional if running in AML context)"
    )
    parser.add_argument(
        "--delete_endpoint",
        action="store_true",
        help="If set, also delete the endpoint itself (only if no other deployments exist)"
    )

    args = parser.parse_args()

    # Build credential
    credential = _build_credential()

    # Try to get workspace from run context first
    try:
        run = Run.get_context(allow_offline=False)
        ws = run.experiment.workspace
        ml_client = MLClient(
            credential=credential,
            subscription_id=ws._subscription_id,
            resource_group_name=ws._resource_group,
            workspace_name=ws._workspace_name,
        )
        print(f"Connected to workspace: {ws._workspace_name}")
    except Exception:
        # Fall back to explicit parameters
        if not all([args.subscription_id, args.resource_group, args.workspace_name]):
            raise SystemExit(
                "Not running in AML context. Please provide --subscription_id, "
                "--resource_group, and --workspace_name"
            )
        ml_client = MLClient(
            credential=credential,
            subscription_id=args.subscription_id,
            resource_group_name=args.resource_group,
            workspace_name=args.workspace_name,
        )
        print(f"Connected to workspace: {args.workspace_name}")

    # Check if endpoint exists
    try:
        endpoint = ml_client.online_endpoints.get(name=args.endpoint_name)
        print(f"Found endpoint: {args.endpoint_name}")
        print(f"Current traffic: {endpoint.traffic}")
    except ResourceNotFoundError:
        raise SystemExit(f"Endpoint '{args.endpoint_name}' not found")

    # Check if deployment exists
    try:
        deployment = ml_client.online_deployments.get(
            name=args.deployment_name,
            endpoint_name=args.endpoint_name
        )
        print(f"Found deployment: {args.deployment_name}")
        print(f"  Instance type: {deployment.instance_type}")
        print(f"  Instance count: {deployment.instance_count}")
    except ResourceNotFoundError:
        raise SystemExit(
            f"Deployment '{args.deployment_name}' not found in endpoint '{args.endpoint_name}'"
        )

    # Check if deployment has traffic
    traffic_percent = endpoint.traffic.get(args.deployment_name, 0)
    if traffic_percent > 0:
        print(f"\n⚠️  WARNING: Deployment '{args.deployment_name}' currently has {traffic_percent}% traffic")
        print("Consider redirecting traffic before deletion:")
        print(f"  1. Get other deployments in the endpoint")
        print(f"  2. Update endpoint traffic to route away from this deployment")
        
        response = input("\nDo you want to continue with deletion? (yes/no): ")
        if response.lower() not in ["yes", "y"]:
            print("Deletion cancelled")
            return

    # Delete the deployment
    print(f"\nDeleting deployment: {args.deployment_name}")
    ml_client.online_deployments.begin_delete(
        name=args.deployment_name,
        endpoint_name=args.endpoint_name
    ).result()
    print(f"✓ Deployment '{args.deployment_name}' deleted successfully")

    # Optionally delete the endpoint if requested
    if args.delete_endpoint:
        # Refresh endpoint to check remaining deployments
        endpoint = ml_client.online_endpoints.get(name=args.endpoint_name)
        
        # Check if there are other deployments
        try:
            deployments = list(ml_client.online_deployments.list(
                endpoint_name=args.endpoint_name
            ))
            if deployments:
                print(f"\n⚠️  Cannot delete endpoint: {len(deployments)} deployment(s) still exist")
                print("Delete all deployments first before deleting the endpoint")
            else:
                print(f"\nDeleting endpoint: {args.endpoint_name}")
                ml_client.online_endpoints.begin_delete(name=args.endpoint_name).result()
                print(f"✓ Endpoint '{args.endpoint_name}' deleted successfully")
        except Exception as e:
            print(f"Error checking/deleting endpoint: {e}")


if __name__ == "__main__":
    main()
