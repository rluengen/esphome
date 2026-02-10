# ESP32-C6 Co-Processor Firmware Flashing Guide

This guide explains how to flash the ESP-Hosted firmware to the ESP32-C6 co-processor on your Waveshare ESP32-P4-Nano board.

## Understanding the Architecture

- **ESP32-P4** = Main processor (runs your ESPHome firmware)
- **ESP32-C6** = Co-processor (provides WiFi 6 and Bluetooth 5)
- Communication between them uses SDIO protocol
- The C6 needs special "ESP-Hosted" firmware to act as a wireless co-processor

## Two Methods to Flash the C6

### Method 1: Automatic OTA Update (RECOMMENDED - Easiest!)

This method is included in your `esp32-p4-nano-dsi-hello.yaml` configuration. The ESP32-P4 will automatically flash the C6 co-processor when you first upload your ESPHome firmware.

**How it works:**
1. Flash your ESPHome configuration to the ESP32-P4 via USB (first time only)
2. The P4 will automatically detect the C6 needs firmware
3. It downloads the firmware from the internet and flashes the C6
4. Future updates happen automatically every 6 hours (checks for new versions)

**Configuration already in your YAML:**
```yaml
http_request:

update:
  - platform: esp32_hosted
    name: "ESP32-C6 Firmware"
    type: http
    source: https://esphome.github.io/esp-hosted-firmware/manifest/esp32c6.json
    update_interval: 6h
```

**Steps:**
1. Make sure your WiFi credentials are in `secrets.yaml`:
   ```yaml
   wifi_ssid: "YourWiFiSSID"
   wifi_password: "YourWiFiPassword"
   api_encryption_key: "generate_with_esphome"
   ota_password: "your_secure_password"
   ap_password: "fallback_password"
   ```

2. Compile and upload to ESP32-P4:
   ```bash
   esphome run esp32-p4-nano-dsi-hello.yaml
   ```

3. During first boot, watch the logs. You should see:
   ```
   [I][esp32_hosted_update:xxx] Checking for ESP32-C6 firmware updates...
   [I][esp32_hosted_update:xxx] Current version: none, Latest: 2.x.x
   [I][esp32_hosted_update:xxx] Downloading firmware...
   [I][esp32_hosted_update:xxx] Flashing ESP32-C6 co-processor...
   [I][esp32_hosted_update:xxx] ESP32-C6 firmware updated successfully!
   ```

4. After the C6 is flashed, the device will reboot and WiFi should work!

### Method 2: Manual Flashing (Advanced)

If automatic update doesn't work, you can manually flash the C6 using esptool.

**Requirements:**
- Python 3.x installed
- esptool.py (`pip install esptool`)
- USB cable connected to the ESP32-P4-Nano

**Steps:**

1. Download the latest ESP32-C6 firmware:
   ```bash
   # Visit: https://esphome.github.io/esp-hosted-firmware/manifest/esp32c6.json
   # Download the latest .bin file from the manifest
   ```

2. Put the board into download mode:
   - Hold the **BOOT** button
   - Press and release the **RESET** button
   - Release the **BOOT** button

3. Find your COM port:
   - Windows: Check Device Manager → Ports (COM & LPT)
   - Linux: `ls /dev/ttyUSB* or /dev/ttyACM*`
   - Should be something like COM3 or /dev/ttyUSB0

4. Erase the C6 flash:
   ```bash
   esptool.py --chip esp32c6 --port COM3 erase_flash
   ```

5. Flash the ESP-Hosted firmware:
   ```bash
   esptool.py --chip esp32c6 --port COM3 write_flash 0x0 network_adapter.bin
   ```

6. Press **RESET** button to reboot

## Verifying the Flash

After flashing (either method), check the ESPHome logs:

```bash
esphome logs esp32-p4-nano-dsi-hello.yaml
```

Look for these indicators of success:
- `[I][esp32_hosted:xxx] ESP32-C6 co-processor initialized`
- `[I][esp32_hosted:xxx] Firmware version: 2.x.x`
- `[I][wifi:xxx] WiFi connected!`
- `[I][wifi:xxx] IP Address: 192.168.x.x`

## Troubleshooting

### WiFi doesn't work after flashing
- Check that the C6 firmware version matches or is lower than the ESP-Hosted library in ESPHome
- Verify GPIO pins are correct (GPIO54=reset, GPIO19=cmd, GPIO18=clk, GPIO14-17=data)
- Try power cycling the board completely

### Can't enter download mode
- Some boards have different button combinations
- Try holding BOOT during power-on instead

### esptool.py errors
- Make sure you have permissions (Linux: add user to dialout group)
- Try a different USB cable (some are power-only)
- Check if another program is using the serial port

### Automatic update fails
- Ensure the P4 has internet access (WiFi is working)
- Check that `http_request:` component is in your configuration
- Look at logs for specific error messages

## Additional Resources

- [ESP-Hosted Firmware Repository](https://github.com/esphome/esp-hosted-firmware)
- [ESPHome ESP32-Hosted Documentation](https://next.esphome.io/components/esp32_hosted/)
- [Waveshare ESP32-P4-Nano Wiki](https://www.waveshare.com/wiki/ESP32-P4-Nano-StartPage)
- [ESPHome Devices - ESP32-P4-Nano](https://devices.esphome.io/devices/waveshare-esp32-p4-nano/)

## Summary

**For most users:** Just use Method 1 (automatic OTA). Flash your ESPHome config to the P4, and it will handle the C6 firmware automatically. The configuration in `esp32-p4-nano-dsi-hello.yaml` already includes everything you need!

The first boot will take longer while it downloads and flashes the C6, but subsequent boots will be fast. Updates happen automatically in the background.
