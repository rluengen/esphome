# Contributing to ESPHome Templates

Thank you for your interest in contributing to this repository! This guide will help you add new templates or improve existing ones.

## 🎯 What to Contribute

We welcome contributions for:

- New sensor templates (PIR, ultrasonic, gas sensors, etc.)
- New device configurations (specific boards, modules)
- Additional light/LED templates (effects, patterns)
- Switch and automation templates
- Complete example configurations
- Documentation improvements
- Bug fixes

## 📝 Template Guidelines

### 1. File Naming

- Use lowercase with hyphens: `sensor-name.yaml`
- Be descriptive: `bme680-air-quality.yaml` not `sensor1.yaml`
- Place in appropriate directory:
  - `templates/sensors/` - Individual sensors
  - `templates/switches/` - Switches and relays
  - `templates/lights/` - Lights and LEDs
  - `templates/devices/` - Base device configurations
  - `examples/` - Complete working examples

### 2. Template Structure

Each template should include:

```yaml
# Clear descriptive header comment
# Explain what hardware is needed
# List GPIO pin connections

# Your YAML configuration here
# Use ${friendly_name} substitution where appropriate
# Include helpful inline comments
```

### 3. Best Practices

- **Use substitutions** for device-specific values
- **Add comments** explaining GPIO pins and hardware connections
- **Include all necessary configuration** (don't assume other includes)
- **Test your template** before submitting
- **Specify hardware requirements** in comments
- **Provide default values** that work but can be customized
- **Use meaningful names** for IDs and entities

### 4. Example Template Format

```yaml
# BME680 Air Quality Sensor Template
# I2C sensor for temperature, humidity, pressure, and gas resistance
# Connections: SCL to GPIO22, SDA to GPIO21 (ESP32 default)
#              SCL to GPIO5, SDA to GPIO4 (ESP8266 default)

i2c:
  sda: GPIO21  # Change for ESP8266: GPIO4
  scl: GPIO22  # Change for ESP8266: GPIO5
  scan: true

sensor:
  - platform: bme680
    temperature:
      name: "${friendly_name} Temperature"
      oversampling: 16x
    pressure:
      name: "${friendly_name} Pressure"
      oversampling: 16x
    humidity:
      name: "${friendly_name} Humidity"
      oversampling: 16x
    gas_resistance:
      name: "${friendly_name} Gas Resistance"
    address: 0x77  # or 0x76
    update_interval: 60s
```

## 🔄 Submission Process

1. **Fork the repository**
2. **Create a new branch** for your contribution
   ```bash
   git checkout -b add-bme680-template
   ```
3. **Add your template** in the appropriate directory
4. **Update README.md** if adding a new category
5. **Test your configuration** on actual hardware if possible
6. **Commit your changes** with a clear message
   ```bash
   git commit -m "Add BME680 air quality sensor template"
   ```
7. **Push to your fork**
   ```bash
   git push origin add-bme680-template
   ```
8. **Create a Pull Request** with description of what you added

## ✅ Pull Request Checklist

Before submitting, ensure:

- [ ] Template is properly commented
- [ ] GPIO pins are clearly marked
- [ ] File is in the correct directory
- [ ] File naming follows conventions
- [ ] Uses substitutions appropriately
- [ ] Tested (if possible)
- [ ] README.md updated if needed
- [ ] No secrets or passwords in the file

## 📖 Documentation

When adding a new template:

1. Update the main README.md if it's a new category
2. Include hardware requirements in the file header
3. Provide wiring/connection information
4. List any required external components

## 🐛 Bug Reports

If you find a bug or issue:

1. Check if it's already reported in Issues
2. Provide clear description of the problem
3. Include relevant configuration snippets
4. Specify hardware and ESPHome version if applicable

## 💬 Questions?

If you have questions about contributing:

- Open an issue with the "question" label
- Join the [ESPHome Discord](https://discord.gg/KhAMKrd)
- Check the [ESPHome documentation](https://esphome.io/)

## 📄 License

By contributing, you agree that your contributions will be licensed under the same terms as the project.

---

Thank you for helping make this resource better for everyone! 🙏
