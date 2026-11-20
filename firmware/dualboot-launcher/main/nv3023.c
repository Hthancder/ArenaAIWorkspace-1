#include "nv3023.h"
#include "font5x7.h"

#include <string.h>
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define PIN_TFT_CS    14
#define PIN_TFT_DC    8
#define PIN_TFT_RST   18
#define PIN_TFT_SCLK  9
#define PIN_TFT_MOSI  10
#define PIN_TFT_BL    13

#define DMA_CHUNK_PIXELS (LCD_WIDTH * 16)

static spi_device_handle_t s_spi = NULL;
static uint16_t *s_dma_buf = NULL;
static bool s_inited = false;

static inline uint16_t swap16(uint16_t c)
{
    return (uint16_t)((c >> 8) | (c << 8));
}

static void lcd_cmd(uint8_t cmd)
{
    gpio_set_level(PIN_TFT_DC, 0);
    spi_transaction_t t = {0};
    t.length = 8;
    t.flags = SPI_TRANS_USE_TXDATA;
    t.tx_data[0] = cmd;
    spi_device_polling_transmit(s_spi, &t);
}

static void lcd_data(const uint8_t *data, size_t len)
{
    if (!len) return;
    gpio_set_level(PIN_TFT_DC, 1);
    spi_transaction_t t = {0};
    t.length = len * 8;
    if (len <= 4) {
        t.flags = SPI_TRANS_USE_TXDATA;
        memcpy(t.tx_data, data, len);
    } else {
        t.tx_buffer = data;
    }
    spi_device_polling_transmit(s_spi, &t);
}

static void lcd_data_u8(uint8_t v)
{
    lcd_data(&v, 1);
}

static void lcd_set_window(int x0, int y0, int x1, int y1)
{
    int cx0 = x0 + LCD_X_OFF;
    int cx1 = x1 + LCD_X_OFF;
    uint8_t col[4] = {
        (uint8_t)(cx0 >> 8), (uint8_t)(cx0 & 0xFF),
        (uint8_t)(cx1 >> 8), (uint8_t)(cx1 & 0xFF),
    };
    uint8_t row[4] = {
        (uint8_t)(y0 >> 8), (uint8_t)(y0 & 0xFF),
        (uint8_t)(y1 >> 8), (uint8_t)(y1 & 0xFF),
    };
    lcd_cmd(0x2A);
    lcd_data(col, 4);
    lcd_cmd(0x2B);
    lcd_data(row, 4);
    lcd_cmd(0x2C);
}

static void lcd_write_pixels(const uint16_t *buf, size_t pixel_count)
{
    gpio_set_level(PIN_TFT_DC, 1);
    size_t offset = 0;
    while (offset < pixel_count) {
        size_t chunk = pixel_count - offset;
        if (chunk > DMA_CHUNK_PIXELS) chunk = DMA_CHUNK_PIXELS;
        spi_transaction_t t = {0};
        t.length = chunk * 16;
        t.tx_buffer = buf + offset;
        spi_device_polling_transmit(s_spi, &t);
        offset += chunk;
    }
}

void nv3023_backlight(bool on)
{
    gpio_set_level(PIN_TFT_BL, on ? 1 : 0);
}

