import argparse
from pathlib import Path
from uuid import uuid4
from datetime import datetime
import os
import pandas as pd
import numpy as np
import mlflow
from sklearn.model_selection import train_test_split
import mltable

#### Client Getting ML Client
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

parser = argparse.ArgumentParser("transform")
parser.add_argument("--clean_data", type=str, help="Path to prepped data")
parser.add_argument("--train_data", type=str, help="Path of train output data")
parser.add_argument("--test_data", type=str, help="Path of test output data")
parser.add_argument("--test_split_ratio", type=float, help="ratio of train test split")

args = parser.parse_args()


lines = [
    f"Clean data path: {args.clean_data}",
    f"Transformed data output path for train data: {args.train_data}",
    f"Transformed data output path for test data: {args.test_data}",
]

for line in lines:
    print(line)

print("mounted_path files: ")
arr = os.listdir(args.clean_data)
print(arr)

df_list = []
for filename in arr:
    print("reading file: %s ..." % filename)
    with open(os.path.join(args.clean_data, filename), "r") as handle:
        # print (handle.read())
        # ('input_df_%s' % filename) = pd.read_csv((Path(args.training_data) / filename))
        input_df = pd.read_csv((Path(args.clean_data) / filename))
        df_list.append(input_df)


# Transform the data
combined_df = df_list[0]
# These functions filter out coordinates for locations that are outside the city border.

# Filter out coordinates for locations that are outside the city border.
# Chain the column filter commands within the filter() function
# and define the minimum and maximum bounds for each field

combined_df = combined_df.astype(
    {
        "pickup_longitude": "float64",
        "pickup_latitude": "float64",
        "dropoff_longitude": "float64",
        "dropoff_latitude": "float64",
    }
)

latlong_filtered_df = combined_df[
    (combined_df.pickup_longitude <= -73.72)
    & (combined_df.pickup_longitude >= -74.09)
    & (combined_df.pickup_latitude <= 40.88)
    & (combined_df.pickup_latitude >= 40.53)
    & (combined_df.dropoff_longitude <= -73.72)
    & (combined_df.dropoff_longitude >= -74.72)
    & (combined_df.dropoff_latitude <= 40.88)
    & (combined_df.dropoff_latitude >= 40.53)
]

latlong_filtered_df.reset_index(inplace=True, drop=True)

# These functions replace undefined values and rename to use meaningful names.
replaced_stfor_vals_df = latlong_filtered_df.replace(
    {"store_forward": "0"}, {"store_forward": "N"}
).fillna({"store_forward": "N"})

replaced_distance_vals_df = replaced_stfor_vals_df.replace(
    {"distance": ".00"}, {"distance": 0}
).fillna({"distance": 0})

normalized_df = replaced_distance_vals_df.astype({"distance": "float64"})

# These functions transform the renamed data to be used finally for training.

# Split the pickup and dropoff date further into the day of the week, day of the month, and month values.
# To get the day of the week value, use the derive_column_by_example() function.
# The function takes an array parameter of example objects that define the input data,
# and the preferred output. The function automatically determines your preferred transformation.
# For the pickup and dropoff time columns, split the time into the hour, minute, and second by using
# the split_column_by_example() function with no example parameter. After you generate the new features,
# use the drop_columns() function to delete the original fields as the newly generated features are preferred.
# Rename the rest of the fields to use meaningful descriptions.

temp = pd.DatetimeIndex(normalized_df["pickup_datetime"], dtype="datetime64[ns]")
normalized_df["pickup_date"] = temp.date
normalized_df["pickup_weekday"] = temp.dayofweek
normalized_df["pickup_month"] = temp.month
normalized_df["pickup_monthday"] = temp.day
normalized_df["pickup_time"] = temp.time
normalized_df["pickup_hour"] = temp.hour
normalized_df["pickup_minute"] = temp.minute
normalized_df["pickup_second"] = temp.second

temp = pd.DatetimeIndex(normalized_df["dropoff_datetime"], dtype="datetime64[ns]")
normalized_df["dropoff_date"] = temp.date
normalized_df["dropoff_weekday"] = temp.dayofweek
normalized_df["dropoff_month"] = temp.month
normalized_df["dropoff_monthday"] = temp.day
normalized_df["dropoff_time"] = temp.time
normalized_df["dropoff_hour"] = temp.hour
normalized_df["dropoff_minute"] = temp.minute
normalized_df["dropoff_second"] = temp.second

