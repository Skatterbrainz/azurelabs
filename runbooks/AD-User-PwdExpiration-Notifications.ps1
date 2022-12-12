<#
.SYNOPSIS
	AD-User-PwdExpiration-Notifications.ps1
.DESCRIPTION
	Azure Automation Runbook for sending email notifications to AD Users with
	passwords expiring within specified days.
.PARAMETER SendMail
	Optional. $True = send email messages. $False = do not send (default = $False)
.PARAMETER SendFrom
	Required. SMTP sender address
.PARAMETER SummarySendTo
	Optional. SMTP address to send summary report when processing is completed
.PARAMETER Warning1
	Required. Days left until password expires to send first warning notification
.PARAMETER Warning2
	Required. Days left until password expires to send second warning notification
.PARAMETER Warning1Daily
	Optional. Send daily notifications when password will expire within Warning1 to Warning2 days
.PARAMETER Warning2Daily
	Optional. Send daily notifications when password will expire within [zero] to Warning2 days
.NOTES
	1.0.0 - 2022-03-23 - David Stein

	Requires PowerShell module: ActiveDirectory

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
	INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
	PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
	FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
	OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
	DEALINGS IN THE SOFTWARE.

#>
[CmdletBinding()]
param (
	[parameter(Mandatory=$False)][boolean]$SendMail = $False,
	[parameter(Mandatory=$False)][string]$SendFrom = "IT Communications <itcommunications@contoso.com>",
	[parameter(Mandatory=$False)][string]$SummarySendTo = "helpdesk <helpdesk@contoso.com>",
	[parameter(Mandatory=$False)][int32]$Warning1 = 14,
	[parameter(Mandatory=$False)][int32]$Warning2 = 7,
	[parameter(Mandatory=$False)][boolean]$Warning1Daily = $True,
	[parameter(Mandatory=$False)][boolean]$Warning2Daily = $True
)

[string]$subject    = "Password Expiration Notification - $(Get-Date -Format g)"
[string]$scriptver  = "1.0.0"
[string]$SearchBase = ""

#region function definitions

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-UserPasswordExpirations {
	[CmdletBinding()]
	param (
		[parameter(Mandatory=$False)][int32]$WarningLevel = 14,
		[parameter(Mandatory=$False)][int32]$CriticalLevel = 7,
		[parameter(Mandatory=$False)][string]$Domain = ""
	)
	if ([string]::IsNullOrEmpty($Domain)) {
		$Domain = (Get-ADDomain).DNSRoot
	}
	$uParams = @{
		Filter      = 'Enabled -eq $True -and PasswordNeverExpires -eq $False'
		Properties  = ('pwdLastSet','msDS-UserPasswordExpiryTimeComputed','EmailAddress','DisplayName')
		Server      = $Domain
		ErrorAction = 'stop'
	}
	if (![string]::IsNullOrWhiteSpace($SearchBase)) {
		$uParams.Add("SearchBase", $SearchBase)
	}
	[array]$users = Get-ADUser @uParams | Where-Object {$_.SamAccountName -notin ('krbtgt','guest','administrator','EPIC$') -and (-not[string]::IsNullOrEmpty($_.EmailAddress)) }
	foreach ($user in $users) {
		try { $pls = [datetime]::FromFileTime($user.pwdLastSet) } catch { $pls = $null }
		try { $pex = [datetime]::FromFileTime($user.'msDS-UserPasswordExpiryTimeComputed') } catch { $pex = $null }
		if ($null -ne $pex) { $pdl = $(New-TimeSpan -Start (Get-Date) -End $pex).Days } else { $pdl = 0 }
		if ($pdl -lt 0) {
			$status = 'Expired'
		} elseif ($pdl -gt $CriticalLevel -and $pdl -le $WarningLevel) {
			$status = 'Warning'
		} elseif ($pdl -le $CriticalLevel) {
			$status = 'Critical'
		} else {
			$status = 'Good'
		}
		[pscustomobject]@{
			SamAccountName    = $user.SamAccountName
			UserPrincipalName = $user.UserPrincipalName
			DisplayName = $user.DisplayName
			Email       = $user.EmailAddress
			Enabled     = $user.Enabled
			PwdLastSet  = $pls
			PwdExpires  = $pex
			DaysLeft    = $pdl
			Status      = $status
		}
	}
} # function

