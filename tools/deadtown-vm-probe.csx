// Experimental feasibility probe only. This does NOT reconstruct a playable game.
// Requires UndertaleModTool 0.9.2.0 and the supplied APK's unmodified game.droid.
using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
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
var sourceScriptNames = new HashSet<string>(paths.Select(Path.GetFileNameWithoutExtension), StringComparer.Ordinal);
var apkScriptNames = new HashSet<string>(Data.Scripts.Select(x => x.Name.Content), StringComparer.Ordinal);
Console.WriteLine($"PROBE: attempting {paths.Length} staged offline source scripts; APK scripts absent from source={apkScriptNames.Except(sourceScriptNames).Count()}, source scripts absent from APK={sourceScriptNames.Except(apkScriptNames).Count()}");
var group = new CodeImportGroup(Data);
foreach (string script in paths)
    group.QueueReplace("gml_Script_" + Path.GetFileNameWithoutExtension(script), File.ReadAllText(script));

// Probe the translated event bodies without attaching them: version/ID
// compatibility and drag-and-drop semantic equivalence are still unverified.
string objectsDir = Path.Combine(Directory.GetParent(Path.GetDirectoryName(path)).FullName, "objects");
var objectFiles = Directory.GetFiles(objectsDir, "*.object.gmx");
var sourceObjectNames = new HashSet<string>(objectFiles.Select(x => Path.GetFileName(x).Replace(".object.gmx", "")), StringComparer.Ordinal);
var apkObjectNames = new HashSet<string>(Data.GameObjects.Select(x => x.Name.Content), StringComparer.Ordinal);
Console.WriteLine($"PROBE: APK objects absent from source={apkObjectNames.Except(sourceObjectNames).Count()}, source objects absent from APK={sourceObjectNames.Except(apkObjectNames).Count()}");
string eventsPath = Environment.GetEnvironmentVariable("GML_PROBE_EVENTS");
if (string.IsNullOrEmpty(eventsPath)) throw new Exception("GML_PROBE_EVENTS is not set");
using var document = JsonDocument.Parse(File.ReadAllText(eventsPath));
int selected = 0;
foreach (var evt in document.RootElement.EnumerateArray())
{
    string objectName = evt.GetProperty("object").GetString();
    string text = evt.GetProperty("gml").GetString();
    var code = UndertaleCode.CreateEmptyEntry(Data, "probe_" + objectName + "_" + selected);
    group.QueueReplace(code, text);
    selected++;
}
Console.WriteLine($"PROBE: compiling {selected} translated event bodies; event behavior is not yet verified");
var result = group.Import(false);
Console.WriteLine($"PROBE: compile_success={result.Successful}, code_entries={Data.Code.Count}, variables={Data.Variables.Count}, functions={Data.Functions.Count}");
if (!result.Successful)
{
    foreach (var error in result.Errors)
        Console.WriteLine("PROBE_ERROR: " + error.Code.Name.Content + ": " + error.GenerateDetailedMessage().Replace('\n', ' '));
    throw new Exception("Probe compilation failed");
}
Console.WriteLine("PROBE: scripts and selected event bodies compiled in memory, with no event bindings or playable game or IPA");
