cmake_minimum_required(VERSION 3.13)

set(PICO_BOARD pico2 CACHE STRING "Pico SDK board name")

if(NOT PICO_SDK_PATH AND DEFINED ENV{PICO_SDK_PATH})
  set(PICO_SDK_PATH $ENV{PICO_SDK_PATH})
endif()

if(NOT EXISTS "${PICO_SDK_PATH}/external/pico_sdk_import.cmake")
  message(FATAL_ERROR "Set PICO_SDK_PATH to a Pico SDK checkout")
endif()

include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(gc9a01_speedometer C CXX ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

set(LOVYANGFX_PATH "${CMAKE_CURRENT_LIST_DIR}/../../tmp/LovyanGFX"
    CACHE PATH "Path to a LovyanGFX checkout")

if(NOT EXISTS "${LOVYANGFX_PATH}/CMakeLists.txt")
  message(FATAL_ERROR
    "LovyanGFX was not found. Set LOVYANGFX_PATH or clone it to tmp/LovyanGFX")
endif()

add_subdirectory(${LOVYANGFX_PATH} ${CMAKE_BINARY_DIR}/LovyanGFX)

set(GC9A01_SPI_PORT 0 CACHE STRING "SPI controller: 0 or 1")
set(GC9A01_PIN_SCLK 18 CACHE STRING "GPIO connected to SCLK")
set(GC9A01_PIN_MOSI 19 CACHE STRING "GPIO connected to DIN/MOSI")
set(GC9A01_PIN_CS 17 CACHE STRING "GPIO connected to CS")
set(GC9A01_PIN_DC 20 CACHE STRING "GPIO connected to DC")
set(GC9A01_PIN_RST 21 CACHE STRING "GPIO connected to RST")
set(GC9A01_PIN_BL 22 CACHE STRING "GPIO connected to BL; -1 disables control")
set(GC9A01_SPI_FREQUENCY 40000000 CACHE STRING "LCD write frequency in Hz")

add_executable(gc9a01_speedometer
  main.cpp
)

target_include_directories(gc9a01_speedometer PRIVATE
  ${CMAKE_CURRENT_LIST_DIR}
)

target_compile_definitions(gc9a01_speedometer PRIVATE
  GC9A01_SPI_PORT=${GC9A01_SPI_PORT}
  GC9A01_PIN_SCLK=${GC9A01_PIN_SCLK}
  GC9A01_PIN_MOSI=${GC9A01_PIN_MOSI}
  GC9A01_PIN_CS=${GC9A01_PIN_CS}
  GC9A01_PIN_DC=${GC9A01_PIN_DC}
  GC9A01_PIN_RST=${GC9A01_PIN_RST}
  GC9A01_PIN_BL=${GC9A01_PIN_BL}
  GC9A01_SPI_FREQUENCY=${GC9A01_SPI_FREQUENCY}
)

target_compile_options(gc9a01_speedometer PRIVATE
  -Wall
  -Wextra
)

target_link_libraries(gc9a01_speedometer PRIVATE
  pico_stdlib
  LovyanGFX
)

pico_enable_stdio_usb(gc9a01_speedometer 1)
pico_enable_stdio_uart(gc9a01_speedometer 0)
pico_add_extra_outputs(gc9a01_speedometer)
