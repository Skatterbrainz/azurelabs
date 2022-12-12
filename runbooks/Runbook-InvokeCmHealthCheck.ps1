<#
.SYNOPSIS
	Invoke a CMHealth health check on primary site server
.DESCRIPTION
	Invoke a health check on configuration manager primary site server
	and save results to automation account variable (for demo purposes only)
.PARAMETER CMHost
	Name of primary site server
.PARAMETER CMSiteCode
	ConfigMgr site code
.PARAMETER SQLHost
	Name of SQL instance or host server
.PARAMETER DBName
	Database name for ConfigMgr site
.NOTES
	1.0.0.5 - 2022-04-12 - David Stein
	https://github.com/skatterbrainz/mms-moa-2022/cm-healthcheck
#>
[CmdletBinding()]
[OutputType()]
param (
	[parameter()][string]$Scope = "All",
	[parameter()][string]$CMHost = "cm01.contoso.local",
	[parameter()][string]$CMSiteCode = "P01",
	[parameter()][string]$SQLHost = "cm01.contoso.local",
	[parameter()][string]$DBName = "CM_P01",
	[parameter()][boolean]$ShowAll = $False,
	[parameter()][boolean]$JsonOut = $False
)

$AutomationAccountName = "aa-cm-lab"
$ResourceGroupName = "rg-cm-lab"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
	if (-not(Get-Module cmhealth -ListAvailable)) {
		Install-Module -Name cmhealth -Scope CurrentUser -Force
	}
	if (-not (Get-Module cmhealth -ListAvailable)) {
		throw "Failed to install cmhealth module"
	}

	Import-Module -Name cmhealth
	$Credential = Get-AutomationPSCredential -Name 'Automation-CMInstaller'

	$params = @{
		SiteServer     = $CMHost
		SiteCode       = $CMSiteCode
		SqlInstance    = $SQLHost
		Database       = $DBName
		TestingScope   = $Scope
		NoVersionCheck = $True
	}

	$result = Test-CmHealth @params -ErrorAction Stop
	$hcresult = ($result | Where-Object {$_.Status -notin ('PASS')}).Count

	Set-AutomationVariable -Name 'LastHealthCheck' -Value "$(Get-Date -f 'yyyy-MM-dd hh:mm') EST"
	Set-AutomationVariable -Name 'LastHealthResult' -Value "$hcresult tests did not pass"

	if ($ShowAll -eq $True) {
		$res = $result | 
			Select-Object Computer,Category,TestGroup,TestName,Status,Description,Message,RunTime # | ConvertTo-Json -Compress
	} else {
		$res = $result | 
			Where-Object {$_.Status -ne 'PASS'} |
				Select-Object Computer,Category,TestGroup,TestName,Status,Description,Message,RunTime #| ConvertTo-Json -Compress
	}

	if ($JsonOut -eq $True) { $res = $res | ConvertTo-Json }

	#$pid | Out-File -FilePath "c:\temp\pid.txt" -Force
	#$([runspace]::DefaultRunspace).Id | Out-File "c:\temp\runspace.txt" -Force
 	#
	#for ($i = 0; $i -lt 300; $i++) {
	#	Start-Sleep -Seconds 1
	#}
}
catch {
	$res = @{
		Status   = 'Error'
		Message  = $($_.Exception.Message -join(';'))
		Activity = $($_.CategoryInfo.Activity -join(";"))
		Trace    = $($_.ScriptStackTrace -join(";"))
		RunAs    = $($env:USERNAME)
		RunOn    = $($env:COMPUTERNAME)
	}
}
finally {
	Write-Output $res
}