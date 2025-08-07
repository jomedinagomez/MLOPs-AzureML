# Azure ML Platform Deployment Automation Script
# PowerShell script to automate the complete deployment process

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("dev", "prod", "both")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipRBAC,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Configuration
$Config = @{
    SubscriptionId = $SubscriptionId
    Location = "canadacentral"
    LocationCode = "cc"
    
    Dev = @{
        Purpose = "dev"
        RandomString = "004"
        VNetCIDR = "10.1.0.0/16"
        SubnetCIDR = "10.1.1.0/24"
        AutoPurge = $true
        ResourceGroups = @(
            "rg-aml-vnet-dev-cc004",
            "rg-aml-ws-dev-cc",
            "rg-aml-reg-dev-cc"
        )
        Resources = @{
            Workspace = "amlwsdevcc004"
            Registry = "amlregdevcc004"
            Storage = "stdevcc004"
            KeyVault = "kvdevcc004"
            VNet = "vnet-amldevcc004"
        }
    }
    
    Prod = @{
        Purpose = "prod"
        RandomString = "001"
        VNetCIDR = "10.2.0.0/16"
        SubnetCIDR = "10.2.1.0/24"
        AutoPurge = $false
        ResourceGroups = @(
            "rg-aml-vnet-prod-cc001",
            "rg-aml-ws-prod-cc",
            "rg-aml-reg-prod-cc"
        )
        Resources = @{
            Workspace = "amlwsprodcc001"
            Registry = "amlregprodcc001"
            Storage = "stprodcc001"
            KeyVault = "kvprodcc001"
            VNet = "vnet-amlprodcc001"
        }
    }
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO" { "White" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "INFO"
    
    # Check Azure CLI
    try {
        $azVersion = az version --query '\"azure-cli\"' -o tsv
        Write-Log "Azure CLI version: $azVersion" "SUCCESS"
    }
    catch {
        Write-Log "Azure CLI not found. Please install Azure CLI." "ERROR"
        exit 1
    }
    
    # Check Azure ML extension
    try {
        $mlExtension = az extension show --name ml --query name -o tsv 2>$null
        if ($mlExtension -eq "ml") {
            Write-Log "Azure ML CLI extension found" "SUCCESS"
        }
        else {
            Write-Log "Installing Azure ML CLI extension..." "INFO"
            az extension add --name ml
        }
    }
    catch {
        Write-Log "Installing Azure ML CLI extension..." "INFO"
        az extension add --name ml
    }
    
    # Check Terraform
    try {
        $tfVersion = terraform version -json | ConvertFrom-Json | Select-Object -ExpandProperty terraform_version
        Write-Log "Terraform version: $tfVersion" "SUCCESS"
    }
    catch {
        Write-Log "Terraform not found. Please install Terraform." "ERROR"
        exit 1
    }
    
    # Check subscription access
    try {
        $currentSub = az account show --query id -o tsv
        if ($currentSub -eq $Config.SubscriptionId) {
            Write-Log "Connected to correct subscription: $currentSub" "SUCCESS"
        }
        else {
            Write-Log "Setting subscription to: $($Config.SubscriptionId)" "INFO"
            az account set --subscription $Config.SubscriptionId
        }
    }
    catch {
        Write-Log "Failed to access subscription. Please run 'az login' first." "ERROR"
        exit 1
    }
}

# Function to create Terraform variable files
function New-TerraformVars {
    param(
        [string]$EnvType
    )
    
    $envConfig = $Config.$EnvType
    
    $tfVarsContent = @"
# Azure ML Platform - $EnvType Environment Configuration
# Generated: $(Get-Date)

# Base configuration
prefix        = "aml"
purpose       = "$($envConfig.Purpose)"
location      = "$($Config.Location)"
location_code = "$($Config.LocationCode)"
naming_suffix = "$($envConfig.NamingSuffix)"

# Resource prefixes
resource_prefixes = {
  vnet               = "vnet-aml"
  subnet             = "subnet-aml"
  workspace          = "amlws"
  registry           = "amlreg"
  storage            = "amlst"
  container_registry = "amlacr"
  key_vault          = "amlkv"
  log_analytics      = "amllog"
}

# Networking configuration
vnet_address_space    = "$($envConfig.VNetCIDR)"
subnet_address_prefix = "$($envConfig.SubnetCIDR)"

# Environment-specific settings
enable_auto_purge = $($envConfig.AutoPurge.ToString().ToLower())

# Resource tagging
tags = {
  environment  = "$($envConfig.Purpose)"
  project      = "ml-platform"
  created_by   = "terraform"
  owner        = "ml-team"
  cost_center  = "$($envConfig.Purpose)-ml"
  deployed_at  = "$(Get-Date -Format 'yyyy-MM-dd')"
}
"@

    $filePath = "terraform.tfvars.$($envConfig.Purpose)"
    $tfVarsContent | Out-File -FilePath $filePath -Encoding UTF8
    Write-Log "Created Terraform variables file: $filePath" "SUCCESS"
}

