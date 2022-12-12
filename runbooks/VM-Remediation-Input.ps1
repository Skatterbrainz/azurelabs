$config = @'
{
	"Folders": [
		{
			"step": 1,
			"path": "c:\temp",
			"comment": ""
		}
	],
	"Registry": [
		{
			"step": 1,
			"key": "HKLM:\\Software\\Microsoft\\Windows Nt\\CurrentVersion\\Winlogon",
			"valuename": "CachedLogonsCount",
			"newvalue": 0,
			"type": "string",
			"platform": "workstation,server",
			"comment": ""
		},
		{
			"step": 2,
			"key": "HKLM:\\Software\\Quisitive\\VMRemediation",
			"valuename": "Lastrun",
			"newvalue": "%%DATETIME%%",
			"type": "string",
			"platform": "workstation,server",
			"comment": ""
		}
	],
	"Services": [
		{
			"step": 1,
			"name": "bits",
			"action": "restart",
			"platform": "server",
			"comment": ""
		},
		{
			"step": 2,
			"name": "wuauserv",
			"action": "restart",
			"platform": "server",
			"comment": ""
		}
	],
	"Modules": [
		{
			"step": 1,
			"name": "psWindowsUpdate",
			"platform": "workstation,server",
			"comment": ""
		},
		{
			"step": 2,
			"name": "carbon",
			"platform": "workstation,server",
			"comment": ""
		}
	],
	"AppX": [
		{
			"step": 1,
			"id": "Greenshot.Greenshot",
			"name": "Greenshot",
			"platform": "workstation",
			"comment": ""
		},
		{
			"step": 2,
			"id": "Winamp.Winamp",
			"name": "WinAmp 5.99",
			"platform": "workstation",
			"comment": ""
		},
		{
			"step": 3,
			"id": "Microsoft.WindowsAdminCenter",
			"name": "Windows Admin Center",
			"platform": "workstation",
			"comment": ""
		},
		{
			"step": 4,
			"id": "Adobe.Acrobat.Reader.32-bit",
			"name": "Adobe Reader DC",
			"platform": "workstation",
			"comment": ""
		}
	]
}
'@

$vmRemediationConfig = $config | ConvertFrom-Json