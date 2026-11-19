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
if (dt_poison_probe_tick == 6) { buff_poison_protect = 1; buff_poison = 20; }
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
}
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
var result = group.Import(false);
if (!result.Successful)
{
    foreach (var error in result.Errors) Console.WriteLine("POISON_INSTRUMENT_ERROR: " + error.GenerateDetailedMessage());
    throw new Exception("Failed to compile poison diagnostic");
}
Console.WriteLine("POISON_INSTRUMENT: disposable desktop VM only; never ship as a game or IPA");
