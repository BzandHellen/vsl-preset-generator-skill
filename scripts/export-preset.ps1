<#
  export-preset.ps1  —  decompress .vsynpreset(s) to plain .json for analysis.

  A .vsynpreset is one zstd frame wrapping the preset JSON. This writes the JSON out
  (lossless by default; -Pretty reformats).

  Safety: refuses to write outside a "Generated"/"generated" folder unless you pass
  -AllowOutsideGenerated (or set VSL_ALLOW_OUTSIDE_GENERATED=1). Never overwrites
  an existing file unless -Force.

  Usage:
    powershell -File export-preset.ps1 -Preset "C:\...\STR Synchron Vln1 a14.vsynpreset" -OutDir "C:\...\Generated\analysis"
    powershell -File export-preset.ps1 -Preset "C:\...\Presets\Strings" -OutDir "C:\...\Generated\analysis" -Pretty
#>
param(
  [Parameter(Mandatory)][string[]]$Preset,
  [string]$OutDir = ".",
  [switch]$Pretty,
  [switch]$Force,
  [switch]$AllowOutsideGenerated
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"
# -File passes a comma list as ONE string, so split it back
if ($Preset.Count -eq 1 -and $Preset[0] -match ',') { $Preset = $Preset[0] -split '\s*,\s*' }

$out = Assert-GeneratedDir -OutDir $OutDir -AllowOutsideGenerated:$AllowOutsideGenerated
New-Item -ItemType Directory -Force $out | Out-Null

$files = New-Object System.Collections.Generic.List[object]
foreach ($p in $Preset) {
  if (Test-Path -LiteralPath $p -PathType Container) {
    Get-ChildItem -LiteralPath $p -File | Where-Object { $_.Extension -in '.vsynpreset','.json' } | ForEach-Object { $files.Add($_) }
  } else {
    Get-Item -LiteralPath $p -ErrorAction SilentlyContinue | ForEach-Object { $files.Add($_) }
  }
}
if ($files.Count -eq 0) { throw "no input files matched" }

$written = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
  $t = Get-PresetText -File $f.FullName
  if ($Pretty) { $t = ($t | ConvertFrom-Json | ConvertTo-Json -Depth 100) }
  $target = Join-Path $out ($f.BaseName + ".json")
  Assert-NoOverwrite -Path $target -Force:$Force
  [IO.File]::WriteAllText($target, $t, (New-Object Text.UTF8Encoding($false)))
  $written.Add($target)
  Write-Host ("wrote {0}  ({1} bytes)" -f (Split-Path $target -Leaf), (Get-Item $target).Length)
}
@{ count = $written.Count; files = $written } | ConvertTo-Json -Compress
