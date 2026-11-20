// Disposable old-source compiler-workaround diagnostic only, not an IPA.
using System;
using System.IO;
using System.Text.Json;
using UndertaleModLib;
using UndertaleModLib.Compiler;

EnsureDataLoaded();
string scripts = Environment.GetEnvironmentVariable("INVENTORY_PROBE_SCRIPTS");
string legacy = Environment.GetEnvironmentVariable("INVENTORY_PROBE_LEGACY");
string events = Environment.GetEnvironmentVariable("GML_PROBE_EVENTS");
if (string.IsNullOrEmpty(scripts) || string.IsNullOrEmpty(legacy) || string.IsNullOrEmpty(events))
    throw new Exception("Missing inventory probe inputs");
var group = new CodeImportGroup(Data);
foreach (string name in new string[] { "item_get", "item_drop", "item_equip", "item_make" })
{
    var current = Data.Code.ByName("gml_Script_" + name) ?? throw new Exception("Missing script " + name);
    group.QueueReplace(current, File.ReadAllText(Path.Combine(scripts, name + ".gml")));
    var old = UndertaleCode.CreateEmptyEntry(Data, "probe_" + name + "_old_unlinked");
    group.QueueReplace(old, File.ReadAllText(Path.Combine(legacy, name + ".gml")));
    Console.WriteLine("INVENTORY_INSTRUMENT: " + name);
}
var doc = JsonDocument.Parse(File.ReadAllText(events));
int index = 0, found = 0;
foreach (var evt in doc.RootElement.EnumerateArray())
{
    var attr = evt.GetProperty("attributes");
    if (evt.GetProperty("object").GetString() == "sys_view" &&
        attr.GetProperty("eventtype").GetString() == "0" && attr.GetProperty("enumb").GetString() == "0")
    {
        found++;
        var code = Data.Code.ByName("probe_sys_view_" + index) ?? throw new Exception("sys_view probe missing");
        string scenario = @"
// Fresh disposable map, restore handles afterward. Not original game execution.
var dt_old_use = global.inven_use;
var dt_old_weapon = global.inven_weapon;
var dt_old_equip = global.inven_equip;
var dt_old_etc = global.inven_etc;
var dt_old_equipped = global.equip_weapon;
var dt_had_weapon_instance = instance_exists(sys_player_weapon);
var dt_old_pointer = -1;
if dt_had_weapon_instance dt_old_pointer = sys_player_weapon.pointer;
var dt_old_null = global.inven_null;
var dt_old_lang = global.language_type;
var dt_old_messages = global.ui_message_number;
global.inven_use = ds_map_create();
global.inven_weapon = ds_map_create();
global.inven_equip = ds_map_create();
global.inven_etc = ds_map_create();
global.equip_weapon = -1;
global.inven_null = ds_map_create();
global.language_type = 0;
global.ui_message_number = 1;
item_get(3,0,2);
item_get(3,0,3);
show_debug_message(""DT_INV|get|"" + string(ds_map_find_value(global.inven_use,0)));
var dt_absent = item_drop(3,1);
var dt_drop = item_drop(3,0);
show_debug_message(""DT_INV|drop|"" + string(dt_absent) + ""|"" + string(dt_drop) + ""|"" + string(ds_map_find_value(global.inven_use,0)));
ds_map_replace(global.inven_use,0,1);
var dt_last = item_drop(3,0);
show_debug_message(""DT_INV|last|"" + string(dt_last) + ""|"" + string(ds_map_exists(global.inven_use,0)));
// Fractional stacks intentionally probe comparison tolerance, not normal gameplay.
var dt_old_epsilon = math_get_epsilon();
ds_map_add(global.inven_use,10,1.000001);
var dt_eps_default_return = item_drop(3,10);
var dt_eps_default_exists = ds_map_exists(global.inven_use,10);
math_set_epsilon(0.0000000001);
ds_map_add(global.inven_use,11,1.000001);
var dt_eps_small_return = item_drop(3,11);
var dt_eps_small_exists = ds_map_exists(global.inven_use,11);
math_set_epsilon(dt_old_epsilon);
show_debug_message(""DT_INV|epsilon|"" + string(round(dt_old_epsilon * 1000000)) + ""|"" + string(dt_eps_default_return) + ""|"" + string(dt_eps_default_exists) + ""|"" + string(dt_eps_small_return) + ""|"" + string(dt_eps_small_exists));
// Distinct keys show each of the four selector cases updates only its own map.
ds_map_add(global.inven_weapon,88,2); ds_map_add(global.inven_equip,88,2);
ds_map_add(global.inven_use,88,2); ds_map_add(global.inven_etc,88,2);
var dt_case1 = item_drop(1,88);
show_debug_message(""DT_INV|case1|"" + string(dt_case1) + ""|"" + string(ds_map_find_value(global.inven_weapon,88)) + ""|"" + string(ds_map_find_value(global.inven_equip,88)) + ""|"" + string(ds_map_find_value(global.inven_use,88)) + ""|"" + string(ds_map_find_value(global.inven_etc,88)));
var dt_case2 = item_drop(2,88);
var dt_case3 = item_drop(3,88);
var dt_case4 = item_drop(4,88);
show_debug_message(""DT_INV|cases234|"" + string(dt_case2) + ""|"" + string(dt_case3) + ""|"" + string(dt_case4) + ""|"" + string(ds_map_find_value(global.inven_weapon,88)) + ""|"" + string(ds_map_find_value(global.inven_equip,88)) + ""|"" + string(ds_map_find_value(global.inven_use,88)) + ""|"" + string(ds_map_find_value(global.inven_etc,88)));
// Force two weapon equips, including returning the previously equipped item.
ds_map_add(global.inven_weapon,0,1); ds_map_add(global.inven_weapon,1,2);
item_equip(1,0);
show_debug_message(""DT_INV|equip_first|"" + string(global.equip_weapon) + ""|"" + string(ds_map_exists(global.inven_weapon,0)) + ""|"" + string(sys_player_weapon.pointer));
item_equip(1,1);
show_debug_message(""DT_INV|equip_swap|"" + string(global.equip_weapon) + ""|"" + string(ds_map_find_value(global.inven_weapon,0)) + ""|"" + string(ds_map_find_value(global.inven_weapon,1)) + ""|"" + string(sys_player_weapon.pointer));
// A synthetic three-ingredient recipe, not an APK recipe.
var dt_recipe = 200;
global.craft_db[dt_recipe,0] = 0;
global.craft_db[dt_recipe,1] = 3; global.craft_db[dt_recipe,2] = 0; global.craft_db[dt_recipe,3] = 2;
global.craft_db[dt_recipe,4] = 3; global.craft_db[dt_recipe,5] = 1; global.craft_db[dt_recipe,6] = 1;
global.craft_db[dt_recipe,7] = 3; global.craft_db[dt_recipe,8] = 2; global.craft_db[dt_recipe,9] = 3;
global.craft_db[dt_recipe,10] = 3; global.craft_db[dt_recipe,11] = 3; global.craft_db[dt_recipe,12] = 2;
var dt_missing = item_make(dt_recipe);
ds_map_add(global.inven_use,0,1); ds_map_add(global.inven_use,1,2); ds_map_add(global.inven_use,2,3);
var dt_short = item_make(dt_recipe);
show_debug_message(""DT_INV|short|"" + string(dt_missing) + ""|"" + string(dt_short) + ""|"" + string(ds_map_find_value(global.inven_use,0)) + ""|"" + string(ds_map_find_value(global.inven_use,1)) + ""|"" + string(ds_map_find_value(global.inven_use,2)));
ds_map_replace(global.inven_use,0,2);
var dt_made = item_make(dt_recipe);
show_debug_message(""DT_INV|craft|"" + string(dt_made) + ""|"" + string(ds_map_exists(global.inven_use,0)) + ""|"" + string(ds_map_find_value(global.inven_use,1)) + ""|"" + string(ds_map_exists(global.inven_use,2)) + ""|"" + string(ds_map_find_value(global.inven_use,3)));
// Recipe with two optional, zero-quantity slots and existing output stack.
global.craft_db[dt_recipe,1] = 3; global.craft_db[dt_recipe,2] = 1; global.craft_db[dt_recipe,3] = 1;
global.craft_db[dt_recipe,4] = 0; global.craft_db[dt_recipe,5] = 0; global.craft_db[dt_recipe,6] = 0;
global.craft_db[dt_recipe,7] = 0; global.craft_db[dt_recipe,8] = 0; global.craft_db[dt_recipe,9] = 0;
global.craft_db[dt_recipe,12] = 1;
var dt_optional = item_make(dt_recipe);
show_debug_message(""DT_INV|optional|"" + string(dt_optional) + ""|"" + string(ds_map_exists(global.inven_use,1)) + ""|"" + string(ds_map_find_value(global.inven_use,3)));
ds_map_destroy(global.inven_use); ds_map_destroy(global.inven_weapon); ds_map_destroy(global.inven_equip); ds_map_destroy(global.inven_etc); ds_map_destroy(global.inven_null);
global.inven_use = dt_old_use; global.inven_weapon = dt_old_weapon; global.inven_equip = dt_old_equip; global.inven_etc = dt_old_etc; global.inven_null = dt_old_null;
global.equip_weapon = dt_old_equipped;
if dt_had_weapon_instance sys_player_weapon.pointer = dt_old_pointer;
else if instance_exists(sys_player_weapon) with (sys_player_weapon) instance_destroy();
global.language_type = dt_old_lang; global.ui_message_number = dt_old_messages;
show_debug_message(""DT_INV_DONE"");
";
        group.QueueReplace(code, evt.GetProperty("gml").GetString() + "\n" + scenario);
    }
    index++;
}
doc.Dispose();
if (found != 1) throw new Exception("Expected one sys_view Create");
var result = group.Import(false);
if (!result.Successful)
{
    foreach (var error in result.Errors) Console.WriteLine("INVENTORY_ERROR: " + error.GenerateDetailedMessage());
    throw new Exception("Inventory probe compile failed");
}
Console.WriteLine("INVENTORY_INSTRUMENT: incomplete disposable desktop VM only; never package");
