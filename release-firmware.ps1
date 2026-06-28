<#
.SYNOPSIS
    Compile ESPHome firmware and create a GitHub Release.

.DESCRIPTION
    Compiles one or more ESPHome device configs, extracts the OTA firmware
    binaries, and optionally creates a GitHub Release with the binaries attached.
    Devices pick up new releases via the Check/Install Firmware Update buttons
    in Home Assistant.

.PARAMETER Configs
    One or more YAML config files to compile. Required.

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
    .\release-firmware.ps1 -Configs led-van-controller.yaml, other-device.yaml
    .\release-firmware.ps1 -SkipRelease
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Configs,
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

# Normalize any path to a repo-relative path using forward slashes
function ConvertTo-RepoRelative($path) {
    if ([System.IO.Path]::IsPathRooted($path)) {
        $full = [System.IO.Path]::GetFullPath($path)
        $root = [System.IO.Path]::GetFullPath($RepoRoot)
        if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $full.Substring($root.Length).TrimStart('\', '/')
        }
    }
    return ($path -replace '\\', '/')
}

# Extract YAML file references (includes + package path entries) from text
function Find-YamlReferences($content) {
    $refs = [System.Collections.Generic.List[string]]::new()

    # `!include file.yaml`  and  `!include { file: file.yaml, vars: {...} }`
    foreach ($m in [regex]::Matches($content, "!include(?:\s+|\s*\{\s*file:\s*)([^\s,}'""]+)")) {
        $refs.Add($m.Groups[1].Value)
    }

    # `path: packages/common.yaml` (remote_packages / local package file lists)
    foreach ($m in [regex]::Matches($content, "(?m)^\s*-?\s*path:\s*([^\s'""]+\.ya?ml)")) {
        $refs.Add($m.Groups[1].Value)
    }

    # Bare list items that are yaml paths, e.g. `- packages/common.yaml`
    foreach ($m in [regex]::Matches($content, "(?m)^\s*-\s*([\w./-]+\.ya?ml)\s*$")) {
        $refs.Add($m.Groups[1].Value)
    }

    return $refs
}

# Resolve a referenced path against the repo root, then the including file's dir
function Resolve-DepPath($ref, $includingDir) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add((ConvertTo-RepoRelative $ref))
    if ($includingDir) {
        $candidates.Add((ConvertTo-RepoRelative (Join-Path $includingDir $ref)))
    }
    foreach ($candidate in $candidates) {
        $full = Join-Path $RepoRoot ($candidate -replace '/', '\')
        if (Test-Path $full -PathType Leaf) {
            return $candidate
        }
    }
    return $null
}

# Recursively resolve the full YAML dependency set for a config (config itself,
# plus everything reached via !include and packages: path entries)
function Resolve-ConfigDependencies($config) {
    $resolved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue((ConvertTo-RepoRelative $config))

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $resolved.Add($current)) { continue }

        $full = Join-Path $RepoRoot ($current -replace '/', '\')
        if (-not (Test-Path $full -PathType Leaf)) { continue }

        $content = Get-Content $full -Raw
        $includingDir = Split-Path -Parent $current
        foreach ($ref in (Find-YamlReferences $content)) {
            $dep = Resolve-DepPath $ref $includingDir
            if ($dep) { $queue.Enqueue($dep) }
        }
    }

    return $resolved
}

