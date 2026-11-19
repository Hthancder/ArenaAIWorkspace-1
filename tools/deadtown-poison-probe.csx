// Research instrumentation for a COPY of the candidate VM data only.
// Never use the resulting data for an IPA, release, or user saves. This checks
// the reconstructed candidate on desktop gmrunner, not the original APK.
using System;
using System.IO;
using System.Text.Json;
using UndertaleModLib;
using UndertaleModLib.Compiler;

EnsureDataLoaded();
string path = Environment.GetEnvironmentVariable("GML_PROBE_EVENTS");
if (string.IsNullOrEmpty(path)) throw new Exception("GML_PROBE_EVENTS is not set");
var doc = JsonDocument.Parse(File.ReadAllText(path));
int index = 0, createCount = 0, stepCount = 0, transferCount = 0;
var group = new CodeImportGroup(Data);
foreach (var evt in doc.RootElement.EnumerateArray())
{
    string obj = evt.GetProperty("object").GetString();
    var attr = evt.GetProperty("attributes");
    string type = attr.GetProperty("eventtype").GetString();
    JsonElement num;
    string number = attr.TryGetProperty("enumb", out num) ? num.GetString() : "";
    string body = evt.GetProperty("gml").GetString();
    string prefix = "", suffix = "";
    if (obj == "obj_player" && type == "0" && number == "0")
    {
        createCount++;
        suffix = @"
// Disposable diagnostic state, not game behavior.
dt_poison_probe_tick = 0;
";
    }
    else if (obj == "obj_player" && type == "3" && number == "0")
    {
        stepCount++;
        // Measure only the poison-damage block before hunger/healing modifies HP.
        // Scaling the delta avoids loss from the runner's string formatting.
        string damageStart = "if 0 < buff_poison\n{\n    if rpg_skill_get_level(20)";
        string damageEnd = "\nif 0<hungry\n{";
        if (body.Split(new string[] { damageStart }, StringSplitOptions.None).Length != 2 ||
            body.Split(new string[] { damageEnd }, StringSplitOptions.None).Length != 2)
            throw new Exception("Unexpected candidate poison damage block");
        body = body.Replace(damageStart, @"
if dt_poison_probe_tick >= 10 && dt_poison_probe_tick <= 13
    dt_hp_before_poison = hp;
" + damageStart);
        body = body.Replace(damageEnd, @"
if dt_poison_probe_tick >= 10 && dt_poison_probe_tick <= 13
    show_debug_message(""DT_POISON|damage|"" + string(dt_poison_probe_tick + 1) + ""|"" + string(rpg_skill_get_level(20)) + ""|"" + string(buff_poison_hurt * 4500) + ""|"" + string((dt_hp_before_poison - hp) * 4500));
" + damageEnd);
        suffix = @"
// Forced scenario, intentionally not a substitute for original APK testing.
dt_poison_probe_tick += 1;
if (dt_poison_probe_tick == 1)
{
    buff_poison = 20;
    buff_poison_protect = 0;
    hp = 80;
    hungry = 100;
    if ds_map_exists(global.inven_use, 20) ds_map_delete(global.inven_use, 20);
    ds_map_add(global.inven_use, 20, 1);
    item_use(20);
    show_debug_message(""DT_POISON|use|"" + string(global.use_db[20,9]) + ""|"" + string(ds_map_exists(global.inven_use,20)) + ""|"" + string(instance_number(obj_player)));
}
if (dt_poison_probe_tick >= 2 && dt_poison_probe_tick <= 9)
{
    show_debug_message(""DT_POISON|state|"" + string(dt_poison_probe_tick) + ""|"" + string(buff_poison_protect) + ""|"" + string(buff_poison) + ""|"" + string(hp));
}
if (dt_poison_probe_tick == 4) { buff_poison_protect = 20000; buff_poison = 20; }
if (dt_poison_probe_tick == 6)
{
    // Test an existing stack separately from the one-item mask.
    if ds_map_exists(global.inven_use, 0) ds_map_delete(global.inven_use, 0);
    ds_map_add(global.inven_use, 0, 2);
    item_use(0);
    show_debug_message(""DT_POISON|stack|"" + string(ds_map_find_value(global.inven_use,0)));
    buff_poison_protect = 1;
    buff_poison = 20;
}
if (dt_poison_probe_tick == 7) { buff_poison = 2; }
if (dt_poison_probe_tick == 10)
{
    buff_poison = 2;
    buff_poison_protect = 321;
    show_debug_message(""DT_POISON|save_start"");
    game_save_protect(""dt_poison_probe.sav"");
    show_debug_message(""DT_POISON|save_done|"" + string(file_exists(""dt_poison_probe.sav"")));
    buff_poison = 0;
    buff_poison_protect = 0;
    var dt_load_result = game_load_protect(""dt_poison_probe.sav"");
    show_debug_message(""DT_POISON|load_done|"" + string(dt_load_result) + ""|"" + string(buff_poison_protect) + ""|"" + string(buff_poison));
    // Prepare two isolated poison-damage blocks, with and without skill 20.
    global.skill_level[20] = 0;
    buff_poison = 20;
    buff_poison_protect = 0;
    hp = 80;
}
if (dt_poison_probe_tick == 11)
{
    global.skill_level[20] = 1;
    buff_poison = 20;
    buff_poison_protect = 0;
    hp = 80;
}
if (dt_poison_probe_tick == 12)
{
    // Observe order when poison and protection coexist, then next step.
    global.skill_level[20] = 0;
    buff_poison = 20;
    buff_poison_protect = 2;
    hp = 80;
}
if (dt_poison_probe_tick == 14) buff_poison = 0;
";
    }
    else if (obj == "sys_player_buff" && type == "3" && number == "2")
    {
        transferCount++;
        prefix = @"
if buff_poison_protect > 0
    show_debug_message(""DT_POISON|transfer|"" + string(buff_poison_protect));
";
    }
    if (prefix.Length != 0 || suffix.Length != 0)
    {
        string name = "probe_" + obj + "_" + index;
        var code = Data.Code.ByName(name) ?? throw new Exception("Expected probe code missing: " + name);
        group.QueueReplace(code, prefix + "\n" + body + "\n" + suffix);
        Console.WriteLine("POISON_INSTRUMENT: " + name);
    }
    index++;
}
doc.Dispose();
if (createCount != 1 || stepCount != 1 || transferCount != 1)
    throw new Exception($"Unexpected event counts: create={createCount} step={stepCount} transfer={transferCount}");
string source = Environment.GetEnvironmentVariable("GML_PROBE_SOURCE");
if (string.IsNullOrEmpty(source)) throw new Exception("GML_PROBE_SOURCE is not set");
var itemCode = Data.Code.ByName("gml_Script_item_use") ?? throw new Exception("item_use code missing");
string itemText = File.ReadAllText(Path.Combine(Path.GetDirectoryName(source), "item_use.gml"));
string itemBefore = @"
show_debug_message(""DT_POISON|item_enter|"" + string(argument0) + ""|"" + string(global.inven_use) + ""|"" + string(ds_map_find_value(global.inven_use,argument0)));
";
string itemAfter = @"
show_debug_message(""DT_POISON|item_exit|"" + string(ds_map_exists(global.inven_use,argument0)) + ""|"" + string(ins.buff_poison_protect));
";
group.QueueReplace(itemCode, itemBefore + "\n" + itemText + "\n" + itemAfter);
Console.WriteLine("POISON_INSTRUMENT: item_use");
// Compile the untouched old-source script into an UNLINKED scratch code entry
// for bytecode analysis. Never invoke it in the candidate gameplay probe.
string legacyPath = Environment.GetEnvironmentVariable("GML_PROBE_LEGACY_ITEM");
if (string.IsNullOrEmpty(legacyPath)) throw new Exception("GML_PROBE_LEGACY_ITEM is not set");
var legacy = UndertaleCode.CreateEmptyEntry(Data, "probe_item_use_legacy_unlinked");
group.QueueReplace(legacy, File.ReadAllText(legacyPath));
Console.WriteLine("POISON_INSTRUMENT: legacy item_use for bytecode comparison only");
var result = group.Import(false);
if (!result.Successful)
{
    foreach (var error in result.Errors) Console.WriteLine("POISON_INSTRUMENT_ERROR: " + error.GenerateDetailedMessage());
    throw new Exception("Failed to compile poison diagnostic");
}
Console.WriteLine("POISON_INSTRUMENT: disposable desktop VM only; never ship as a game or IPA");
