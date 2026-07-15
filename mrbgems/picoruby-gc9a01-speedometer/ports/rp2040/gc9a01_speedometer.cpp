#include <cmath>
#include <cstdint>

#include <LovyanGFX.hpp>
#if defined(PICORB_VM_MRUBY)
#include <mruby.h>
#include <mruby/error.h>
#elif defined(PICORB_VM_MRUBYC)
extern "C" {
#include <mrubyc.h>
}
#endif
#include <pico/stdlib.h>

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

#ifndef GC9A01_SECONDARY_SPI_PORT
#define GC9A01_SECONDARY_SPI_PORT 1
#endif

#ifndef GC9A01_SECONDARY_PIN_SCLK
#define GC9A01_SECONDARY_PIN_SCLK 10
#endif

#ifndef GC9A01_SECONDARY_PIN_MOSI
#define GC9A01_SECONDARY_PIN_MOSI 11
#endif

#ifndef GC9A01_SECONDARY_PIN_CS
#define GC9A01_SECONDARY_PIN_CS 9
#endif

#ifndef GC9A01_SECONDARY_PIN_DC
#define GC9A01_SECONDARY_PIN_DC 12
#endif

#ifndef GC9A01_SECONDARY_PIN_RST
#define GC9A01_SECONDARY_PIN_RST 13
#endif

#ifndef GC9A01_SECONDARY_PIN_BL
#define GC9A01_SECONDARY_PIN_BL 14
#endif

#ifndef GC9A01_SECONDARY_SPI_FREQUENCY
#define GC9A01_SECONDARY_SPI_FREQUENCY 40000000
#endif

namespace {

constexpr int kWidth = 240;
constexpr int kHeight = 240;
constexpr int kCenterX = 120;
constexpr int kCenterY = 120;
constexpr float kPi = 3.14159265358979323846f;
constexpr float kStartAngle = -150.0f;
constexpr float kSweepAngle = 240.0f;
constexpr float kMaxRpm = 180.0f;
constexpr float kMaxDisplayedSpeed = 999.0f;
constexpr float kSimpleStartAngle = 150.0f;
constexpr float kSimpleSweepAngle = 240.0f;
constexpr float kSimpleMaxSpeed = 80.0f;
constexpr int kDisplayCount = 2;

constexpr uint32_t kBackground = 0x050607;
constexpr uint32_t kDialInner = 0x010202;
constexpr uint32_t kRingDark = 0x1d2022;
constexpr uint32_t kRingLight = 0xf1f2f2;
constexpr uint32_t kTick = 0xf1f2f2;
constexpr uint32_t kTickDim = 0x9ba0a3;
constexpr uint32_t kAccent = 0xd71920;
constexpr uint32_t kNeedleShadow = 0x5a1012;
constexpr uint32_t kText = 0x111315;
constexpr uint32_t kIndicatorDisconnected = 0xd71920;
constexpr uint32_t kIndicatorConnected = 0x18c76f;
constexpr uint32_t kSimpleBlack = 0x000000;
constexpr uint32_t kSimpleWhite = 0xffffff;
constexpr uint32_t kSimpleRed = 0xff0000;

struct DisplayConfig {
  int spi_host;
  int pin_sclk;
  int pin_mosi;
  int pin_cs;
  int pin_dc;
  int pin_rst;
  int pin_bl;
  uint32_t frequency;
};

DisplayConfig display_configs[kDisplayCount] = {
    {
        GC9A01_SPI_PORT,       GC9A01_PIN_SCLK, GC9A01_PIN_MOSI,
        GC9A01_PIN_CS,         GC9A01_PIN_DC,   GC9A01_PIN_RST,
        GC9A01_PIN_BL,         GC9A01_SPI_FREQUENCY,
    },
    {
        GC9A01_SECONDARY_SPI_PORT,
        GC9A01_SECONDARY_PIN_SCLK,
        GC9A01_SECONDARY_PIN_MOSI,
        GC9A01_SECONDARY_PIN_CS,
        GC9A01_SECONDARY_PIN_DC,
        GC9A01_SECONDARY_PIN_RST,
        GC9A01_SECONDARY_PIN_BL,
        GC9A01_SECONDARY_SPI_FREQUENCY,
    },
};

class GC9A01Display : public lgfx::LGFX_Device {
 public:
  void configure(const DisplayConfig& config) {
    auto bus_config = bus_.config();
    bus_config.spi_host = config.spi_host;
    bus_config.spi_mode = 0;
    bus_config.freq_write = config.frequency;
    bus_config.freq_read = 16000000;
    bus_config.pin_sclk = config.pin_sclk;
    bus_config.pin_mosi = config.pin_mosi;
    bus_config.pin_miso = -1;
    bus_config.pin_dc = config.pin_dc;
    bus_.config(bus_config);
    panel_.setBus(&bus_);

    auto panel_config = panel_.config();
    panel_config.pin_cs = config.pin_cs;
    panel_config.pin_rst = config.pin_rst;
    panel_config.pin_busy = -1;
    panel_config.panel_width = kWidth;
    panel_config.panel_height = kHeight;
    panel_config.memory_width = kWidth;
    panel_config.memory_height = kHeight;
    panel_config.offset_x = 0;
    panel_config.offset_y = 0;
    panel_config.offset_rotation = 0;
    panel_config.readable = false;
    panel_config.invert = true;
    panel_config.rgb_order = false;
    panel_config.dlen_16bit = false;
    panel_config.bus_shared = true;
    panel_.config(panel_config);

    if (config.pin_bl >= 0) {
      auto light_config = light_.config();
      light_config.pin_bl = config.pin_bl;
      light_config.invert = false;
      light_config.freq = 12000;
      light_config.pwm_channel = config.pin_bl & 1;
      light_.config(light_config);
      panel_.setLight(&light_);
    }

    setPanel(&panel_);
  }

