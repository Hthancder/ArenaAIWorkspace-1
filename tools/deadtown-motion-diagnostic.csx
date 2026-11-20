// Instruments a COPY of old RE-test3 data for desktop research only.
// Not a fix, APK/iOS execution, complete game, or IPA input.
using System;
using System.IO;
using System.Text.Json;
using UndertaleModLib;
using UndertaleModLib.Compiler;

EnsureDataLoaded();
string path = Environment.GetEnvironmentVariable("GML_PROBE_EVENTS");
if (string.IsNullOrEmpty(path)) throw new Exception("GML_PROBE_EVENTS is not set");
var doc = JsonDocument.Parse(File.ReadAllText(path));
int index = 0, createCount = 0, endCount = 0;
var group = new CodeImportGroup(Data);
foreach (var evt in doc.RootElement.EnumerateArray())
{
    var attr = evt.GetProperty("attributes");
    string obj = evt.GetProperty("object").GetString();
    string type = attr.GetProperty("eventtype").GetString();
    JsonElement enumb;
    string number = attr.TryGetProperty("enumb", out enumb) ? enumb.GetString() : "";
    string suffix = "";
    if (obj == "obj_player" && type == "0" && number == "0")
    {
        createCount++;
        suffix = "\ndt_motion_tick = 0;\n";
    }
    if (obj == "obj_player" && type == "3" && number == "2")
    {
        endCount++;
        suffix = @"
// Isolated trace, never copied into a release build.
dt_motion_tick += 1;
if dt_motion_tick <= 65
{
    var dt_appw = -1, dt_apph = -1;
    if surface_exists(application_surface)
    {
        dt_appw = surface_get_width(application_surface);
        dt_apph = surface_get_height(application_surface);
    }
    show_debug_message(""DT_MOTION|"" + string(dt_motion_tick) + ""|"" + string(x) + ""|"" + string(y)
        + ""|"" + string(xprevious) + ""|"" + string(yprevious) + ""|"" + string(background_showcolor)
        + ""|"" + string(view_xview[0]) + ""|"" + string(view_yview[0]) + ""|"" + string(view_wview[0])
        + ""|"" + string(view_hview[0]) + ""|"" + string(view_angle[0]) + ""|"" + string(view_wport[0]) + ""|"" + string(view_hport[0])
        + ""|"" + string(view_visible[1]) + ""|"" + string(dt_appw) + ""|"" + string(dt_apph)
        + ""|"" + string(keyboard_check(ord(""D""))) + ""|"" + string(instance_number(obj_player)));
}
";
    }
    if (suffix != "")
    {
        string name = "probe_" + obj + "_" + index;
        var code = Data.Code.ByName(name) ?? throw new Exception("Expected code missing: " + name);
        group.QueueReplace(code, evt.GetProperty("gml").GetString() + suffix);
        Console.WriteLine("MOTION_INSTRUMENT: " + name);
    }
    index++;
}
doc.Dispose();
if (createCount != 1 || endCount != 1) throw new Exception("Unexpected player event counts");
var result = group.Import(false);
if (!result.Successful)
{
    foreach (var error in result.Errors) Console.WriteLine(error.GenerateDetailedMessage());
    throw new Exception("Could not compile motion diagnostic events");
}
Console.WriteLine("MOTION_INSTRUMENT: disposable desktop only; not an IPA");
