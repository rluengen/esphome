<#
.SYNOPSIS
    Compile ESPHome firmware and create a GitHub Release.

.DESCRIPTION
    Compiles one or more ESPHome device configs, extracts the OTA firmware
    binaries, and optionally creates a GitHub Release with the binaries attached.
    Devices pick up new releases via the Check/Install Firmware Update buttons
    in Home Assistant.

.PARAMETER Configs
    One or more YAML config files to compile. Defaults to lightcontroller.yaml.

.PARAMETER Version
    Semantic version for the release tag (e.g. 1.2.0). If omitted, auto-increments
    the patch version from the latest git tag (or from the config's project_version).

.PARAMETER Major
    Auto-increment the major version (e.g. 1.2.3 → 2.0.0).

.PARAMETER Minor
    Auto-increment the minor version (e.g. 1.2.3 → 1.3.0).

.PARAMETER SkipRelease
    Compile only — don't create a GitHub Release.

.EXAMPLE
    .\release-firmware.ps1                    # auto-increment patch
    .\release-firmware.ps1 -Minor             # auto-increment minor
    .\release-firmware.ps1 -Major             # auto-increment major
    .\release-firmware.ps1 -Version 1.2.0     # explicit version
    .\release-firmware.ps1 -Configs lightcontroller.yaml, other-device.yaml
    .\release-firmware.ps1 -SkipRelease
#>

param(
    [string[]]$Configs = @("lightcontroller.yaml"),
    [string]$Version,
    [switch]$Major,
    [switch]$Minor,
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

# Extract build metadata from ESPHome build artifacts
function Get-BuildMetadata($deviceName) {
    $buildDir = Join-Path $RepoRoot ".esphome\build\$deviceName"
    $meta = @{
        esphome_version = $null
        esp_idf_version = $null
        platform_version = $null
        build_time = $null
        config_hash = $null
        git_sha = $null
    }

    # build_info.json — ESPHome version, build time, config hash
    $buildInfo = Join-Path $buildDir "build_info.json"
    if (Test-Path $buildInfo) {
        $info = Get-Content $buildInfo -Raw | ConvertFrom-Json
        $meta.esphome_version = $info.esphome_version
        $meta.build_time = $info.build_time_str
        $meta.config_hash = $info.config_hash
    }

    # dependencies.lock — ESP-IDF version
    $depsLock = Join-Path $buildDir "dependencies.lock"
    if (Test-Path $depsLock) {
        $depsContent = Get-Content $depsLock -Raw
        if ($depsContent -match '(?ms)^  idf:.*?version:\s*([\d\.]+)') {
            $meta.esp_idf_version = $Matches[1]
        }
    }

    # platformio.ini — PlatformIO platform version
    $pioIni = Join-Path $buildDir "platformio.ini"
    if (Test-Path $pioIni) {
        $pioContent = Get-Content $pioIni -Raw
        if ($pioContent -match 'platform-espressif32/releases/download/([\d\.]+)/') {
            $meta.platform_version = $Matches[1]
        }
    }

    # Git SHA of current commit
    $meta.git_sha = (git rev-parse --short HEAD 2>$null)

    return $meta
}

# Check if a previous build exists and warn about staleness
function Test-BuildStaleness($deviceName) {
    $buildInfo = Join-Path $RepoRoot ".esphome\build\$deviceName\build_info.json"
    if (Test-Path $buildInfo) {
        $info = Get-Content $buildInfo -Raw | ConvertFrom-Json
        $buildEsphome = $info.esphome_version
        if ($buildEsphome -and $buildEsphome -ne $installedRaw) {
            Write-Host "⚠️  Existing build cache for $deviceName was compiled with ESPHome $buildEsphome (current: $installedRaw)" -ForegroundColor Yellow
            Write-Host "   Recommend: clean build to avoid stale artifacts" -ForegroundColor Yellow
            $answer = Read-Host "   Clean build cache and recompile? [Y/n]"
            if ($answer -eq '' -or $answer -match '^[Yy]') {
                $buildDir = Join-Path $RepoRoot ".esphome\build\$deviceName"
                Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
                Write-Host "   🧹 Cleared build cache for $deviceName" -ForegroundColor DarkGray
            }
        }
    }
}

# Detect chip family from ESPHome build output (sdkconfig)
# Maps IDF target names to ESP-Web-Tools chipFamily values
function Get-ChipFamily($deviceName) {
    $sdkconfig = Join-Path $RepoRoot ".esphome\build\$deviceName\sdkconfig.$deviceName"
    if (Test-Path $sdkconfig) {
        $content = Get-Content $sdkconfig -Raw
        if ($content -match 'CONFIG_IDF_TARGET="([^"]+)"') {
            $target = $Matches[1].ToUpper()
            switch ($target) {
                "ESP32"   { return "ESP32" }
                "ESP32S2" { return "ESP32-S2" }
                "ESP32S3" { return "ESP32-S3" }
                "ESP32C3" { return "ESP32-C3" }
                "ESP32C6" { return "ESP32-C6" }
                "ESP32H2" { return "ESP32-H2" }
                "ESP32P4" { return "ESP32-P4" }
                default   { return $target }
            }
        }
    }
    Write-Host "⚠️  Could not detect chip family for $deviceName, defaulting to ESP32" -ForegroundColor Yellow
    return "ESP32"
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

# Determine version: explicit > auto-increment > prompt
function Get-CurrentVersion {
    # Read project_version from first config (most up-to-date source)
    $content = Get-Content (Join-Path $RepoRoot $Configs[0]) -Raw
    if ($content -match "project_version:\s*[`"']?([\d\.]+)[`"']?") {
        return $Matches[1]
    }
    # Fall back to latest git tag
    $latestTag = git --no-pager tag --sort=-v:refname 2>$null | Select-Object -First 1
    if ($latestTag -match "^v?(\d+\.\d+\.\d+)") {
        return $Matches[1]
    }
    return "0.0.0"
}

function Increment-Version($current, $bumpMajor, $bumpMinor) {
    $parts = $current.Split('.')
    $maj = [int]$parts[0]
    $min = [int]$parts[1]
    $pat = [int]$parts[2]

    if ($bumpMajor) {
        return "$($maj + 1).0.0"
    } elseif ($bumpMinor) {
        return "$maj.$($min + 1).0"
    } else {
        return "$maj.$min.$($pat + 1)"
    }
}

# Verify gh CLI is available and authenticated (before doing any work)
if (-not $SkipRelease) {
    $ghPath = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghPath) {
        Write-Error "GitHub CLI (gh) is not installed. Install with: winget install GitHub.cli"
        exit 1
    }

    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n⚠️  GitHub CLI is not authenticated. Launching login..." -ForegroundColor Yellow
        gh auth login --web --git-protocol https
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ GitHub authentication failed"
            exit 1
        }
    }
    Write-Host "✅ GitHub CLI authenticated" -ForegroundColor Green
}

