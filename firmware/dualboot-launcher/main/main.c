/*
 * DSolution 1.83" 2-Mic Dual-Boot Menu (factory partition app)
 *
 * - Latches GPIO21 HIGH on boot so battery power stays on.
 * - Reads boot settings from NVS namespace "dualboot":
 *     def_os:     0 = XiaoZhi HeyLily (default), 1 = Bruce Firmware
 *     timeout_ms: 0 (hold button to show menu), 1500, 2500 (default), 4000
 * - Displays an interactive NV3023 284x240 Cyber Cyan boot menu on every cold
 *   boot / reset with auto-boot countdown into the default OS.
 * - Controls: Vol+ (GPIO39) / Vol- (GPIO40) move selection & pause countdown;
 *             Boot (GPIO0) confirms selection or opens Boot Settings.
 */
#include <stdio.h>
#include <string.h>
#include "driver/gpio.h"
#include "esp_app_desc.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "soc/rtc_cntl_reg.h"
#include "soc/soc.h"

#include "nv3023.h"

#define PIN_LATCH          21
#define PIN_BTN_BOOT       0
#define PIN_BTN_VOL_UP     39
#define PIN_BTN_VOL_DOWN   40

#define DUALBOOT_RTC_REG       RTC_CNTL_STORE5_REG
#define DUALBOOT_MAGIC_BASE    0xD8000000U

// Cyber Cyan palette matching DSolution 1.83" Bruce theme
#define COL_BG         RGB565(7, 13, 18)
#define COL_CARD       RGB565(13, 24, 34)
#define COL_CARD_SEL   RGB565(11, 44, 58)
#define COL_BORDER     RGB565(34, 62, 78)
#define COL_CYAN       RGB565(0, 240, 255)
#define COL_TEAL       RGB565(80, 174, 189)
#define COL_WHITE      RGB565(242, 250, 255)
#define COL_MUTED      RGB565(120, 150, 168)
#define COL_AMBER      RGB565(255, 196, 64)
#define COL_GREEN      RGB565(64, 232, 148)
#define COL_RED        RGB565(255, 92, 108)
#define COL_BAR_BG     RGB565(20, 36, 48)

typedef struct {
    uint8_t def_os;       // 0 = XiaoZhi HeyLily, 1 = Bruce
    uint16_t timeout_ms;  // 0, 1500, 2500, 4000
} dualboot_cfg_t;

typedef struct {
    const esp_partition_t *part;
    bool valid;
    char version[32];
    uint32_t size_kb;
} slot_info_t;

static slot_info_t s_slots[2];
static dualboot_cfg_t s_cfg = { .def_os = 0, .timeout_ms = 2500 };

static bool btn_raw_down(int gpio)
{
    return gpio_get_level(gpio) == 0;
}

