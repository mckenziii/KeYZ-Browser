<#
.SYNOPSIS
  Checks a pull request to the KeYZ mod store (run by .github/workflows/check-mod.yml).

.DESCRIPTION
  Reads the pull request's files as plain data - nothing from the pull request is
  ever run. Writes report.md (posted as a comment) and the step outputs ok, type
  and id. Exits 1 when the mod can't be published, so the check shows red.
#>
param(
  [Parameter(Mandatory = $true)] [string] $Base,
  [Parameter(Mandatory = $true)] [string] $Pr,
  [Parameter(Mandatory = $true)] [string] $Changed,
  [Parameter(Mandatory = $true)] [string] $Author,
  [Parameter(Mandatory = $true)] [string] $Owner,
  [string] $Report = "report.md"
)

$ErrorActionPreference = "Stop"
$errors = New-Object System.Collections.Generic.List[string]
$hints = New-Object System.Collections.Generic.List[string]
$idPattern = '^[a-z0-9][a-z0-9-]{1,39}$'
$filePattern = '^[a-z0-9][a-z0-9._-]{0,60}\.uc\.(css|js|mjs)$'
$maxCode = 512KB
$sensitive = @("Services.logins", "nsILoginManager", "Subprocess", "nsIProcess", "ctypes", "IOUtils.write", "IOUtils.remove",
  "fetch(", "XMLHttpRequest", "WebSocket", "eval(", "new Function", "loadSubScript", "Services.prefs.set", "nsIFile",
  "cookies", "clipboard", "Services.io.newChannel")

$rows = @(Get-Content $Changed | Where-Object { $_.Trim() } | ForEach-Object {
  $parts = $_ -split "`t"
  [pscustomobject]@{ Path = $parts[0]; Status = $parts[1] }
})
$ids = @($rows | ForEach-Object {
  if ($_.Path -match '^mods/([^/]+)/[^/]+$') { $Matches[1] } else { $errors.Add("Only files inside ``mods/<your-mod>/`` can change (not ``$($_.Path)``).") }
} | Sort-Object -Unique)
if ($ids.Count -ne 1) { $errors.Add("A pull request must add or update exactly one mod (this one touches $($ids.Count)).") }
foreach ($row in $rows) {
  if ($row.Status -eq "removed") { $errors.Add("Removing files isn't allowed in a mod pull request (``$($row.Path)``) - ask the store owner.") }
}