function Send-Notification {
	[CmdletBinding()]
	param (
		[parameter(Mandatory=$True)][string]$Recipient,
		[parameter(Mandatory=$True)][string]$Subject,
		[parameter(Mandatory=$True)][string]$MessageBody,
		[parameter(Mandatory=$True)][string]$DisplayName,
		[parameter(Mandatory=$True)][string]$DaysLeft
	)
	$msgtext = $MessageBody -replace '%DISPLAYNAME%', "$DisplayName"
	$msgtext = $msgtext -replace '%PWDEXPDAYS%', "$DaysLeft"
	$mailParams = @{
		SmtpServer     = 'smtp.office365.com'
		Port           = 587
		UseSSL         = $true
		Credential     = $AzCredential
		From           = $SendFrom
		To             = "$DisplayName <$Recipient>"
		Subject        = $Subject
		Body           = $msgtext.ToString()
		BodyAsHtml     = $msgHtml
	}
	if ($SendMail -eq $True) {
		Send-MailMessage @mailParams
	}
}

$msgHtml = $true
$msgtext = @'
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<style><!--
/* Style Definitions */
body {font-family:"Calibri",sans-serif;}
p.MsoNormal, li.MsoNormal, div.MsoNormal
	{margin:0in;
	font-size:11.0pt;
	font-family:"Calibri",sans-serif;}
a:link, span.MsoHyperlink
	{mso-style-priority:99;
	color:blue;
	text-decoration:underline;}
--></style>
</head>
<body lang="EN-US">

<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">
<!--<img border="0" width="275" height="76" style="width:2.8645in;height:.7916in" id="_x0000_i1025" src="https://www.contoso.com/library/images/logo.png"/>-->
<br/><br/>

<p class="MsoNormal">Dear %DISPLAYNAME%,</p>
<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">This is a friendly reminder that your password will expire in %PWDEXPDAYS% days.</p>
<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">
	Please refer to the attached document for instructions on how to reset your password. You will also need to update the the 
	password on your Mobile Devices as well but they should prompt you to be updated. If you have any questions or issues, please submit a ticket to
<a href="mailto:ITSupport@contoso.com">ITSupport@contoso.com</a></p>
<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">Thank you,</p>
<p class="MsoNormal">&nbsp;IT Support</p>
<p class="MsoNormal">&nbsp;</p>

<p class="MsoNormal"><b>Password Change Procedure</b></p>

<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal"><b>IMPORTANT</span></b>: Connect to the VPN before you proceed!</p>
<p class="MsoNormal">&nbsp;</p>

<ul style="margin-top:0in" type="disc">
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">To bring up the password change prompt, press CTRL+ALT+DEL and select "Change a password"</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">Do not modify the username entry!</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">Enter your current (old) password in the "Old password" box</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">Enter your new password in the "New password" box</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">Enter your new password again in the "Confirm password" box</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">If you receive an error about the new password, make sure it complies with the following rules (see below)</li>
</ul>

<p class="MsoNormal">&nbsp;</p>

<p class="MsoNormal"><b>Password Requirements</b></p>
<p class="MsoNormal">&nbsp;</p>

<ul style="margin-top:0in" type="disc">
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">Passwords must be at least 12 characters long, and must include:</li>
	<ul style="margin-top:0in" type="circle">
		<li class="MsoNormal";margin-left:0in;mso-list:l1 level2 lfo1">Both UPPER and lower case characters (a to z, and A to Z)</li>
		<li class="MsoNormal";margin-left:0in;mso-list:l1 level2 lfo1">At least one number (0 to 9)</li>
		<li class="MsoNormal";margin-left:0in;mso-list:l1 level2 lfo1">At least one non-alphanumeric symbol (examples: % # @ ! $ &amp;)</li>
	</ul>
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">Passwords must be different than the previous 24 passwords you have used</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l1 level1 lfo1">Avoid using the same password you use for other accounts, especially personal accounts (Facebook, Twitter, etc.)</li>
</ul>

<p class="MsoNormal"><o:p>&nbsp;</o:p></p>
<p class="MsoNormal">
	<b>After changing your password</b>, it is strongly recommended that you lock your computer (Windows_Button + L) and then unlock it to sign in again with your new password.&nbsp; This will prevent issues with applications
 and web sessions like Outlook, Teams, OneDrive, SharePoint and others.&nbsp; Password changes do not affect
Zoom, Adobe, GoToMeeting or DeliverySlip. &nbsp;Passwords will expire after 90 days from each reset.</p>
<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">
	<b>If you receive an error about the Domain Controller</span></b>:
</p>

