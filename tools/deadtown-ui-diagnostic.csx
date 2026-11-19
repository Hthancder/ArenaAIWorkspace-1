// Diagnostic only: instruments a COPY of the incomplete VM game, not an IPA.
// Requires UndertaleModTool 0.9.2.0, the events.json generated from the same
// offline GMX inputs, and data.win from the matching VM probe.
using System;
using System.IO;
using System.Text.Json;
using UndertaleModLib;
using UndertaleModLib.Compiler;

EnsureDataLoaded();
string path = Environment.GetEnvironmentVariable("GML_PROBE_EVENTS");
if (string.IsNullOrEmpty(path)) throw new Exception("GML_PROBE_EVENTS is not set");
var doc = JsonDocument.Parse(File.ReadAllText(path));
int index = 0, found = 0;
foreach (var evt in doc.RootElement.EnumerateArray())
{
    var attr = evt.GetProperty("attributes");
    if (evt.GetProperty("object").GetString() == "sys_view" &&
        attr.GetProperty("eventtype").GetString() == "0" && attr.GetProperty("enumb").GetString() == "0")
    {
        found++;
        string name = "probe_sys_view_" + index;
        var code = Data.Code.ByName(name) ?? throw new Exception("Expected code missing: " + name);
        string body = evt.GetProperty("gml").GetString();
        string trace = @"
show_debug_message(""DT_COORDS display="" + string(display_get_width()) + ""x"" + string(display_get_height())
    + "" gui="" + string(display_get_gui_width()) + ""x"" + string(display_get_gui_height())
    + "" window="" + string(window_get_width()) + ""x"" + string(window_get_height())
    + "" viewport="" + string(view_wport[0]) + ""x"" + string(view_hport[0])
    + "" os_type="" + string(os_type));
";
        var group = new CodeImportGroup(Data);
        group.QueueReplace(code, body + "\n" + trace);
        var result = group.Import(false);
        if (!result.Successful)
        {
            foreach (var error in result.Errors) Console.WriteLine(error.GenerateDetailedMessage());
            throw new Exception("Could not compile diagnostic event");
        }
        Console.WriteLine("UI_DIAGNOSTIC: instrumented " + name);
    }
    index++;
}
doc.Dispose();
if (found != 1) throw new Exception("Expected exactly one sys_view Create event, got " + found);
Console.WriteLine("UI_DIAGNOSTIC: data is instrumented and incomplete; never package or publish as a game");