void nv3023_init(void)
{
    if (s_inited) return;

    gpio_config_t io = {
        .pin_bit_mask = (1ULL << PIN_TFT_DC) | (1ULL << PIN_TFT_RST) | (1ULL << PIN_TFT_BL),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&io);
    gpio_set_level(PIN_TFT_BL, 0);
    gpio_set_level(PIN_TFT_DC, 1);
    gpio_set_level(PIN_TFT_RST, 1);

    s_dma_buf = (uint16_t *)heap_caps_malloc(DMA_CHUNK_PIXELS * sizeof(uint16_t), MALLOC_CAP_DMA);

    spi_bus_config_t buscfg = {
        .mosi_io_num = PIN_TFT_MOSI,
        .miso_io_num = -1,
        .sclk_io_num = PIN_TFT_SCLK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = DMA_CHUNK_PIXELS * 2 + 16,
    };
    spi_bus_initialize(SPI2_HOST, &buscfg, SPI_DMA_CH_AUTO);

    spi_device_interface_config_t devcfg = {
        .clock_speed_hz = 40 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = PIN_TFT_CS,
        .queue_size = 4,
    };
    spi_bus_add_device(SPI2_HOST, &devcfg, &s_spi);

    // Hardware reset pulse
    gpio_set_level(PIN_TFT_RST, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    gpio_set_level(PIN_TFT_RST, 1);
    vTaskDelay(pdMS_TO_TICKS(120));

    // Exact NV3023 vendor unlock + power/gamma sequence (matches NV3023_Panel.h)
    static const uint8_t init_seq[] = {
        0xFD, 2, 0x06, 0x08,
        0x61, 2, 0x07, 0x04,
        0x62, 3, 0x00, 0x44, 0x45,
        0x63, 4, 0x41, 0x07, 0x12, 0x12,
        0x64, 1, 0x37,
        0x65, 3, 0x09, 0x10, 0x21,
        0x66, 3, 0x09, 0x10, 0x21,
        0x67, 2, 0x20, 0x40,
        0x68, 4, 0x90, 0x4C, 0x7C, 0x66,
        0xB1, 3, 0x0F, 0x02, 0x01,
        0xB4, 1, 0x01,
        0xB5, 4, 0x02, 0x02, 0x0A, 0x14,
        0xB6, 5, 0x04, 0x01, 0x9F, 0x00, 0x02,
        0xDF, 1, 0x11,
        0xE2, 6, 0x13, 0x00, 0x00, 0x30, 0x33, 0x3F,
        0xE5, 6, 0x3F, 0x33, 0x30, 0x00, 0x00, 0x13,
        0xE1, 2, 0x00, 0x57,
        0xE4, 2, 0x58, 0x00,
        0xE0, 8, 0x01, 0x03, 0x0D, 0x0E, 0x0E, 0x0C, 0x15, 0x19,
        0xE3, 8, 0x1A, 0x16, 0x0C, 0x0F, 0x0E, 0x0D, 0x02, 0x01,
        0xE6, 2, 0x00, 0xFF,
        0xE7, 6, 0x01, 0x04, 0x03, 0x03, 0x00, 0x12,
        0xE8, 3, 0x00, 0x70, 0x00,
        0xEC, 1, 0x52,
        0xF1, 3, 0x01, 0x01, 0x02,
        0xF6, 4, 0x09, 0x10, 0x00, 0x00,
        0xFD, 2, 0xFA, 0xFC,
        0x35, 1, 0x00,
        0xFF
    };

    size_t i = 0;
    while (init_seq[i] != 0xFF) {
        uint8_t cmd = init_seq[i++];
        uint8_t cnt = init_seq[i++];
        lcd_cmd(cmd);
        if (cnt > 0) {
            lcd_data(&init_seq[i], cnt);
            i += cnt;
        }
    }

    // MADCTL = MV | MY | BGR (0xA8) for 284x240 landscape, RGB565 (0x55), INVON (0x21)
    lcd_cmd(0x36);
    lcd_data_u8(0xA8);
    lcd_cmd(0x3A);
    lcd_data_u8(0x55);
    lcd_cmd(0x21);

    lcd_cmd(0x11); // SLPOUT
    vTaskDelay(pdMS_TO_TICKS(150));
    lcd_cmd(0x29); // DISPON
    vTaskDelay(pdMS_TO_TICKS(20));

    s_inited = true;
}

void nv3023_fill_rect(int x, int y, int w, int h, uint16_t color)
{
    if (!s_inited || !s_dma_buf || w <= 0 || h <= 0) return;
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > LCD_WIDTH) w = LCD_WIDTH - x;
    if (y + h > LCD_HEIGHT) h = LCD_HEIGHT - y;
    if (w <= 0 || h <= 0) return;

    size_t total = (size_t)w * (size_t)h;
    size_t fill = total < DMA_CHUNK_PIXELS ? total : DMA_CHUNK_PIXELS;
    uint16_t sw = swap16(color);
    for (size_t i = 0; i < fill; ++i) {
        s_dma_buf[i] = sw;
    }

    lcd_set_window(x, y, x + w - 1, y + h - 1);
    gpio_set_level(PIN_TFT_DC, 1);
    size_t sent = 0;
    while (sent < total) {
        size_t chunk = total - sent;
        if (chunk > DMA_CHUNK_PIXELS) chunk = DMA_CHUNK_PIXELS;
        spi_transaction_t t = {0};
        t.length = chunk * 16;
        t.tx_buffer = s_dma_buf;
        spi_device_polling_transmit(s_spi, &t);
        sent += chunk;
    }
}

void nv3023_draw_rect(int x, int y, int w, int h, int thickness, uint16_t color)
{
    if (thickness <= 0) thickness = 1;
    nv3023_fill_rect(x, y, w, thickness, color);
    nv3023_fill_rect(x, y + h - thickness, w, thickness, color);
    nv3023_fill_rect(x, y, thickness, h, color);
    nv3023_fill_rect(x + w - thickness, y, thickness, h, color);
}

