/*
 * Custom 2nd-stage Dual-Boot bootloader for DSolution 1.83" 2-Mic (ESP32-S3).
 *
 * Boot selection flow via RTC_CNTL_STORE5_REG (survives software esp_restart(),
 * cleared on power-on, brownout, external reset pin, and after reading):
 *   - 0xD8000000U -> boot ota_0 (XiaoZhi HeyLily) directly
 *   - 0xD8000001U -> boot ota_1 (Bruce Firmware) directly
 *   - anything else (cold power-on, hardware Reset, app restart) -> boot factory
 *     Dual-Boot Menu (if present), otherwise fall back to standard otadata rules.
 */
#include <stdbool.h>
#include "sdkconfig.h"
#include "esp_log.h"
#include "esp_rom_sys.h"
#include "esp_rom_caps.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "bootloader_init.h"
#include "bootloader_utility.h"
#include "bootloader_common.h"

#define DUALBOOT_RTC_REG       RTC_CNTL_STORE5_REG
#define DUALBOOT_MAGIC_MASK    0xFFFFFFF0U
#define DUALBOOT_MAGIC_BASE    0xD8000000U

static const char *TAG = "dualboot";

static int select_partition_number(bootloader_state_t *bs);
static int selected_boot_partition(const bootloader_state_t *bs);

void __attribute__((noreturn)) call_start_cpu0(void)
{
    if (bootloader_init() != ESP_OK) {
        bootloader_reset();
    }

#ifdef CONFIG_BOOTLOADER_SKIP_VALIDATE_IN_DEEP_SLEEP
    bootloader_utility_load_boot_image_from_deep_sleep();
#endif

    bootloader_state_t bs = {0};
    int boot_index = select_partition_number(&bs);
    if (boot_index == INVALID_INDEX) {
        bootloader_reset();
    }

    bootloader_utility_load_boot_image(&bs, boot_index);
}

static int select_partition_number(bootloader_state_t *bs)
{
    if (!bootloader_utility_load_partition_table(bs)) {
        ESP_LOGE(TAG, "load partition table error!");
        return INVALID_INDEX;
    }
    return selected_boot_partition(bs);
}

static int selected_boot_partition(const bootloader_state_t *bs)
{
    uint32_t magic = REG_READ(DUALBOOT_RTC_REG);
    // Clear one-shot handoff token immediately so a subsequent reset/crash returns to menu
    REG_WRITE(DUALBOOT_RTC_REG, 0);

    if (esp_rom_get_reset_reason(0) != RESET_REASON_CORE_DEEP_SLEEP) {
        if ((magic & DUALBOOT_MAGIC_MASK) == DUALBOOT_MAGIC_BASE) {
            uint32_t slot = magic & 0x0FU;
            if (slot < MAX_OTA_SLOTS && bs->ota[slot].offset != 0) {
                return (int)slot;
            }
        }
        // Cold boot, Reset button, or ordinary app restart -> show Dual-Boot Menu
        if (bs->factory.offset != 0) {
            return FACTORY_INDEX;
        }
    }

    return bootloader_utility_get_selected_boot_partition(bs);
}

struct _reent *__getreent(void)
{
    return _GLOBAL_REENT;
}
