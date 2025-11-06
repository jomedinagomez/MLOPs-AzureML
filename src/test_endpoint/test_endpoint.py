
import argparse
import json
import os
import tempfile
from typing import List, Optional

import pandas as pd
from azure.identity import ManagedIdentityCredential
from azure.ai.ml import MLClient


parser = argparse.ArgumentParser("test_endpoint")
parser.add_argument("--endpoint_name", type=str, required=True, help="Name of the endpoint to test")
parser.add_argument("--deployment_name", type=str, required=True, help="Deployment name")
parser.add_argument("--deployment_name_file", type=str, required=False, help="File containing deployment slot name")
parser.add_argument("--default_slot", type=str, required=False, help="Fallback slot to use when no name is provided")
parser.add_argument("--test_data", type=str, required=True, help="Path to test data (CSV or MLTable)")
parser.add_argument("--report_folder", type=str, required=True, help="Folder to save the test results report")
parser.add_argument("--deploy_status", type=str, required=False, help="Dummy dependency folder from deployment job")
args = parser.parse_args()

if args.deploy_status:
    print(f"[Dependency Check] deploy_status folder received: {args.deploy_status}")
    if os.path.exists(args.deploy_status):
        print(f"[Dependency Check] deploy_status folder exists and contains: {os.listdir(args.deploy_status)}")
    else:
        print(f"[Dependency Check] deploy_status folder path does not exist!")

print("Initializing MLClient for endpoint testing...")
msi_client_id = os.environ.get("DEFAULT_IDENTITY_CLIENT_ID")
credential = ManagedIdentityCredential(client_id=msi_client_id)

from azureml.core.run import Run
run = Run.get_context(allow_offline=False)
ws = run.experiment.workspace
ml_client = MLClient(
    credential=credential,
    subscription_id=ws._subscription_id,
    resource_group_name=ws._resource_group,
    workspace_name=ws._workspace_name,
)

print(f"Getting endpoint: {args.endpoint_name}")
endpoint = ml_client.online_endpoints.get(name=args.endpoint_name)


def _resolve_deployment_name() -> str:
    preferred = (args.deployment_name or "").strip()
    if preferred:
        return preferred
    if args.deployment_name_file and os.path.exists(args.deployment_name_file):
        with open(args.deployment_name_file, "r", encoding="utf-8") as slot_file:
            value = slot_file.read().strip()
            if value:
                return value
    return (args.default_slot or "").strip()


resolved_deployment = _resolve_deployment_name()
if resolved_deployment:
    print(f"Targeting deployment slot: {resolved_deployment}")

# Load test data
def load_test_data(path):
    if path.endswith(".csv"):
        return pd.read_csv(path)
    elif os.path.isdir(path):
        # Assume MLTable folder with data.csv inside
        for file in os.listdir(path):
            if file.endswith(".csv"):
                return pd.read_csv(os.path.join(path, file))
        raise FileNotFoundError("No CSV found in MLTable folder")
    else:
        raise ValueError("Unsupported test data format")

test_df = load_test_data(args.test_data)

sample_df = test_df.head(min(len(test_df), 10)).copy()
target_values: Optional[List[str]] = None
if "cost" in sample_df.columns:
    target_values = sample_df.pop("cost").astype(str).tolist()

payload = {
    "input_data": {
        "columns": list(sample_df.columns),
        "data": sample_df.values.tolist(),
    }
}

print("Invoking endpoint using MLClient.invoke()...")
try:
    tmp_payload_path = ""
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as payload_file:
        json.dump(payload, payload_file)
        tmp_payload_path = payload_file.name

    raw_response = ml_client.online_endpoints.invoke(
        endpoint_name=args.endpoint_name,
        deployment_name=resolved_deployment or None,
        request_file=tmp_payload_path,
        content_type="application/json",
    )
    status_code = 200
    if isinstance(raw_response, bytes):
        response_text = raw_response.decode("utf-8")
    else:
        response_text = str(raw_response)
except Exception as exc:
    status_code = 500
    response_text = f"{exc.__class__.__name__}: {exc}"
finally:
    if "tmp_payload_path" in locals() and tmp_payload_path and os.path.exists(tmp_payload_path):
        os.remove(tmp_payload_path)

predictions: Optional[List[str]] = None
if status_code == 200:
    try:
        predictions = json.loads(response_text)
        if isinstance(predictions, dict) and "predictions" in predictions:
            predictions = predictions["predictions"]
        if isinstance(predictions, list):
            predictions = [str(item) for item in predictions]
        else:
            predictions = None
    except json.JSONDecodeError:
        predictions = None

match_rate: Optional[float] = None
if target_values and predictions and len(predictions) == len(target_values):
    total = len(predictions)
    matches = sum(1 for truth, pred in zip(target_values, predictions) if pred == truth)
    match_rate = matches / total if total else None


# Ensure the output folder exists
os.makedirs(args.report_folder, exist_ok=True)

# Determine report file name based on endpoint_name
endpoint_name_lower = args.endpoint_name.lower()
if "-ex-" in endpoint_name_lower or endpoint_name_lower.endswith("-ex"):
    report_filename = "test_endpoint_ex_report.txt"
elif "-ws-" in endpoint_name_lower or endpoint_name_lower.endswith("-ws"):
    report_filename = "test_endpoint_ws_report.txt"
else:
    report_filename = "test_endpoint_report.txt"

report_path = os.path.join(args.report_folder, report_filename)
with open(report_path, "w") as f:
    f.write(f"Status code: {status_code}\n")
    f.write(f"Response: {response_text}\n")
    if predictions is not None:
        f.write(f"Predictions: {predictions}\n")
    if match_rate is not None:
        f.write(f"Match rate: {match_rate:.4f}\n")

print("Test results saved to", report_path)

if status_code != 200:
    raise SystemExit("Endpoint invocation failed; reverting to previous deployment required.")