 private:
  lgfx::Panel_GC9A01 panel_;
  lgfx::Bus_SPI bus_;
  lgfx::Light_PWM light_;
};

enum MeterMode {
  kNoMeter,
  kTachometer,
  kSimpleSpeedometer,
};

struct DisplayState {
  bool initialized;
  bool initialization_failed;
  bool connection_indicators_drawn;
  bool previous_speed_connected;
  bool previous_cadence_connected;
  uint32_t animation_started_ms;
  float previous_rpm;
  float previous_simple_speed;
  MeterMode active_meter;
};

GC9A01Display displays[kDisplayCount];
DisplayState display_states[kDisplayCount] = {};

bool valid_display_index(int display_index) {
  return 0 <= display_index && display_index < kDisplayCount;
}

float to_radians(float degrees) {
  return degrees * kPi / 180.0f;
}

float rpm_to_angle(float rpm) {
  return kStartAngle + (rpm / kMaxRpm) * kSweepAngle;
}

float simple_speed_to_angle(float speed) {
  return kSimpleStartAngle + (speed / kSimpleMaxSpeed) * kSimpleSweepAngle;
}

void polar_point(float angle_degrees, float radius, int* x, int* y) {
  const float radians = to_radians(angle_degrees - 90.0f);
  *x = static_cast<int>(std::lround(kCenterX + std::cos(radians) * radius));
  *y = static_cast<int>(std::lround(kCenterY + std::sin(radians) * radius));
}

void fill_scale_band(GC9A01Display& display, int first_rpm, int last_rpm,
                     uint32_t color,
                     float inner_radius = 72.0f,
                     float outer_radius = 104.0f) {
  for (int rpm = first_rpm; rpm < last_rpm; rpm += 2) {
    int inner_x0;
    int inner_y0;
    int outer_x0;
    int outer_y0;
    int inner_x1;
    int inner_y1;
    int outer_x1;
    int outer_y1;
    const float angle0 = rpm_to_angle(static_cast<float>(rpm));
    const float angle1 = rpm_to_angle(static_cast<float>(rpm + 2));
    polar_point(angle0, inner_radius, &inner_x0, &inner_y0);
    polar_point(angle0, outer_radius, &outer_x0, &outer_y0);
    polar_point(angle1, inner_radius, &inner_x1, &inner_y1);
    polar_point(angle1, outer_radius, &outer_x1, &outer_y1);
    display.fillTriangle(inner_x0, inner_y0, outer_x0, outer_y0,
                         outer_x1, outer_y1, color);
    display.fillTriangle(inner_x0, inner_y0, outer_x1, outer_y1,
                         inner_x1, inner_y1, color);
  }
}

void draw_rings(GC9A01Display& display) {
  display.fillScreen(kBackground);
  display.fillCircle(kCenterX, kCenterY, 112, kRingDark);
  display.fillCircle(kCenterX, kCenterY, 107, kBackground);
  display.fillCircle(kCenterX, kCenterY, 105, kDialInner);
  display.drawCircle(kCenterX, kCenterY, 106, 0x34383a);
  fill_scale_band(display, 0, 180, kRingLight);
  display.fillCircle(kCenterX, kCenterY, 70, kDialInner);
  display.drawCircle(kCenterX, kCenterY, 71, 0x292c2e);
}

void draw_redline_arc(GC9A01Display& display) {
  for (int rpm = 140; rpm < 180; rpm += 10) {
    fill_scale_band(display, rpm, rpm + 8, kAccent, 88.0f, 104.0f);
  }
}

void draw_ticks(GC9A01Display& display) {
  for (int rpm = 0; rpm <= 180; rpm += 5) {
    const bool major = (rpm % 30) == 0;
    const float angle = rpm_to_angle(static_cast<float>(rpm));
    const float inner_radius = major ? 82.0f : 90.0f;
    const uint32_t color = rpm >= 140 ? 0x6f1114 : (major ? kTick : kTickDim);
    int x0;
    int y0;
    int x1;
    int y1;
    polar_point(angle, inner_radius, &x0, &y0);
    polar_point(angle, 98.0f, &x1, &y1);
    display.drawLine(x0, y0, x1, y1, color);
    if (major) {
      int x2;
      int y2;
      polar_point(angle + 1.0f, inner_radius, &x2, &y2);
      display.drawLine(x2, y2, x1, y1, color);
    }
  }
}

void draw_labels(GC9A01Display& display) {
  display.setFont(&fonts::Font0);
  display.setTextDatum(middle_center);
  display.setTextColor(kText, kDialInner);
  char label[4];
  for (int rpm = 0; rpm <= 180; rpm += 30) {
    int x;
    int y;
    const float radius = 84.0f;
    polar_point(rpm_to_angle(static_cast<float>(rpm)), radius, &x, &y);
    std::snprintf(label, sizeof(label), "%d", rpm);
    display.setTextColor(kText, kRingLight);
    display.drawString(label, x, y);
  }

  display.setTextColor(0xaeb3b6, kDialInner);
  display.drawCenterString("rpm", kCenterX, 93, &fonts::Font0);
}

void draw_speed_value(GC9A01Display& display, float speed) {
  char value[4];
  std::snprintf(value, sizeof(value), "%03d", static_cast<int>(speed + 0.5f));
  display.fillRect(158, 136, 68, 48, kDialInner);
  display.setTextColor(0xff3b34, kDialInner);
  display.setTextDatum(middle_center);
  display.drawString(value, 192, 153, &fonts::Font4);
  display.setTextColor(0xd72a27, kDialInner);
  display.drawString("km/h", 192, 176, &fonts::Font0);
}

void draw_stopwatch_indicator(GC9A01Display& display, int center_x,
                              int center_y, uint32_t color) {
  display.drawCircle(center_x, center_y, 6, color);
  display.drawCircle(center_x, center_y, 5, color);
  display.drawLine(center_x - 2, center_y - 8,
                   center_x + 2, center_y - 8, color);
  display.drawLine(center_x, center_y - 8,
                   center_x, center_y - 6, color);
  display.drawLine(center_x + 5, center_y - 6,
                   center_x + 7, center_y - 4, color);
  display.drawLine(center_x, center_y,
                   center_x, center_y - 4, color);
  display.drawLine(center_x, center_y,
                   center_x + 3, center_y + 2, color);
  display.fillCircle(center_x, center_y, 1, color);
}

void draw_crank_indicator(GC9A01Display& display, int center_x,
                          int center_y, uint32_t color) {
  const int left_x = center_x - 5;
  const int left_y = center_y + 4;
  const int right_x = center_x + 5;
  const int right_y = center_y - 4;
  display.drawLine(left_x, left_y, right_x, right_y, color);
  display.drawCircle(left_x, left_y, 3, color);
  display.drawCircle(right_x, right_y, 3, color);
  display.fillCircle(left_x, left_y, 1, color);
  display.fillCircle(right_x, right_y, 1, color);
  display.drawLine(left_x - 3, left_y + 2,
                   left_x - 7, left_y + 2, color);
  display.drawLine(right_x + 3, right_y - 2,
                   right_x + 7, right_y - 2, color);
}

void draw_connection_indicators(GC9A01Display& display,
                                bool speed_connected,
                                bool cadence_connected) {
  constexpr int kIndicatorTop = 187;
  display.fillRect(97, kIndicatorTop, 47, 21, kDialInner);
  draw_stopwatch_indicator(
      display, 106, 198,
      speed_connected ? kIndicatorConnected : kIndicatorDisconnected);
  draw_crank_indicator(
      display, 130, 198,
      cadence_connected ? kIndicatorConnected : kIndicatorDisconnected);
}

void update_connection_indicators(GC9A01Display& display,
                                  DisplayState& state,
                                  bool speed_connected,
                                  bool cadence_connected) {
  if (state.connection_indicators_drawn &&
      state.previous_speed_connected == speed_connected &&
      state.previous_cadence_connected == cadence_connected) {
    return;
  }
  draw_connection_indicators(display, speed_connected, cadence_connected);
  state.connection_indicators_drawn = true;
  state.previous_speed_connected = speed_connected;
  state.previous_cadence_connected = cadence_connected;
}

void draw_needle(GC9A01Display& display, float rpm) {
  const float angle = rpm_to_angle(rpm);
  int tip_x;
  int tip_y;
  int left_x;
  int left_y;
  int right_x;
  int right_y;
  int tail_x;
  int tail_y;
  polar_point(angle, 88.0f, &tip_x, &tip_y);
  polar_point(angle - 90.0f, 5.0f, &left_x, &left_y);
  polar_point(angle + 90.0f, 5.0f, &right_x, &right_y);
  polar_point(angle + 180.0f, 18.0f, &tail_x, &tail_y);

  display.fillTriangle(left_x + 2, left_y + 2, tip_x + 2, tip_y + 2,
                       right_x + 2, right_y + 2, kNeedleShadow);
  display.fillTriangle(left_x, left_y, tip_x, tip_y, right_x, right_y, kAccent);
  display.drawLine(kCenterX, kCenterY, tail_x, tail_y, kAccent);
  display.fillCircle(kCenterX, kCenterY, 10, 0x111315);
  display.fillCircle(kCenterX, kCenterY, 7, kAccent);
  display.fillCircle(kCenterX - 2, kCenterY - 2, 2, 0xffa09b);
}

void draw_static_dial(GC9A01Display& display) {
  draw_rings(display);
  draw_redline_arc(display);
  draw_ticks(display);
  draw_labels(display);
}

void erase_needle(GC9A01Display& display, float rpm) {
  int tip_x;
  int tip_y;
  int left_x;
  int left_y;
  int right_x;
  int right_y;
  int tail_x;
  int tail_y;
  const float angle = rpm_to_angle(rpm);
  polar_point(angle, 88.0f, &tip_x, &tip_y);
  polar_point(angle - 90.0f, 5.0f, &left_x, &left_y);
  polar_point(angle + 90.0f, 5.0f, &right_x, &right_y);
  polar_point(angle + 180.0f, 18.0f, &tail_x, &tail_y);

  display.fillTriangle(left_x + 2, left_y + 2, tip_x + 2, tip_y + 2,
                       right_x + 2, right_y + 2, kDialInner);
  display.fillTriangle(left_x, left_y, tip_x, tip_y, right_x, right_y,
                       kDialInner);
  display.drawLine(kCenterX, kCenterY, tail_x, tail_y, kDialInner);
  display.fillCircle(kCenterX, kCenterY, 11, kDialInner);
}

void restore_needle_background(GC9A01Display& display, float rpm) {
  int tip_x;
  int tip_y;
  int tail_x;
  int tail_y;
  const float angle = rpm_to_angle(rpm);
  polar_point(angle, 90.0f, &tip_x, &tip_y);
  polar_point(angle + 180.0f, 20.0f, &tail_x, &tail_y);

  constexpr int kMargin = 12;
  int left = tip_x < tail_x ? tip_x : tail_x;
  int top = tip_y < tail_y ? tip_y : tail_y;
  int right = tip_x > tail_x ? tip_x : tail_x;
  int bottom = tip_y > tail_y ? tip_y : tail_y;
  left = (left < kCenterX ? left : kCenterX) - kMargin;
  top = (top < kCenterY ? top : kCenterY) - kMargin;
  right = (right > kCenterX ? right : kCenterX) + kMargin;
  bottom = (bottom > kCenterY ? bottom : kCenterY) + kMargin;
  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (right >= kWidth) right = kWidth - 1;
  if (bottom >= kHeight) bottom = kHeight - 1;

  display.setClipRect(left, top, right - left + 1, bottom - top + 1);
  erase_needle(display, rpm);
  fill_scale_band(display, 0, 180, kRingLight);
  draw_redline_arc(display);
  draw_ticks(display);
  draw_labels(display);
  display.clearClipRect();
}

void draw_simple_scale_arc(GC9A01Display& display) {
  for (int speed = 0; speed < 80; ++speed) {
    int x0;
    int y0;
    int x1;
    int y1;
    polar_point(simple_speed_to_angle(static_cast<float>(speed)),
                102.0f, &x0, &y0);
    polar_point(simple_speed_to_angle(static_cast<float>(speed + 1)),
                102.0f, &x1, &y1);
    display.drawLine(x0, y0, x1, y1, kSimpleWhite);
    polar_point(simple_speed_to_angle(static_cast<float>(speed)),
                101.0f, &x0, &y0);
    polar_point(simple_speed_to_angle(static_cast<float>(speed + 1)),
                101.0f, &x1, &y1);
    display.drawLine(x0, y0, x1, y1, kSimpleWhite);
  }
}

void draw_simple_ticks(GC9A01Display& display) {
  for (int speed = 0; speed <= 80; speed += 2) {
    const bool major = (speed % 10) == 0;
    const float angle = simple_speed_to_angle(static_cast<float>(speed));
    int x0;
    int y0;
    int x1;
    int y1;
    polar_point(angle, major ? 82.0f : 91.0f, &x0, &y0);
    polar_point(angle, 99.0f, &x1, &y1);
    display.drawLine(x0, y0, x1, y1, kSimpleWhite);
    if (major) {
      int x2;
      int y2;
      polar_point(angle + 0.8f, 82.0f, &x2, &y2);
      display.drawLine(x2, y2, x1, y1, kSimpleWhite);
    }
  }
}

void draw_simple_labels(GC9A01Display& display) {
  display.setFont(&fonts::Font0);
  display.setTextDatum(middle_center);
  display.setTextColor(kSimpleWhite, kSimpleBlack);
  char label[3];
  for (int speed = 0; speed <= 80; speed += 10) {
    int x;
    int y;
    polar_point(simple_speed_to_angle(static_cast<float>(speed)),
                72.0f, &x, &y);
    std::snprintf(label, sizeof(label), "%d", speed);
    display.drawString(label, x, y);
  }
  display.drawCenterString("km/h", kCenterX, 96, &fonts::Font0);
}

void draw_simple_static_dial(GC9A01Display& display) {
  display.fillScreen(kSimpleBlack);
  draw_simple_scale_arc(display);
  draw_simple_ticks(display);
  draw_simple_labels(display);
}

void draw_simple_needle(GC9A01Display& display, float speed) {
  const float angle = simple_speed_to_angle(speed);
  int tip_x;
  int tip_y;
  int left_x;
  int left_y;
  int right_x;
  int right_y;
  int tail_x;
  int tail_y;
  polar_point(angle, 88.0f, &tip_x, &tip_y);
  polar_point(angle - 90.0f, 4.0f, &left_x, &left_y);
  polar_point(angle + 90.0f, 4.0f, &right_x, &right_y);
  polar_point(angle + 180.0f, 15.0f, &tail_x, &tail_y);
  display.fillTriangle(left_x, left_y, tip_x, tip_y, right_x, right_y,
                       kSimpleRed);
  display.drawLine(kCenterX, kCenterY, tail_x, tail_y, kSimpleRed);
  display.fillCircle(kCenterX, kCenterY, 7, kSimpleRed);
}

void erase_simple_needle(GC9A01Display& display, float speed) {
  const float angle = simple_speed_to_angle(speed);
  int tip_x;
  int tip_y;
  int left_x;
  int left_y;
  int right_x;
  int right_y;
  int tail_x;
  int tail_y;
  polar_point(angle, 88.0f, &tip_x, &tip_y);
  polar_point(angle - 90.0f, 4.0f, &left_x, &left_y);
  polar_point(angle + 90.0f, 4.0f, &right_x, &right_y);
  polar_point(angle + 180.0f, 15.0f, &tail_x, &tail_y);
  display.fillTriangle(left_x, left_y, tip_x, tip_y, right_x, right_y,
                       kSimpleBlack);
  display.drawLine(kCenterX, kCenterY, tail_x, tail_y, kSimpleBlack);
  display.fillCircle(kCenterX, kCenterY, 8, kSimpleBlack);
}

void restore_simple_needle_background(GC9A01Display& display, float speed) {
  int tip_x;
  int tip_y;
  int tail_x;
  int tail_y;
  const float angle = simple_speed_to_angle(speed);
  polar_point(angle, 90.0f, &tip_x, &tip_y);
  polar_point(angle + 180.0f, 17.0f, &tail_x, &tail_y);

  constexpr int kMargin = 10;
  int left = tip_x < tail_x ? tip_x : tail_x;
  int top = tip_y < tail_y ? tip_y : tail_y;
  int right = tip_x > tail_x ? tip_x : tail_x;
  int bottom = tip_y > tail_y ? tip_y : tail_y;
  left = (left < kCenterX ? left : kCenterX) - kMargin;
  top = (top < kCenterY ? top : kCenterY) - kMargin;
  right = (right > kCenterX ? right : kCenterX) + kMargin;
  bottom = (bottom > kCenterY ? bottom : kCenterY) + kMargin;
  if (left < 0) left = 0;
  if (top < 0) top = 0;
  if (right >= kWidth) right = kWidth - 1;
  if (bottom >= kHeight) bottom = kHeight - 1;

  display.setClipRect(left, top, right - left + 1, bottom - top + 1);
  erase_simple_needle(display, speed);
  draw_simple_scale_arc(display);
  draw_simple_ticks(display);
  draw_simple_labels(display);
  display.clearClipRect();
}

enum ConfigResult {
  kConfigOk,
  kConfigLocked,
  kConfigInvalidDisplay,
  kConfigInvalidHost,
  kConfigInvalidPin,
  kConfigInvalidFrequency,
};

ConfigResult set_display_config(int display_index, int spi_host, int pin_sclk,
                                int pin_mosi, int pin_cs, int pin_dc,
                                int pin_rst, int pin_bl, int frequency) {
  if (!valid_display_index(display_index)) {
    return kConfigInvalidDisplay;
  }
  DisplayState& state = display_states[display_index];
  if (state.initialized) {
    return kConfigLocked;
  }
  if (spi_host < 0 || spi_host > 1) {
    return kConfigInvalidHost;
  }
  if (pin_sclk < 0 || pin_mosi < 0 || pin_dc < 0 || pin_cs < -1 ||
      pin_rst < -1 || pin_bl < -1) {
    return kConfigInvalidPin;
  }
  if (frequency < 1000000 || frequency > 100000000) {
    return kConfigInvalidFrequency;
  }
  DisplayConfig& config = display_configs[display_index];
  config.spi_host = spi_host;
  config.pin_sclk = pin_sclk;
  config.pin_mosi = pin_mosi;
  config.pin_cs = pin_cs;
  config.pin_dc = pin_dc;
  config.pin_rst = pin_rst;
  config.pin_bl = pin_bl;
  config.frequency = static_cast<uint32_t>(frequency);
  return kConfigOk;
}

bool begin_display(int display_index) {
  if (!valid_display_index(display_index)) {
    return false;
  }
  DisplayState& state = display_states[display_index];
  DisplayConfig& config = display_configs[display_index];
  GC9A01Display& display = displays[display_index];
  if (state.initialized) {
    return true;
  }
  if (state.initialization_failed) {
    return false;
  }
  display.configure(config);
  if (!display.init()) {
    state.initialization_failed = true;
    return false;
  }
  display.setRotation(0);
  display.setColorDepth(16);
  if (config.pin_bl >= 0) {
    display.setBrightness(220);
  }
  state.animation_started_ms = to_ms_since_boot(get_absolute_time());
  state.initialized = true;
  return true;
}

float render_values(int display_index, float speed_kmh, float rpm,
                    bool speed_connected = false,
                    bool cadence_connected = false) {
  if (!begin_display(display_index)) {
    return -1.0f;
  }
  DisplayState& state = display_states[display_index];
  GC9A01Display& display = displays[display_index];
  if (speed_kmh < 0.0f) {
    speed_kmh = 0.0f;
  } else if (speed_kmh > kMaxDisplayedSpeed) {
    speed_kmh = kMaxDisplayedSpeed;
  }
  if (rpm < 0.0f) {
    rpm = 0.0f;
  } else if (rpm > kMaxRpm) {
    rpm = kMaxRpm;
  }
  display.startWrite();
  if (state.active_meter == kTachometer) {
    restore_needle_background(display, state.previous_rpm);
  } else {
    draw_static_dial(display);
    state.active_meter = kTachometer;
    state.connection_indicators_drawn = false;
  }
  draw_speed_value(display, speed_kmh);
  draw_needle(display, rpm);
  update_connection_indicators(
      display, state, speed_connected, cadence_connected);
  display.endWrite();
  state.previous_rpm = rpm;
  return speed_kmh;
}

float render_simple_speed(int display_index, float speed_kmh) {
  if (!begin_display(display_index)) {
    return -1.0f;
  }
  DisplayState& state = display_states[display_index];
  GC9A01Display& display = displays[display_index];
  if (speed_kmh < 0.0f) {
    speed_kmh = 0.0f;
  } else if (speed_kmh > kSimpleMaxSpeed) {
    speed_kmh = kSimpleMaxSpeed;
  }
  display.startWrite();
  if (state.active_meter == kSimpleSpeedometer) {
    restore_simple_needle_background(display, state.previous_simple_speed);
  } else {
    draw_simple_static_dial(display);
    state.active_meter = kSimpleSpeedometer;
  }
  draw_simple_needle(display, speed_kmh);
  display.endWrite();
  state.previous_simple_speed = speed_kmh;
  return speed_kmh;
}

void demo_values(int display_index, float* speed_kmh, float* rpm) {
  constexpr uint32_t kCycleMs = 9000;
  const DisplayState& state = display_states[display_index];
  const uint32_t now = to_ms_since_boot(get_absolute_time());
  const float phase = static_cast<float>(
                          (now - state.animation_started_ms) % kCycleMs) /
                      static_cast<float>(kCycleMs);
  const float sweep = 0.5f * (1.0f - std::cos(phase * 2.0f * kPi));
  *speed_kmh = sweep * 60.0f;
  *rpm = sweep * kMaxRpm;
}

float simple_demo_speed(int display_index) {
  constexpr uint32_t kCycleMs = 7000;
  const DisplayState& state = display_states[display_index];
  const uint32_t now = to_ms_since_boot(get_absolute_time());
  const float phase = static_cast<float>(
                          (now - state.animation_started_ms) % kCycleMs) /
                      static_cast<float>(kCycleMs);
  return 0.5f * (1.0f - std::cos(phase * 2.0f * kPi)) * kSimpleMaxSpeed;
}

#if defined(PICORB_VM_MRUBY)

mrb_value mrb_display_configure(mrb_state* mrb, mrb_value self) {
  (void)self;
  mrb_int display_index;
  mrb_int spi_host;
  mrb_int pin_sclk;
  mrb_int pin_mosi;
  mrb_int pin_cs;
  mrb_int pin_dc;
  mrb_int pin_rst;
  mrb_int pin_bl;
  mrb_int frequency;
  mrb_get_args(mrb, "iiiiiiiii", &display_index, &spi_host, &pin_sclk,
               &pin_mosi, &pin_cs, &pin_dc, &pin_rst, &pin_bl, &frequency);
  const ConfigResult result = set_display_config(
      static_cast<int>(display_index), static_cast<int>(spi_host),
      static_cast<int>(pin_sclk), static_cast<int>(pin_mosi),
      static_cast<int>(pin_cs), static_cast<int>(pin_dc),
      static_cast<int>(pin_rst), static_cast<int>(pin_bl),
      static_cast<int>(frequency));
  if (result == kConfigLocked) {
    mrb_raise(mrb, E_RUNTIME_ERROR, "display is already initialized");
  } else if (result == kConfigInvalidDisplay) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  } else if (result == kConfigInvalidHost) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "spi_host must be 0 or 1");
  } else if (result == kConfigInvalidPin) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "invalid GPIO pin");
  } else if (result == kConfigInvalidFrequency) {
    mrb_raise(mrb, E_ARGUMENT_ERROR,
              "frequency must be between 1000000 and 100000000");
  }
  return mrb_true_value();
}

