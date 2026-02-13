<#
.SYNOPSIS
    Compile ESPHome firmware and create a GitHub Release.

.DESCRIPTION
    Compiles one or more ESPHome device configs, extracts the OTA firmware
    binaries, and optionally creates a GitHub Release with the binaries attached.
    Devices automatically pick up new releases via the http_request update platform.

.PARAMETER Configs
    One or more YAML config files to compile. Defaults to lightcontroller.yaml.

.PARAMETER Version
    Semantic version for the release tag (e.g. 1.2.0). Prompted if not provided.

.PARAMETER SkipRelease
    Compile only — don't create a GitHub Release.

.EXAMPLE
    .\release-firmware.ps1
    .\release-firmware.ps1 -Version 1.2.0
    .\release-firmware.ps1 -Configs lightcontroller.yaml, other-device.yaml
    .\release-firmware.ps1 -SkipRelease
#>

param(
    [string[]]$Configs = @("lightcontroller.yaml"),
    [string]$Version,
    [switch]$SkipRelease
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Map config files to device names by reading the device_name substitution
function Get-DeviceName($config) {
    $content = Get-Content (Join-Path $RepoRoot $config) -Raw
    if ($content -match "device_name:\s*(.+)") {
        return $Matches[1].Trim()
    }
    throw "Could not find device_name substitution in $config"
}

# Update project_version in a YAML config file
function Update-ProjectVersion($config, $newVersion) {
    $configPath = Join-Path $RepoRoot $config
    $content = Get-Content $configPath -Raw
    if ($content -match "project_version:\s*[`"']?[\d\.]+[`"']?") {
        $updated = $content -replace "(project_version:\s*)[`"']?[\d\.]+[`"']?", "`${1}`"$newVersion`""
        Set-Content $configPath $updated -NoNewline
        Write-Host "📝 Updated project_version to $newVersion in $config" -ForegroundColor Cyan
        return $true
    }
    Write-Host "⚠️  No project_version found in $config, skipping version update" -ForegroundColor Yellow
    return $false
}

# Prompt for version if not provided
if (-not $Version) {
    $latestTag = git --no-pager tag --sort=-v:refname | Select-Object -First 1
    if ($latestTag) {
        Write-Host "`nLatest tag: $latestTag" -ForegroundColor DarkGray
    }
    $Version = Read-Host "`nEnter version for this release (e.g. 1.2.0)"
    if (-not $Version) {
        Write-Error "Version is required"
        exit 1
    }
}

$tag = "v$Version"

# Update version numbers in config files and commit
$versionUpdated = $false
foreach ($config in $Configs) {
    if (Update-ProjectVersion $config $Version) {
        $versionUpdated = $true
    }
}

if ($versionUpdated) {
    Write-Host "`n📦 Committing version bump..." -ForegroundColor Cyan
    Push-Location $RepoRoot
    git add -A
    git commit -m "Bump firmware version to $Version"
    Pop-Location
}

# Compile and extract firmware
$artifacts = @()
foreach ($config in $Configs) {
    $configPath = Join-Path $RepoRoot $config
    if (-not (Test-Path $configPath)) {
        Write-Error "Config file not found: $configPath"
        exit 1
    }

    $deviceName = Get-DeviceName $config
    Write-Host "`n🔨 Compiling $config (device: $deviceName)..." -ForegroundColor Cyan

    Push-Location $RepoRoot
    esphome compile $config
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Compilation failed for $config"
        Pop-Location
        exit 1
    }
    Pop-Location

    $srcBin = Join-Path $RepoRoot ".esphome\build\$deviceName\.pioenvs\$deviceName\firmware.ota.bin"
    if (-not (Test-Path $srcBin)) {
        Write-Error "❌ firmware.ota.bin not found at $srcBin"
        exit 1
    }

    $destBin = Join-Path $RepoRoot "$deviceName.ota.bin"
    Copy-Item $srcBin $destBin -Force
    $size = [math]::Round((Get-Item $destBin).Length / 1KB, 1)
    $md5 = (Get-FileHash $destBin -Algorithm MD5).Hash.ToLower()
    Write-Host "✅ $deviceName.ota.bin ($size KB, md5: $md5)" -ForegroundColor Green

    $artifacts += @{ Name = $deviceName; Path = $destBin }
}

if ($SkipRelease) {
    Write-Host "`n📦 Firmware compiled. Skipping release creation." -ForegroundColor Yellow
    Write-Host "Binaries:"
    $artifacts | ForEach-Object { Write-Host "  $($_.Path)" }
    exit 0
}

# Verify gh CLI is available and authenticated
$ghPath = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghPath) {
    Write-Error "GitHub CLI (gh) is not installed. Install with: winget install GitHub.cli"
    exit 1
}

$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n⚠️  GitHub CLI is not authenticated." -ForegroundColor Yellow
    Write-Host "Run: gh auth login --web --git-protocol https" -ForegroundColor Yellow
    Write-Host "Then open https://github.com/login/device and enter the code shown." -ForegroundColor Yellow
    exit 1
}

# Ensure latest commits are pushed
Write-Host "`n📤 Pushing latest commits..." -ForegroundColor Cyan
git push origin main

# Create the release with all firmware binaries attached
$assetArgs = $artifacts | ForEach-Object { $_.Path }
Write-Host "`n🚀 Creating release $tag..." -ForegroundColor Cyan

$deviceList = ($artifacts | ForEach-Object { "- ``$($_.Name).ota.bin``" }) -join "`n"
$notes = @"
## Firmware Release $Version

### Devices
$deviceList

### Update
Devices with ``update: platform: http_request`` can check for and install this release via the Check/Install Firmware Update buttons in Home Assistant.
"@

gh release create $tag $assetArgs --title "Firmware $Version" --notes $notes
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Failed to create release"
    exit 1
}

Write-Host "`n✅ Release $tag created successfully!" -ForegroundColor Green
Write-Host "View at: https://github.com/rluengen/esphome/releases/tag/$tag" -ForegroundColor DarkGray

# Clean up local .ota.bin files
$artifacts | ForEach-Object { Remove-Item $_.Path -Force }
Write-Host "🧹 Cleaned up local .ota.bin files" -ForegroundColor DarkGray