# Function to deploy infrastructure
function Deploy-Infrastructure {
    param(
        [string]$EnvType
    )
    
    $envConfig = $Config.$EnvType
    
    Write-Log "Starting infrastructure deployment for $EnvType environment..." "INFO"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would deploy $EnvType infrastructure" "WARNING"
        return
    }
    
    try {
        # Initialize Terraform if needed
        if (-not (Test-Path ".terraform")) {
            Write-Log "Initializing Terraform..." "INFO"
            terraform init
        }
        
        # Create terraform variables file
        New-TerraformVars -EnvType $EnvType
        
        # Plan deployment
        Write-Log "Planning $EnvType deployment..." "INFO"
        $planFile = "$($envConfig.Purpose).tfplan"
        terraform plan -var-file="terraform.tfvars.$($envConfig.Purpose)" -out=$planFile
        
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform plan failed"
        }
        
        # Apply deployment
        if ($Force -or (Read-Host "Apply $EnvType deployment? (y/N)") -eq 'y') {
            Write-Log "Applying $EnvType deployment..." "INFO"
            terraform apply $planFile
            
            if ($LASTEXITCODE -ne 0) {
                throw "Terraform apply failed"
            }
            
            # Save outputs
            $outputFile = "$($envConfig.Purpose)-outputs.txt"
            terraform output > $outputFile
            Write-Log "Terraform outputs saved to: $outputFile" "SUCCESS"
            
            Write-Log "$EnvType infrastructure deployment completed successfully!" "SUCCESS"
        }
        else {
            Write-Log "$EnvType deployment cancelled by user" "WARNING"
        }
    }
    catch {
        Write-Log "Infrastructure deployment failed: $_" "ERROR"
        throw
    }
}

# Function to configure RBAC
function Set-RBACConfiguration {
    param(
        [string]$EnvType
    )
    
    if ($SkipRBAC) {
        Write-Log "Skipping RBAC configuration (--SkipRBAC specified)" "WARNING"
        return
    }
    
    $envConfig = $Config.$EnvType
    
    Write-Log "Configuring RBAC for $EnvType environment..." "INFO"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would configure RBAC for $EnvType" "WARNING"
        return
    }
    
    try {
        # Get managed identity IDs from Terraform outputs
        $workspaceMI = terraform output -raw "$($envConfig.Purpose)_workspace_managed_identity_id"
        $computeMI = terraform output -raw "$($envConfig.Purpose)_compute_managed_identity_id"
        
        if (-not $workspaceMI -or -not $computeMI) {
            Write-Log "Failed to get managed identity IDs from Terraform outputs" "ERROR"
            return
        }
        
        Write-Log "Workspace MI: $workspaceMI" "INFO"
        Write-Log "Compute MI: $computeMI" "INFO"
        
        # Configure workspace UAMI roles
        Write-Log "Configuring workspace managed identity roles..." "INFO"
        
        $workspaceRoles = @(
            @{
                Role = "Azure AI Administrator"
                Scope = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($envConfig.ResourceGroups[0])"
            },
            @{
                Role = "Azure AI Enterprise Network Connection Approver"
                Scope = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($envConfig.ResourceGroups[2])/providers/Microsoft.MachineLearningServices/registries/$($envConfig.Resources.Registry)"
            },
            @{
                Role = "Storage Blob Data Owner"
                Scope = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($envConfig.ResourceGroups[1])/providers/Microsoft.Storage/storageAccounts/$($envConfig.Resources.Storage)"
            }
        )
        
        foreach ($roleAssignment in $workspaceRoles) {
            Write-Log "Assigning role '$($roleAssignment.Role)' to workspace MI..." "INFO"
            az role assignment create --assignee $workspaceMI --role $roleAssignment.Role --scope $roleAssignment.Scope
        }
        
        # Configure compute UAMI roles
        Write-Log "Configuring compute managed identity roles..." "INFO"
        
        $computeRoles = @(
            @{
                Role = "AzureML Data Scientist"
                Scope = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($envConfig.ResourceGroups[1])/providers/Microsoft.MachineLearningServices/workspaces/$($envConfig.Resources.Workspace)"
            },
            @{
                Role = "Storage Blob Data Contributor"
                Scope = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($envConfig.ResourceGroups[1])/providers/Microsoft.Storage/storageAccounts/$($envConfig.Resources.Storage)"
            },
            @{
                Role = "AzureML Registry User"
                Scope = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($envConfig.ResourceGroups[2])/providers/Microsoft.MachineLearningServices/registries/$($envConfig.Resources.Registry)"
            }
        )
        
        foreach ($roleAssignment in $computeRoles) {
            Write-Log "Assigning role '$($roleAssignment.Role)' to compute MI..." "INFO"
            az role assignment create --assignee $computeMI --role $roleAssignment.Role --scope $roleAssignment.Scope
        }
        
        Write-Log "RBAC configuration for $EnvType completed successfully!" "SUCCESS"
    }
    catch {
        Write-Log "RBAC configuration failed: $_" "ERROR"
        throw
    }
}