static void init_gpio_early(void)
{
    gpio_config_t latch_cfg = {
        .pin_bit_mask = (1ULL << PIN_LATCH),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&latch_cfg);
    gpio_set_level(PIN_LATCH, 1);

    gpio_config_t btn_cfg = {
        .pin_bit_mask = (1ULL << PIN_BTN_BOOT) | (1ULL << PIN_BTN_VOL_UP) | (1ULL << PIN_BTN_VOL_DOWN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&btn_cfg);
}

static void cfg_load(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    if (err != ESP_OK) return;

    nvs_handle_t h;
    if (nvs_open("dualboot", NVS_READONLY, &h) == ESP_OK) {
        uint8_t def_os = 0;
        uint16_t tout = 2500;
        if (nvs_get_u8(h, "def_os", &def_os) == ESP_OK && def_os <= 1) {
            s_cfg.def_os = def_os;
        }
        if (nvs_get_u16(h, "timeout_ms", &tout) == ESP_OK) {
            s_cfg.timeout_ms = tout;
        }
        nvs_close(h);
    }
}

static void cfg_save(void)
{
    nvs_handle_t h;
    if (nvs_open("dualboot", NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_u8(h, "def_os", s_cfg.def_os);
        nvs_set_u16(h, "timeout_ms", s_cfg.timeout_ms);
        nvs_commit(h);
        nvs_close(h);
    }
}

static void probe_slot(int idx, esp_partition_subtype_t subtype)
{
    memset(&s_slots[idx], 0, sizeof(slot_info_t));
    const esp_partition_t *p = esp_partition_find_first(ESP_PARTITION_TYPE_APP, subtype, NULL);
    s_slots[idx].part = p;
    if (!p) return;

    s_slots[idx].size_kb = p->size / 1024;
    uint8_t magic = 0;
    if (esp_partition_read(p, 0, &magic, 1) == ESP_OK && magic == 0xE9) {
        s_slots[idx].valid = true;
        esp_app_desc_t desc;
        if (esp_ota_get_partition_description(p, &desc) == ESP_OK) {
            snprintf(s_slots[idx].version, sizeof(s_slots[idx].version), "%.24s", desc.version);
        } else {
            snprintf(s_slots[idx].version, sizeof(s_slots[idx].version), "Ready");
        }
    }
}

static void __attribute__((noreturn)) boot_slot(int slot, bool show_screen)
{
    if (!s_slots[slot].valid) {
        slot = s_slots[0].valid ? 0 : (s_slots[1].valid ? 1 : slot);
    }
    if (s_slots[slot].part) {
        const esp_partition_t *cur = esp_ota_get_boot_partition();
        if (!cur || cur->address != s_slots[slot].part->address) {
            esp_ota_set_boot_partition(s_slots[slot].part);
        }
    }
    if (show_screen) {
        nv3023_fill_rect(12, 198, LCD_WIDTH - 24, 34, COL_BG);
        nv3023_fill_round_rect(12, 198, LCD_WIDTH - 24, 30, 6, COL_CARD_SEL);
        nv3023_draw_round_rect(12, 198, LCD_WIDTH - 24, 30, 6, COL_CYAN);
        const char *msg = (slot == 0) ? "Booting XiaoZhi..." : "Booting Bruce...";
        nv3023_draw_text_centered(LCD_WIDTH / 2, 206, msg, COL_WHITE, COL_CARD_SEL, 2);
        vTaskDelay(pdMS_TO_TICKS(80));
    }

    REG_WRITE(DUALBOOT_RTC_REG, DUALBOOT_MAGIC_BASE | ((uint32_t)slot & 0x0FU));
    esp_restart();
}

static void draw_header(const char *subtitle)
{
    nv3023_fill_rect(0, 0, LCD_WIDTH, 34, COL_CARD);
    nv3023_fill_rect(0, 34, LCD_WIDTH, 2, COL_CYAN);
    nv3023_draw_text(12, 10, "DSOLUTION 1.83\"", COL_CYAN, COL_CARD, 2);
    int sw = nv3023_text_width(subtitle, 1);
    nv3023_draw_text(LCD_WIDTH - sw - 12, 14, subtitle, COL_TEAL, COL_CARD, 1);
}

static void draw_os_card(int y, bool selected, bool is_default, const char *title,
                         const char *sub, const slot_info_t *info, int slot_idx)
{
    uint16_t bg = selected ? COL_CARD_SEL : COL_CARD;
    uint16_t border = selected ? COL_CYAN : COL_BORDER;

    nv3023_fill_round_rect(12, y, LCD_WIDTH - 24, 56, 8, bg);
    nv3023_draw_round_rect(12, y, LCD_WIDTH - 24, 56, 8, border);
    if (selected) {
        nv3023_draw_round_rect(13, y + 1, LCD_WIDTH - 26, 54, 7, border);
        nv3023_fill_rect(16, y + 10, 4, 36, COL_CYAN);
    }

    nv3023_draw_text(26, y + 10, title, COL_WHITE, bg, 2);

    char meta[80];
    if (info->valid) {
        snprintf(meta, sizeof(meta), "%.16s  (%.24s)", sub, info->version);
    } else {
        snprintf(meta, sizeof(meta), "%.16s  (Not flashed)", sub);
    }
    nv3023_draw_text(26, y + 34, meta, info->valid ? COL_TEAL : COL_RED, bg, 1);

    const char *badge = is_default ? "DEFAULT" : (slot_idx == 0 ? "OTA_0" : "OTA_1");
    uint16_t bcol = is_default ? COL_GREEN : COL_MUTED;
    int bw = nv3023_text_width(badge, 1);
    nv3023_draw_text(LCD_WIDTH - 22 - bw, y + 13, badge, bcol, bg, 1);
}

static void draw_main_menu(int sel, bool countdown_active, int remain_ms)
{
    draw_header("DUAL-BOOT");

    draw_os_card(44, sel == 0, s_cfg.def_os == 0,
                 "XiaoZhi HeyLily", "AI Voice", &s_slots[0], 0);
    draw_os_card(108, sel == 1, s_cfg.def_os == 1,
                 "Bruce Firmware", "Cyber Suite", &s_slots[1], 1);

    // Compact row 3: Boot Settings
    uint16_t opt_bg = (sel == 2) ? COL_CARD_SEL : COL_CARD;
    uint16_t opt_bd = (sel == 2) ? COL_CYAN : COL_BORDER;
    nv3023_fill_round_rect(12, 172, LCD_WIDTH - 24, 24, 6, opt_bg);
    nv3023_draw_round_rect(12, 172, LCD_WIDTH - 24, 24, 6, opt_bd);
    char opt_lbl[80];
    if (s_cfg.timeout_ms == 0) {
        snprintf(opt_lbl, sizeof(opt_lbl), "Boot Options  (Def:%s | 0s Instant)",
                 s_cfg.def_os == 0 ? "HeyLily" : "Bruce");
    } else {
        unsigned secs = s_cfg.timeout_ms / 1000U;
        unsigned decs = (s_cfg.timeout_ms % 1000U) / 100U;
        snprintf(opt_lbl, sizeof(opt_lbl), "Boot Options  (Def:%s | %u.%us)",
                 s_cfg.def_os == 0 ? "HeyLily" : "Bruce", secs, decs);
    }
    nv3023_draw_text(24, 180, opt_lbl, sel == 2 ? COL_WHITE : COL_TEAL, opt_bg, 1);

    // Footer status / countdown bar
    nv3023_fill_rect(12, 202, LCD_WIDTH - 24, 34, COL_BG);
    if (countdown_active && s_cfg.timeout_ms > 0) {
        char line[80];
        int tenths = (remain_ms + 99) / 100;
        if (tenths < 0) tenths = 0;
        snprintf(line, sizeof(line), "Auto-boot %s in %d.%ds",
                 s_cfg.def_os == 0 ? "HeyLily" : "Bruce", tenths / 10, tenths % 10);
        nv3023_draw_text_centered(LCD_WIDTH / 2, 204, line, COL_AMBER, COL_BG, 1);

        int bar_w = LCD_WIDTH - 36;
        int fill_w = (remain_ms * bar_w) / s_cfg.timeout_ms;
        if (fill_w < 0) fill_w = 0;
        if (fill_w > bar_w) fill_w = bar_w;
        nv3023_fill_round_rect(18, 218, bar_w, 8, 3, COL_BAR_BG);
        if (fill_w > 0) {
            nv3023_fill_rect(18, 218, fill_w, 8, COL_CYAN);
        }
        nv3023_draw_text_centered(LCD_WIDTH / 2, 229, "Vol+/Vol- Select  |  Boot Confirm", COL_MUTED, COL_BG, 1);
    } else {
        nv3023_draw_text_centered(LCD_WIDTH / 2, 210, "Timer paused - pick OS with Vol+/Vol-", COL_TEAL, COL_BG, 1);
        nv3023_draw_text_centered(LCD_WIDTH / 2, 224, "Press BOOT (GPIO0) to launch / edit", COL_MUTED, COL_BG, 1);
    }
}

static void update_countdown_bar_only(int remain_ms)
{
    if (s_cfg.timeout_ms == 0) return;
    char line[80];
    int tenths = (remain_ms + 99) / 100;
    if (tenths < 0) tenths = 0;
    snprintf(line, sizeof(line), "Auto-boot %s in %d.%ds   ",
             s_cfg.def_os == 0 ? "HeyLily" : "Bruce", tenths / 10, tenths % 10);
    nv3023_draw_text_centered(LCD_WIDTH / 2, 204, line, COL_AMBER, COL_BG, 1);

    int bar_w = LCD_WIDTH - 36;
    int fill_w = (remain_ms * bar_w) / s_cfg.timeout_ms;
    if (fill_w < 0) fill_w = 0;
    if (fill_w > bar_w) fill_w = bar_w;
    nv3023_fill_rect(18, 218, bar_w, 8, COL_BAR_BG);
    if (fill_w > 0) {
        nv3023_fill_rect(18, 218, fill_w, 8, COL_CYAN);
    }
}

static void draw_options_screen(int opt_sel)
{
    nv3023_fill_rect(0, 0, LCD_WIDTH, LCD_HEIGHT, COL_BG);
    draw_header("SETTINGS");

    const char *labels[3] = {
        "Default OS",
        "Auto-Boot Timer",
        "Save & Back"
    };
    char vals[3][48];
    snprintf(vals[0], sizeof(vals[0]), "%s", s_cfg.def_os == 0 ? "XiaoZhi HeyLily" : "Bruce Firmware");
    if (s_cfg.timeout_ms == 0) {
        snprintf(vals[1], sizeof(vals[1]), "0s (Hold key=Menu)");
    } else {
        unsigned secs = s_cfg.timeout_ms / 1000U;
        unsigned decs = (s_cfg.timeout_ms % 1000U) / 100U;
        snprintf(vals[1], sizeof(vals[1]), "%u.%us", secs, decs);
    }
    snprintf(vals[2], sizeof(vals[2]), "Return to Boot Menu");

    for (int i = 0; i < 3; ++i) {
        int y = 48 + i * 50;
        uint16_t bg = (opt_sel == i) ? COL_CARD_SEL : COL_CARD;
        uint16_t bd = (opt_sel == i) ? COL_CYAN : COL_BORDER;
        nv3023_fill_round_rect(12, y, LCD_WIDTH - 24, 42, 7, bg);
        nv3023_draw_round_rect(12, y, LCD_WIDTH - 24, 42, 7, bd);
        nv3023_draw_text(22, y + 8, labels[i], COL_WHITE, bg, 1);
        nv3023_draw_text(22, y + 22, vals[i], (i == 2) ? COL_GREEN : COL_CYAN, bg, 2);
    }
    nv3023_draw_text_centered(LCD_WIDTH / 2, 216, "Vol+/Vol- Move  |  Boot Toggle/Save", COL_MUTED, COL_BG, 1);
}

static void run_options_menu(void)
{
    static const uint16_t kTimeouts[] = { 1500, 2500, 4000, 0 };
    int opt_sel = 0;
    draw_options_screen(opt_sel);

    bool prev_up = false, prev_dn = false, prev_ok = true; // require release first
    while (true) {
        bool up = btn_raw_down(PIN_BTN_VOL_UP);
        bool dn = btn_raw_down(PIN_BTN_VOL_DOWN);
        bool ok = btn_raw_down(PIN_BTN_BOOT);

        if (up && !prev_up) {
            opt_sel = (opt_sel + 2) % 3;
            draw_options_screen(opt_sel);
        } else if (dn && !prev_dn) {
            opt_sel = (opt_sel + 1) % 3;
            draw_options_screen(opt_sel);
        } else if (ok && !prev_ok) {
            if (opt_sel == 0) {
                s_cfg.def_os = (s_cfg.def_os == 0) ? 1 : 0;
                draw_options_screen(opt_sel);
            } else if (opt_sel == 1) {
                int idx = 1;
                for (int k = 0; k < 4; ++k) {
                    if (kTimeouts[k] == s_cfg.timeout_ms) { idx = k; break; }
                }
                s_cfg.timeout_ms = kTimeouts[(idx + 1) % 4];
                draw_options_screen(opt_sel);
            } else {
                cfg_save();
                nv3023_fill_rect(0, 0, LCD_WIDTH, LCD_HEIGHT, COL_BG);
                return;
            }
        }
        prev_up = up;
        prev_dn = dn;
        prev_ok = ok;
        vTaskDelay(pdMS_TO_TICKS(25));
    }
}

void app_main(void)
{
    init_gpio_early();
    cfg_load();

    probe_slot(0, ESP_PARTITION_SUBTYPE_APP_OTA_0);
    probe_slot(1, ESP_PARTITION_SUBTYPE_APP_OTA_1);

    // Ensure default OS points to a populated slot if only one exists
    if (!s_slots[s_cfg.def_os].valid && s_slots[1 - s_cfg.def_os].valid) {
        s_cfg.def_os = 1 - s_cfg.def_os;
    }

    bool any_key_held = btn_raw_down(PIN_BTN_BOOT) || btn_raw_down(PIN_BTN_VOL_UP) || btn_raw_down(PIN_BTN_VOL_DOWN);
    if (s_cfg.timeout_ms == 0 && !any_key_held && (s_slots[0].valid || s_slots[1].valid)) {
        boot_slot(s_cfg.def_os, false);
    }

    nv3023_init();
    nv3023_fill_rect(0, 0, LCD_WIDTH, LCD_HEIGHT, COL_BG);

    int sel = s_cfg.def_os;
    bool countdown = (s_cfg.timeout_ms > 0) && !any_key_held && (s_slots[0].valid || s_slots[1].valid);
    int64_t deadline_us = esp_timer_get_time() + (int64_t)s_cfg.timeout_ms * 1000LL;
    int last_drawn_tenths = -1;

    draw_main_menu(sel, countdown, (int)s_cfg.timeout_ms);
    nv3023_backlight(true);

    // Wait for initial held keys to release before processing clicks
    bool prev_up = btn_raw_down(PIN_BTN_VOL_UP);
    bool prev_dn = btn_raw_down(PIN_BTN_VOL_DOWN);
    bool prev_ok = btn_raw_down(PIN_BTN_BOOT);

    while (true) {
        bool up = btn_raw_down(PIN_BTN_VOL_UP);
        bool dn = btn_raw_down(PIN_BTN_VOL_DOWN);
        bool ok = btn_raw_down(PIN_BTN_BOOT);

        if ((up && !prev_up) || (dn && !prev_dn)) {
            countdown = false;
            if (up && !prev_up) {
                sel = (sel + 2) % 3;
            } else {
                sel = (sel + 1) % 3;
            }
            draw_main_menu(sel, false, 0);
        } else if (ok && !prev_ok) {
            if (sel == 2) {
                countdown = false;
                run_options_menu();
                sel = s_cfg.def_os;
                draw_main_menu(sel, false, 0);
            } else if (s_slots[sel].valid) {
                boot_slot(sel, true);
            }
        }

        if (countdown) {
            int64_t rem_us = deadline_us - esp_timer_get_time();
            if (rem_us <= 0) {
                boot_slot(s_cfg.def_os, true);
            }
            int rem_ms = (int)(rem_us / 1000);
            int tenths = (rem_ms + 99) / 100;
            if (tenths != last_drawn_tenths) {
                last_drawn_tenths = tenths;
                update_countdown_bar_only(rem_ms);
            }
        }

        prev_up = up;
        prev_dn = dn;
        prev_ok = ok;
        vTaskDelay(pdMS_TO_TICKS(25));
    }
}
