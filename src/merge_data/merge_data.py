import argparse
from pathlib import Path
import pandas as pd
from io import StringIO

# Try to import OneLake dependencies (optional)
try:
    from azure.storage.filedatalake import DataLakeServiceClient
    from azure.identity import ManagedIdentityCredential
    ONELAKE_AVAILABLE = True
except ImportError:
    ONELAKE_AVAILABLE = False
    print("⚠ azure-storage-file-datalake not available. OneLake write will be skipped.")

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

# Write to the standard output location
print(f'Writing merged data to {args.merged_data}')
output_path = Path(args.merged_data) / "merged_taxi_data.csv"
df_combined_taxi.to_csv(output_path, index=False)
print(f'✓ Saved to: {output_path}')

# Also write to OneLake using ABFS
print('\nWriting to OneLake...')
if not ONELAKE_AVAILABLE:
    print('⚠ Skipping OneLake write - azure-storage-file-datalake not installed')
    print('To enable: Add azure-storage-file-datalake to your environment dependencies')
else:
    try:
        # OneLake configuration
        onelake_endpoint = "https://onelake.dfs.fabric.microsoft.com"
        workspace_name = "TechNextWS"
        lakehouse_name = "TechNextLH.Lakehouse"
        
        # Use ManagedIdentityCredential directly for Azure ML compute
        # This works better than DefaultAzureCredential in compute clusters
        credential = ManagedIdentityCredential()
        
        # Create DataLakeServiceClient
        service_client = DataLakeServiceClient(
            account_url=onelake_endpoint,
            credential=credential
        )
        
        # Get file system and directory client
        file_system_client = service_client.get_file_system_client(workspace_name)
        directory_client = file_system_client.get_directory_client(
            f"{lakehouse_name}/Files/uploaded_data"
        )
        
        # Upload the merged data to OneLake
        file_client = directory_client.get_file_client("merged_taxi_data.csv")
        
        # Convert DataFrame to CSV string
        csv_buffer = StringIO()
        df_combined_taxi.to_csv(csv_buffer, index=False)
        csv_data = csv_buffer.getvalue()
        
        # Upload to OneLake
        file_client.upload_data(csv_data, overwrite=True)
        
        onelake_path = f"abfss://{workspace_name}@onelake.dfs.fabric.microsoft.com/{lakehouse_name}/Files/uploaded_data/merged_taxi_data.csv"
        print(f'✓ Saved to OneLake: {onelake_path}')
        
    except Exception as e:
        print(f'⚠ Warning: Could not write to OneLake: {e}')
        print('Continuing with standard output only...')
