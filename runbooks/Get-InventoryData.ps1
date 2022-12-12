<#
.SYNOPSIS
	Get-InventoryData.ps1
.DESCRIPTION
	Runbook which transforms data files in an Azure Storage Blob Container, into Excel workbook
	and exports the Excel workbook to another Blob Container
.PARAMETER None
.NOTES
	1.0.0 - 2022-10-07 - Quisitive, Cameron Fuller and David Stein

	Requires:
	* Azure Storage Account information (read and write)
	* Source files in blob container
(insert disclaimer)
#>

$accountName   = Get-AutomationVariable -Name 'StorageAccount'
$accountKey    = Get-AutomationVariable -Name 'StorageKey'
$containerName = "container1"
$blobPath      = "sub1" # "roles/API_Audit"
$xlfile        = "$($env:TEMP)\api_inventory2.xlsx"

$context = New-AzStorageContext -StorageAccountName $accountName -StorageAccountKey $accountKey
$container_client = Get-AzStorageContainer -Name $containerName -Context $context

. .\Helper-Functions.ps1

Write-Output "# IMPORT DATA FROM FILES"

$asp = Import-BlobContent -ContainerClient $container_client -BlobName "$($blobPath)/app_service_plans.tsv" -TabDelimited
$rgs = Import-BlobContent -ContainerClient $container_client -BlobName "$($blobPath)/resource_groups.tsv" -TabDelimited
$azf = Import-BlobContent -ContainerClient $container_client -BlobName "$($blobPath)/azure-functions-endpoints.csv" -TabDelimited

Write-Output "$($asp.Count) asp rows imported"
Write-Output "$($rgs.Count) rgs rows imported"
Write-Output "$($azf.Count) azf rows imported"

<#
COLUMN NAMES:
asp = ase ase_rg asp_loc id name rg
rgs = name cost_center project application environment
azf = appname endpoint url auth https_only resource_group cost_center project application environment asp_id
#>

Write-Output "# JOIN [azf] and [asp] DATASETS"

$inv = Join-Csv -DataSet1 $azf -DataSet2 $asp -Id1 "asp_id" -Id2 "id" -Suffix1 "" -Suffix2 "_asp" -JoinType Inner

Write-Output "# JOIN [previous] and [rgs] DATASETS"

$inv2 = Join-Csv -DataSet1 $inv -DataSet2 $rgs -Id1 "resource_group" -Id2 "name" -Suffix1 "" -Suffix2 "_rg" -JoinType Inner

Write-Output "# CLEAR PREVIOUS FILE"

if (Test-Path $xlfile) {
	Get-Item -Path $xlfile | Remove-Item -Force
}

Write-Output "# EXPORT DATA TO EXCEL FILE"

#$inv | Export-Excel -Path $xlfile -WorksheetName "Inv" -ClearSheet -AutoSize -AutoFilter -FreezeTopRow
$inv2 | Export-Excel -Path $xlfile -WorksheetName "Combined" -ClearSheet -AutoSize -AutoFilter -FreezeTopRow
$azf | Export-Excel -Path $xlfile -WorksheetName "Function Endpoints" -ClearSheet -AutoSize -AutoFilter -FreezeTopRow
$rgs | Export-Excel -Path $xlfile -WorksheetName "Resource Groups" -ClearSheet -AutoSize -AutoFilter -FreezeTopRow
$asp | Export-Excel -Path $xlfile -WorksheetName "App Service Plans" -ClearSheet -AutoSize -AutoFilter -FreezeTopRow

$dataset = Import-Excel -Path $xlfile -WorksheetName "Combined"
Write-Output "$($dataset.count) rows in [combined] worksheet"

Write-Output "# UPLOAD EXCEL WORKBOOK FILE TO BLOB"

$response = Set-AzStorageBlobContent -File $xlfile -Container $containerName -Context $context -Blob "$($blobpath)/api_inventory2.xlsx" -Force
Write-Output "# Uploaded to $($response.Name)"

Write-Output "# COMPLETED!"
