ini_open("setting.ini")

ini_write_real("setting","check",1)

ini_write_real("sound","effect",global.setting_sound_effect)
ini_write_real("sound","bgm",global.setting_bgm)

ini_write_real("ui","size",global.setting_ui)

ini_write_real("left","size",global.setting_left_size)
ini_write_real("left","pos",global.setting_left_pos)

ini_write_real("left","relative",global.setting_left_relative)

ini_write_real("right","size",global.setting_right_size)
ini_write_real("right","pos",global.setting_right_pos)

// Partial native candidates: neutral aliases for unidentified global names.
ini_write_real("feedback","feedback",global.__dt_setting_feedback)
ini_write_real("effect","interpolate",global.__dt_setting_interpolate)
ini_write_real("effect","soundeffect",global.__dt_setting_soundeffect)
ini_write_real("effect","crosshair",global.__dt_setting_crosshair)
ini_write_real("effect","shadow",global.__dt_setting_shadow)
ini_write_real("left","finger",global.__dt_setting_finger)
ini_write_real("effect","particle",global.__dt_setting_particle)
ini_write_real("control","gamepad",global.__dt_setting_gamepad)
ini_write_real("lang","type",global.setting_lang)

ini_close()
