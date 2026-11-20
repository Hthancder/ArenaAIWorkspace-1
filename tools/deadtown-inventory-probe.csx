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
var dt_old_null = global.inven_null;
var dt_old_lang = global.language_type;
var dt_old_messages = global.ui_message_number;
global.inven_use = ds_map_create();
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
ds_map_destroy(global.inven_use); ds_map_destroy(global.inven_null);
global.inven_use = dt_old_use; global.inven_null = dt_old_null;
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
