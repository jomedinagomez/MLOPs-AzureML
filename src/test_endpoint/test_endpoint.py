
import argparse
import os
import pandas as pd
from azure.identity import ManagedIdentityCredential
from azure.ai.ml import MLClient

parser = argparse.ArgumentParser("test_endpoint")
parser.add_argument("--endpoint_name", type=str, required=True, help="Name of the endpoint to test")
parser.add_argument("--deployment_name", type=str, required=False, help="Deployment name (optional)")
parser.add_argument("--test_data", type=str, required=True, help="Path to test data (CSV or MLTable)")
parser.add_argument("--output_report", type=str, required=True, help="Path to save the test results report")
args = parser.parse_args()

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

# Prepare payload (assume first 10 rows for quick test)
payload = {"input_data": {"columns": list(test_df.columns), "data": test_df.head(10).values.tolist()}}

print("Invoking endpoint using MLClient.invoke()...")
try:
    result = ml_client.online_endpoints.invoke(
        endpoint_name=args.endpoint_name,
        request_payload=payload,
        deployment_name=args.deployment_name if args.deployment_name else None,
    )
    status_code = 200
    response_text = str(result)
except Exception as e:
    status_code = 500
    response_text = str(e)

with open(args.output_report, "w") as f:
    f.write(f"Status code: {status_code}\n")
    f.write(f"Response: {response_text}\n")

print("Test results saved to", args.output_report)
