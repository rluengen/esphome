# Firmware Release Process

This repository uses GitHub Pages to host compiled ESPHome firmware binaries. Devices automatically check for updates and install new firmware over-the-air (OTA).

## Architecture

```
Local Machine                   GitHub                        ESPHome Device
─────────────                   ──────                        ─────────────
secrets.yaml + YAML configs
        │
        ▼
esphome compile ──► .ota.bin
        │
        ▼
Create GitHub Release
  + attach .ota.bin ──────► GitHub Actions workflow
                              │
                              ├─ Downloads .ota.bin from release
                              ├─ Generates manifest.json (version + MD5)
                              └─ Deploys to GitHub Pages
                                        │
                                        ▼
                            https://rluengen.github.io/esphome/
                              firmware/<device>/manifest.json
                              firmware/<device>/firmware.ota.bin
                                        │
                                        ▼
                                  Device polls every 6h
                                  and auto-updates OTA
```

Secrets (WiFi credentials, API keys) never leave your local machine. Compilation happens locally; GitHub only hosts the resulting binary.

## Prerequisites

- **ESPHome CLI** installed locally (`pip install esphome`)
- **GitHub Pages** enabled on the repository (Settings → Pages → Source: **GitHub Actions**)
- Device YAML config includes the OTA update components (see [Device Configuration](#device-configuration))

## Releasing Firmware

### Quick Release (Recommended)

Use the included script to compile, build, and create a GitHub Release in one step:

```powershell
# Compile and release (will prompt for version)
.\release-firmware.ps1

# Specify version upfront
.\release-firmware.ps1 -Version 1.2.0

# Compile multiple devices
.\release-firmware.ps1 -Configs lightcontroller.yaml, other-device.yaml

# Compile only, no release
.\release-firmware.ps1 -SkipRelease
```

The script will:
1. Compile the ESPHome config(s) locally using your `secrets.yaml`
2. Extract and rename the `.ota.bin` file(s)
3. Push any unpushed commits
4. Create a GitHub Release with the binaries attached
5. Clean up local binary files

### Manual Release

### 1. Compile locally

Run the ESPHome compiler on your local machine where `secrets.yaml` is present:

```bash
esphome compile lightcontroller.yaml
```

### 2. Copy the firmware binary

The compiled OTA binary is located at:

```
.esphome/build/<device-name>/.pioenvs/<device-name>/firmware.ota.bin
```

Copy and rename it using the device name:

**Windows (PowerShell):**
```powershell
Copy-Item .esphome\build\led-van-controller\.pioenvs\led-van-controller\firmware.ota.bin `
  -Destination led-van-controller.ota.bin
```

**macOS/Linux:**
```bash
cp .esphome/build/led-van-controller/.pioenvs/led-van-controller/firmware.ota.bin \
   led-van-controller.ota.bin
```

> **Important:** The filename must follow the pattern `<device-name>.ota.bin` where `<device-name>` matches the `device_name` substitution in your YAML config. The GitHub Actions workflow uses this name to organize firmware on GitHub Pages.

### 3. Create a GitHub Release

1. Go to your repository on GitHub → **Releases** → **Draft a new release**
2. Create a new tag following semver (e.g. `v1.0.1`)
3. Attach the `<device-name>.ota.bin` file(s) as release assets
4. Publish the release

You can attach multiple device binaries to the same release if updating several devices at once.

### 4. Automatic deployment

Once the release is published, the `deploy-firmware.yml` workflow automatically:

1. Downloads all `.ota.bin` files from the release
2. Computes MD5 checksums for integrity verification
3. Generates a `manifest.json` for each device with the version and checksum
4. Deploys everything to GitHub Pages

### 5. Device update

Devices check for updates every 6 hours by polling their manifest URL:

```
https://rluengen.github.io/esphome/firmware/<device-name>/manifest.json
```

When a new version is detected, the device downloads the firmware and installs it automatically. The update also appears as an entity in Home Assistant if the device is connected via the API.

## Device Configuration

To enable OTA updates from GitHub Pages, add these components to your device YAML:

```yaml
http_request:

ota:
  - platform: http_request

update:
  - platform: http_request
    name: "Firmware Update"
    source: https://rluengen.github.io/esphome/firmware/${device_name}/manifest.json
    update_interval: 6h
```

These work alongside the standard `ota: platform: esphome` for local push-based updates.

## Adding a New Device

1. Add the OTA update components (above) to the device YAML config
2. Add a new entry to the workflow matrix in `.github/workflows/deploy-firmware.yml` if you need per-device `chipFamily` overrides (default is `ESP32`)
3. When releasing, attach the new device's `.ota.bin` with the matching `<device-name>.ota.bin` filename

## Manual Deployment

You can also trigger the workflow manually for a previously published release:

1. Go to **Actions** → **Deploy Firmware to GitHub Pages**
2. Click **Run workflow**
3. Enter the release tag (e.g. `v1.0.0`)

## Manifest Format

Each device gets a manifest at `firmware/<device-name>/manifest.json`:

```json
{
  "name": "led-van-controller",
  "version": "1.0.1",
  "builds": [
    {
      "chipFamily": "ESP32",
      "ota": {
        "md5": "abc123...",
        "path": "firmware.ota.bin",
        "summary": "Firmware update 1.0.1"
      }
    }
  ]
}
```

This follows the [ESP Web Tools manifest format](https://esphome.io/components/update/http_request.html) with the OTA extension required by ESPHome's `update: platform: http_request`.

## Troubleshooting

### Device not picking up updates
- Verify GitHub Pages is enabled and the manifest URL is accessible in a browser
- Check the device logs for HTTP errors during update checks
- Ensure `http_request:` and `ota: platform: http_request` are both present in the config

### Workflow fails
- Confirm the release has `.ota.bin` files attached (not `.factory.bin`)
- Check that the filename follows `<device-name>.ota.bin` naming
- Review the Actions log for details

### Wrong firmware version shown
- The version in the manifest comes from the git tag (e.g. `v1.0.1` → `1.0.1`)
- Update the `project_version` substitution in your YAML to match for consistency
