param(
  [string]$BootstrapFile = "packages/ota/esp32_hosted_bootstrap.yaml",
  [string]$ManifestUrl = "https://esphome.github.io/esp-hosted-firmware/manifest/esp32c6.json",
  [string]$Version = "latest",
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  param([string]$ScriptRoot)
  return (Resolve-Path (Join-Path $ScriptRoot "..")).Path
}

function Convert-ToVersion {
  param([string]$Text)
  try {
    return [version]$Text
  } catch {
    return [version]"0.0.0"
  }
}

$repoRoot = Get-RepoRoot -ScriptRoot $PSScriptRoot
$bootstrapPath = Join-Path $repoRoot $BootstrapFile
$targetBinPath = Join-Path $repoRoot "network_adapter_esp32c6.bin"

if (-not (Test-Path $bootstrapPath)) {
  throw "Bootstrap file not found: $bootstrapPath"
}

Write-Host "Fetching manifest: $ManifestUrl"
$manifest = Invoke-RestMethod -Uri $ManifestUrl
if (-not $manifest.versions -or $manifest.versions.Count -eq 0) {
  throw "Manifest has no versions."
}

if ($Version -eq "latest") {
  $selected = $manifest.versions |
    Sort-Object -Property @{ Expression = { Convert-ToVersion $_.version } } -Descending |
    Select-Object -First 1
} else {
  $selected = $manifest.versions | Where-Object { $_.version -eq $Version } | Select-Object -First 1
}

if (-not $selected) {
  throw "Version '$Version' not found in manifest."
}

Write-Host "Selected version: $($selected.version)"
Write-Host "Download URL: $($selected.url)"
Write-Host "Manifest SHA256: $($selected.sha256)"

$tempPath = Join-Path $env:TEMP ("esp32c6-hosted-" + [guid]::NewGuid().ToString() + ".bin")
try {
  Write-Host "Downloading firmware to temp file..."
  Invoke-WebRequest -Uri $selected.url -OutFile $tempPath

  $downloadedHash = (Get-FileHash -Algorithm SHA256 -Path $tempPath).Hash.ToLowerInvariant()
  $manifestHash = $selected.sha256.ToLowerInvariant()
  if ($downloadedHash -ne $manifestHash) {
    throw "Downloaded hash mismatch. Expected $manifestHash, got $downloadedHash"
  }

  if ($DryRun) {
    Write-Host "Dry run: verified download and hash; no files were changed."
    return
  }

  Copy-Item -Path $tempPath -Destination $targetBinPath -Force
  Write-Host "Updated binary: $targetBinPath"

  $yaml = Get-Content -Path $bootstrapPath -Raw
  $yaml = [regex]::Replace($yaml, "(?m)^# Pinned version: .*$", "# Pinned version: $($selected.version)")
  $yaml = [regex]::Replace($yaml, "(?m)^# Firmware URL: .*$", "# Firmware URL: $($selected.url)")
  $yaml = [regex]::Replace($yaml, "(?m)^(\s*sha256:\s*).*$", ('$1' + $manifestHash))

  Set-Content -Path $bootstrapPath -Value $yaml -NoNewline
  Write-Host "Updated bootstrap YAML: $bootstrapPath"

  Write-Host "Done."
} finally {
  if (Test-Path $tempPath) {
    Remove-Item -Path $tempPath -Force
  }
}