# Function to configure cross-environment access
function Set-CrossEnvironmentAccess {
    if ($SkipRBAC) {
        Write-Log "Skipping cross-environment access configuration (--SkipRBAC specified)" "WARNING"
        return
    }
    
    Write-Log "Configuring cross-environment access..." "INFO"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would configure cross-environment access" "WARNING"
        return
    }
    
    try {
        # Get production managed identity IDs
        $prodComputeMI = terraform output -raw "prod_compute_managed_identity_id"
        $prodWorkspaceMI = terraform output -raw "prod_workspace_managed_identity_id"
        
        # Give production compute MI access to dev registry
        Write-Log "Granting prod compute MI access to dev registry..." "INFO"
        az role assignment create `
            --assignee $prodComputeMI `
            --role "AzureML Registry User" `
            --scope "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.Dev.ResourceGroups[2])/providers/Microsoft.MachineLearningServices/registries/$($Config.Dev.Resources.Registry)"
        
        # Give production workspace MI network access to dev registry
        Write-Log "Granting prod workspace MI network access to dev registry..." "INFO"
        az role assignment create `
            --assignee $prodWorkspaceMI `
            --role "Azure AI Enterprise Network Connection Approver" `
            --scope "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.Dev.ResourceGroups[2])/providers/Microsoft.MachineLearningServices/registries/$($Config.Dev.Resources.Registry)"
        
        # Configure outbound rule for cross-environment connectivity
        Write-Log "Configuring outbound rule for cross-environment connectivity..." "INFO"
        
        $outboundRuleBody = @{
            properties = @{
                type = "PrivateEndpoint"
                destination = @{
                    serviceResourceId = "/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.Dev.ResourceGroups[2])/providers/Microsoft.MachineLearningServices/registries/$($Config.Dev.Resources.Registry)"
                    subresourceTarget = "amlregistry"
                }
                category = "UserDefined"
            }
        } | ConvertTo-Json -Depth 10
        
        $uri = "https://management.azure.com/subscriptions/$($Config.SubscriptionId)/resourceGroups/$($Config.Prod.ResourceGroups[1])/providers/Microsoft.MachineLearningServices/workspaces/$($Config.Prod.Resources.Workspace)/outboundRules/allow-dev-registry?api-version=2024-10-01-preview"
        
        az rest --method PUT --url $uri --body $outboundRuleBody
        
        Write-Log "Cross-environment access configuration completed successfully!" "SUCCESS"
    }
    catch {
        Write-Log "Cross-environment access configuration failed: $_" "ERROR"
        throw
    }
}

# Function to verify deployment
function Test-Deployment {
    param(
        [string]$EnvType
    )
    
    $envConfig = $Config.$EnvType
    
    Write-Log "Verifying $EnvType deployment..." "INFO"
    
    try {
        # Test workspace connectivity
        $workspace = az ml workspace show --name $envConfig.Resources.Workspace --resource-group $envConfig.ResourceGroups[1] --query "name" -o tsv
        if ($workspace -eq $envConfig.Resources.Workspace) {
            Write-Log "✅ Workspace '$workspace' is accessible" "SUCCESS"
        }
        else {
            Write-Log "❌ Workspace '$($envConfig.Resources.Workspace)' is not accessible" "ERROR"
        }
        
        # Test registry connectivity
        $registry = az ml registry show --name $envConfig.Resources.Registry --resource-group $envConfig.ResourceGroups[2] --query "name" -o tsv
        if ($registry -eq $envConfig.Resources.Registry) {
            Write-Log "✅ Registry '$registry' is accessible" "SUCCESS"
        }
        else {
            Write-Log "❌ Registry '$($envConfig.Resources.Registry)' is not accessible" "ERROR"
        }
        
        # Test storage connectivity
        $storage = az storage account show --name $envConfig.Resources.Storage --resource-group $envConfig.ResourceGroups[1] --query "name" -o tsv
        if ($storage -eq $envConfig.Resources.Storage) {
            Write-Log "✅ Storage account '$storage' is accessible" "SUCCESS"
        }
        else {
            Write-Log "❌ Storage account '$($envConfig.Resources.Storage)' is not accessible" "ERROR"
        }
        
        Write-Log "$EnvType deployment verification completed!" "SUCCESS"
    }
    catch {
        Write-Log "Deployment verification failed: $_" "ERROR"
        throw
    }
}

