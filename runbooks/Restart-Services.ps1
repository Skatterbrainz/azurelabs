
[CmdletBinding()]
param (
	[parameter(Mandatory=$False)][string]$ServiceNames = "",
	[parameter(Mandatory=$False)][Boolean]$Force = $False
)
if ([string]::IsNullOrEmpty($ServiceNames)) {
	$services = Get-CimInstance -ClassName Win32_Service | 
		Where-Object {$_.StartMode -eq 'Auto' -and $_.State -eq 'Stopped'} | 
			Select-Object Name,StartMode,State
} else {
	$services = Get-CimInstance -ClassName Win32_Service |
		Where-Object {$_.Name -in $($ServiceNames -split ',')} |
			Select-Object Name,StartMode,State
}

if ($Force -eq $True) {
	foreach ($service in $services) {
		try {
			if ($service.State -ne 'Running') {
				Get-Service -Name $service.Name | Start-Service -ErrorAction Stop
				$stat = 'Restart successful'
			} else {
				Get-Service -Name $service.Name | Restart-Service -ErrorAction Stop
				$stat = 'Start successful'
			}
		}
		catch {
			$stat = 'Failed to start'
		}
		[pscustomobject]@{
			Name      = $service.Name
			StartType = $service.StartMode
			Status    = $service.State
			Message   = $stat
		}
	}
} else {
	foreach ($service in $services) {
		[pscustomobject]@{
			Name      = $service.Name
			StartType = $service.StartMode
			Status    = $service.State
			Message   = 'No change'
		}
	}
}