import json
import os
import urllib.error
import urllib.parse
import urllib.request

import mlflow


token_query = urllib.parse.urlencode(
    {
        "api-version": "2018-02-01",
        "resource": "https://ml.azure.com",
        "client_id": os.environ["MANAGED_IDENTITY_CLIENT_ID"],
    }
)
token_request = urllib.request.Request(
    f"http://169.254.169.254/metadata/identity/oauth2/token?{token_query}",
    headers={"Metadata": "true"},
)
with urllib.request.urlopen(token_request, timeout=30) as response:
    access_token = json.load(response)["access_token"]

probe_request = urllib.request.Request(
    os.environ["BATCH_ENDPOINT_URI"],
    data=b"{}",
    method="POST",
    headers={
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "azureml-model-deployment": os.environ["BATCH_DEPLOYMENT_NAME"],
    },
)
try:
    with urllib.request.urlopen(probe_request, timeout=60) as response:
        status = response.status
        body = response.read().decode("utf-8")
except urllib.error.HTTPError as error:
    status = error.code
    body = error.read().decode("utf-8")

mlflow.log_param("probe_http_status", str(status))
mlflow.set_tag("probe_response", body[:500])
print(json.dumps({"probe_http_status": status, "response": body[:500]}))