#ifdef USE_ESP32_VARIANT_ESP32P4

#include "waveshare_dsi.h"
#include "esphome/core/log.h"
#include "esphome/core/hal.h"

// ESP-IDF LCD APIs
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_mipi_dsi.h"

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "esp_heap_caps.h"

namespace esphome {
namespace waveshare_dsi {

static const char *const TAG = "waveshare_dsi";

static bool IRAM_ATTR on_color_trans_done(esp_lcd_panel_handle_t panel,
                                           esp_lcd_dpi_panel_event_data_t *edata,
                                           void *user_ctx) {
  auto *sem = static_cast<SemaphoreHandle_t>(user_ctx);
  BaseType_t need_yield = pdFALSE;
  xSemaphoreGiveFromISR(sem, &need_yield);
  return (need_yield == pdTRUE);
}

void WaveshareDSI::setup() {
  esp_err_t err;

  ESP_LOGI(TAG, "===== Waveshare 8.8\" DSI Display Init =====");
  ESP_LOGI(TAG, "MCU init should have been done by on_boot priority 600");

  // ---- Step 1: Create DSI bus ----
  ESP_LOGI(TAG, "Step 1: Creating DSI bus (2 lanes, 1300 Mbps)");
  esp_lcd_dsi_bus_handle_t bus_handle = nullptr;
  esp_lcd_dsi_bus_config_t bus_cfg = {};
  bus_cfg.bus_id = 0;
  bus_cfg.num_data_lanes = 2;
  bus_cfg.phy_clk_src = MIPI_DSI_PHY_CLK_SRC_DEFAULT;
  bus_cfg.lane_bit_rate_mbps = 1300;

  err = esp_lcd_new_dsi_bus(&bus_cfg, &bus_handle);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_lcd_new_dsi_bus FAILED: %s", esp_err_to_name(err));
    this->mark_failed();
    return;
  }
  ESP_LOGI(TAG, "  DSI bus created OK");

  // ---- Step 2: Create DBI IO for DCS commands (LP mode) ----
  ESP_LOGI(TAG, "Step 2: Creating DBI IO (virtual channel 0)");
  esp_lcd_panel_io_handle_t io_handle = nullptr;
  esp_lcd_dbi_io_config_t dbi_cfg = {};
  dbi_cfg.virtual_channel = 0;
  dbi_cfg.lcd_cmd_bits = 8;
  dbi_cfg.lcd_param_bits = 8;

  err = esp_lcd_new_panel_io_dbi(bus_handle, &dbi_cfg, &io_handle);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_lcd_new_panel_io_dbi FAILED: %s", esp_err_to_name(err));
    this->mark_failed();
    return;
  }
  ESP_LOGI(TAG, "  DBI IO created OK");

  // ---- Step 3: Create DPI panel (does NOT start video yet) ----
  ESP_LOGI(TAG, "Step 3: Creating DPI panel (480x1920, RGB565, 75MHz pclk)");
  esp_lcd_dpi_panel_config_t dpi_cfg = {};
  dpi_cfg.virtual_channel = 0;
  dpi_cfg.dpi_clk_src = MIPI_DSI_DPI_CLK_SRC_DEFAULT;
  dpi_cfg.dpi_clock_freq_mhz = 75;
  dpi_cfg.pixel_format = LCD_COLOR_PIXEL_FORMAT_RGB565;
  dpi_cfg.num_fbs = 1;
  dpi_cfg.video_timing.h_size = 480;
  dpi_cfg.video_timing.v_size = 1920;
  dpi_cfg.video_timing.hsync_pulse_width = 50;
  dpi_cfg.video_timing.hsync_back_porch = 50;
  dpi_cfg.video_timing.hsync_front_porch = 50;
  dpi_cfg.video_timing.vsync_pulse_width = 20;
  dpi_cfg.video_timing.vsync_back_porch = 20;
  dpi_cfg.video_timing.vsync_front_porch = 20;
  dpi_cfg.flags.use_dma2d = true;

  err = esp_lcd_new_panel_dpi(bus_handle, &dpi_cfg, reinterpret_cast<esp_lcd_panel_handle_t *>(&this->panel_handle_));
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_lcd_new_panel_dpi FAILED: %s", esp_err_to_name(err));
    this->mark_failed();
    return;
  }
  ESP_LOGI(TAG, "  DPI panel created OK");

  // ---- Step 4: Send DCS commands via DBI IO (LP mode, before video starts) ----
  // NO SW_RESET! The HW reset via GPIO27 was already done in on_boot.
  // Sending DCS SW_RESET would reset the OTA7290B bridge and undo I2C config.
  // BSP sends SLPOUT/DISPON with 1-byte param {0x00} (DCS Short Write With Parameter).
  ESP_LOGI(TAG, "Step 4: Sending DCS commands (LP mode, before DPI video)");

  const uint8_t zero_param = 0x00;

  ESP_LOGI(TAG, "  Sending SLPOUT (0x11)");
  err = esp_lcd_panel_io_tx_param(io_handle, 0x11, &zero_param, 1);
  if (err != ESP_OK) {
    ESP_LOGW(TAG, "  SLPOUT failed: %s", esp_err_to_name(err));
  }
  delay(120);  // Wait 120ms after Sleep Out per MIPI DCS spec

  ESP_LOGI(TAG, "  Sending DISPON (0x29)");
  err = esp_lcd_panel_io_tx_param(io_handle, 0x29, &zero_param, 1);
  if (err != ESP_OK) {
    ESP_LOGW(TAG, "  DISPON failed: %s", esp_err_to_name(err));
  }
  delay(20);

  // ---- Step 5: Init panel → starts DPI video (HS mode) ----
  ESP_LOGI(TAG, "Step 5: Starting DPI video (esp_lcd_panel_init)");
  auto panel_h = static_cast<esp_lcd_panel_handle_t>(this->panel_handle_);
  err = esp_lcd_panel_init(panel_h);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_lcd_panel_init FAILED: %s", esp_err_to_name(err));
    this->mark_failed();
    return;
  }
  ESP_LOGI(TAG, "  DPI video started OK");

  // ---- Step 6: Set up DMA completion semaphore ----
  this->dma_sem_ = xSemaphoreCreateBinary();
  esp_lcd_dpi_panel_event_callbacks_t cbs = {};
  cbs.on_color_trans_done = on_color_trans_done;
  err = esp_lcd_dpi_panel_register_event_callbacks(panel_h, &cbs, this->dma_sem_);
  if (err != ESP_OK) {
    ESP_LOGW(TAG, "register_event_callbacks failed: %s", esp_err_to_name(err));
  }

  // ---- Step 7: Clear screen to black before LVGL takes over ----
  ESP_LOGI(TAG, "Step 7: Clearing screen to black");
  this->fill(Color::BLACK);

  this->init_ok_ = true;
  ESP_LOGI(TAG, "===== Waveshare DSI Display Init COMPLETE =====");
}

