<#
.SYNOPSIS
	AD-Computer-Cleanup-Disable.ps1
.DESCRIPTION
	Disable and move stale AD computer accounts to a designated OU.
	Update object attribute (description) to indicate when disabled.
	This is part 1 of a 2-part process (part 2 is AD-Computer-Cleanup-Remove.ps1)
.PARAMETER ApplyChanges
	True = disable/move stale computers. False = just report, but do not make any changes (default = False)
.PARAMETER SendMail
	True = send email report. False = no email. (default = False)
.NOTES
	1.0.0 - 2022-05-11 - David Stein

	1. get AD computers in OU=$TargetOU with LastLogonTimestamp date > $DaysInactive old
		foreach: disable > move to $CemeteryOU > set $TimestampAttribute to (Tooday + $DeferralDays)
	2. get AD computers in OU=$CemeteryOU with $TimestampAttribute datestamp = Today
		foreach: delete AD computer account
#>
[CmdletBinding()]
param (
	[parameter(Mandatory=$False)][boolean]$ApplyChanges = $False,
	[parameter(Mandatory=$False)][boolean]$SendMail = $False
)

. .\AD-Computer-Cleanup-Support.ps1

[string]$TimestampAttribute = "description"
[int32]$DaysInactive = 40

[string]$SendFrom = "IT Communications <itcommunications@contoso.com>"
[string]$SendTo   = "Help Desk <helpdesk@contoso.com>" # ;John Doe <john.doe@contoso.com>
[string]$Subject  = "AD Computer Account Cleanup - Disable"
[string]$LogPath  = "c:\temp\ad-computer-disable-$(Get-Date -f 'yyyyMMdd').txt"

try {
	Write-Log "------------------- begin processing -------------------"
	if (-not(Get-Module ActiveDirectory -ListAvailable)) { throw "ActiveDirectory PowerShell module is not installed" }
	Import-Module ActiveDirectory

	$results = @()
	$mstatus = "false"

	$computers = @(Get-StaleComputers -TargetOU $TargetOU -DaysInactive $DaysInactive -CheckAAD $True)
	Write-Log "$($computers.Count) inactive computers were found"
	
	if ($computers.Count -gt 0) {
		[string]$timestamp = "DISABLED ON: $(Get-Date -f 'yyyy-MM-dd')"
		Write-Log "attribute value will be: $timestamp"
		foreach ($computer in $computers) {
			if ($ApplyChanges -eq $True) {
				try {
					Write-Log "disabling computer: $($computer.ComputerName)"
					Disable-ADAccount -Identity $computer.DN -Credential $adcred -ErrorAction Stop | Out-Null
					Write-Log "setting timestamp on computer: $($timestamp) using attribute: $TimestampAttribute"
					Set-ADComputer -Identity $computer.DN -Credential $adcred -Description $timestamp | Out-Null
					Write-Log "moving computer: $($computer.ComputerName)"
					Move-ADObject -Identity $computer.DN -TargetPath $CemeteryOU -Credential $adcred -ErrorAction Stop | Out-Null
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
				Status       = $res
				Message      = $msg
			}
			Write-Log "computer: $($computer.ComputerName), action: $msg"
			Write-Log "--dn: $($computer.DN)"
		}

		if ($SendMail -eq $True) {
			Write-Log "converting results to HTML table"
			[string]$msgx = $results | ConvertTo-Html -Fragment -As Table
			$response = Send-EmailMessage -Subject $Subject -SendTo $SendTo -SendFrom $SendFrom -MessageBody $msgx
			Write-Log "mail sending result = $($response.Status)"
			$mstatus = $($response.Status).ToString()
		} else {
			Write-Log "no email being sent"
		}

		Write-Log "stale computers count is $($results.count)"
	}

	$result = @{
		Status     = 'Success'
		StaleCount = $results.count
		EmailSent  = $mstatus
	}

	Write-Log "processing completed"
}
catch {
	$result = @{
		Status   = 'Error'
		Activity = $($_.CategoryInfo.Activity -join(";"))
		Message  = $($_.Exception.Message -join(";"))
		Trace    = $($_.ScriptStackTrace -join(";"))
		RunAs    = $($env:USERNAME)
		RunOn    = $($env:COMPUTERNAME)
	}
	Write-Log "exception: $($_.Exception.Message -join ';')" -Category 'Error'
}
finally {
	Write-Output $result
}