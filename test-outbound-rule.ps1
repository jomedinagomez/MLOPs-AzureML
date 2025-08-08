$ErrorActionPreference = 'Stop'
$wsId = '/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-ws-dev-cc01/providers/Microsoft.MachineLearningServices/workspaces/mlwdevcc01'
$regId = '/subscriptions/5784b6a5-de3f-4fa4-8b8f-e5bb70ff6b25/resourceGroups/rg-aml-reg-dev-cc01/providers/Microsoft.MachineLearningServices/registries/mlrdevcc01'

function Invoke-RuleTest {
    param(
        [string]$RuleName,
        [hashtable]$Destination
    )
    $payload = @{ properties = @{ type = 'PrivateEndpoint'; category = 'UserDefined'; destination = $Destination } } | ConvertTo-Json -Depth 8
    Write-Host "===== Testing $RuleName =====" -ForegroundColor Cyan
    Write-Host $payload
    try {
    $url = 'https://management.azure.com' + $wsId + '/outboundRules/' + $RuleName + '?api-version=2024-10-01-preview'
    az rest --method put --url $url --body $payload --headers 'Content-Type=application/json' --only-show-errors -o json | ConvertFrom-Json | Select-Object id,name,properties | Format-List
    }
    catch {
        Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Variant 1: documented key 'subresourceTarget'
Invoke-RuleTest -RuleName 'TestRegOutbound1' -Destination @{ serviceResourceId = $regId; subresourceTarget = 'amlregistry' }

# Variant 2: alternate camelCase 'subResourceTarget'
Invoke-RuleTest -RuleName 'TestRegOutbound2' -Destination @{ serviceResourceId = $regId; subResourceTarget = 'amlregistry' }

# Variant 3: attempt adding both keys sequentially
$dest3 = @{ serviceResourceId = $regId; subresourceTarget = 'amlregistry' }
$dest3.subResourceTarget = 'amlregistry'
Invoke-RuleTest -RuleName 'TestRegOutbound3' -Destination $dest3