mrb_value mrb_speedometer_init(mrb_state* mrb, mrb_value self) {
  mrb_int display_index;
  mrb_get_args(mrb, "i", &display_index);
  if (!valid_display_index(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  }
  if (!begin_display(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_RUNTIME_ERROR, "GC9A01 display initialization failed");
  }
  return self;
}

mrb_value mrb_speedometer_render(mrb_state* mrb, mrb_value self) {
  (void)self;
  mrb_int display_index;
  mrb_float speed;
  mrb_float rpm;
  mrb_bool speed_connected;
  mrb_bool cadence_connected;
  mrb_get_args(mrb, "iffbb", &display_index, &speed, &rpm,
               &speed_connected, &cadence_connected);
  if (!valid_display_index(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  }
  return mrb_float_value(mrb, render_values(
      static_cast<int>(display_index), static_cast<float>(speed),
      static_cast<float>(rpm), speed_connected, cadence_connected));
}

mrb_value mrb_speedometer_demo_step(mrb_state* mrb, mrb_value self) {
  (void)self;
  mrb_int display_index;
  mrb_get_args(mrb, "i", &display_index);
  if (!valid_display_index(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  }
  float speed_kmh;
  float rpm;
  demo_values(static_cast<int>(display_index), &speed_kmh, &rpm);
  return mrb_float_value(
      mrb, render_values(static_cast<int>(display_index), speed_kmh, rpm));
}

mrb_value mrb_simple_speedometer_render(mrb_state* mrb, mrb_value self) {
  (void)self;
  mrb_int display_index;
  mrb_float speed;
  mrb_get_args(mrb, "if", &display_index, &speed);
  if (!valid_display_index(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  }
  return mrb_float_value(mrb, render_simple_speed(
      static_cast<int>(display_index), static_cast<float>(speed)));
}

mrb_value mrb_simple_speedometer_demo_step(mrb_state* mrb, mrb_value self) {
  (void)self;
  mrb_int display_index;
  mrb_get_args(mrb, "i", &display_index);
  if (!valid_display_index(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  }
  return mrb_float_value(mrb, render_simple_speed(
      static_cast<int>(display_index),
      simple_demo_speed(static_cast<int>(display_index))));
}

mrb_value mrb_speedometer_set_brightness(mrb_state* mrb, mrb_value self) {
  (void)self;
  mrb_int display_index;
  mrb_int value;
  mrb_get_args(mrb, "ii", &display_index, &value);
  if (!valid_display_index(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  }
  if (value < 0) {
    value = 0;
  } else if (value > 255) {
    value = 255;
  }
  if (!begin_display(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_RUNTIME_ERROR, "GC9A01 display initialization failed");
  }
  const DisplayConfig& config = display_configs[display_index];
  if (config.pin_bl >= 0) {
    displays[display_index].setBrightness(static_cast<uint8_t>(value));
  }
  return mrb_fixnum_value(value);
}

mrb_value mrb_speedometer_initialized(mrb_state* mrb, mrb_value self) {
  (void)self;
  mrb_int display_index;
  mrb_get_args(mrb, "i", &display_index);
  if (!valid_display_index(static_cast<int>(display_index))) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "display_index must be 0 or 1");
  }
  return mrb_bool_value(display_states[display_index].initialized);
}

#elif defined(PICORB_VM_MRUBYC)

bool mrbc_numeric_arg(mrbc_vm* vm, mrbc_value* v, int index,
                      float* result) {
  if (GET_TT_ARG(index) == MRBC_TT_FLOAT) {
    *result = static_cast<float>(GET_FLOAT_ARG(index));
    return true;
  }
  if (GET_TT_ARG(index) == MRBC_TT_INTEGER) {
    *result = static_cast<float>(GET_INT_ARG(index));
    return true;
  }
  mrbc_raise(vm, MRBC_CLASS(TypeError), "numeric argument required");
  return false;
}

void c_display_configure(mrbc_vm* vm, mrbc_value* v, int argc) {
  if (argc != 9) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "wrong number of arguments");
    return;
  }
  for (int index = 1; index <= 9; ++index) {
    if (GET_TT_ARG(index) != MRBC_TT_INTEGER) {
      mrbc_raise(vm, MRBC_CLASS(TypeError), "integer argument required");
      return;
    }
  }
  const ConfigResult result = set_display_config(
      GET_INT_ARG(1), GET_INT_ARG(2), GET_INT_ARG(3), GET_INT_ARG(4),
      GET_INT_ARG(5), GET_INT_ARG(6), GET_INT_ARG(7), GET_INT_ARG(8),
      GET_INT_ARG(9));
  if (result == kConfigLocked) {
    mrbc_raise(vm, MRBC_CLASS(RuntimeError), "display is already initialized");
    return;
  }
  if (result == kConfigInvalidDisplay) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  if (result == kConfigInvalidHost) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "spi_host must be 0 or 1");
    return;
  }
  if (result == kConfigInvalidPin) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "invalid GPIO pin");
    return;
  }
  if (result == kConfigInvalidFrequency) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "frequency must be between 1000000 and 100000000");
    return;
  }
  SET_TRUE_RETURN();
}

