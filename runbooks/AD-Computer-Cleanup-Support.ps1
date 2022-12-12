<#
.SYNOPSIS
	AD-Computer-Cleanup-Support.ps1
.DESCRIPTION
	Support functions for the AD computer cleanup runbooks
.NOTES
	1.0.0 - 2022-08-18 - David Stein
#>
[string]$CemeteryOU = Get-AutomationVariable -Name 'AD-Computer-Cleanup-TargetOU' #"OU=Disabled Computers,DC=contoso,DC=local"
[string]$TargetOU = Get-AutomationVariable -Name 'AD-Computer-Cleanup-SourceOU' #"OU=AzureAD Join,OU=Workstations,DC=contoso,DC=local"

$ADcred = Get-AutomationPSCredential -Name 'AD-Computer-Manage'
$AzCredential = Get-AutomationPSCredential -Name 'IT_Communications'

# Note: RunAs Credential uses a Certificate that must be renewed (check AzureAD app registrations)
# It also requires Graph permissions: Directory:Read-All, Device:Read-All

$AADCredential = Get-AutomationPSCredential -Name 'Contoso_RunAs'
$TenantID = Get-AutomationVariable -Name 'TenantId'
$SubscriptionID = Get-AutomationVariable -Name 'SubscriptionId'

function Write-Log {
	param (
		[parameter()][string]$Message = "",
		[parameter()][string][ValidateSet('Info','Warning','Error')]$Category = 'Info'
	)
	$string = "$(Get-Date -f u) - $Category - $Message"
	$string | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

function Send-EmailMessage {
	[CmdletBinding()]
	param (
		[parameter()][string]$SendTo = "",
		[parameter()][string]$SendFrom = "",
		[parameter()][string]$Subject = "",
		[parameter()][string]$MessageBody = ""
	)
	try {
		if ([string]::IsNullOrEmpty($SendTo)) { throw "Missing input parameter: SendTo" }
		if ([string]::IsNullOrEmpty($SendFrom)) { throw "Missing input parameter: SendFrom" }
		if ([string]::IsNullOrEmpty($Subject)) { throw "Missing input parameter: Subject" }
		if ([string]::IsNullOrEmpty($MessageBody)) { throw "Missing input parameter: MessageBody" }
		
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		Write-Log "building message body, heading"
		[string]$msgHeader = @'
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<style><!--
/* Style Definitions */
body {font-family:"Calibri",sans-serif;}
p.MsoNormal, li.MsoNormal, div.MsoNormal {
	margin:0in;
	font-size:11.0pt;
	font-family:"Calibri",sans-serif;}
a:link, span.MsoHyperlink {
	mso-style-priority:99;
	color:blue;
	text-decoration:underline;}
h1,h2,h3,h4 {font-family:"Calibri",sans-serif;}
table,tr,td,th {
	border:1px solid;
	padding: 5pt;
	spacing: 1pt;
	bordercolor: black;
	font-family: "Segoe UI";
	font-size: 11pt;
	border-collapse:collapse;}
th {background-color: #e0e0e0;}
--></style>
</head>
'@

$msgtext = @'
<body lang="EN-US">
<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">
<!--<img border="0" width="275" height="76" style="width:2.8645in;height:.7916in" id="_x0000_i1025" src="https://www.contoso.com/library/images/logo.png"/>-->
<br/><br/>
<h2>%MESSAGESUBJECT%</h2>
<p class="MsoNormal">&nbsp;</p>
%MESSAGECONTENT%
</body>
</html>
'@
		Write-Log "merging subject and body into message template"
		$msgtext = $msgtext -replace '%MESSAGESUBJECT%', $Subject
		$msgtext = $msgtext -replace '%MESSAGECONTENT%', $MessageBody
		
		$msgbody = $msgHeader+$msgtext
		
		$mailParams = @{
			SmtpServer     = 'smtp.office365.com'
			Port           = 587
			UseSSL         = $true
			Credential     = $AzCredential
			From           = $SendFrom
			To             = $SendTo.Split(';')
			Subject        = $Subject
			Body           = $msgbody
			BodyAsHtml     = $true
		}
		Write-Log "sending mail message now..."
		Send-MailMessage @mailParams
		
		$result = @{
			Status  = 'Success'
			SendTo  = $SendTo
			Subject = $Subject
			Content = $msgtext
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
}

function Get-AADDeviceLastLogon {
	[CmdletBinding()]
	param (
		[parameter(Mandatory)][string]$DeviceName
	)
	try {
		Write-Log "getting AzureAD device login: $DeviceName"
		#$response = Get-AzureADDevice -SearchString "$($DeviceName)" -ErrorAction Stop
		$response = Get-AzureADDevice -Filter "startswith(displayName,'$DeviceName')" -ErrorAction Stop | 
			Where-Object {![string]::IsNullOrEmpty($_.ApproximateLastLogontimestamp)}
		if ($response) {
			Write-Log "calculating age of ApproximateLastLogonTimeStamp"
			$lastlogon = [datetime]($response.ApproximateLastLogonTimeStamp)
			$daysago = (New-TimeSpan -Start $lastlogon -End (Get-Date)).TotalDays
			$daysago = [math]::Round($daysago,0)
			Write-Log "$DeviceName - AAD last logon was $daysago days ago"
			[pscustomobject]@{
				DisplayName = $($response.DisplayName).ToString()
				AccountEnabled = $($response.AccountEnabled)
				LastLogon = $lastlogon
				DaysAgo = $daysago
				Status = 'Success'
			}
		} else {
			throw "$DeviceName - Device not found in AAD"
		}
	}
	catch {
		$msg = $($_.Exception.Message -join(';'))
		Write-Log "AAD query returned an error: $msg" -Category 'Error'
		[pscustomobject]@{
			DisplayName = $DeviceName
			Status = 'Error'
			Message = $msg
		}
	}
}

function Get-StaleComputers {
	param (
		[parameter(Mandatory=$True)][string]$TargetOU,
		[parameter()][int]$DaysInactive = 40,
		[parameter()][boolean]$CheckAAD = $False
	)
	try {
		Write-Log "searching for inactive computers in path: $TargetOU"
		[datetime]$CutOffDate = (Get-Date).AddDays(-($DaysInactive))
		Write-Log "cut off date = $CutOffDate ($DaysInactive days ago)"
		$output = @()
		$cparams = @{
			SearchBase = $TargetOU
			Filter = {LastLogonTimeStamp -lt $CutOffDate} 
			ResultPageSize = 2000
			Properties = ('Name','OperatingSystem','SamAccountName','DistinguishedName','lastLogonTimestamp','description')
			Credential = $ADcred
		}
		$adcomputers = @(Get-ADComputer @cparams)
		Write-Log "$($adcomputers.Count) computers returned from query"

		if ($CheckAAD -eq $True) {
			if ($adcomputers.Count -gt 0) {
				Write-Log "opening connection to Azure"
				$azparams = @{
					Credential = $AADCredential
					Tenant = $TenantID
					Subscription = $SubscriptionID
					ServicePrincipal = $True
					ErrorAction = 'Stop'
					Scope = 'Process'
					WarningAction = 'SilentlyContinue'
				}
				$AzCon = Connect-AzAccount @azparams
				$AzureEnvironmentName = 'AzureCloud'
				$context  = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
				$aadToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.windows.net").AccessToken
				Write-Log "opening connection to AAD"
				$aadparams = @{
					AzureEnvironmentName = $AzureEnvironmentName
					AadAccessToken = $aadToken
					AccountId = $context.Account.Id
					TenantId  = $context.tenant.id
					ErrorAction   = 'Stop'
					WarningAction = 'SilentlyContinue'
				}
				$aadconnection = Connect-AzureAD @aadparams
				Write-Log "connection opened to AAD"
			} else {
				Write-Log "no connections were opened to Azure or Azure AD"
			}
		}

		foreach ($computer in $adcomputers) {
			$cn   = $computer.Name
			$desc = $computer.description
			$llogon  = $null
			$daysago = $null
			if (![string]::IsNullOrEmpty($computer.lastlogontimestamp)) {
				$llogon = [DateTime]::FromFileTime($computer.lastlogontimestamp)
				$daysago = (New-TimeSpan -Start $llogon -End (Get-Date)).Days
				if ($CheckAAD -eq $True) {
					$aad = Get-AADDeviceLastLogon -DeviceName $cn
					if ($aad.Status -eq 'Success') {
						if ($daysago -gt $aad.DaysAgo) {
							$daysago = $aad.DaysAgo
							$msg = "AAD Login is more recent"
							Write-Log "$cn - last AD logon: $llogon"
							Write-Log "$cn - last AAD logon: $($aad.LastLogon) - more recent than AD"
							$llogon = $aad.LastLogon
						} else {
							$msg = "AAD Login is same or older"
							Write-Log "$cn - last AD logon: $llogon"
							Write-Log "$cn - last AAD logon: $($aad.LastLogon)"
						}
					} else {
						$msg = $aad.Message
						Write-Log "$cn - AAD query returned an error: $msg" -Category 'Error'
					}
				} else {
					Write-Log "$cn - last AD logon: $llogon"
				}
			} else {
				Write-Log "$cn - last AD logon: never"
				if ($CheckAAD -eq $True) {
					Write-Log "$cn - last AAD logon: unknown"
				}
			}
			Write-Log "$cn - os: $($computer.OperatingSystem), lastlogon: $($llogon), days: $($daysago)"
			if (($null -eq $llogon) -or ($daysago -ge $DaysInactive)) {
				if ($desc -like '*DO NOT DISABLE*') {
					Write-Log "$cn - skipping cleanup - account description: $desc"
				} else {
					$output += [pscustomobject]@{
						ComputerName = $cn
						OperatingSystem = $computer.OperatingSystem
						LastLogon = $llogon
						DaysAgo = $daysago
						DN = $computer.DistinguishedName
						Description = $computer.description
					}
				}
			}
		} # foreach
		if ($CheckAAD -and $aadconnection) {
			Write-Log "closing Azure and AAD connections"
			$null = Disconnect-AzureAD
			$null = Disconnect-AzAccount
			$aadconnection = $null
		}
		Write-Log "no stale computers found - nothing more to do"
	}
	catch {
		Write-Log -Category 'Error' -Message "[Get-StaleComputers] error: $($_.Exception.Message -join(';'))"
	}
	finally {
		Write-Output $output
		if ($CheckAAD -and $aadconnection) {
			$null = Disconnect-AzureAD
			$null = Disconnect-AzAccount
		}
	}
}
