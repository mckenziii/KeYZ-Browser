<#
.SYNOPSIS
  Rebuilds index.json for the KeYZ mod store from mods/*/mod.json.

.DESCRIPTION
  Records each file's SHA-256 and the commit the index describes; KeYZ Browser
  downloads files from exactly that commit and refuses any that don't match.
  Run by the store's workflows; works in PowerShell 5.1 and 7.
#>
param(
  [Parameter(Mandatory = $true)] [string] $Repo,
  [string] $Root = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"
Push-Location $Root
try {
  $commit = "$(git rev-parse HEAD)".Trim()
  $mods = New-Object System.Collections.Generic.List[object]
  foreach ($dir in Get-ChildItem (Join-Path $Root "mods") -Directory | Sort-Object Name) {
    $manifest = Join-Path $dir.FullName "mod.json"
    if (-not (Test-Path $manifest)) { continue }
    $m = Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($f in @($m.files)) {
      $path = Join-Path $dir.FullName "$f"
      if (Test-Path $path) {
        $files.Add([ordered]@{ name = "$f"; sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower(); size = (Get-Item $path).Length })
      }
    }
    if ($files.Count -eq 0) { continue }
    $updated = "$(git log -1 --format=%cI -- "mods/$($dir.Name)")".Trim()
    $preview = if (Test-Path (Join-Path $dir.FullName "preview.png")) { "preview.png" } else { $null }
    $mods.Add([ordered]@{
      id          = $dir.Name
      name        = "$($m.name)"
      version     = "$($m.version)"
      description = "$($m.description)"
      type        = "$($m.type)"
      author      = "$($m.author)"
      tags        = @(@($m.tags) | Where-Object { $_ } | ForEach-Object { "$_" })
      updated     = $updated
      files       = $files.ToArray()
      preview     = $preview
    })
  }
  $index = [ordered]@{
    format    = "keyz-mod-index"
    version   = 1
    generated = (Get-Date).ToUniversalTime().ToString("o")
    repo      = $Repo
    commit    = $commit
    mods      = $mods.ToArray()
  }
  [IO.File]::WriteAllText((Join-Path $Root "index.json"), ($index | ConvertTo-Json -Depth 8) + "`n")
  Write-Host "index.json: $($mods.Count) mods at $commit"
} finally {
  Pop-Location
}
