import argparse
import json
import os
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple
import time

from azure.ai.ml import MLClient
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azureml.core.run import Run


def _build_credential():
    client_id = os.environ.get("DEFAULT_IDENTITY_CLIENT_ID")
    if client_id:
        credential = ManagedIdentityCredential(client_id=client_id)
        try:
            credential.get_token("https://management.azure.com/.default")
            print("Using managed identity credential for Azure ML cleanup")
            return credential
        except Exception as exc:  # pragma: no cover - fallback logging only
            print(f"Managed identity auth failed, falling back to DefaultAzureCredential: {exc}")
    credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    credential.get_token("https://management.azure.com/.default")
    print("Using DefaultAzureCredential for Azure ML cleanup")
    return credential


def _get_workspace_client(credential, args) -> Optional[MLClient]:
    try:
        run = Run.get_context(allow_offline=False)
        ws = run.experiment.workspace
        return MLClient(
            credential=credential,
            subscription_id=ws._subscription_id,
            resource_group_name=ws._resource_group,
            workspace_name=ws._workspace_name,
        )
    except Exception:
        if args.subscription_id and args.resource_group and args.workspace_name:
            return MLClient(
                credential=credential,
                subscription_id=args.subscription_id,
                resource_group_name=args.resource_group,
                workspace_name=args.workspace_name,
            )
    return None


def _get_registry_client(credential, registry_name: Optional[str]) -> Optional[MLClient]:
    if not registry_name:
        return None
    try:
        return MLClient(credential=credential, registry_name=registry_name)
    except Exception as exc:
        print(f"Unable to create registry client for {registry_name}: {exc}")
        return None


