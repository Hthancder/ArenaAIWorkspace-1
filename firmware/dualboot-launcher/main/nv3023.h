#pragma once

#include <stdint.h>
#include <stdbool.h>

#define LCD_WIDTH   284
#define LCD_HEIGHT  240
#define LCD_X_OFF   36

// RGB565 helper macro (host order; nv3023 driver swaps to SPI big-endian on TX)
#define RGB565(r, g, b) ((uint16_t)((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | (((b) & 0xF8) >> 3)))

void nv3023_init(void);
void nv3023_backlight(bool on);
void nv3023_fill_rect(int x, int y, int w, int h, uint16_t color);
void nv3023_draw_rect(int x, int y, int w, int h, int thickness, uint16_t color);
void nv3023_draw_round_rect(int x, int y, int w, int h, int r, uint16_t color);
void nv3023_fill_round_rect(int x, int y, int w, int h, int r, uint16_t color);
void nv3023_draw_char(int x, int y, char c, uint16_t fg, uint16_t bg, int scale);
void nv3023_draw_text(int x, int y, const char *s, uint16_t fg, uint16_t bg, int scale);
void nv3023_draw_text_centered(int cx, int y, const char *s, uint16_t fg, uint16_t bg, int scale);
int  nv3023_text_width(const char *s, int scale);