void c_speedometer_init(mrbc_vm* vm, mrbc_value* v, int argc) {
  if (argc != 1) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "wrong number of arguments");
    return;
  }
  if (GET_TT_ARG(1) != MRBC_TT_INTEGER) {
    mrbc_raise(vm, MRBC_CLASS(TypeError), "integer argument required");
    return;
  }
  const int display_index = GET_INT_ARG(1);
  if (!valid_display_index(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  if (!begin_display(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(RuntimeError),
               "GC9A01 display initialization failed");
    return;
  }
  SET_TRUE_RETURN();
}

void c_speedometer_render(mrbc_vm* vm, mrbc_value* v, int argc) {
  if (argc != 5) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "wrong number of arguments");
    return;
  }
  if (GET_TT_ARG(1) != MRBC_TT_INTEGER) {
    mrbc_raise(vm, MRBC_CLASS(TypeError), "integer argument required");
    return;
  }
  const int display_index = GET_INT_ARG(1);
  if (!valid_display_index(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  float speed;
  float rpm;
  if (!mrbc_numeric_arg(vm, v, 2, &speed) ||
      !mrbc_numeric_arg(vm, v, 3, &rpm)) {
    return;
  }
  if ((GET_TT_ARG(4) != MRBC_TT_TRUE && GET_TT_ARG(4) != MRBC_TT_FALSE) ||
      (GET_TT_ARG(5) != MRBC_TT_TRUE && GET_TT_ARG(5) != MRBC_TT_FALSE)) {
    mrbc_raise(vm, MRBC_CLASS(TypeError), "boolean argument required");
    return;
  }
  SET_FLOAT_RETURN(render_values(display_index, speed, rpm,
                                 GET_TT_ARG(4) == MRBC_TT_TRUE,
                                 GET_TT_ARG(5) == MRBC_TT_TRUE));
}

void c_speedometer_demo_step(mrbc_vm* vm, mrbc_value* v, int argc) {
  if (argc != 1 || GET_TT_ARG(1) != MRBC_TT_INTEGER) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "display index required");
    return;
  }
  const int display_index = GET_INT_ARG(1);
  if (!valid_display_index(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  float speed;
  float rpm;
  demo_values(display_index, &speed, &rpm);
  SET_FLOAT_RETURN(render_values(display_index, speed, rpm));
}

void c_simple_speedometer_render(mrbc_vm* vm, mrbc_value* v, int argc) {
  if (argc != 2) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "wrong number of arguments");
    return;
  }
  if (GET_TT_ARG(1) != MRBC_TT_INTEGER) {
    mrbc_raise(vm, MRBC_CLASS(TypeError), "integer argument required");
    return;
  }
  const int display_index = GET_INT_ARG(1);
  if (!valid_display_index(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  float speed;
  if (!mrbc_numeric_arg(vm, v, 2, &speed)) {
    return;
  }
  SET_FLOAT_RETURN(render_simple_speed(display_index, speed));
}

void c_simple_speedometer_demo_step(mrbc_vm* vm, mrbc_value* v,
                                    int argc) {
  if (argc != 1 || GET_TT_ARG(1) != MRBC_TT_INTEGER) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "display index required");
    return;
  }
  const int display_index = GET_INT_ARG(1);
  if (!valid_display_index(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  SET_FLOAT_RETURN(render_simple_speed(
      display_index, simple_demo_speed(display_index)));
}

void c_speedometer_set_brightness(mrbc_vm* vm, mrbc_value* v, int argc) {
  if (argc != 2) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "wrong number of arguments");
    return;
  }
  if (GET_TT_ARG(1) != MRBC_TT_INTEGER ||
      GET_TT_ARG(2) != MRBC_TT_INTEGER) {
    mrbc_raise(vm, MRBC_CLASS(TypeError), "integer argument required");
    return;
  }
  const int display_index = GET_INT_ARG(1);
  if (!valid_display_index(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  int value = GET_INT_ARG(2);
  if (value < 0) {
    value = 0;
  } else if (value > 255) {
    value = 255;
  }
  if (!begin_display(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(RuntimeError),
               "GC9A01 display initialization failed");
    return;
  }
  if (display_configs[display_index].pin_bl >= 0) {
    displays[display_index].setBrightness(static_cast<uint8_t>(value));
  }
  SET_INT_RETURN(value);
}

void c_speedometer_initialized(mrbc_vm* vm, mrbc_value* v, int argc) {
  if (argc != 1 || GET_TT_ARG(1) != MRBC_TT_INTEGER) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "display index required");
    return;
  }
  const int display_index = GET_INT_ARG(1);
  if (!valid_display_index(display_index)) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError),
               "display_index must be 0 or 1");
    return;
  }
  SET_BOOL_RETURN(display_states[display_index].initialized);
}