def _load_deploy_metadata(deploy_state: Optional[str]) -> Dict[str, str]:
    if not deploy_state:
        return {}
    path = Path(deploy_state) / "deployment_state.json"
    if not path.exists():
        print(f"Deployment metadata not found at {path}")
        return {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return {k: str(v) for k, v in data.items() if v is not None}
    except Exception as exc:
        print(f"Failed to parse deployment metadata at {path}: {exc}")
        return {}


def _version_key(model) -> Tuple[int, str]:
    raw_version = str(getattr(model, "version", ""))
    try:
        return (0, f"{int(raw_version):020d}")
    except (ValueError, TypeError):
        return (1, raw_version)


def _expand_keep_set(
    models: Sequence,
    keep_versions: Set[str],
    retain_count: int,
) -> Set[str]:
    target = max(retain_count, len(keep_versions))
    ordered = sorted(models, key=_version_key, reverse=True)
    for model in ordered:
        if len(keep_versions) >= target:
            break
        version = str(getattr(model, "version", ""))
        if version:
            keep_versions.add(version)
    return keep_versions


def _collect_versions(models: Iterable) -> List[str]:
    return [str(getattr(model, "version", "")) for model in models if getattr(model, "version", None) is not None]


def _wait_for_deletion(client: MLClient, model_name: str, version: str, retries: int = 10, delay: float = 3.0) -> None:
    for attempt in range(retries):
        try:
            client.models.get(name=model_name, version=version)
        except ResourceNotFoundError:
            return
        time.sleep(delay)
    raise HttpResponseError(message=f"Model version {model_name}:{version} still exists after deletion attempts")


def _delete_model_version(client: MLClient, model_name: str, version: str) -> None:
    operation = client.models._model_versions_operation
    scope = client.models._operation_scope
    registry_name = getattr(scope, "_registry_name", None)
    resource_group = getattr(scope, "_resource_group_name", None)
    if registry_name:
        try:
            operation.delete(model_name, version, resource_group, registry_name)
        except HttpResponseError as exc:
            if getattr(exc, "status_code", None) in (202, 204) or "status 'Accepted'" in str(exc):
                print(f"Deletion accepted asynchronously for registry version {version}; waiting for completion")
            else:
                raise
        _wait_for_deletion(client, model_name, version)
    else:
        workspace_name = getattr(scope, "_workspace_name", None)
        operation.delete(resource_group, workspace_name, model_name, version)
        _wait_for_deletion(client, model_name, version)


def _cleanup_for_client(
    scope_name: str,
    client: MLClient,
    model_name: str,
    keep_versions: Set[str],
    retain_count: int,
    dry_run: bool,
) -> Dict[str, object]:
    try:
        models = list(client.models.list(name=model_name))
    except ResourceNotFoundError:
        print(f"[{scope_name}] No registered model named {model_name} exists")
        return {
            "scope": scope_name,
            "total_versions": 0,
            "kept_versions": sorted(list(keep_versions)),
            "deleted_versions": [],
            "dry_run": dry_run,
        }
    except Exception as exc:
        print(f"[{scope_name}] Failed to enumerate model versions: {exc}")
        return {
            "scope": scope_name,
            "error": str(exc),
            "total_versions": 0,
            "kept_versions": [],
            "deleted_versions": [],
            "dry_run": dry_run,
        }

    ordered_models = sorted(models, key=_version_key, reverse=True)
    resolved_keep = _expand_keep_set(ordered_models, set(keep_versions), retain_count)
    delete_candidates = [m for m in ordered_models if str(getattr(m, "version", "")) not in resolved_keep]
    deleted_versions: List[str] = []
    for candidate in delete_candidates:
        version = str(getattr(candidate, "version", ""))
        if not version:
            continue
        print(f"[{scope_name}] Preparing to delete model version {model_name}:{version}")
        if dry_run:
            deleted_versions.append(version)
            continue
        try:
            _delete_model_version(client, model_name, version)
            deleted_versions.append(version)
            print(f"[{scope_name}] Deleted model version {version}")
        except ResourceNotFoundError:
            print(f"[{scope_name}] Model version {version} already removed")
        except HttpResponseError as exc:
            print(f"[{scope_name}] Failed to delete version {version}: {exc}")
            raise
    kept_versions = [str(getattr(model, "version", "")) for model in ordered_models if str(getattr(model, "version", "")) in resolved_keep]
    return {
        "scope": scope_name,
        "total_versions": len(ordered_models),
        "kept_versions": kept_versions,
        "deleted_versions": deleted_versions,
        "dry_run": dry_run,
    }


def _write_summary(output_folder: Optional[str], report: Dict[str, object]) -> None:
    if not output_folder:
        return
    path = Path(output_folder)
    path.mkdir(parents=True, exist_ok=True)
    with open(path / "cleanup_report.json", "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
    kept = []
    for scope in report.get("scopes", []):
        kept.extend(scope.get("kept_versions", []))
    with open(path / "summary.txt", "w", encoding="utf-8") as handle:
        handle.write(f"Cleanup executed for model {report.get('model_name')}.\n")
        handle.write(f"Dry run: {report.get('dry_run')}\n")
        handle.write(f"Retained versions: {', '.join(sorted(set(kept))) or 'none'}\n")


def main():
    parser = argparse.ArgumentParser("cleanup_models")
    parser.add_argument("--model_name", required=True)
    parser.add_argument("--registry", required=False)
    parser.add_argument("--retain_versions", type=int, default=1)
    parser.add_argument("--deploy_state", required=False)
    parser.add_argument("--scope", choices=["workspace", "registry", "both"], default="both")
    parser.add_argument("--output_folder", required=False)
    parser.add_argument("--dry_run", action="store_true")
    parser.add_argument("--subscription_id", required=False)
    parser.add_argument("--resource_group", required=False)
    parser.add_argument("--workspace_name", required=False)
    args = parser.parse_args()

    if args.retain_versions < 1:
        raise SystemExit("retain_versions must be at least 1")

    credential = _build_credential()

    deploy_metadata = _load_deploy_metadata(args.deploy_state)
    keep_versions: Set[str] = set()
    deployed_version = deploy_metadata.get("model_version")
    if deployed_version:
        keep_versions.add(deployed_version)
        print(f"Will preserve deployed model version {deployed_version}")
    elif deploy_metadata:
        print("Deployment metadata did not include model_version; only retain count will be used")

    if deploy_metadata and deploy_metadata.get("model_name") and deploy_metadata.get("model_name") != args.model_name:
        print(
            "Deployment metadata model name does not match target; proceeding with target name only",
        )

    scopes: List[Tuple[str, MLClient]] = []
    if args.scope in ("workspace", "both"):
        workspace_client = _get_workspace_client(credential, args)
        if workspace_client:
            scopes.append(("workspace", workspace_client))
        else:
            print("Workspace client unavailable; skipping workspace cleanup")
    if args.scope in ("registry", "both"):
        registry_client = _get_registry_client(credential, args.registry)
        if registry_client:
            scopes.append(("registry", registry_client))
        else:
            print("Registry client unavailable; skipping registry cleanup")

    if not scopes:
        raise SystemExit("No valid Azure ML clients available for cleanup")

    scope_reports = []
    for scope_name, client in scopes:
        report = _cleanup_for_client(
            scope_name=scope_name,
            client=client,
            model_name=args.model_name,
            keep_versions=keep_versions,
            retain_count=args.retain_versions,
            dry_run=args.dry_run,
        )
        scope_reports.append(report)

    final_report: Dict[str, object] = {
        "model_name": args.model_name,
        "deploy_metadata": deploy_metadata,
        "retain_versions": args.retain_versions,
        "dry_run": args.dry_run,
        "scopes": scope_reports,
    }

    _write_summary(args.output_folder, final_report)

    deletions_attempted = any(report.get("deleted_versions") for report in scope_reports)
    print("Cleanup complete")
    for report in scope_reports:
        print(
            f"[{report.get('scope')}] kept {report.get('kept_versions')} | "
            f"deleted {report.get('deleted_versions')} | total {report.get('total_versions')}",
        )
    if args.dry_run:
        print("Dry run requested; no versions were deleted")
    elif not deletions_attempted:
        print("No model versions required deletion")


if __name__ == "__main__":
    main()
