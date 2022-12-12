<#
.SYNOPSIS
	VM-Remediation-Test.ps1
.DESCRIPTION
	Test the VM-Remediation functions library
.PARAMETER ApplyChanges
	Optional. True = modify settings, False = read current settings
.NOTE
	1.0.0 - 2022-11-18 - Quisitive, David Stein
#>
[CmdletBinding()]
param (
	[parameter()][string]$Computers = "",
	[parameter()][boolean]$ApplyChanges = $False
)
if ([string]::IsNullOrWhiteSpace($Computers)) {
	Write-Output "Computers parameter was not provided"
	break
}
if ($env:COMPUTERNAME -ne "upst-wsus-1") {
	Write-Output "Not running on correct Hybrid Worker. Try again"
	break
}

$cred = Get-AutomationPSCredential -Name 'Automation-OnPrem'

$KeyPath = "HKLM:\Software\Microsoft\Windows Nt\CurrentVersion\Winlogon"
$ValueName = "CachedLogonsCount"

# load functions library into current runspace
. .\VM-Remediation.ps1

foreach ($computer in $computers.Split(",")) {

	if ($ApplyChanges -eq $True) {
		Set-RegistryValue -ComputerName $computer -KeyPath $keypath -ValueName $valuename -Value 0 -DataType "String" -Credential $cred
		Rename-LocalAccount -ComputerName $computer -NameMapping "Guest=LocalGuest" -Credential $cred
		#Restart-Services -ComputerName $computer -ServiceName "bits,wuauserv" -Credential $cred
		#Deploy-PSModules -ComputerName $computer -Modules "powershellget" -Credential $cred -UpdateIfInstalled
	} else {
		Get-RegistryValue -ComputerName $computer -KeyPath $keypath -ValueName $valuename -Credential $cred
		Get-LocalAccount -ComputerName $computer -Name "Guest" -Credential $cred
	}

	# add/modify/remove files/folders
	# download content from the internet
	# install software (locally) --> from downloaded pkg or from network share?
	# identify machines with software installed
}