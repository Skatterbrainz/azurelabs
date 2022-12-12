<#
.SYNOPSIS
	AD-Computer-Cleanup-Remove.ps1
.DESCRIPTION
	Delete stale AD computer accounts which are disabled and in a designated OU.
	This is part 2 of a 2-part process (part 1 is AD-Computer-Cleanup-Disable.ps1)
.PARAMETER ApplyChanges
	True = delete disabled stale computers. False = just report, but do not make any changes (default = False)
.PARAMETER SendMail
	True = send email report. False = no email. (default = False)
.NOTES
	1.0.0 - 2022-05-19 - David Stein

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

[int32]$DeferralDays = 90
[string]$TimestampAttribute = "description"

[string]$SendFrom = "IT Communications <itcommunications@contoso.com>"
[string]$SendTo   = "Help Desk <helpdesk@contoso.com>" # append with semicolon
[string]$Subject  = "AD Computer Account Cleanup - Deletions"

[string]$LogPath = "c:\temp\ad-computer-removals-$(Get-Date -f 'yyyyMMdd').txt"

Write-Log "------------------ begin processing -----------------------"

try {
	if (-not(Get-Module ActiveDirectory -ListAvailable)) {
		Write-Warning "ActiveDirectory PowerShell module is not installed"
		break
	}

	$cparams = @{
		Filter = 'description -like "DISABLED*"'
		ResultPageSize = 2000
		resultSetSize = $null
		Properties = ('Name','OperatingSystem','SamAccountName','DistinguishedName','description')
		SearchBase = $CemeteryOU
		Credential = $ADCred
	}

	Write-Verbose "searching for disabled computers in path: $CemeteryOU"

	[array]$computers = Get-ADComputer @cparams | Sort-Object Name

	Write-Log "$($computers.Count) computer accounts found in OU: $CemeteryOU"
	$results = @()
	$dcount = 0
	foreach ($computer in $computers) {
		$status = $null
		$xdate  = "NULL"
		$cn     = $computer.Name
		$dn     = $computer.DistinguishedName
		$os     = $computer.OperatingSystem
		$desc   = $($computer.description).Trim()
		$resx   = 'Ignore'
        $defer  = 0
		$isdeleted = $False
        if ($computer.Enabled -ne $True) {
            if (![string]::IsNullOrEmpty($desc)) {
                $xdate = $($desc.Split(':')[1]).Trim()
                if (![string]::IsNullOrEmpty($xdate)) {
                    $defer = (New-TimeSpan -Start (Get-Date $xdate) -End (Get-Date)).Days
                    if ($defer -ge $DeferralDays) {
                        $resx = 'Delete'
						if ($ApplyChanges -eq $True) {
							try {
								$xx = "account deleted from AD"
								#Remove-ADComputer -Identity $dn -Confirm:$False -Credential $adcred -ErrorAction Stop | Out-Null
								$null = Remove-ADObject -Identity $dn -Recursive -Credential $adcred -Confirm:$False
								$dcount++
							}
							catch {
								$xx = "error: $($_.Exception.Message -join ';')"
							}
						} else {
							$xx = "would be deleted"
						}
                    } else {
						$xx = "not ready to delete"
					}
                } else {
					$xx = "no date in the description"
				}
            } else {
				$xx = "empty description"
			}
        } else {
			$xx = "account is still enabled"
		}
		Write-Log "$cn - $xdate - $xx"

		$results += [pscustomobject]@{
			Computer     = $cn
			Description  = $desc
			DisabledOn   = $xdate
			DaysDisabled = $defer
			Status       = $resx
			Action       = $xx
		}
    } # foreach

	if ($SendMail -eq $True) {
		Write-Log "converting results to HTML table"
		[string]$msgx = $results | ConvertTo-Html -Fragment -As Table
		$response = Send-EmailMessage -Subject $Subject -SendTo $SendTo -SendFrom $SendFrom -MessageBody $msgx
		Write-Log "mail sending result = $($response.Status)"
		$mstatus = $($response.Status).ToString()
	} else {
		Write-Log "no email being sent"
		$mstatus = "false"
	}
	Write-Log "$($dcount) of $($computers.count) computers in OU were deleted"
	Write-Log "processing completed"

	$result = @{
		Status   = 'Success'
		Deleted  = $dcount
		MailSent = $mstatus
	}
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
}
finally {
	Write-Output $result
}