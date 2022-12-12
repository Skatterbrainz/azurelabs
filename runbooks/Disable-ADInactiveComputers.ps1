<#
.SYNOPSIS
	Disable-InactiveADComputers.ps1
.DESCRIPTION
	Disable and move stagnant AD computer accounts to a designated OU
.PARAMETER TargetOU
	OU path to restrict AD search
.PARAMETER CemeteryOU
	OU path to move disabled AD computers into
.PARAMETER DaysInactive
	Number of days since lastLogonTimestamp to consider device as stagnant
	Default number is 180
.PARAMETER TimestampAttribute
	AD object attribute to use for updating with timestamp of being disabled.
	Default attribute is 'description'
.NOTES
	1.0.1 - 2022-04-26 - Catapult Systems, David Stein

	1. get AD computers in OU=$TargetOU with LastLogonTimestamp date > $DaysInactive old
		foreach: disable > move to $CemeteryOU > set $TimestampAttribute to (Tooday + $DeferralDays)
	2. get AD computers in OU=$CemeteryOU with $TimestampAttribute datestamp = Today
		foreach: delete AD computer account

#>
[CmdletBinding()]
param (
	[parameter(Mandatory=$False)][string]$TargetOU = "OU=Workstations,OU=CORP,DC=contoso,DC=local",
	[parameter(Mandatory=$False)][string]$CemeteryOU = "OU=Computers,OU=DisabledAccounts,OU=CORP,DC=contoso,DC=local",
	[parameter(Mandatory=$False)][int32]$DaysInactive = 180,
	[parameter(Mandatory=$False)][string]$TimestampAttribute = "description"
)

[string]$LogPath = "c:\windows\temp\ad-computer-disable-$(Get-Date -f 'yyyyMMddhhmm').txt"

function Write-Log {
	param (
		[string]$Message = "",
		[string][ValidateSet('Info','Warning','Error')]$Category = "Info"
	)
	$msg = $(Get-Date -f 'yyyyMMdd-hhmmss') - $Category - $Message
	$msg | Out-File -FilePath $LogPath -Append
}

$cred = Get-AutomationPSCredential -Name 'Automation-CMInstaller'

try {
	if (-not(Get-Module ActiveDirectory -ListAvailable)) {
		Write-Log "ActiveDirectory PowerShell module is not installed"
		break
	}

	[datetime]$CutOffDate = (Get-Date).AddDays(-($DaysInactive))
	[datetime]$KillDate   = (Get-Date).AddDays($DeferralDays)

	Write-Log "cut off date = $CutOffDate"
	Write-Log "future deletion date = $KillDate"

	$cparams = @{
        SearchBase = $TargetOU
		Filter = {LastLogonTimeStamp -lt $CutOffDate} 
		ResultPageSize = 2000
		resultSetSize = $null
		Properties = ('Name','OperatingSystem','SamAccountName','DistinguishedName','lastlogontimestamp')
		Credential = $cred
	}

	Write-Log "searching for inactive computers in path: $TargetOU"

	[array]$computers = Get-ADComputer @cparams | Foreach-Object {
		if ($null -ne $_.lastlogontimestamp) {
			$llogon = [DateTime]::FromFileTime($_.lastlogontimestamp)
			$daysago = (New-TimeSpan -Start $llogon -End (Get-Date)).Days
            Write-Log "last logon: $llogon"
		} else {
			$llogon  = $null
			$daysago = $null
            Write-Log "last logon: never"
		}
		if (($null -eq $llogon) -or ($daysago -ge $DaysInactive)) {
			[pscustomobject]@{
				ComputerName    = $_.Name
				OperatingSystem = $_.OperatingSystem
				DN         = $_.DistinguishedName
				LastLogon  = $llogon
				DaysAgo    = $daysago
			}
		}
	}
	Write-Log "$($computers.Count) inactive computers were found"
	
	[string]$timestamp = "AUTO DISABLED ON: $(Get-Date -f 'yyyy-MM-dd')"

	$results = @()
	Write-Log "moving computers to cemetery OU: $CemeteryOU"
	foreach ($computer in $computers) {
		if ($WhatIfPreference -ne $True) {
			try {
				Write-Log "disabling computer: $($computer.ComputerName)"
				Disable-ADAccount -Identity $computer.DN -Credential $cred -ErrorAction Stop | Out-Null
				Write-Log "setting timestamp on computer: $() using attribute"
				Set-ADComputer -Identity $computer.DN -Description $timestamp -Credential $cred | Out-Null
				Write-Log "moving computer: $($computer.ComputerName)"
				Move-ADObject -Identity $computer.DN -TargetPath $CemeteryOU -Credential $cred -ErrorAction Stop | Out-Null
				$msg = 'moved'
				$res = 'success'
			}
			catch {
				$msg = $($_.Exception.Message -join ';')
				$res = 'error'
			}
		} else {
			$msg = 'no-change'
			$res = 'success'
		}
		$results += [pscustomobject]@{
			ComputerName = $computer.ComputerName
			OriginalOU   = $computer.DN
			LastLogon    = $computer.LastLogon
			DaysAgo      = $computer.DaysAgo
			Status  = $res
			Message = $msg
		}
	}
}
catch {
	Write-Log $($_.Exception.Message -join ';') -Category 'Error'
}
finally {
	$results
	Write-Log "completed"
}