#endif

}  // namespace

#if defined(PICORB_VM_MRUBY)

extern "C" void mrb_picoruby_gc9a01_speedometer_gem_init(mrb_state* mrb) {
  RClass* display_class =
      mrb_define_class(mrb, "GC9A01Display", mrb->object_class);
  mrb_define_class_method(mrb, display_class, "_configure",
                          mrb_display_configure, MRB_ARGS_REQ(9));

  RClass* speedometer =
      mrb_define_class(mrb, "GC9A01Speedometer", mrb->object_class);
  mrb_define_method(mrb, speedometer, "_init", mrb_speedometer_init,
                    MRB_ARGS_REQ(1));
  mrb_define_method(mrb, speedometer, "_render", mrb_speedometer_render,
                    MRB_ARGS_REQ(5));
  mrb_define_method(mrb, speedometer, "_demo_step",
                    mrb_speedometer_demo_step, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, speedometer, "_set_brightness",
                    mrb_speedometer_set_brightness, MRB_ARGS_REQ(2));
  mrb_define_method(mrb, speedometer, "_initialized",
                    mrb_speedometer_initialized, MRB_ARGS_REQ(1));

  RClass* simple_speedometer =
      mrb_define_class(mrb, "GC9A01SimpleSpeedometer", mrb->object_class);
  mrb_define_method(mrb, simple_speedometer, "_init", mrb_speedometer_init,
                    MRB_ARGS_REQ(1));
  mrb_define_method(mrb, simple_speedometer, "_render",
                    mrb_simple_speedometer_render, MRB_ARGS_REQ(2));
  mrb_define_method(mrb, simple_speedometer, "_demo_step",
                    mrb_simple_speedometer_demo_step, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, simple_speedometer, "_set_brightness",
                    mrb_speedometer_set_brightness, MRB_ARGS_REQ(2));
  mrb_define_method(mrb, simple_speedometer, "_initialized",
                    mrb_speedometer_initialized, MRB_ARGS_REQ(1));
}