del normalized_df["pickup_datetime"]
del normalized_df["dropoff_datetime"]

normalized_df.reset_index(inplace=True, drop=True)


print(normalized_df.head)
print(normalized_df.dtypes)


# Drop the pickup_date, dropoff_date, pickup_time, dropoff_time columns because they're
# no longer needed (granular time features like hour,
# minute and second are more useful for model training).
del normalized_df["pickup_date"]
del normalized_df["dropoff_date"]
del normalized_df["pickup_time"]
del normalized_df["dropoff_time"]

# Change the store_forward column to binary values
normalized_df["store_forward"] = np.where((normalized_df.store_forward == "N"), 0, 1)

# Before you package the dataset, run two final filters on the dataset.
# To eliminate incorrectly captured data points,
# filter the dataset on records where both the cost and distance variable values are greater than zero.
# This step will significantly improve machine learning model accuracy,
# because data points with a zero cost or distance represent major outliers that throw off prediction accuracy.

final_df = normalized_df[(normalized_df.distance > 0) & (normalized_df.cost > 0)]
final_df.reset_index(inplace=True, drop=True)

categorical_target = categorical_target = list(pd.cut(final_df['cost'], list(final_df['cost'].quantile([.1, .2, .3, .4, .5, .6 , .7, .8, .9, 1])), labels = ['B','C','D','E','F','G','H','I','J'], retbins=False))
final_df['cost'] = categorical_target
final_df['cost'] = final_df['cost'].fillna("A")
print(len(final_df))

print(final_df.head())


# Splitting data on train/test

print(final_df.columns)

# Split the data into input(X) and output(y)
y = final_df["cost"]
# X = train_data.drop(['cost'], axis=1)
X = final_df[
    ["distance", "dropoff_latitude", "dropoff_longitude", "passengers", "pickup_latitude","pickup_longitude","store_forward","vendor","pickup_weekday","pickup_month","pickup_monthday","pickup_hour","pickup_minute","pickup_second","dropoff_weekday","dropoff_month","dropoff_monthday","dropoff_hour","dropoff_minute","dropoff_second",]
]

# Split the data into train and test sets
trainX, testX, trainy, testy = train_test_split(
    X, y, test_size=args.test_split_ratio, random_state=42, stratify = y
)
print(trainX.shape)
print(trainX.columns)

##-----------------------------------------------------------------
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Data

# test_data = pd.DataFrame(testX, columns = )
testX["cost"] = testy
print(testX.shape)

#Saving CSV File to test_data location
test_data_location = str(Path(args.test_data) / "test_data.csv")
print(test_data_location)
test_data = testX.to_csv(test_data_location,index=False)

## Save mlflow table to output folder
paths = [{"file": test_data_location}]
tbl = mltable.from_delimited_files(paths = paths)
tbl.save(str(Path(args.test_data)))

## Create and update dataset
tbl.save(str(Path(args.test_data)))

## Save register dataset

my_data = Data(
    path=str(Path(args.test_data)),
    type=AssetTypes.MLTABLE,
    description="The titanic dataset.",
    name="cat-sample-test-data",)

ml_client.data.create_or_update(my_data)


##-----------------------------------------------------------------

# train_data = pd.DataFrame(trainX, columns = )
trainX["cost"] = trainy
print(testX.shape)

#Saving CSV File to train_data location
train_data_location = str(Path(args.train_data) / "train_data.csv")
print(train_data_location)
train_data = trainX.to_csv(train_data_location,index=False)

## Save mlflow table to output folder
paths = [{"file": train_data_location}]
tbl = mltable.from_delimited_files(paths = paths)
tbl.save(str(Path(args.train_data)))

## Create and update dataset
tbl.save(str(Path(args.train_data)))

## Save register dataset

my_data = Data(
    path=str(Path(args.train_data)),
    type=AssetTypes.MLTABLE,
    description="The titanic dataset.",
    name="cat-sample-train-data",)

ml_client.data.create_or_update(my_data)