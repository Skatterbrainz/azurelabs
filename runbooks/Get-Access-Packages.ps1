# https://techcommunity.microsoft.com/t5/integrations-on-azure-blog/grant-graph-api-permission-to-managed-identity-object/ba-p/2792127
[CmdletBinding()]
param ()

try {
	Import-Module Microsoft.Graph.Identity.Governance
	Connect-MgGraph -Scopes 'EntitlementManagement.Read.All'
	Select-MgProfile -Name "beta"
	Write-Output "connected to graph"
	Get-MgEntitlementManagementAccessPackage
	Write-Output "completed!"
}
catch {
	$_.Exception
}
finally {
	Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
	Write-Output "disconnected"
}