extern "C" void mrb_picoruby_gc9a01_speedometer_gem_final(mrb_state*) {}

#elif defined(PICORB_VM_MRUBYC)

extern "C" void mrbc_gc9a01_speedometer_init(mrbc_vm* vm) {
  mrbc_class* display_class =
      mrbc_define_class(vm, "GC9A01Display", mrbc_class_object);
  mrbc_define_method(vm, display_class, "_configure", c_display_configure);

  mrbc_class* speedometer =
      mrbc_define_class(vm, "GC9A01Speedometer", mrbc_class_object);
  mrbc_define_method(vm, speedometer, "_init", c_speedometer_init);
  mrbc_define_method(vm, speedometer, "_render", c_speedometer_render);
  mrbc_define_method(vm, speedometer, "_demo_step", c_speedometer_demo_step);
  mrbc_define_method(vm, speedometer, "_set_brightness",
                     c_speedometer_set_brightness);
  mrbc_define_method(vm, speedometer, "_initialized",
                     c_speedometer_initialized);

  mrbc_class* simple_speedometer =
      mrbc_define_class(vm, "GC9A01SimpleSpeedometer", mrbc_class_object);
  mrbc_define_method(vm, simple_speedometer, "_init", c_speedometer_init);
  mrbc_define_method(vm, simple_speedometer, "_render",
                     c_simple_speedometer_render);
  mrbc_define_method(vm, simple_speedometer, "_demo_step",
                     c_simple_speedometer_demo_step);
  mrbc_define_method(vm, simple_speedometer, "_set_brightness",
                     c_speedometer_set_brightness);
  mrbc_define_method(vm, simple_speedometer, "_initialized",
                     c_speedometer_initialized);
}

#endif