# Ensure ESPHome is up to date before compiling release firmware
Write-Host "`n🔍 Checking ESPHome version..." -ForegroundColor Cyan
$installedRaw = (esphome version 2>&1) | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches[0].Value }
if (-not $installedRaw) {
    Write-Error "❌ Could not determine installed ESPHome version. Is esphome installed?"
    exit 1
}

try {
    $latestRaw = (Invoke-RestMethod -Uri "https://pypi.org/pypi/esphome/json" -TimeoutSec 10).info.version
} catch {
    Write-Host "⚠️  Could not check PyPI for latest version (offline?). Continuing with $installedRaw" -ForegroundColor Yellow
    $latestRaw = $installedRaw
}

if ($installedRaw -ne $latestRaw) {
    Write-Host "⬆️  ESPHome update available: $installedRaw → $latestRaw" -ForegroundColor Yellow
    $answer = Read-Host "Upgrade now? [Y/n]"
    if ($answer -eq '' -or $answer -match '^[Yy]') {
        Write-Host "📦 Upgrading ESPHome..." -ForegroundColor Cyan
        pip install --upgrade esphome
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ ESPHome upgrade failed"
            exit 1
        }
        Write-Host "✅ ESPHome upgraded to $latestRaw" -ForegroundColor Green

        # Clean build cache after upgrade to avoid stale artifacts
        $buildDir = Join-Path $RepoRoot ".esphome\build"
        if (Test-Path $buildDir) {
            Write-Host "🧹 Clearing build cache after upgrade..." -ForegroundColor DarkGray
            Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "Continuing with ESPHome $installedRaw" -ForegroundColor DarkGray
    }
} else {
    Write-Host "✅ ESPHome $installedRaw is the latest version" -ForegroundColor Green
}

