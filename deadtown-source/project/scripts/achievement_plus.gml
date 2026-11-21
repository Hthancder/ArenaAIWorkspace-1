global.achievement_info[argument0,0] += 1

if global.achievement_info[argument0,1] < global.achievement_info[argument0,0]
{
    global.achievement_info[argument0,0] = global.achievement_info[argument0,1]
}


// Offline: retain local progress without posting.

achievement_save()
