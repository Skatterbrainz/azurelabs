function Join-Csv {
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]$DataSet1,
        [parameter(Mandatory)]$DataSet2,
        [parameter(Mandatory)][string]$Id1 = "",
        [parameter(Mandatory)][string]$Id2 = "",
        [parameter()][string]$Suffix1 = "",
        [parameter()][string]$Suffix2 = "",
        [parameter()][string][ValidateSet('Full','Left','Inner')] $JoinType = 'Full'
    )

    $columns1 = $DataSet1[0].psobject.Properties.Name
    $columns2 = $DataSet2[0].psobject.Properties.Name

    $joins = @()

    foreach ($leftrow in $DataSet1) {
        $join    = @{}
        $leftval = $leftrow."$Id1"
        $fmatch  = $null
        write-verbose "search for $Id2 = $leftval"
        $fmatch = @($DataSet2 | Where-Object {$_."$Id2" -eq $leftval} | Select-Object -Unique)
        if ($fmatch.count -gt 0) {
            write-verbose "$($fmatch.count) matches were found"
            foreach ($col in $columns1) {
                $col1 = "$($col)$suffix1"
                $val1 = $leftrow."$col"
                if ([string]::IsNullOrWhiteSpace($val1)) { $val1 = "" }
                $join.Add($col1, $val1)
            }
            foreach ($col in $columns2) {
                $col2 = "$($col)$suffix2"
                $val2 = $fmatch."$col"
                if ([string]::IsNullOrWhiteSpace($val2)) { $val2 = "" }
                $join.Add($col2, $val2)
            }
        } else {
            write-verbose "no matches were found"
            if ($JoinType -in ('Left','Full')) {
                write-verbose "appending blank right-side"
                foreach ($col in $columns1) {
                    $col1 = "$($col)$suffix1"
                    $val1 = $leftrow."$col"
                    if ([string]::IsNullOrWhiteSpace($val1)) { $val1 = "" }
                    $join.Add($col1, $val1)
                }
                foreach ($col in $columns2) {
                    $col2 = "$($col)$suffix2"
                    $join.Add($col2, $null)
                }
            }
        }
        if ($join.Count -gt 0) {
            $joins += [pscustomobject]$join
        }
    }
    $joins
}

function Import-BlobContent {
	[CmdletBinding()]
	param (
		[parameter(Mandatory)]$ContainerClient,
		[parameter(Mandatory)][string]$BlobName,
		[parameter()][switch]$TabDelimited
	)
	$source_blob_client = $ContainerClient.CloudBlobContainer.GetBlockBlobReference("$BlobName")
	if ($TabDelimited) {
		Write-Output $($source_blob_client.DownloadText() | ConvertFrom-Csv -Delimiter "`t")
	} else {
		Write-Output $($source_blob_client.DownloadText() | ConvertFrom-Csv)
	}
}