$id = if ($ids.Count -eq 1) { $ids[0] } else { "" }
$type = ""
if ($id) {
  $dir = Join-Path $Pr "mods/$id"
  $manifestPath = Join-Path $dir "mod.json"
  $m = $null
  if ($id -notmatch $idPattern) { $errors.Add("The folder name ``$id`` must be lower-case letters, numbers and dashes.") }
  if (-not (Test-Path $manifestPath)) {
    $errors.Add("``mods/$id/mod.json`` is missing.")
  } else {
    try { $m = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $errors.Add("``mod.json`` isn't valid JSON.") }
  }
  if ($m) {
    if ("$($m.id)" -cne $id) { $errors.Add("``mod.json``'s id must be ``$id`` (the folder name).") }
    if (-not "$($m.name)".Trim() -or "$($m.name)".Length -gt 60) { $errors.Add("``name`` is required (60 characters at most).") }
    if ("$($m.version)" -notmatch '^\d+\.\d+\.\d+$') { $errors.Add("``version`` must look like 1.0.0.") }
    if ("$($m.description)".Length -gt 300) { $errors.Add("``description`` is 300 characters at most.") }
    if ("$($m.author)" -ne $Author) { $errors.Add("``author`` must be your GitHub name (``$Author``).") }
    if (@("style", "script") -notcontains "$($m.type)") { $errors.Add("``type`` must be ``style`` or ``script``.") } else { $type = "$($m.type)" }
    $files = @($m.files | ForEach-Object { "$_" })
    if ($files.Count -lt 1 -or $files.Count -gt 5) { $errors.Add("``files`` must list 1 to 5 files.") }
    foreach ($f in $files) {
      if ($f -notmatch $filePattern) { $errors.Add("``$f`` isn't an allowed file name (something.uc.css, .uc.js or .uc.mjs)."); continue }
      if ($type -eq "style" -and $f -notmatch '\.uc\.css$') { $errors.Add("Style mods can only contain .uc.css files (``$f``).") }
      $path = Join-Path $dir $f
      if (-not (Test-Path $path)) { $errors.Add("``$f`` is listed but missing."); continue }
      if ((Get-Item $path).Length -gt $maxCode) { $errors.Add("``$f`` is bigger than 512 KB.") }
      $text = [IO.File]::ReadAllText((Resolve-Path $path).Path)
      if ($f -match '\.uc\.css$') {
        if ($text -match '(?i)url\(\s*["'']?\s*(https?:|ftp:|file:|//)') { $errors.Add("``$f`` loads something from the internet (``url(http...)``). Style mods must be self-contained: use data: URLs.") }
        if ($text -match '(?i)@import') { $errors.Add("``$f`` uses ``@import``, which isn't allowed.") }
        if ($text -match '(?i)-moz-binding|javascript:') { $errors.Add("``$f`` contains something only script mods may do.") }
      } else {
        foreach ($api in $sensitive) {
          if ($text.Contains($api)) { $hints.Add("``$f`` uses ``$api``") }
        }
      }
    }
    $allowed = @("mod.json", "README.md", "preview.png") + $files
    foreach ($file in Get-ChildItem $dir -File) {
      if ($allowed -notcontains $file.Name) { $errors.Add("Unexpected file ``$($file.Name)`` in ``mods/$id/``.") }
    }
    $preview = Join-Path $dir "preview.png"
    if ((Test-Path $preview) -and (Get-Item $preview).Length -gt 500KB) { $errors.Add("``preview.png`` is bigger than 500 KB.") }

    # Updates: only the original author (or the store owner) may change a mod, and the version must go up.
    $oldPath = Join-Path $Base "mods/$id/mod.json"
    if (Test-Path $oldPath) {
      $old = Get-Content $oldPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ("$($old.author)" -ne $Author -and $Author -ne $Owner) { $errors.Add("``$id`` belongs to $($old.author); only they can update it.") }
      if ("$($m.version)" -match '^\d+\.\d+\.\d+$' -and [version]"$($m.version)" -le [version]"$($old.version)") {
        $errors.Add("The version must go up (the store has $($old.version)).")
      }
      if ("$($old.type)" -eq "style" -and $type -eq "script") { $hints.Add("This update turns a style mod into a script mod.") }
    }
  }
}

$ok = $errors.Count -eq 0
$lines = New-Object System.Collections.Generic.List[string]
if ($ok -and $type -eq "style") {
  $lines.Add("✅ **$id** passed the checks. Style mods go live automatically - it'll be in the store in a minute or two.")
} elseif ($ok) {
  $lines.Add("✅ **$id** passed the automatic checks. It's a **script mod**, so @$Owner will review the code before it goes live.")
  if ($hints.Count) {
    $lines.Add("")
    $lines.Add("Things for the reviewer to look at:")
    foreach ($hint in $hints | Sort-Object -Unique) { $lines.Add("- $hint") }
  }
} else {
  $lines.Add("❌ This pull request can't be published yet:")
  $lines.Add("")
  foreach ($e in $errors) { $lines.Add("- $e") }
  $lines.Add("")
  $lines.Add("Fix these and publish again from KeYZ Browser (or push to this branch) - the checks re-run by themselves.")
}
[IO.File]::WriteAllText((Join-Path (Get-Location) $Report), ($lines -join "`n") + "`n")
if ($env:GITHUB_OUTPUT) {
  Add-Content -Path $env:GITHUB_OUTPUT -Value "ok=$($ok.ToString().ToLower())"
  Add-Content -Path $env:GITHUB_OUTPUT -Value "type=$type"
  Add-Content -Path $env:GITHUB_OUTPUT -Value "id=$id"
}
Write-Host ($lines -join "`n")
if (-not $ok) { exit 1 }
exit 0
