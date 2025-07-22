import argparse
from pathlib import Path
import pandas as pd
# this script is good
parser = argparse.ArgumentParser(description="Merge the green and yellow taxi data")
parser.add_argument("--raw_data_green", type=str, help="Path to green data")
parser.add_argument("--raw_data_yellow", type=str, help="Path to yellow data")
parser.add_argument("--merged_data", type=str, help="Path to merged data output")

args = parser.parse_args()
df_green_taxi = pd.read_csv(args.raw_data_green)
df_yellow_taxi = pd.read_csv(args.raw_data_yellow)


columns_taxi_data_combined = [
    "cost",
    "distance",
    "dropoff_datetime",
    "dropoff_latitude",
    "dropoff_longitude",
    "passengers",
    "pickup_datetime",
    "pickup_latitude",
    "pickup_longitude",
    "store_forward",
    "vendor"
]

green_columns_remap =    {
        "vendorID": "vendor",
        "lpepPickupDatetime": "pickup_datetime",
        "lpepDropoffDatetime": "dropoff_datetime",
        "storeAndFwdFlag": "store_forward",
        "pickupLongitude": "pickup_longitude",
        "pickupLatitude": "pickup_latitude",
        "dropoffLongitude": "dropoff_longitude",
        "dropoffLatitude": "dropoff_latitude",
        "passengerCount": "passengers",
        "fareAmount": "cost",
        "tripDistance": "distance",
    }

df_green_taxi = df_green_taxi.rename(columns=green_columns_remap) 
df_green_taxi = df_green_taxi[columns_taxi_data_combined]

yellow_columns_remap = {
        "vendorID": "vendor",
        "tpepPickupDateTime": "pickup_datetime",
        "tpepDropoffDateTime": "dropoff_datetime",
        "storeAndFwdFlag": "store_forward",
        "startLon": "pickup_longitude",
        "startLat": "pickup_latitude",
        "endLon": "dropoff_longitude",
        "endLat": "dropoff_latitude",
        "passengerCount": "passengers",
        "fareAmount": "cost",
        "tripDistance": "distance",
    }
df_yellow_taxi = df_yellow_taxi.rename(columns=yellow_columns_remap)
df_yellow_taxi = df_yellow_taxi[columns_taxi_data_combined]

df_combined_taxi = pd.concat([df_yellow_taxi, df_green_taxi]) \
                    .dropna(how="all") \
                    .reset_index(drop=True)

print(f'writing merged data to {args.merged_data}')
df_combined_taxi.to_csv(Path(args.merged_data) / "merged_taxi_data.csv", index=False)