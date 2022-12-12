<#
.SYNOPSIS
	DbaTools-Check-LastBackup.ps1
.DESCRIPTION
	Get last backup info for SQL Server database
.PARAMETER ComputerName
	Name of computer / SQL instance
.PARAMETER Database
	Name of SQL database
.NOTES
	1.0.0 - 2022-01-09 - David Stein
#>
param (
	[parameter()][string]$ComputerName = "cm01.contoso.local",
	[parameter()][string]$Database = "CM_P01"
)

try {
	Import-Module dbatools -ErrorAction Stop
	Get-DbaLastBackup -SqlInstance $ComputerName -Database $Database | FT
}
catch {
	Write-Output "ERROR: $($_.Exception.Message -join ';')"
}

