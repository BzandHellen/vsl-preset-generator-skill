<#
  query-patches.ps1  —  query the extracted VSL patch database.

  Usage:
    powershell -File query-patches.ps1 -Instrument "Horn 1" -Patch "Rips" -Limit 20
    powershell -File query-patches.ps1 -Collection "02 Synchron Strings Pro"
    powershell -File query-patches.ps1 -Database <csv> -Json
#>
param(
  [string]$Database = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data\vsl-patches.csv'),
  [string]$Collection,
  [string]$Product,
  [string]$Instrument,
  [string]$Articulation,
  [string]$Patch,          # regex against PatchFile
  [string]$ContentId,
  [int]$Limit = 100,
  [switch]$CountOnly
)
if (-not (Test-Path $Database)) { Write-Error "database not found: $Database (run build-vsl-patch-db.ps1)"; exit 1 }
$rows = Import-Csv $Database
if ($Collection)   { $rows = $rows | Where-Object { $_.Collection   -like "*$Collection*" } }
if ($Product)      { $rows = $rows | Where-Object { $_.Product      -like "*$Product*" } }
if ($Instrument)   { $rows = $rows | Where-Object { $_.Instrument   -like "*$Instrument*" } }
if ($Articulation) { $rows = $rows | Where-Object { $_.Articulation -like "*$Articulation*" } }
if ($ContentId)    { $rows = $rows | Where-Object { $_.ContentId    -like "*$ContentId*" } }
if ($Patch)        { $rows = $rows | Where-Object { $_.PatchFile -match $Patch } }
if ($CountOnly) { @{ count = @($rows).Count } | ConvertTo-Json -Compress; exit 0 }
$sel = $rows | Select-Object -First $Limit Volume,ContentId,Collection,Product,Instrument,Articulation,PatchFile,Index,Path
@{ count = @($rows).Count; returned = @($sel).Count; rows = @($sel) } | ConvertTo-Json -Depth 4