<ul style="margin-top:0in" type="disc">
	<li class="MsoNormal";margin-left:0in;mso-list:l2 level1 lfo2;">Make sure you are connected to the vpn.</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l2 level1 lfo2;">Click the Wi-Fi icon in bottom right corner of you screen.</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l2 level1 lfo2;">Go to your home Wi-Fi connection and disconnect (THIS WILL KICK YOU OFF INTERNET)</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l2 level1 lfo2;">Reconnect to your home internet.</li>
	<li class="MsoNormal";margin-left:0in;mso-list:l2 level1 lfo2;">Ctrl-alt-delete and try to change password again.</li>
</ul>

<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">
	<b>To Unlock Your Account (Follow Directions in Link Below)</b>
</p>

<ul style="margin-top:0in" type="disc">
	<li class="MsoNormal";margin-left:0in;mso-list:l0 level1 lfo3;">
		<a href="https://contoso.sharepoint.com/Shared Documents/SSPR.pdf">Self Service Password Reset.pdf (sharepoint.com)</a>
	</li>
</ul>
<p class="MsoNormal">&nbsp;</p>
</body>
</html>
'@

#endregion

#------------------------ begin processing here -----------------------------

$AzCredential = Get-AutomationPSCredential -Name 'IT_Communications'
$output = @()

[array]$users = Get-UserPasswordExpirations -WarningLevel $Warning1 -CriticalLevel $Warning2 | 
	Where-Object {$_.Status -in ('Critical','Warning')}
if ($users.count -gt 0) {
	foreach ($aduser in $users) {
		<# example $aduser dataset
		SamAccountName    : jsmith
		UserPrincipalName : jsmith@contoso.local
		Email             : jsmith@contoso.com
		Enabled           : True
		PwdLastSet        : 12/23/2021 1:01:35 AM
		PwdExpires        : 3/23/2022 2:01:35 AM
		DaysLeft          : 13
		Status            : Warning
		#>
		if ($aduser.DaysLeft -eq $Warning1 -or $aduser.DaysLeft -eq $Warning2) {
			Send-Notification -Recipient $aduser.Email -Subject $Subject -MessageBody $msgtext -DisplayName $aduser.DisplayName -DaysLeft $aduser.DaysLeft
			$rule = 'warning1-enabled'
		} elseif ($aduser.DaysLeft -gt $Warning2 -and $aduser.DaysLeft -lt $Warning1) {
			if ($Warning1Daily -eq $True) {
				Send-Notification -Recipient $aduser.Email -Subject $Subject -MessageBody $msgtext -DisplayName $aduser.DisplayName -DaysLeft $aduser.DaysLeft
				$rule = 'warning1daily-enabled'
			} else {
				$rule = 'warning1daily-disabled'
			}
		} elseif ($aduser.DaysLeft -le $Warning2) {
			if ($Warning2Daily -eq $True) {
				Send-Notification -Recipient $aduser.Email -Subject $Subject -MessageBody $msgtext -DisplayName $aduser.DisplayName -DaysLeft $aduser.DaysLeft
				$rule = 'warning2daily-enabled'
			} else {
				$rule = 'warning2daily-disabled'
			}
		} else {
			$rule = 'default'
		}
		$output += [pscustomobject]@{
			UserName = $($aduser.UserPrincipalName).ToString()
			Email    = $($aduser.Email).ToString()
			DaysLeft = $($aduser.DaysLeft).ToString()
			Status   = $($aduser.Status).ToString()
			Rule     = $rule.ToString()
			Sent     = $SendMail
		}
	}
} else {
	$output = "no users found with passwords expiring within $Warning1 days"
}

if (![string]::IsNullOrEmpty($SummarySendTo)) {
$msgtext = @'
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
<body lang="EN-US">

<p class="MsoNormal">&nbsp;</p>
<p class="MsoNormal">
<!--<img border="0" width="275" height="76" style="width:2.8645in;height:.7916in" id="_x0000_i1025" src="https://www.contoso.com/library/images/logo.png"/> -->
<br/><br/>
<h2>Password Expiration Notification - Summary Report</h2>
<p class="MsoNormal">&nbsp;</p>
%OUTPUT%
<p>%TOTALCOUNT%</p>
</body>
</html>
'@
	$msgtext = $msgtext -replace '%OUTPUT%', $($output | ConvertTo-Html -Fragment)
	$msgtext = $msgtext -replace '%TOTALCOUNT%', "$($output.Count) users returned for notification processing"
	$mailParams = @{
		SmtpServer     = 'smtp.office365.com'
		Port           = 587
		UseSSL         = $true
		Credential     = $AzCredential
		From           = $SendFrom
		To             = $SummarySendTo
		Subject        = "PSG Password Expiration Notification Summary Report"
		Body           = $msgtext.ToString()
		BodyAsHtml     = $true
	}
	Send-MailMessage @mailParams
}
$output | FT
