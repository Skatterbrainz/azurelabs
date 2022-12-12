[CmdletBinding()]
param()

$ErrorActionPreference = "stop"

try {
	$azCred = Get-AutomationPSCredential -Name 'Automation-AzureAD'
	$opCred = Get-AutomationPSCredential -Name 'Automation-OnPrem'

	Import-Module ActiveDirectory
	Import-Module AzureAD

	[string]$OUSearchPath = "OU=Users,OU=CORP,DC=contoso,DC=local"

	[array]$adUsers = Get-ADUser -Filter * -SearchBase $OUSearchPath -Credential $opCred | 
		Where-Object {$_.Enabled -eq $True} | 
			Select-Object SamAccountName,UserPrincipalName

	$conn = Connect-AzureAD -Credential $azCred

	[array]$aadUsers = $users = Get-AzureADUser -Filter "userType eq 'Member' and accountEnabled eq true" |
		Where-Object {$_.UserPrincipalName -notlike '*sync*' -and $_.DirSyncEnabled -ne $true -and $_.ImmutableId -eq $null} |
			Foreach-Object {
				$sam = $($_.UserPrincipalName -split '@')[0]
				[pscustomobject]@{
					DisplayName = $_.DisplayName
					UserPrincipalName = $_.UserPrincipalName
					SamAccountName = $sam
				}
			}

	[array]$pending  = $aadusers | Where-Object {$_.SamAccountName -notin $adUsers.SamAccountName}
	[array]$complete = $aadusers | Where-Object {$_.SamAccountName -in $adUsers.SamAccountName}

}
catch {
	$_.Exception
}
finally {
	Disconnect-AzureAD
	$pending | Format-Table
}