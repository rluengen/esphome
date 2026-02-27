#pragma once

#ifdef USE_ESP32_VARIANT_ESP32P4

#include "esphome/components/display/display.h"

namespace esphome {
namespace waveshare_dsi {

/// ESPHome Display driver for Waveshare 8.8" 480×1920 MIPI-DSI display.
/// Uses OTA7290B bridge IC which requires BSP-correct init ordering:
///   DSI bus -> DBI IO -> DPI panel -> DCS SLPOUT/DISPON -> panel_init
class WaveshareDSI : public display::Display {
 public:
  void setup() override;
  void update() override;
  void dump_config() override;
  float get_setup_priority() const override { return 500.0f; }

  display::DisplayType get_display_type() override { return display::DisplayType::DISPLAY_TYPE_COLOR; }

  void draw_pixels_at(int x_start, int y_start, int w, int h, const uint8_t *ptr,
                       display::ColorOrder order, display::ColorBitness bitness,
                       bool big_endian, int x_offset, int y_offset, int x_pad) override;

  void draw_pixel_at(int x, int y, Color color) override;

  void fill(Color color) override;

 protected:
  int get_width_internal() override { return 480; }
  int get_height_internal() override { return 1920; }

  void *panel_handle_{nullptr};  // esp_lcd_panel_handle_t
  void *dma_sem_{nullptr};       // SemaphoreHandle_t
  bool init_ok_{false};
};

}  // namespace waveshare_dsi
}  // namespace esphome

#endif  // USE_ESP32_VARIANT_ESP32P4
