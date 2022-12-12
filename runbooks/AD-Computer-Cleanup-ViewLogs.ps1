<#
.SYNOPSIS
	AD-Computer-Cleanup-ViewLogs.ps1
.DESCRIPTION
	List processing log files, or view contents of most recent log file
.PARAMETER LogFile
	If provided = display contents of file
	If not provided = display list of file names (copy one to enter for viewing contents)
.NOTES
	1.0.0 - 2022-05-11 - David Stein
#>
[CmdletBinding()]
param (
	[parameter()][string]$LogFile = "",
	[parameter()][boolean]$ViewLatest = $False
)

[string]$Path = "C:\temp"

try {
	if ([string]::IsNullOrEmpty($LogFile)) {
		[array]$files = Get-ChildItem -Path $Path -Filter "ad-computer-*.txt" -ErrorAction Stop |
			Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName
		if ($ViewLatest) {
			Get-Content -Path $files[0] -Raw -ErrorAction Stop
		} else {
			Write-Output $files
			Write-Output "$($files.Count) log files were found"
		}
	} else {
		if (Test-Path $LogFile) {
			Get-Content -Path $LogFile -Raw -ErrorAction Stop
		} else {
			throw "File not found: $LogFile"
		}
	}
}
catch {
	Write-Output "error: $($_.Exception.Message -join ';')"
}
