/// Candidate reconstructed from Android ARM32; first connected device only.
if (gamepad_is_supported())
{
    var __dt_gp_count, __dt_gp_index;
    __dt_gp_count = gamepad_get_device_count();
    for (__dt_gp_index = 0; __dt_gp_index < __dt_gp_count; __dt_gp_index += 1)
    {
        if (gamepad_is_connected(__dt_gp_index))
            return gamepad_button_check_released(__dt_gp_index, argument0);
    }
}
