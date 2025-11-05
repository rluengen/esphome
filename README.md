# ESPHome YAML Templates

A comprehensive collection of ESPHome YAML configuration templates for ESP8266 and ESP32 microcontrollers. These templates provide ready-to-use configurations for common IoT scenarios, sensors, switches, and LED controls.

## 📁 Repository Structure

```
├── templates/
│   ├── base/           # Reusable base configurations
│   ├── devices/        # Device-specific templates (ESP8266, ESP32)
│   ├── sensors/        # Sensor templates (DHT22, BME280, etc.)
│   ├── switches/       # Relay and switch templates
│   └── lights/         # LED and light control templates
├── examples/           # Complete working examples
└── secrets.yaml.example # Template for sensitive credentials
```

## 🚀 Quick Start

### 1. Prerequisites

- [ESPHome](https://esphome.io/) installed
- ESP8266 or ESP32 microcontroller
- Home Assistant (optional, but recommended)

### 2. Setup Secrets File

Copy the example secrets file and fill in your credentials:

```bash
cp secrets.yaml.example secrets.yaml
```

Edit `secrets.yaml` with your actual WiFi credentials and passwords. **Never commit this file to version control!**

### 3. Choose a Template

Browse the templates directory or examples folder to find a configuration that matches your hardware setup.

### 4. Customize and Deploy

1. Copy a template or example to your ESPHome config directory
2. Update the `substitutions` section with your device details
3. Adjust GPIO pins to match your hardware connections
4. Compile and upload:

```bash
esphome run your-device.yaml
```

## 📚 Available Templates

### Base Templates

Located in `templates/base/`:

- **`wifi.yaml`** - WiFi configuration with fallback AP
- **`common.yaml`** - Common components (logging, API, OTA, status sensors)

Include these in your configs with:
```yaml
<<: !include templates/base/wifi.yaml
<<: !include templates/base/common.yaml
```

### Device Templates

Located in `templates/devices/`:

- **`esp8266-basic.yaml`** - Basic ESP8266 configuration
- **`esp32-basic.yaml`** - Basic ESP32 configuration

### Sensor Templates

Located in `templates/sensors/`:

- **`dht22.yaml`** - DHT22/DHT11/DHT21 temperature & humidity sensor
- **`bme280.yaml`** - BME280 temperature, humidity & pressure sensor (I2C)
- **`ds18b20.yaml`** - DS18B20 waterproof temperature sensor (1-Wire)
- **`bh1750.yaml`** - BH1750 light/illuminance sensor (I2C)

### Switch Templates

Located in `templates/switches/`:

- **`relay-basic.yaml`** - Single relay/switch control
- **`relay-4ch.yaml`** - 4-channel relay board
- **`relay-with-button.yaml`** - Relay with physical button toggle

### Light Templates

Located in `templates/lights/`:

- **`led-single-esp8266.yaml`** - Single color PWM LED strip for ESP8266
- **`led-single-esp32.yaml`** - Single color PWM LED strip for ESP32
- **`led-rgb-esp8266.yaml`** - RGB LED strip (PWM) for ESP8266
- **`led-rgb-esp32.yaml`** - RGB LED strip (PWM) for ESP32
- **`led-rgbw-esp8266.yaml`** - RGBW LED strip (PWM) for ESP8266
- **`led-rgbw-esp32.yaml`** - RGBW LED strip (PWM) for ESP32
- **`led-ws2812b.yaml`** - Addressable LED strip (WS2812B/NeoPixel) - works on both platforms

## 💡 Complete Examples

Located in `examples/`:

### ESP8266 Examples
- **`esp8266-dht22-sensor.yaml`** - Temperature & humidity monitoring station
- **`esp8266-multi-sensor.yaml`** - Multi-sensor weather station (BME280 + BH1750)

### ESP32 Examples
- **`esp32-relay-with-button.yaml`** - Smart switch with physical button
- **`esp32-rgb-led.yaml`** - RGB LED strip controller

## 🔧 Customization Guide

### Substitutions

Each template uses substitutions for easy customization:

```yaml
substitutions:
  devicename: my_device      # Internal device name (no spaces)
  friendly_name: My Device   # Display name in Home Assistant
  board_type: nodemcuv2      # Your board type
```

### GPIO Pin Mapping

Always verify GPIO pins match your hardware:

**Common ESP8266 pins:**
- D0 = GPIO16, D1 = GPIO5, D2 = GPIO4, D3 = GPIO0
- D4 = GPIO2, D5 = GPIO14, D6 = GPIO12, D7 = GPIO13, D8 = GPIO15

**Common ESP32 pins:**
- Most GPIOs can be freely used (check your board's pinout)
- Avoid GPIO 6-11 (connected to flash)
- I2C default: SDA=GPIO21, SCL=GPIO22

### Combining Templates

You can combine multiple templates in a single configuration:

```yaml
substitutions:
  devicename: multi_device
  friendly_name: Multi Device

esphome:
  name: ${devicename}

esp32:
  board: esp32dev

<<: !include templates/base/wifi.yaml
<<: !include templates/base/common.yaml
<<: !include templates/sensors/dht22.yaml
<<: !include templates/switches/relay-basic.yaml
```

## 🔐 Security Best Practices

1. **Always use secrets.yaml** for sensitive information
2. **Enable API encryption** for Home Assistant connection
3. **Set OTA password** to prevent unauthorized updates
4. **Use strong WiFi passwords**
5. **Add secrets.yaml to .gitignore**

Example `.gitignore`:
```
secrets.yaml
*.bin
```

## 📖 Additional Resources

- [ESPHome Official Documentation](https://esphome.io/)
- [ESPHome Component Reference](https://esphome.io/components/)
- [Home Assistant](https://www.home-assistant.io/)
- [ESPHome Discord Community](https://discord.gg/KhAMKrd)

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Add new templates for additional sensors/devices
- Improve existing templates
- Fix bugs or documentation issues
- Share your working configurations

## 📄 License

This repository is provided as-is for educational and development purposes. Use at your own risk.

## ⚠️ Disclaimer

Always double-check GPIO pin assignments and electrical connections before powering on your device. Incorrect wiring can damage your microcontroller or connected components.

---

**Happy Building with ESPHome! 🎉**