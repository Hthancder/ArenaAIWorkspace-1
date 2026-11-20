idf_component_register(
    SRCS "main.c" "nv3023.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES driver esp_partition app_update esp_app_format heap esp_system nvs_flash esp_timer esp_hw_support soc
)
