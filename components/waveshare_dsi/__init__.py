"""
Waveshare 8.8" DSI Display Component for ESP32-P4

Implements the ESPHome Display interface with BSP-correct DSI init order:
  HW Reset -> MCU Init -> DSI bus -> DPI panel -> DCS SLPOUT/DISPON -> panel_init

Required for OTA7290B bridge displays where DCS commands must be sent in
LP mode BEFORE DPI video starts.  The built-in mipi_dsi component sends
DCS after panel_init, causing blank screen on these displays.
"""
import esphome.codegen as cg
import esphome.config_validation as cv
from esphome.const import CONF_ID
from esphome.components.esp32 import VARIANT_ESP32P4, only_on_variant
from esphome.components import display

CODEOWNERS = ["@rluengen"]
DEPENDENCIES = ["esp32", "psram", "esp_ldo"]
AUTO_LOAD = ["display"]

waveshare_dsi_ns = cg.esphome_ns.namespace("waveshare_dsi")
WaveshareDSI = waveshare_dsi_ns.class_("WaveshareDSI", display.Display)

CONFIG_SCHEMA = cv.All(
    display.FULL_DISPLAY_SCHEMA.extend(
        {
            cv.GenerateID(): cv.declare_id(WaveshareDSI),
        }
    ),
    cv.only_on_esp32,
    only_on_variant(supported=[VARIANT_ESP32P4]),
)


async def to_code(config):
    var = cg.new_Pvariable(config[CONF_ID])
    await display.register_display(var, config)

    # Ensure display headers compile (display component to_code may not run)
    cg.add_define("USE_DISPLAY")

    # esp_lcd is excluded by default in ESPHome's ESP32 platform to save
    # compile time.  Re-include it so we can use esp_lcd_mipi_dsi.h and
    # the DSI bus / DPI panel APIs.
    from esphome.components.esp32 import include_builtin_idf_component

    include_builtin_idf_component("esp_lcd")
