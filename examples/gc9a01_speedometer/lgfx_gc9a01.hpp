#pragma once

#include <LovyanGFX.hpp>

#ifndef GC9A01_SPI_PORT
#define GC9A01_SPI_PORT 0
#endif

#ifndef GC9A01_PIN_SCLK
#define GC9A01_PIN_SCLK 18
#endif

#ifndef GC9A01_PIN_MOSI
#define GC9A01_PIN_MOSI 19
#endif

#ifndef GC9A01_PIN_CS
#define GC9A01_PIN_CS 17
#endif

#ifndef GC9A01_PIN_DC
#define GC9A01_PIN_DC 20
#endif

#ifndef GC9A01_PIN_RST
#define GC9A01_PIN_RST 21
#endif

#ifndef GC9A01_PIN_BL
#define GC9A01_PIN_BL 22
#endif

#ifndef GC9A01_SPI_FREQUENCY
#define GC9A01_SPI_FREQUENCY 40000000
#endif

class GC9A01Display : public lgfx::LGFX_Device {
 public:
  GC9A01Display() {
    configure_bus();
    configure_panel();
    configure_backlight();
    setPanel(&panel_);
  }

 private:
  lgfx::Panel_GC9A01 panel_;
  lgfx::Bus_SPI bus_;
#if GC9A01_PIN_BL >= 0
  lgfx::Light_PWM backlight_;
#endif

  void configure_bus() {
    auto config = bus_.config();
    config.spi_host = GC9A01_SPI_PORT;
    config.spi_mode = 0;
    config.freq_write = GC9A01_SPI_FREQUENCY;
    config.freq_read = 16000000;
    config.pin_sclk = GC9A01_PIN_SCLK;
    config.pin_mosi = GC9A01_PIN_MOSI;
    config.pin_miso = -1;
    config.pin_dc = GC9A01_PIN_DC;
    bus_.config(config);
    panel_.setBus(&bus_);
  }

  void configure_panel() {
    auto config = panel_.config();
    config.pin_cs = GC9A01_PIN_CS;
    config.pin_rst = GC9A01_PIN_RST;
    config.pin_busy = -1;
    config.panel_width = 240;
    config.panel_height = 240;
    config.memory_width = 240;
    config.memory_height = 240;
    config.offset_x = 0;
    config.offset_y = 0;
    config.offset_rotation = 0;
    config.readable = false;
    config.invert = true;
    config.rgb_order = false;
    config.dlen_16bit = false;
    config.bus_shared = false;
    panel_.config(config);
  }

  void configure_backlight() {
#if GC9A01_PIN_BL >= 0
    auto config = backlight_.config();
    config.pin_bl = GC9A01_PIN_BL;
    config.invert = false;
    config.freq = 12000;
    config.pwm_channel = 0;
    backlight_.config(config);
    panel_.setLight(&backlight_);
#endif
  }
};
