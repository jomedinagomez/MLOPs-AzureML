import argparse
import pandas as pd
import os
from pathlib import Path
from sklearn.linear_model import LinearRegression
import mlflow
import mltable

mlflow.sklearn.autolog()

#### Client Getting ML Client
print("Initializing MLclient")
from azure.identity import DefaultAzureCredential,ManagedIdentityCredential,AzureCliCredential
from azure.ai.ml import automl, Input, MLClient, command
from azureml.core.run import Run

msi_client_id = os.environ.get("DEFAULT_IDENTITY_CLIENT_ID")
credential = ManagedIdentityCredential(client_id=msi_client_id)
credential.get_token("https://management.azure.com/.default")
run = Run.get_context(allow_offline=False)
ws = run.experiment.workspace
ml_client = MLClient(credential=credential,subscription_id=ws._subscription_id,resource_group_name=ws._resource_group,workspace_name=ws._workspace_name,)
####


parser = argparse.ArgumentParser("predict")
parser.add_argument("--model_input", type=str, help="Path of input model")
parser.add_argument("--test_data", type=str, help="Path to test data")
parser.add_argument("--model_name", type=str, help="Registered Model Name")
parser.add_argument("--predictions", type=str, help="Path of predictions")
parser.add_argument("--compare_output", type=str, help="Path of predictions")

args = parser.parse_args()

print("hello scoring world...")

lines = [
    f"Model path: {args.model_input}",
    f"Model Name: {args.model_name}",
    f"Test data path: {args.test_data}",
    f"Predictions path: {args.predictions}",
    f"Predictions path: {args.compare_output}",
]

for line in lines:
    print(line)

# Load and split the test data

print("mounted_path files: ")
arr = os.listdir(args.test_data)

print(arr)
test_data = mltable.load(str(Path(args.test_data))).to_pandas_dataframe() ## pd.read_csv(Path(args.test_data) / "test_data.csv")
testy = test_data["cost"]
# testX = test_data.drop(['cost'], axis=1)
testX = test_data[
    [
        "distance",
        "dropoff_latitude",
        "dropoff_longitude",
        "passengers",
        "pickup_latitude",
        "pickup_longitude",
        "store_forward",
        "vendor",
        "pickup_weekday",
        "pickup_month",
        "pickup_monthday",
        "pickup_hour",
        "pickup_minute",
        "pickup_second",
        "dropoff_weekday",
        "dropoff_month",
        "dropoff_monthday",
        "dropoff_hour",
        "dropoff_minute",
        "dropoff_second",
    ]
]
print(testX.shape)
print(testX.columns)

##--------------------------------------------------------------------------------------------------------

from sklearn.metrics import mean_squared_error, r2_score,accuracy_score

# Load the new model from input port
new_model = mlflow.pyfunc.load_model(str(Path(args.model_input) / "outputs")+"/"+"mlflow-model")

# Make predictions with the new model
new_model_predictions = new_model.predict(testX)
new_model_accuracy = accuracy_score(testy, new_model_predictions)

print(f"New model accuracy: {new_model_accuracy}")

##--------------------------------------------------------------------------------------------------------
def compare_metrics(baseline_model_accuracy, new_model_accuracy):
    if new_model_accuracy >= baseline_model_accuracy:
        print("Candidate model improved upon the baseline model (Accuracy):")
        print(f"Baseline accuracy: {baseline_model_accuracy}")
        print(f"New model accuracy: {new_model_accuracy}")
        return True
    else:
        print("Candidate model does not perform better than baseline model:")
        print(f"Baseline accuracy: {baseline_model_accuracy}")
        print(f"New model accuracy: {new_model_accuracy}")
        raise Exception("candidate model does not perform better than baseline model")

# Check if a baseline model exists for comparison
target_for_current_downloaded_model = "downloaded_model"
baseline_exists = False

try:
    models = ml_client.models.list(name=args.model_name)
    model_list = [model for model in models]
    if model_list:
        baseline_exists = True
        latest_model_version = model_list[0].version
        print(f"Found existing model version: {latest_model_version}")
        
        # Download the baseline model
        ml_client.models.download(name=args.model_name, version=latest_model_version, download_path=target_for_current_downloaded_model)
        
        full_path_to_cwd = os.path.realpath('.')
        full_path_to_model = os.path.join(full_path_to_cwd, target_for_current_downloaded_model, args.model_name, "mlflow-model")
        
        # Load and evaluate baseline model
        baseline_model = mlflow.pyfunc.load_model(full_path_to_model)
        baseline_predictions = baseline_model.predict(testX)
        baseline_model_accuracy = accuracy_score(testy, baseline_predictions)
        
        print(f"Baseline model accuracy: {baseline_model_accuracy}")
        
        # Compare models
        compare_metrics(baseline_model_accuracy, new_model_accuracy)
        
except Exception as e:
    print(f"No baseline model found for comparison: {e}")
    print("This appears to be the first model - skipping baseline comparison.")

# Create output data with predictions
output_data = pd.DataFrame(testX)
output_data["actual_cost"] = testy
output_data["predicted_cost"] = new_model_predictions

if baseline_exists:
    output_data["baseline_predicted_cost"] = baseline_predictions

print(f"Output data shape: {output_data.shape}")

# Save the output data
output_data.to_csv((Path(args.compare_output) / "predictions.csv"), index=False)
