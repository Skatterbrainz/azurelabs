<#
.SYNOPSIS
	VM-Remediation.ps1
.DESCRIPTION
	Functions to support remote management operations from a hybrid worker
.PARAMETER (none)
.NOTES
	1.0.0 - 2022-11-18 - Quisitive, David Stein
#>

[array]$dtypes = ('DWord','String','MultiString','Qword','ExpandString')

function Get-RegistryValue {
	[CmdletBinding()]
	param (
		[parameter(Mandatory=$True)][string][ValidateNotNullOrEmpty()]$ComputerName,
		[parameter(Mandatory=$True)][string][ValidateNotNullOrEmpty()]$KeyPath,
		[parameter(Mandatory=$True)][string][ValidateNotNullOrEmpty()]$ValueName,
		[parameter(Mandatory=$True)][pscredential]$Credential
	)
	try {
		$response = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
			Get-ItemProperty $using:KeyPath -Name $Using:ValueName -ErrorAction Stop | select -ExpandProperty $Using:ValueName
		} -ErrorAction Stop
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			KeyPath   = $KeyPath
			ValueName = $ValueName
			Result    = $response
			Status    = "Success"
		}
	}
	catch {
		$msg = $_.Exception.Message
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			KeyPath   = $KeyPath
			ValueName = $ValueName
			Result    = $msg
			Status    = "Error"
		}
	}
	finally {
		$result
	}
}

function Set-RegistryValue {
	[CmdletBinding()]
	param (
		[parameter(Mandatory=$True)][string][ValidateNotNullOrEmpty()]$ComputerName,
		[parameter(Mandatory=$True)][string][ValidateNotNullOrEmpty()]$KeyPath,
		[parameter(Mandatory=$True)][string][ValidateNotNullOrEmpty()]$ValueName,
		[parameter()][ValidateNotNullOrEmpty()]$Value,
		[parameter()][string][ValidateSet('DWord','String','MultiString','Qword','ExpandString')]$DataType = "String",
		[parameter(Mandatory=$True)][pscredential]$Credential
	)
	try {
		$response = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
			if (!(Test-Path $using:KeyPath)) {
				$null = New-Item -Path $using:KeyPath -ItemType RegistryKey -ErrorAction Stop
			}
			$null = New-ItemProperty -Path $using:KeyPath -Name $using:ValueName -PropertyType $using:DataType -Value $using:Value -Force -ErrorAction Stop
		} -ErrorAction Stop
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			KeyPath      = $KeyPath
			ValueName    = $ValueName
			Value        = $Value
			DataType     = $DataType
			Status       = "Success"
		}
	}
	catch {
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			KeyPath      = $KeyPath
			ValueName    = $ValueName
			Value        = $Value
			DataType     = $DataType
			Message      = $_.Exception.Message -join ";"
			Status       = "Error"
		}
	}
	finally {
		$result
	}
}

function Restart-Services {
	[CmdletBinding()]
	param (
		[parameter()][string][ValidateNotNullOrEmpty()]$ComputerName,
		[parameter()][string][ValidateNotNullOrEmpty()]$ServiceName,
		[parameter()][pscredential]$Credential
	)
	try {
		$response = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
			$services = $using:ServiceName -split ","
			foreach ($service in $services) {
				$null = Restart-Service -Name $service -Force
				write-output $service
			}
		}
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			ServiceName  = $($response -join ';')
			Status       = "Success"
		}
	}
	catch {
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			ServiceName  = $($response -join ';')
			Message      = $_.Exception.Message -join ";"
			Status       = "Error"
		}
	}
	finally {
		$result
	}
}

function Deploy-PSModules {
	[CmdletBinding()]
	param (
		[parameter(Mandatory)][string][ValidateNotNullOrEmpty()]$ComputerName,
		[parameter(Mandatory)][string][ValidateNotNullOrEmpty()]$Modules,
		[parameter(Mandatory)][pscredential]$Credential,
		[parameter()][switch]$UpdateIfInstalled
	)
	try {
		$response = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
			$modules = $using:Modules -split ","
			[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
			foreach ($module in $modules) {
				$action = $null
				$m = $null
				$v = ""
				if (!($m = Get-Module $module -ListAvailable)) {
					#$null = Install-Module $module -Force
					$action = 'Installed'
				} else {
					$v = ($m | Sort-Object Version | Select-Object -Last 1 -ExpandProperty Version).ToString()
					if ($UpdateIfInstalled) {
						#$null = Update-Module $module
						$action = 'Updated'
					} else {
						$action = 'NoChange'
					}
				}
				Write-Output "$($module):$($v)=$($action)"
			}
		}
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			Message = $response -join ';'
			Status  = "Success"
		}
	}
	catch {
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			Message = $_.Exception.Message -join ';'
			Status  = "Error"
		}
	}
	finally {
		$result
	}
}

function Rename-LocalAccount {
	[CmdletBinding()]
	param (
		[parameter(Mandatory)][string][ValidateNotNullOrEmpty()]$ComputerName,
		[parameter(Mandatory)][string][ValidateNotNullOrEmpty()]$NameMapping,
		[parameter(Mandatory)][pscredential]$Credential
	)
	try {
		$response = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
			$mappings = $using:NameMapping -split ","
			foreach ($mapping in $mappings) {
				$map = $mapping -split "="
				$oldname = $map[0]
				$newname = $map[1]
				try {
					$null = Rename-LocalUser -Name $oldname -NewName $newname -ErrorAction Stop
					Write-Output "$($oldname)=$($newname)=renamed"
				}
				catch {
					Write-Output "$($oldname)=$($newname)=failed"
				}
			}
		}
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			Message = $response -join ';'
			Status  = "Success"
		}
	}
	catch {
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			Message = $_.Exception.Message -join ';'
			Status  = "Error"
		}
	}
	finally {
		$result
	}
}

function Get-LocalAccount {
	[CmdletBinding()]
	param (
		[parameter(Mandatory)][string][ValidateNotNullOrEmpty()]$ComputerName,
		[parameter(Mandatory)][string][ValidateNotNullOrEmpty()]$Name,
		[parameter(Mandatory)][pscredential]$Credential
	)
	try {
		$response = Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
			Write-Output ($null -ne (Get-LocalUser -Name $using:Name -ErrorAction SilentlyContinue))
		}
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			UserName = $Name
			Exists   = $response
			Status   = "Success"
		}
	}
	catch {
		$result = [pscustomobject]@{
			ComputerName = $ComputerName
			Message = $_.Exception.Message -join ';'
			Status  = "Error"
		}
	}
	finally {
		$result
	}
}