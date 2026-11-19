// Experimental feasibility probe only. This does NOT reconstruct a playable game.
// Requires UndertaleModTool 0.9.2.0 and the supplied APK's unmodified game.droid.
using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using UndertaleModLib;
using UndertaleModLib.Models;
using UndertaleModLib.Compiler;

EnsureDataLoaded();
Console.WriteLine($"PROBE: YYC={Data.IsYYC()}, bytecode={Data.GeneralInfo.BytecodeVersion}, scripts={Data.Scripts.Count}, objects={Data.GameObjects.Count}, rooms={Data.Rooms.Count}");
if (!Data.IsYYC()) throw new Exception("Expected an unmodified YYC container");

// Empty YYC chunks have no bytecode tables; creating tables here is only an
// experiment, and does not convert the missing compiled native game logic.
Data.FORM.CODE.List = new UndertalePointerList<UndertaleCode>();
Data.FORM.VARI.List = new List<UndertaleVariable>();
Data.FORM.FUNC.Functions = new UndertaleSimpleList<UndertaleFunction>();
Data.FORM.FUNC.CodeLocals = new UndertaleSimpleList<UndertaleCodeLocals>();

string path = Environment.GetEnvironmentVariable("GML_PROBE_SOURCE");
if (string.IsNullOrEmpty(path)) throw new Exception("GML_PROBE_SOURCE is not set");
var paths = Directory.GetFiles(Path.GetDirectoryName(path), "*.gml");
Array.Sort(paths, StringComparer.Ordinal);
Console.WriteLine($"PROBE: attempting {paths.Length} staged offline source scripts");
var group = new CodeImportGroup(Data);
foreach (string script in paths)
    group.QueueReplace("gml_Script_" + Path.GetFileNameWithoutExtension(script), File.ReadAllText(script));

// Probe a conservative subset of event code separately. Do not attach events to
// the APK objects: matching object and room versions is still unresolved.
string objectsDir = Path.Combine(Directory.GetParent(Path.GetDirectoryName(path)).FullName, "objects");
int selected = 0, skipped = 0;
foreach (string filename in Directory.GetFiles(objectsDir, "*.object.gmx").OrderBy(x => x, StringComparer.Ordinal))
{
    string objectName = Path.GetFileName(filename).Replace(".object.gmx", "");
    var events = XDocument.Load(filename).Root.Element("events")?.Elements("event");
    if (events == null) continue;
    foreach (var evt in events)
    {
        var actions = evt.Elements("action").ToArray();
        if (actions.Length != 1 || (string)actions[0].Element("id") != "603" ||
            (string)actions[0].Element("whoName") != "self") { skipped++; continue; }
        var text = actions[0].Element("arguments")?.Element("argument")?.Element("string")?.Value;
        if (text == null) { skipped++; continue; }
        var code = UndertaleCode.CreateEmptyEntry(Data, "probe_" + objectName + "_" + selected);
        group.QueueReplace(code, text);
        selected++;
    }
}
Console.WriteLine($"PROBE: compiling {selected} single-action events, skipped {skipped} multi-action or unsupported events");
var result = group.Import(false);
Console.WriteLine($"PROBE: compile_success={result.Successful}, code_entries={Data.Code.Count}, variables={Data.Variables.Count}, functions={Data.Functions.Count}");
if (!result.Successful)
{
    foreach (var error in result.Errors)
        Console.WriteLine("PROBE_ERROR: " + error.Code.Name.Content + ": " + error.GenerateDetailedMessage().Replace('\n', ' '));
    throw new Exception("Probe compilation failed");
}
Console.WriteLine("PROBE: scripts and selected event bodies compiled in memory, with no event bindings or playable game or IPA");
