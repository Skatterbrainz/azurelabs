[CmdletBinding()]
param (
	[parameter(Mandatory=$False)][string]$HybridWorkerName = ""
)
try {
	if ([string]::IsNullOrEmpty($HybridWorkerName)) {
		throw "HybridWorkerName was not specified"
	}
	if (-not(Get-Module Az.OperationalInsights -ListAvailable)) {
		throw "Module not installed: Az.OperationalInsights"
	}
	$query = @"
Heartbeat
| summarize arg_max(TimeGenerated, *) by Computer
| extend Elapsed = now() - TimeGenerated
| extend hours   = datetime_diff('hour', now(), TimeGenerated)
| extend seconds = datetime_diff('second', now(), TimeGenerated)
| extend minutes = datetime_diff('minute', now(), TimeGenerated)
| project Computer, TimeGenerated, Elapsed, hours, minutes, seconds
| order by Computer
"@
	$conn = Connect-AzAccount -Identity
	$WorkspaceID = Get-AutomationVariable -Name 'WorkspaceID'
	$response = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $query | Select-Object -ExpandProperty Results
	$result = $response | Where-Object {$_.Computer -eq $HybridWorkerName}
}
catch {
	$_.Exception.Message
}
finally {
	Write-Output $result
}