# Find the highest ESPHome min_version declared across a config and all of its
# resolved YAML dependencies. Returns a [version], or $null if none declared.
function Get-RequiredEsphomeVersion($config) {
    $highest = $null
    foreach ($dep in (Resolve-ConfigDependencies $config)) {
        $full = Join-Path $RepoRoot ($dep -replace '/', '\')
        if (-not (Test-Path $full -PathType Leaf)) { continue }
        $content = Get-Content $full -Raw
        foreach ($m in [regex]::Matches($content, "(?m)^\s*min_version:\s*[""']?(\d+\.\d+(?:\.\d+)?)")) {
            $parsed = $null
            if ([version]::TryParse($m.Groups[1].Value, [ref]$parsed)) {
                if (-not $highest -or $parsed -gt $highest) { $highest = $parsed }
            }
        }
    }
    return $highest
}

# Look up the latest release for a device and the git commit it was built from.
# Returns @{ Tag; Sha } or $null if there is no usable prior release.
function Get-LatestReleaseInfo($device) {
    $releasesJson = gh release list --limit 200 --json tagName 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $releasesJson) { return $null }

    $prefix = "$device-v"
    $latest = $releasesJson | ConvertFrom-Json |
        Where-Object { $_.tagName -like "$prefix*" } |
        ForEach-Object {
            $versionText = $_.tagName.Substring($prefix.Length)
            $parsed = $null
            if ([version]::TryParse($versionText, [ref]$parsed)) {
                [pscustomobject]@{ Tag = $_.tagName; Version = $parsed }
            }
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $latest) { return $null }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("rel-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        gh release download $latest.Tag --dir $tempDir --pattern "$device.manifest.json" 2>$null | Out-Null
        $manifestFile = Join-Path $tempDir "$device.manifest.json"
        if (-not (Test-Path $manifestFile)) { return $null }
        $sha = (Get-Content $manifestFile -Raw | ConvertFrom-Json).build_metadata.git_sha
    } finally {
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
    if (-not $sha) { return $null }

    return [pscustomobject]@{ Tag = $latest.Tag; Sha = $sha }
}

# Return the list of dependency YAML files that changed (working tree vs the
# given release commit) for a config.
function Get-ChangedDependencies($config, $releaseSha) {
    $deps = @(Resolve-ConfigDependencies $config)
    Push-Location $RepoRoot
    try {
        $changed = git diff --name-only $releaseSha -- $deps 2>$null
    } finally {
        Pop-Location
    }
    return @($changed | Where-Object { $_ })
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

# Analyze what changed since each config's last release (before bumping the
# version, so the version-bump edit itself isn't counted as a change).
$stalenessResults = @()
if (-not $SkipRelease) {
    Write-Host "`n🔎 Checking what changed since the last release..." -ForegroundColor Cyan
    $anyChangesDetected = $false
    $allHavePriorRelease = $true

    foreach ($config in $Configs) {
        $device = Get-DeviceName $config
        $release = Get-LatestReleaseInfo $device
        if (-not $release) {
            $allHavePriorRelease = $false
            $stalenessResults += [pscustomobject]@{ Config = $config; Device = $device; Tag = $null; Changed = @(); FirstRelease = $true; Unknown = $false }
            Write-Host "   $device — no prior release (first release)" -ForegroundColor DarkGray
            continue
        }

        Push-Location $RepoRoot
        git cat-file -e "$($release.Sha)^{commit}" 2>$null
        $reachable = ($LASTEXITCODE -eq 0)
        Pop-Location
        if (-not $reachable) {
            # Can't compare — treat as changed so we don't wrongly prompt "no changes"
            $anyChangesDetected = $true
            $stalenessResults += [pscustomobject]@{ Config = $config; Device = $device; Tag = $release.Tag; Changed = @(); FirstRelease = $false; Unknown = $true }
            Write-Host "   $device — release commit $($release.Sha) not in local history (run 'git fetch')" -ForegroundColor Yellow
            continue
        }

        $changed = Get-ChangedDependencies $config $release.Sha
        if ($changed.Count -gt 0) { $anyChangesDetected = $true }
        $stalenessResults += [pscustomobject]@{ Config = $config; Device = $device; Tag = $release.Tag; Changed = $changed; FirstRelease = $false; Unknown = $false }

        if ($changed.Count -eq 0) {
            Write-Host "   $device — no dependency changes since $($release.Tag)" -ForegroundColor DarkGray
        } else {
            Write-Host "   $device — $($changed.Count) changed since $($release.Tag):" -ForegroundColor Yellow
            $changed | Sort-Object | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
        }
    }

    # If nothing changed across all configs (and each had a prior release), confirm
    if ($allHavePriorRelease -and -not $anyChangesDetected) {
        Write-Host "`n⚠️  No dependency changes detected since the last release for any config." -ForegroundColor Yellow
        $answer = Read-Host "Release a new version anyway? [y/N]"
        if ($answer -notmatch '^[Yy]') {
            Write-Host "Aborted — no new release created." -ForegroundColor DarkGray
            exit 0
        }
    }
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
        $installedRaw = $latestRaw

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

# Enforce each config's declared ESPHome min_version (fail fast before compiling)
$installedParsed = $null
[version]::TryParse($installedRaw, [ref]$installedParsed) | Out-Null
foreach ($config in $Configs) {
    $required = Get-RequiredEsphomeVersion $config
    if (-not $required) { continue }
    if ($installedParsed -and $installedParsed -lt $required) {
        Write-Error "❌ $config requires ESPHome >= $required, but $installedRaw is installed. Upgrade with: pip install --upgrade esphome"
        exit 1
    }
    Write-Host "✅ $config min_version >= $required satisfied by $installedRaw" -ForegroundColor Green
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

# Build "changes since last release" section from the earlier staleness analysis
$changesLines = foreach ($result in $stalenessResults) {
    if ($result.FirstRelease) {
        "- **$($result.Device)**: first release"
    } elseif ($result.Unknown) {
        "- **$($result.Device)**: previous release commit not available locally (changes undetermined)"
    } elseif ($result.Changed.Count -eq 0) {
        "- **$($result.Device)**: no YAML dependency changes since $($result.Tag)"
    } else {
        $files = ($result.Changed | Sort-Object | ForEach-Object { "  - ``$_``" }) -join "`n"
        "- **$($result.Device)** (since $($result.Tag)):`n$files"
    }
}
$changesSection = if ($changesLines) { $changesLines -join "`n" } else { "- No prior release data" }

$notes = @"
## $primaryDevice Firmware Release $Version

### Devices
$deviceList

### Changes Since Last Release
$changesSection

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