void nv3023_fill_round_rect(int x, int y, int w, int h, int r, uint16_t color)
{
    if (r <= 1 || w <= 2 * r || h <= 2 * r) {
        nv3023_fill_rect(x, y, w, h, color);
        return;
    }
    nv3023_fill_rect(x + r, y, w - 2 * r, h, color);
    nv3023_fill_rect(x, y + r, r, h - 2 * r, color);
    nv3023_fill_rect(x + w - r, y + r, r, h - 2 * r, color);

    int f = 1 - r;
    int ddF_x = 1;
    int ddF_y = -2 * r;
    int px = 0;
    int py = r;
    while (px < py) {
        if (f >= 0) {
            py--;
            ddF_y += 2;
            f += ddF_y;
        }
        px++;
        ddF_x += 2;
        f += ddF_x;
        // Fill horizontal spans for top/bottom rounded corners
        nv3023_fill_rect(x + r - px, y + r - py, w - 2 * (r - px), 1, color);
        nv3023_fill_rect(x + r - py, y + r - px, w - 2 * (r - py), 1, color);
        nv3023_fill_rect(x + r - px, y + h - 1 - r + py, w - 2 * (r - px), 1, color);
        nv3023_fill_rect(x + r - py, y + h - 1 - r + px, w - 2 * (r - py), 1, color);
    }
}

void nv3023_draw_round_rect(int x, int y, int w, int h, int r, uint16_t color)
{
    if (r <= 1 || w <= 2 * r || h <= 2 * r) {
        nv3023_draw_rect(x, y, w, h, 1, color);
        return;
    }
    nv3023_fill_rect(x + r, y, w - 2 * r, 1, color);
    nv3023_fill_rect(x + r, y + h - 1, w - 2 * r, 1, color);
    nv3023_fill_rect(x, y + r, 1, h - 2 * r, color);
    nv3023_fill_rect(x + w - 1, y + r, 1, h - 2 * r, color);

    int f = 1 - r;
    int ddF_x = 1;
    int ddF_y = -2 * r;
    int px = 0;
    int py = r;
    while (px < py) {
        if (f >= 0) {
            py--;
            ddF_y += 2;
            f += ddF_y;
        }
        px++;
        ddF_x += 2;
        f += ddF_x;
        nv3023_fill_rect(x + w - 1 - r + px, y + r - py, 1, 1, color);
        nv3023_fill_rect(x + w - 1 - r + py, y + r - px, 1, 1, color);
        nv3023_fill_rect(x + r - px, y + r - py, 1, 1, color);
        nv3023_fill_rect(x + r - py, y + r - px, 1, 1, color);
        nv3023_fill_rect(x + w - 1 - r + px, y + h - 1 - r + py, 1, 1, color);
        nv3023_fill_rect(x + w - 1 - r + py, y + h - 1 - r + px, 1, 1, color);
        nv3023_fill_rect(x + r - px, y + h - 1 - r + py, 1, 1, color);
        nv3023_fill_rect(x + r - py, y + h - 1 - r + px, 1, 1, color);
    }
}

void nv3023_draw_char(int x, int y, char c, uint16_t fg, uint16_t bg, int scale)
{
    if (!s_inited || !s_dma_buf) return;
    if (scale < 1) scale = 1;
    if (scale > 4) scale = 4;

    uint8_t uc = (uint8_t)c;
    const uint8_t *glyph = &kFont5x7[uc * 5];
    int cw = 6 * scale;
    int ch = 8 * scale;
    if (x < 0 || y < 0 || x + cw > LCD_WIDTH || y + ch > LCD_HEIGHT) return;

    uint16_t fg_sw = swap16(fg);
    uint16_t bg_sw = swap16(bg);
    for (int row = 0; row < 8; ++row) {
        for (int sr = 0; sr < scale; ++sr) {
            int out_y = row * scale + sr;
            for (int col = 0; col < 6; ++col) {
                uint8_t bits = (col < 5) ? glyph[col] : 0;
                uint16_t px = (bits & (1 << row)) ? fg_sw : bg_sw;
                for (int sc = 0; sc < scale; ++sc) {
                    s_dma_buf[out_y * cw + col * scale + sc] = px;
                }
            }
        }
    }
    lcd_set_window(x, y, x + cw - 1, y + ch - 1);
    lcd_write_pixels(s_dma_buf, (size_t)cw * (size_t)ch);
}

int nv3023_text_width(const char *s, int scale)
{
    if (!s) return 0;
    if (scale < 1) scale = 1;
    return (int)strlen(s) * 6 * scale;
}

void nv3023_draw_text(int x, int y, const char *s, uint16_t fg, uint16_t bg, int scale)
{
    if (!s) return;
    if (scale < 1) scale = 1;
    int adv = 6 * scale;
    while (*s && x + adv <= LCD_WIDTH) {
        nv3023_draw_char(x, y, *s++, fg, bg, scale);
        x += adv;
    }
}

void nv3023_draw_text_centered(int cx, int y, const char *s, uint16_t fg, uint16_t bg, int scale)
{
    if (!s) return;
    int w = nv3023_text_width(s, scale);
    int x = cx - w / 2;
    if (x < 0) x = 0;
    nv3023_draw_text(x, y, s, fg, bg, scale);
}
