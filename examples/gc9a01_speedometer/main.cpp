#include <cmath>
#include <cstdint>
#include <cstdio>

#include <pico/stdlib.h>

#include "lgfx_gc9a01.hpp"

namespace {

constexpr int kWidth = 240;
constexpr int kHeight = 240;
constexpr int kCenterX = 120;
constexpr int kCenterY = 120;
constexpr float kPi = 3.14159265358979323846f;
constexpr float kStartAngle = -135.0f;
constexpr float kSweepAngle = 270.0f;
constexpr float kMaxSpeed = 240.0f;
constexpr uint32_t kFrameIntervalUs = 33333;

constexpr uint32_t kBackground = 0x07090d;
constexpr uint32_t kDialInner = 0x10151c;
constexpr uint32_t kRingDark = 0x242b33;
constexpr uint32_t kRingLight = 0x8b949e;
constexpr uint32_t kTick = 0xe6edf3;
constexpr uint32_t kTickDim = 0x69727d;
constexpr uint32_t kAccent = 0xe53935;
constexpr uint32_t kNeedleShadow = 0x3a0909;
constexpr uint32_t kText = 0xf2f5f7;

GC9A01Display display;
LGFX_Sprite frame(&display);

float to_radians(float degrees) {
  return degrees * kPi / 180.0f;
}

float speed_to_angle(float speed) {
  return kStartAngle + (speed / kMaxSpeed) * kSweepAngle;
}

void polar_point(float angle_degrees, float radius, int* x, int* y) {
  const float radians = to_radians(angle_degrees - 90.0f);
  *x = static_cast<int>(std::lround(kCenterX + std::cos(radians) * radius));
  *y = static_cast<int>(std::lround(kCenterY + std::sin(radians) * radius));
}

void draw_rings() {
  frame.fillScreen(kBackground);
  frame.fillCircle(kCenterX, kCenterY, 116, kRingDark);
  frame.fillCircle(kCenterX, kCenterY, 113, kRingLight);
  frame.fillCircle(kCenterX, kCenterY, 109, kBackground);
  frame.fillCircle(kCenterX, kCenterY, 103, kDialInner);
  frame.drawCircle(kCenterX, kCenterY, 102, 0x343d47);
  frame.drawCircle(kCenterX, kCenterY, 101, 0x090b0f);
}

void draw_redline_arc() {
  for (int speed = 200; speed < 240; speed += 2) {
    int x0;
    int y0;
    int x1;
    int y1;
    polar_point(speed_to_angle(static_cast<float>(speed)), 96.0f, &x0, &y0);
    polar_point(speed_to_angle(static_cast<float>(speed + 2)), 96.0f, &x1, &y1);
    frame.drawLine(x0, y0, x1, y1, kAccent);
    polar_point(speed_to_angle(static_cast<float>(speed)), 95.0f, &x0, &y0);
    polar_point(speed_to_angle(static_cast<float>(speed + 2)), 95.0f, &x1, &y1);
    frame.drawLine(x0, y0, x1, y1, kAccent);
  }
}

void draw_ticks() {
  for (int speed = 0; speed <= 240; speed += 5) {
    const bool major = (speed % 20) == 0;
    const float angle = speed_to_angle(static_cast<float>(speed));
    const float inner_radius = major ? 82.0f : 88.0f;
    const uint32_t color = speed >= 200 ? kAccent : (major ? kTick : kTickDim);
    int x0;
    int y0;
    int x1;
    int y1;
    polar_point(angle, inner_radius, &x0, &y0);
    polar_point(angle, 96.0f, &x1, &y1);
    frame.drawLine(x0, y0, x1, y1, color);
    if (major) {
      int x2;
      int y2;
      polar_point(angle + 0.7f, inner_radius, &x2, &y2);
      frame.drawLine(x2, y2, x1, y1, color);
    }
  }
}

void draw_labels() {
  frame.setFont(&fonts::Font0);
  frame.setTextDatum(middle_center);
  frame.setTextColor(kText, kDialInner);
  char label[4];
  for (int speed = 0; speed <= 240; speed += 20) {
    int x;
    int y;
    polar_point(speed_to_angle(static_cast<float>(speed)), 69.0f, &x, &y);
    std::snprintf(label, sizeof(label), "%d", speed);
    frame.drawString(label, x, y);
  }

  frame.setTextColor(0xaeb7c1, kDialInner);
  frame.drawCenterString("km/h", kCenterX, 160, &fonts::Font2);
  frame.setTextColor(0x68727d, kDialInner);
  frame.drawCenterString("PicoRuby", kCenterX, 181, &fonts::Font0);
}

void draw_speed_value(float speed) {
  char value[4];
  std::snprintf(value, sizeof(value), "%03d", static_cast<int>(speed + 0.5f));
  frame.fillRoundRect(82, 132, 76, 24, 4, 0x05070a);
  frame.drawRoundRect(82, 132, 76, 24, 4, 0x303842);
  frame.setTextColor(kText, 0x05070a);
  frame.setTextDatum(middle_center);
  frame.drawString(value, kCenterX, 144, &fonts::Font4);
}

void draw_needle(float speed) {
  const float angle = speed_to_angle(speed);
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

  frame.fillTriangle(left_x + 2, left_y + 2, tip_x + 2, tip_y + 2,
                     right_x + 2, right_y + 2, kNeedleShadow);
  frame.fillTriangle(left_x, left_y, tip_x, tip_y, right_x, right_y, kAccent);
  frame.drawLine(kCenterX, kCenterY, tail_x, tail_y, kAccent);
  frame.fillCircle(kCenterX, kCenterY, 9, 0x111820);
  frame.fillCircle(kCenterX, kCenterY, 7, kAccent);
  frame.fillCircle(kCenterX - 2, kCenterY - 2, 2, 0xff8a80);
}

void render(float speed) {
  draw_rings();
  draw_redline_arc();
  draw_ticks();
  draw_labels();
  draw_speed_value(speed);
  draw_needle(speed);
  frame.pushSprite(0, 0);
}

float demo_speed(uint32_t elapsed_ms) {
  constexpr float kCycleMs = 9000.0f;
  const float phase = static_cast<float>(elapsed_ms % static_cast<uint32_t>(kCycleMs)) /
                      kCycleMs;
  return 0.5f * (1.0f - std::cos(phase * 2.0f * kPi)) * kMaxSpeed;
}

}  // namespace

int main() {
  stdio_init_all();

  display.init();
  display.setRotation(0);
  display.setColorDepth(16);
#if GC9A01_PIN_BL >= 0
  display.setBrightness(220);
#endif

  frame.setColorDepth(16);
  if (frame.createSprite(kWidth, kHeight) == nullptr) {
    display.fillScreen(0x000000);
    display.setTextColor(0xff0000, 0x000000);
    display.drawCenterString("SPRITE ALLOC FAILED", 120, 116, &fonts::Font2);
    while (true) {
      sleep_ms(1000);
    }
  }

  const absolute_time_t started_at = get_absolute_time();
  absolute_time_t next_frame = started_at;

  while (true) {
    const int64_t elapsed_us = absolute_time_diff_us(started_at, get_absolute_time());
    render(demo_speed(static_cast<uint32_t>(elapsed_us / 1000)));
    next_frame = delayed_by_us(next_frame, kFrameIntervalUs);
    sleep_until(next_frame);
  }
}
