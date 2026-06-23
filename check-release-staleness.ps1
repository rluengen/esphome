<#
.SYNOPSIS
    Determine whether the latest firmware release for a device is stale
    relative to its current YAML config and the YAML files it depends on.

.DESCRIPTION
    Each release produced by release-firmware.ps1 records the git commit it was
    built from (build_metadata.git_sha inside the attached <device>.manifest.json).

    This script:
      1. Resolves the recursive YAML dependency graph for a device config,
         following both `!include` directives and `packages:` file lists
         (the `path:` entries under remote_packages / local packages).
      2. Looks up the latest GitHub release for that device (tag
         "<device>-v<version>") and reads the git_sha it was built from.
      3. Asks git whether any dependency file has changed since that commit,
         including uncommitted working-tree changes.

    If any dependency changed, the release is reported as STALE — meaning the
    firmware on a device updating from that release no longer matches the
    current config.

    NOTE: The resolver follows YAML `!include` and package `path:` references.
    It does not trace non-YAML assets (custom components under components/,
    fonts, images) — changes to those will not be detected.

.PARAMETER Config
    The device YAML config to check (e.g. led-van-controller.yaml).

.PARAMETER Json
    Emit a machine-readable JSON result instead of formatted text.

.EXAMPLE
    .\check-release-staleness.ps1 -Config led-van-controller.yaml

.EXAMPLE
    .\check-release-staleness.ps1 -Config gps.yaml -Json

.NOTES
    Exit codes: 0 = up to date, 2 = stale, 1 = error.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Config,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Read the device_name substitution from a config file
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

# Recursively resolve the full YAML dependency set for a config
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

# --- Validate config exists ---------------------------------------------------
$configPath = Join-Path $RepoRoot $Config
if (-not (Test-Path $configPath -PathType Leaf)) {
    Write-Error "Config file not found: $configPath"
    exit 1
}

$device = Get-DeviceName $Config

# --- Find the latest release for this device ----------------------------------
$ghPath = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghPath) {
    Write-Error "GitHub CLI (gh) is not installed. Install with: winget install GitHub.cli"
    exit 1
}

$releasesJson = gh release list --limit 200 --json tagName 2>$null
if ($LASTEXITCODE -ne 0 -or -not $releasesJson) {
    Write-Error "Could not list GitHub releases (is gh authenticated?)."
    exit 1
}

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

if (-not $latest) {
    Write-Error "No releases found for device '$device' (expected tags like '${prefix}1.0.0')."
    exit 1
}

# --- Read the git_sha the release was built from ------------------------------
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("release-check-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    gh release download $latest.Tag --dir $tempDir --pattern "$device.manifest.json" 2>$null | Out-Null
    $manifestFile = Join-Path $tempDir "$device.manifest.json"
    if (-not (Test-Path $manifestFile)) {
        Write-Error "Release $($latest.Tag) has no '$device.manifest.json' asset to read git_sha from."
        exit 1
    }
    $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
    $releaseSha = $manifest.build_metadata.git_sha
} finally {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}

if (-not $releaseSha) {
    Write-Error "Release $($latest.Tag) manifest does not contain build_metadata.git_sha."
    exit 1
}

# --- Verify the commit is reachable in local history --------------------------
Push-Location $RepoRoot
try {
    git cat-file -e "$releaseSha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Error "Release commit '$releaseSha' is not in local git history. Run 'git fetch' and retry."
        exit 1
    }

    # --- Resolve dependencies and diff against the release commit -------------
    $deps = Resolve-ConfigDependencies $Config
    $depList = @($deps)

    # Compare working tree (committed + uncommitted) against the release commit
    $changed = git diff --name-only $releaseSha -- $depList 2>$null
    $changedList = @($changed | Where-Object { $_ })
} finally {
    Pop-Location
}

$isStale = $changedList.Count -gt 0

# --- Report -------------------------------------------------------------------
if ($Json) {
    [pscustomobject]@{
        device       = $device
        release_tag  = $latest.Tag
        release_sha  = $releaseSha
        dependencies = ($depList | Sort-Object)
        changed      = ($changedList | Sort-Object)
        stale        = $isStale
    } | ConvertTo-Json -Depth 4
} else {
    Write-Host ""
    Write-Host "Device:          $device" -ForegroundColor Cyan
    Write-Host "Latest release:  $($latest.Tag) (built from $releaseSha)" -ForegroundColor Cyan
    Write-Host "Dependencies:    $($depList.Count) YAML file(s) tracked" -ForegroundColor DarkGray

    if ($isStale) {
        Write-Host "`n⚠️  STALE — $($changedList.Count) dependency file(s) changed since the release:" -ForegroundColor Yellow
        $changedList | Sort-Object | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
        Write-Host "`nRun: .\release-firmware.ps1 -Configs $Config" -ForegroundColor DarkGray
    } else {
        Write-Host "`n✅ UP TO DATE — no tracked YAML dependency has changed since $($latest.Tag)." -ForegroundColor Green
    }
}

if ($isStale) { exit 2 } else { exit 0 }