if (-not $Version) {
    $currentVersion = Get-CurrentVersion
    if ($Major -or $Minor -or -not $PSBoundParameters.ContainsKey('Version')) {
        $Version = Increment-Version $currentVersion $Major $Minor
        $bumpType = if ($Major) { "major" } elseif ($Minor) { "minor" } else { "patch" }
        Write-Host "`n📌 Auto-incrementing $bumpType version: $currentVersion → $Version" -ForegroundColor Cyan
    } else {
        Write-Host "`nCurrent version: $currentVersion" -ForegroundColor DarkGray
        $Version = Read-Host "Enter version for this release (e.g. 1.2.0)"
        if (-not $Version) {
            Write-Error "Version is required"
            exit 1
        }
    }
}

# Build device-scoped tag (e.g. gps-v1.0.4, lightcontroller-v1.2.0)
$primaryDevice = Get-DeviceName $Configs[0]
$tag = "$primaryDevice-v$Version"

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
    # Check for stale build cache (compiled with different ESPHome version)
    Test-BuildStaleness $deviceName

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

    # Detect chip family and extract build metadata
    $chipFamily = Get-ChipFamily $deviceName
    $buildMeta = Get-BuildMetadata $deviceName

    # Generate manifest.json with build metadata
    $manifest = @{
        name = $deviceName
        version = $Version
        builds = @(
            @{
                chipFamily = $chipFamily
                ota = @{
                    md5 = $md5
                    path = "firmware.ota.bin"
                    summary = "Firmware update $Version"
                }
            }
        )
        build_metadata = @{
            esphome_version = $buildMeta.esphome_version
            esp_idf_version = $buildMeta.esp_idf_version
            platform_version = $buildMeta.platform_version
            build_time = $buildMeta.build_time
            config_hash = "$($buildMeta.config_hash)"
            git_sha = $buildMeta.git_sha
        }
    } | ConvertTo-Json -Depth 4

    $manifestPath = Join-Path $RepoRoot "$deviceName.manifest.json"
    Set-Content $manifestPath $manifest -NoNewline

    Write-Host "✅ $deviceName.ota.bin ($size KB, md5: $md5, chip: $chipFamily)" -ForegroundColor Green
    Write-Host "   ESPHome: $($buildMeta.esphome_version) | ESP-IDF: $($buildMeta.esp_idf_version) | Platform: $($buildMeta.platform_version) | Git: $($buildMeta.git_sha)" -ForegroundColor DarkGray

    $artifacts += @{ Name = $deviceName; BinPath = $destBin; ManifestPath = $manifestPath; BuildMeta = $buildMeta }
}

if ($SkipRelease) {
    Write-Host "`n📦 Firmware compiled. Skipping release creation." -ForegroundColor Yellow
    Write-Host "Artifacts:"
    $artifacts | ForEach-Object {
        Write-Host "  $($_.BinPath)"
        Write-Host "  $($_.ManifestPath)"
    }
    exit 0
}

# Ensure latest commits are pushed
Write-Host "`n📤 Pushing latest commits..." -ForegroundColor Cyan
git push origin main

# Create the release with all firmware binaries and manifests attached
$assetArgs = $artifacts | ForEach-Object { $_.BinPath; $_.ManifestPath }
Write-Host "`n🚀 Creating release $tag..." -ForegroundColor Cyan

$deviceList = ($artifacts | ForEach-Object { "- ``$($_.Name).ota.bin``" }) -join "`n"
$primaryMeta = $artifacts[0].BuildMeta
$notes = @"
## $primaryDevice Firmware Release $Version

### Devices
$deviceList

### Build Environment
| Component | Version |
|-----------|--------|
| ESPHome | $($primaryMeta.esphome_version) |
| ESP-IDF | $($primaryMeta.esp_idf_version) |
| PlatformIO Platform | $($primaryMeta.platform_version) |
| Git Commit | $($primaryMeta.git_sha) |
| Build Time | $($primaryMeta.build_time) |

### Update
Devices with ``update: platform: http_request`` can check for and install this release via the Check/Install Firmware Update buttons in Home Assistant.
"@

gh release create $tag $assetArgs --title "$primaryDevice Firmware $Version" --notes $notes
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Failed to create release"
    exit 1
}

Write-Host "`n✅ Release $tag created successfully!" -ForegroundColor Green
Write-Host "View at: https://github.com/rluengen/esphome/releases/tag/$tag" -ForegroundColor DarkGray

# Clean up local build artifacts
$artifacts | ForEach-Object {
    Remove-Item $_.BinPath -Force
    Remove-Item $_.ManifestPath -Force
}
Write-Host "🧹 Cleaned up local build artifacts" -ForegroundColor DarkGray
