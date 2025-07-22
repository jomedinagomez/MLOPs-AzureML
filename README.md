# MLOPs-AzureML

## Prerequisites
The Azure CLI and the ml extension to the Azure CLI, installed and configured. For more information, see Install and set up the CLI (v2).

A Bash shell or a compatible shell, for example, a shell on a Linux system or Windows Subsystem for Linux. The Azure CLI examples in this article assume that you use this type of shell.

An Azure Machine Learning workspace.

```json
{
  "azure-cli": "2.75.0",
  "azure-cli-core": "2.75.0",
  "azure-cli-telemetry": "1.1.0",
  "extensions": {
    "azure-firewall": "1.2.2",
    "k8s-extension": "1.6.3",
    "ml": "2.38.0"
  }
}

pip install --pre --upgrade azure-ai-ml azure-identity
```

## How to run code

```
az account set --subscription <subscription>
az configure --defaults workspace=<workspace> group=<resource-group> location=<location>
```