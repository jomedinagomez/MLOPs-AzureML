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

# Load the model from input port
new_model = mlflow.pyfunc.load_model(str(Path(args.model_input) / "outputs")+"/"+"mlflow-model")

# Make predictions on testX data and record them in a column named predicted_cost

# Compare predictions to actuals (testy)
output_data = pd.DataFrame(testX)
output_data["actual_cost"] = testy
print(output_data)

# Save the output data with feature columns, predicted cost, and actual cost in csv file

output_data["predicted_cost"] = new_model.predict(testX)
new_model_predictions = output_data["predicted_cost"]
output_data = output_data["predicted_cost"]
new_model_accuracy = accuracy_score(testy, new_model_predictions)

##--------------------------------------------------------------------------------------------------------
def compare_metrics(baseline_model_accuracy,new_model_accuracy):
    if baseline_model_accuracy <= new_model_accuracy: ##Change in practice
        print ("candidate improved upon the baseline model (Accuracy):")
        print("baseline accuracy: ", baseline_model_accuracy )
        print("baseline accuracy: ", new_model_accuracy )
    else:
        print("baseline accuracy: ", baseline_model_accuracy )
        print("baseline accuracy: ", new_model_accuracy )
        raise Exception("candidate model does not perform better than baseline model")

target_for_current_downloaded_model = "downloaded_model"
try:

    models = ml_client.models.list(name="taxi-classification")
    model_list = [model for model in models]
    latest_model_version = model_list[0].version
    model = ml_client.models.download(name=args.model_name, version=latest_model_version,download_path=target_for_current_downloaded_model)

    print("We have a version of the model trained")

    full_path_to_cwd = os.path.realpath('.')
    full_path_to_model = (full_path_to_cwd+"/"+target_for_current_downloaded_model+"/"+args.model_name+"/"+"mlflow-model")

    basline_model = mlflow.pyfunc.load_model(full_path_to_model)

    # Make predictions on testX data and record them in a column named predicted_cost
    # Compare predictions to actuals (testy)
    output_data = pd.DataFrame(testX)
    output_data["actual_cost"] = testy
    output_data["base_predicted_cost"] = basline_model.predict(testX)
    base_model_predictions = output_data["base_predicted_cost"]
    output_data = output_data["base_predicted_cost"]
    baseline_model_accuracy = accuracy_score(testy, base_model_predictions)

    compare_metrics(baseline_model_accuracy,new_model_accuracy)

except:
    print("model not yet trained")

# Save the output data with feature columns, predicted cost, and actual cost in csv file
output_data = output_data.to_csv((Path(args.compare_output) / "predictions.csv"),index=False)
