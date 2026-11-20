// Disposable incomplete-VM diagnostic, NEVER for a game/IPA or user saves.
// Compares the old source lang_get against a candidate fallback inferred from
// static APK ARM evidence. It does not execute the original APK.
using System;
using System.IO;
using System.Text.Json;
using UndertaleModLib;
using UndertaleModLib.Compiler;

EnsureDataLoaded();
string mode = Environment.GetEnvironmentVariable("LANG_PROBE_MODE");
if (mode != "legacy" && mode != "candidate" && mode != "candidate_native_table") throw new Exception("Unexpected LANG_PROBE_MODE");
string events = Environment.GetEnvironmentVariable("GML_PROBE_EVENTS");
if (string.IsNullOrEmpty(events)) throw new Exception("GML_PROBE_EVENTS is not set");
var group = new CodeImportGroup(Data);
if (mode != "legacy")
{
    var code = Data.Code.ByName("gml_Script_lang_get") ?? throw new Exception("lang_get missing");
    // This only covers source language selectors 0..3 and a map-existence
    // fallback. Global registration and native runtime are NOT proven.
    group.QueueReplace(code, @"
switch(global.language_type)
{
    case 0: return argument0;
    case 1:
        if ds_map_exists(global.language_map_korean, argument0)
            return ds_map_find_value(global.language_map_korean, argument0);
        return argument0;
    case 2:
        if ds_map_exists(global.language_map_chinese, argument0)
            return ds_map_find_value(global.language_map_chinese, argument0);
        return argument0;
    case 3:
        if ds_map_exists(global.language_map_japanese, argument0)
            return ds_map_find_value(global.language_map_japanese, argument0);
        return argument0;
}
");
}
if (mode == "candidate_native_table")
{
    string nativeEvents = Environment.GetEnvironmentVariable("GML_PROBE_NATIVE_EVENTS");
    if (string.IsNullOrEmpty(nativeEvents)) throw new Exception("GML_PROBE_NATIVE_EVENTS is not set");
    var nativeDoc = JsonDocument.Parse(File.ReadAllText(nativeEvents));
    int nativeIndex = 0, nativeFound = 0;
    foreach (var evt in nativeDoc.RootElement.EnumerateArray())
    {
        var attr = evt.GetProperty("attributes");
        if (evt.GetProperty("object").GetString() == "sys_global" &&
            attr.GetProperty("eventtype").GetString() == "0" && attr.GetProperty("enumb").GetString() == "0")
        {
            nativeFound++;
            string name = "probe_sys_global_" + nativeIndex;
            var code = Data.Code.ByName(name) ?? throw new Exception("Expected sys_global probe missing: " + name);
            group.QueueReplace(code, evt.GetProperty("gml").GetString());
            Console.WriteLine("LANG_PROBE_INSTRUMENT: candidate native-table event " + name);
        }
        nativeIndex++;
    }
    nativeDoc.Dispose();
    if (nativeFound != 1) throw new Exception("Expected one candidate native-table event");
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
        string name = "probe_sys_view_" + index;
        var code = Data.Code.ByName(name) ?? throw new Exception("Expected probe event missing: " + name);
        string body = evt.GetProperty("gml").GetString();
        string trace = @"
// Forced synthetic keys; restored before the real event returns.
var dt_lang_old = global.language_type;
var dt_lang_key = ""__DT_LANG_KNOWN__"";
var dt_lang_empty = ""__DT_LANG_EMPTY__"";
var dt_lang_unknown = ""__DT_LANG_UNKNOWN__"";
if ds_map_exists(global.language_map_korean, dt_lang_key) || ds_map_exists(global.language_map_chinese, dt_lang_key) || ds_map_exists(global.language_map_japanese, dt_lang_key)
    show_debug_message(""DT_LANG_ERROR|known key exists"");
if ds_map_exists(global.language_map_korean, dt_lang_empty) || ds_map_exists(global.language_map_chinese, dt_lang_empty) || ds_map_exists(global.language_map_japanese, dt_lang_empty)
    show_debug_message(""DT_LANG_ERROR|empty key exists"");
if ds_map_exists(global.language_map_korean, dt_lang_unknown) || ds_map_exists(global.language_map_chinese, dt_lang_unknown) || ds_map_exists(global.language_map_japanese, dt_lang_unknown)
    show_debug_message(""DT_LANG_ERROR|missing key exists"");
ds_map_add(global.language_map_korean, dt_lang_key, ""KO"");
ds_map_add(global.language_map_chinese, dt_lang_key, ""ZH"");
ds_map_add(global.language_map_japanese, dt_lang_key, ""JA"");
ds_map_add(global.language_map_korean, dt_lang_empty, """");
ds_map_add(global.language_map_chinese, dt_lang_empty, """");
ds_map_add(global.language_map_japanese, dt_lang_empty, """");
for (var dt_lang_i = 0; dt_lang_i < 4; dt_lang_i += 1)
{
    global.language_type = dt_lang_i;
    var dt_lang_a = lang_get(dt_lang_key);
    var dt_lang_b = lang_get(dt_lang_empty);
    var dt_lang_c = lang_get(dt_lang_unknown);
    if is_undefined(dt_lang_c) dt_lang_c = ""<undefined>"";
    if is_undefined(dt_lang_a) dt_lang_a = ""<undefined>"";
    if is_undefined(dt_lang_b) dt_lang_b = ""<undefined>"";
    show_debug_message(""DT_LANG|"" + string(dt_lang_i) + ""|"" + string(dt_lang_a) + ""|"" + string(dt_lang_b) + ""|"" + string(dt_lang_c));
}
ds_map_delete(global.language_map_korean, dt_lang_key);
ds_map_delete(global.language_map_chinese, dt_lang_key);
ds_map_delete(global.language_map_japanese, dt_lang_key);
ds_map_delete(global.language_map_korean, dt_lang_empty);
ds_map_delete(global.language_map_chinese, dt_lang_empty);
ds_map_delete(global.language_map_japanese, dt_lang_empty);
global.language_type = dt_lang_old;
show_debug_message(""DT_LANG_DONE"");
";
        string tableTrace = "";
        if (mode == "candidate_native_table") tableTrace = @"
// Candidate table and duplicate-key behavior in this runner only.
var dt_table_old = global.language_type;
show_debug_message(""DT_LANG_TABLE|sizes|"" + string(ds_map_size(global.language_map_korean)) + ""|"" + string(ds_map_size(global.language_map_chinese)) + ""|"" + string(ds_map_size(global.language_map_japanese)));
global.language_type = 1;
show_debug_message(""DT_LANG_TABLE|ko|"" + string(lang_get(""Gas mask"")) + ""|"" + string(lang_get(""Splint"")) + ""|"" + string(lang_get(""Light machine gun"")) + ""|"" + string(lang_get(""Heavy machine gun"")));
global.language_type = 2;
show_debug_message(""DT_LANG_TABLE|zh|"" + string(ds_map_exists(global.language_map_chinese, ""Gas mask"")) + ""|"" + string(string_length(lang_get(""Gas mask""))));
global.language_type = 3;
show_debug_message(""DT_LANG_TABLE|ja|"" + string(ds_map_exists(global.language_map_japanese, ""Gas mask"")) + ""|"" + string(string_length(lang_get(""Gas mask""))));
global.language_type = dt_table_old;
// Write disposable runner-specific map serializations for independent checking.
// These files are never uploaded or used as game saves.
var dt_table_file = file_text_open_write(""dt_lang_ko.dat"");
file_text_write_string(dt_table_file, ds_map_write(global.language_map_korean));
file_text_close(dt_table_file);
dt_table_file = file_text_open_write(""dt_lang_zh.dat"");
file_text_write_string(dt_table_file, ds_map_write(global.language_map_chinese));
file_text_close(dt_table_file);
dt_table_file = file_text_open_write(""dt_lang_ja.dat"");
file_text_write_string(dt_table_file, ds_map_write(global.language_map_japanese));
file_text_close(dt_table_file);
show_debug_message(""DT_LANG_TABLE_DONE"");
";
        group.QueueReplace(code, body + "\n" + trace + "\n" + tableTrace);
        Console.WriteLine("LANG_PROBE_INSTRUMENT: " + mode + " " + name);
    }
    index++;
}
doc.Dispose();
if (found != 1) throw new Exception("Expected exactly one sys_view Create event");
var result = group.Import(false);
if (!result.Successful)
{
    foreach (var error in result.Errors) Console.WriteLine("LANG_PROBE_ERROR: " + error.GenerateDetailedMessage());
    throw new Exception("Could not compile language probe");
}
Console.WriteLine("LANG_PROBE_INSTRUMENT: disposable incomplete desktop VM only; never package or publish");
