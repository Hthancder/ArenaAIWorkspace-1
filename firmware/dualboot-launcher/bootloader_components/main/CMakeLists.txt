idf_component_register(SRCS "bootloader_start.c"
                    REQUIRES bootloader bootloader_support)

idf_build_get_property(target IDF_TARGET)
set(target_folder "${target}")

set(scripts "${IDF_PATH}/components/bootloader/subproject/main/ld/${target_folder}/bootloader.ld"
            "${IDF_PATH}/components/bootloader/subproject/main/ld/${target_folder}/bootloader.rom.ld")

target_linker_script(${COMPONENT_LIB} INTERFACE "${scripts}")
