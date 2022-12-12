$Credential = Get-AutomationPSCredential -Name 'My_RunAs'
$SubscriptionId = Get-AutomationVariable -Name 'SubscriptionId'
$TenantID = Get-AutomationVariable -Name 'TenantId'
$WorkspaceId = Get-AutomationVariable -Name 'WorkspaceID'

if ($Credential){
    Connect-AzAccount -Scope Process -SubscriptionId $SubscriptionId -Credential $Credential -Tenant $TenantID -ServicePrincipal -ErrorAction Stop | Out-Null
}

$query = @"
VMComputer
| project HostName,OperatingSystemFullName,Ipv4Addresses,AzureSize,AzureLocation,_ResourceId
"@

$results = (Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $Query).Results
#$results[0].TimeGenerated.ToLocalTime()
$results