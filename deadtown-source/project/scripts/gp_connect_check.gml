/// Partial Android ARM32 candidate; slot 88 has a neutral, invented alias.
var __dt_gp_result, __dt_gp_count, __dt_gp_index;
__dt_gp_result = 0;
// Native compares os_type to numeric 4 and converts slot 88 to int before > 0.
if (os_type == 4 && global.__dt_setting_gamepad >= 1 && gamepad_is_supported())
{
    __dt_gp_count = gamepad_get_device_count();
    for (__dt_gp_index = 0; __dt_gp_index < __dt_gp_count; __dt_gp_index += 1)
    {
        if (gamepad_is_connected(__dt_gp_index))
        {
            gamepad_set_axis_deadzone(__dt_gp_index, 0.2);
            __dt_gp_result = 1;
        }
    }
}
return __dt_gp_result;
