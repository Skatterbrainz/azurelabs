[CmdletBinding()]
param(
	[parameter(Mandatory=$False)][string] $Path = "C:\GIT\azurelabs\runbooks",
	[parameter(Mandatory=$False)][string] $ResourceGroupName = "rg-cm-lab",
	[parameter(Mandatory=$False)][string] $AutomationAccount = "aa-cm-lab",
	[parameter(Mandatory=$False)][pscredential] $Credential,
	[parameter(Mandatory=$False)][switch]$ListOnly,
	[parameter(Mandatory=$False)][string]$Filter = "*"
)

try {
	if (!$Credential) {
		if (!$global:azConn) {
			$global:azConn = Connect-AzAccount
		}
	}
	$runbooks = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount |
		Where-Object {$_.Name -notlike 'AzureAutomationTutorial*'}
	if ($Filter -ne '*') { [array]$runbooks = $runbooks | Where-Object {$_.Name -like $Filter} }

	$runbooks | Foreach-Object { 
		if (-not $ListOnly) {
			Write-Host "Exporting: $($_.Name)"
			<#
			if ($_.Name -like "WD*") {
				$dlpath = "C:\GIT\cat-tmhcc\workday\runbooks" #"$Path\workday"
			} elseif ($_.Name -like "Test*") {
				$dlpath = "$Path\test"
			} elseif ($_.Name -like "Utility*") {
				$dlpath = "$Path\utility"
			} elseif ($_.Name -like "SPN*") {
				$dlpath = "$Path\psoft"
			} else {
				$dlpath = "$Path"
			}
			#>
			$dlpath = $Path
			if (!(Test-Path $dlpath)) { mkdir $dlpath -Force }
			Export-AzAutomationRunbook -Name $_.Name -OutputFolder $dlpath -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccount -Force | Out-Null
		} else {
			Write-Output $_
		}
	}
	Write-Host "$($runbooks.Count) runbooks exported to $Path"
}
catch {
	Write-Error $_.Exception.Message 
}