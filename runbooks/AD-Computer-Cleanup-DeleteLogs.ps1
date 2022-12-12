<#
.SYNOPSIS
	AD-Computer-Cleanup-DeleteLogs.ps1
.DESCRIPTION
	Remove AD-Computer-Cleanup-* log files older than X days
.PARAMETER DaysOld
	Number of days back to keep (anything older would be removed). Default = 90
.PARAMETER DeleteFiles
	True = Delete files which are older than [DaysOld] days
	False = Do not delete (default)
.NOTES
	1.0.0 - 2022-05-11 - David Stein
#>
[CmdletBinding()]
param (
	[parameter()][int]$DaysOld = 90,
	[parameter()][boolean]$DeleteFiles = $False
)
[string]$LogPath = "c:\temp"

try {
	if (!(Test-Path $LogPath)) { throw "Path not found: $LogPath" }
	$fcount = 0
	$ocount = 0
	$dcount = 0
	[array]$files = Get-ChildItem -Path $LogPath -Filter "ad-computer-*.txt" -ErrorAction Stop | Select-Object FullName,LastWriteTime
	$fcount = $files.count
	[datetime]$CutOffDate = (Get-Date).AddDays(-$DaysOld)
	[array]$oldfiles = $files | Where-Object {$_.LastWriteTime -lt $CutOffDate}
	$ocount = $oldfiles.Count
	if ($DeleteFiles -eq $True) {
		#Write-Output $oldfiles
		$oldfiles | Remove-Item -Force
		$dcount = $ocount
	}
	$result = @{
		Status = "Success"
		TotalFiles = $fCount
		OldFiles   = $oCount
		Deleted    = $dcount
	}
}
catch {
	$result = @{
		Status = "Error"
		Activity = $($_.CategoryInfo.Activity -join(";"))
		Message  = $($_.Exception.Message -join(";"))
		Trace    = $($_.ScriptStackTrace -join(";"))
		RunAs    = $($env:USERNAME)
		RunOn    = $($env:COMPUTERNAME)
	}
}
finally {
	$result
}