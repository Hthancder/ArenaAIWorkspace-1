/// Candidate restored from Android ARM32; numeric locals are invented names.
var __dt_angle, __dt_distance, __dt_frame;
__dt_angle = point_direction(argument0, argument1, argument2, argument3);
__dt_distance = point_distance(argument0, argument1, argument2, argument3);
__dt_frame = 0;
if (__dt_distance > 100)
{
    __dt_frame = 1;
}
draw_sprite_ext(spr_crosshair, __dt_frame, argument0, argument1, __dt_distance / 100, 1, __dt_angle, draw_get_colour(), draw_get_alpha());