void WaveshareDSI::update() { this->do_update_(); }

void WaveshareDSI::draw_pixels_at(int x_start, int y_start, int w, int h, const uint8_t *ptr,
                                   display::ColorOrder order, display::ColorBitness bitness,
                                   bool big_endian, int x_offset, int y_offset, int x_pad) {
  if (this->panel_handle_ == nullptr)
    return;

  if (x_offset == 0 && x_pad == 0) {
    // Fast path: tightly packed pixel data — direct DMA2D transfer (LVGL path)
    auto panel_h = static_cast<esp_lcd_panel_handle_t>(this->panel_handle_);
    esp_lcd_panel_draw_bitmap(panel_h, x_start, y_start, x_start + w, y_start + h, ptr);
    if (this->dma_sem_) {
      xSemaphoreTake(static_cast<SemaphoreHandle_t>(this->dma_sem_), pdMS_TO_TICKS(1000));
    }
  } else {
    // Padded data — fall back to base class pixel-by-pixel
    Display::draw_pixels_at(x_start, y_start, w, h, ptr, order, bitness, big_endian, x_offset, y_offset, x_pad);
  }
}

void WaveshareDSI::draw_pixel_at(int x, int y, Color color) {
  if (this->panel_handle_ == nullptr)
    return;
  if (x < 0 || x >= this->get_width() || y < 0 || y >= this->get_height())
    return;

  // Single pixel via DMA2D — functional but inefficient.
  // LVGL always uses draw_pixels_at for bulk operations.
  uint16_t pixel = ((color.red & 0xF8) << 8) | ((color.green & 0xFC) << 3) | (color.blue >> 3);
  auto panel_h = static_cast<esp_lcd_panel_handle_t>(this->panel_handle_);
  esp_lcd_panel_draw_bitmap(panel_h, x, y, x + 1, y + 1, &pixel);
  if (this->dma_sem_) {
    xSemaphoreTake(static_cast<SemaphoreHandle_t>(this->dma_sem_), pdMS_TO_TICKS(100));
  }
}

void WaveshareDSI::fill(Color color) {
  if (this->panel_handle_ == nullptr) {
    ESP_LOGW(TAG, "fill() called but panel not initialized yet");
    return;
  }

  const int w = this->get_width_internal();
  const int h = this->get_height_internal();
  uint16_t pixel_565 = ((color.red & 0xF8) << 8) | ((color.green & 0xFC) << 3) | (color.blue >> 3);

  // Full-frame DMA transfer (same pattern as the working red-screen test)
  const size_t frame_bytes = w * h * sizeof(uint16_t);
  auto *frame = static_cast<uint16_t *>(heap_caps_malloc(frame_bytes, MALLOC_CAP_SPIRAM));
  if (frame == nullptr) {
    ESP_LOGW(TAG, "fill: failed to allocate %u byte frame buffer", (unsigned) frame_bytes);
    return;
  }
  const int total_pixels = w * h;
  for (int i = 0; i < total_pixels; i++) {
    frame[i] = pixel_565;
  }

  auto panel_h = static_cast<esp_lcd_panel_handle_t>(this->panel_handle_);
  auto sem = static_cast<SemaphoreHandle_t>(this->dma_sem_);
  esp_lcd_panel_draw_bitmap(panel_h, 0, 0, w, h, frame);
  if (sem) {
    xSemaphoreTake(sem, pdMS_TO_TICKS(5000));
  }
  heap_caps_free(frame);
  ESP_LOGI(TAG, "fill() complete (color R=%d G=%d B=%d)", color.red, color.green, color.blue);
}

void WaveshareDSI::dump_config() {
  ESP_LOGCONFIG(TAG, "Waveshare 8.8\" DSI Display:");
  ESP_LOGCONFIG(TAG, "  Init: %s", this->init_ok_ ? "OK" : "FAILED");
  ESP_LOGCONFIG(TAG, "  Resolution: %dx%d", this->get_width_internal(), this->get_height_internal());
  ESP_LOGCONFIG(TAG, "  Color Depth: RGB565 (16-bit)");
  ESP_LOGCONFIG(TAG, "  DSI Lanes: 2 @ 1300 Mbps");
  ESP_LOGCONFIG(TAG, "  Pixel Clock: 75 MHz");
}

}  // namespace waveshare_dsi
}  // namespace esphome

#endif  // USE_ESP32_VARIANT_ESP32P4