# Function to create test promotion script
function New-PromotionTestScript {
    $testScript = @'
# Test Asset Promotion Script
from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential

def test_promotion_connectivity():
    """Test connectivity for asset promotion workflow"""
    
    credential = DefaultAzureCredential()
    subscription_id = "5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25"
    
    try:
        # Initialize clients
        ml_client_dev_workspace = MLClient(
            credential=credential,
            subscription_id=subscription_id,
            resource_group_name="rg-aml-ws-dev-cc",
            workspace_name="amlwsdevcc004"
        )
        
        ml_client_dev_registry = MLClient(
            credential=credential,
            subscription_id=subscription_id,
            registry_name="amlregdevcc004"
        )
        
        ml_client_prod_registry = MLClient(
            credential=credential,
            subscription_id=subscription_id,
            registry_name="amlregprodcc001"
        )
        
        print("✅ All ML clients initialized successfully")
        
        # Test registry access
        dev_models = list(ml_client_dev_registry.models.list())
        prod_models = list(ml_client_prod_registry.models.list())
        
        print(f"✅ Dev registry: {len(dev_models)} models found")
        print(f"✅ Prod registry: {len(prod_models)} models found")
        
        print("🎉 Asset promotion connectivity test passed!")
        
    except Exception as e:
        print(f"❌ Connectivity test failed: {e}")

if __name__ == "__main__":
    test_promotion_connectivity()
'@

    $testScript | Out-File -FilePath "test_promotion_connectivity.py" -Encoding UTF8
    Write-Log "Created promotion test script: test_promotion_connectivity.py" "SUCCESS"
}

# Main execution
function Main {
    Write-Log "Azure ML Platform Deployment Automation" "INFO"
    Write-Log "Environment: $Environment" "INFO"
    Write-Log "Subscription: $($Config.SubscriptionId)" "INFO"
    
    if ($DryRun) {
        Write-Log "DRY RUN MODE: No actual changes will be made" "WARNING"
    }
    
    # Check prerequisites
    Test-Prerequisites
    
    # Navigate to infrastructure directory
    $infraPath = Join-Path $PSScriptRoot "infra"
    if (Test-Path $infraPath) {
        Set-Location $infraPath
        Write-Log "Changed to infrastructure directory: $infraPath" "INFO"
    }
    else {
        Write-Log "Infrastructure directory not found: $infraPath" "ERROR"
        exit 1
    }
    
    try {
        switch ($Environment) {
            "dev" {
                Deploy-Infrastructure -EnvType "Dev"
                Set-RBACConfiguration -EnvType "Dev"
                Test-Deployment -EnvType "Dev"
            }
            "prod" {
                Deploy-Infrastructure -EnvType "Prod"
                Set-RBACConfiguration -EnvType "Prod"
                Test-Deployment -EnvType "Prod"
            }
            "both" {
                # Deploy development first
                Deploy-Infrastructure -EnvType "Dev"
                Set-RBACConfiguration -EnvType "Dev"
                Test-Deployment -EnvType "Dev"
                
                # Deploy production
                Deploy-Infrastructure -EnvType "Prod"
                Set-RBACConfiguration -EnvType "Prod"
                Test-Deployment -EnvType "Prod"
                
                # Configure cross-environment access
                Set-CrossEnvironmentAccess
            }
        }
        
        # Create test scripts
        New-PromotionTestScript
        
        Write-Log "Deployment automation completed successfully! 🎉" "SUCCESS"
        Write-Log "Next steps:" "INFO"
        Write-Log "1. Test asset promotion with: python test_promotion_connectivity.py" "INFO"
        Write-Log "2. Create your first ML model and test the promotion workflow" "INFO"
        Write-Log "3. Configure monitoring and alerts as needed" "INFO"
    }
    catch {
        Write-Log "Deployment automation failed: $_" "ERROR"
        exit 1
    }
}

# Execute main function
Main
