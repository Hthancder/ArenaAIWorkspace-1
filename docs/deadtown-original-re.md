# Dead Town 1.4.2: original APK investigation

This is an evidence inventory, not a recovery of the original source or a new IPA.
The current experimental build combines assets from the APK with code from a
separate GMX project and a third-party VM runner. A name match does not imply
that the compiled native function has the same contents or behavior as the GMX.

## Inputs and reproducibility

* APK: repository commit `8643abdda26944002384bc216bf555717a9e1e42`, file
  `Dead+Town+-+Zombie+survival_1.4.2_APKPure.apk`, SHA-256
  `bc8fa1990cb2cdde8d184f2a942fe4010820f0592d88a36e1cbee0a6aac081fb`.
* GMX: `kjs104901/deadtown` commit `5e3d798f914c8cd3b066c8289323005d63111f37`,
  directory `deadtown.gmx`. Comparison is against the unmodified source files,
  not against the offline-patched game.
* APK `assets/game.droid` SHA-256
  `0900da067462bd48040da6e217a86e2d5411397b05f07d55d13c58440b82a7b8`;
  `lib/armeabi-v7a/libyoyo.so` SHA-256
  `7f3895e245d83edc498859d0869017acf55ec1e92fc801cb734f7fe8315e1c23`.
* Reproduce the inventory on a machine with Python 3.9+ and GNU `nm` capable of
  reading ELF dynamic symbol tables:

  ```sh
  python tools/deadtown_native_inventory.py /path/to/original.apk \
      /path/to/deadtown/deadtown.gmx --output inventory.json
  ```

The JSON includes all names/event keys and native virtual addresses/sizes. It
contains no recovered game code. The tool treats collision subtype numbers as
APK object indices and reports any names it cannot resolve separately. Both
all-files and project-declared inventories are provided: the GMX directory has
extra, undeclared files, which the experimental VM probe also compiled.

## What the binary actually contains

The game uses GameMaker's **YYC** native compilation. The `CODE`, `VARI`, and
`FUNC` chunks of this APK's `game.droid` do not contain the original GML VM
program; executable game logic is in the Android ARM32 `libyoyo.so`. Its
exported symbol table retains 192 unique game script names and 859 unique
object-event names. The asset container lists 192 scripts, 240 objects and 15
rooms. This Android native library cannot simply be placed into the iOS ARM64
VM runner and executed as GameMaker bytecode.

## Source-to-APK comparison

The comparison below counts every GMX source file, including undeclared files,
so it corresponds to the input set used by the existing experimental probe.

| Inventory | APK / native | GMX files | Common keys |
| --- | ---: | ---: | ---: |
| Scripts | 192 exports | 138 files | 124 names |
| Objects | 240 resources | 165 files | 146 names |
| Object events | 859 exports | 539 event keys | 490 keys |
| Rooms | 15 resources | 7 declared | 7 names |

Thus 68 native script names, 94 APK object names, and 369 native event keys do
not have a corresponding GMX file or event key in this comparison. GMX also has
49 event keys not in the native exported set. `project_declared` has 124 scripts,
150 objects and 514 event keys; the same 490 event keys and 124 script names
match. Zero collision targets were unresolved in this input. The counts do not
prove that any matching implementations are equivalent.

The extra APK rooms are `rom_setting_display`, `rom_setting_effect`,
`rom_setting_save`, `rom_multi_login`, `rom_multi_lobby`, `rom_multi_room`,
`rom_play_sewer`, and `rom_play_defence`. Missing script names include
`item_grind`, `get_enchant_price`, `get_enchant_my_money`, the `gp_*` input
scripts, and sewer/defence save and load routines. Missing objects include
`obj_grinder`, `obj_enchanter`, save-slot controls, and defence objects. A name
alone does not establish which feature works or how it works.

## A deeper look, and what remains uncertain

ARM disassembly confirms the retained names refer to actual native functions,
not recoverable GML source. `sys_global` Create is about 517 KB of native code;
static callsite inspection indicates it contains substantially more `lang_add`
and database-add callsites than the GMX's corresponding Create event. Counting
calls in a disassembly that includes ARM literal pools is only an estimate, not
an extraction of data entries or proof of dynamic behavior. `sys_view` Step
contains calls to native `gp_*` scripts absent in the GMX; `sys_UI` Draw GUI
calls enchant-related scripts absent in the GMX. Their calling semantics and
full control flow have not been reconstructed.

The user screenshot shows an on-screen virtual gamepad and text starting with
`str...`; it is not proof of the original game's intended UI. The gamepad is
provided by the third-party runner, not evidence of the original APK's layout.
The landscape test's new-install default hides that overlay, but an update
retains existing config. `lang_get` in GMX returns the English key for language
0 and uses maps for other languages; the native function has a broadly similar
switch, but the cause of the screenshot's `str...` text has **not** been
established. Neither localization failure nor debug text should be claimed as
the cause without tracing the exact string through the running test build.

The previous experimental probe linked only 504 GMX events and cleared 68
unresolved native code IDs to serialize its VM data. It rendered screenshots
on desktop and ran on the user's iOS device, but that is not a reconstruction of
the original behavior, nor validation of touch, progression or visual fidelity.
The prior 90 audio payloads were extracted byte-for-byte without transcoding.

## Next investigation stages

1. Trace the `str...` values in the test build from creation to rendering,
   checking serialized strings and runner VM string/reference behavior first.
2. Extract and validate original static tables and call arguments from native
   code (translation and item databases), preserving addresses and comparing
   individual entries rather than trusting callsite counts.
3. Recover or manually reimplement the missing single-player event/script logic
   in priority order (startup/lobby, player controls/UI, items, saving, gameplay)
   and compare against original Android behavior and screenshots at each stage.
4. Only after equivalent behavior is evidenced, integrate offline/no-ad changes,
   retest on an iOS device and publish a new test. Multiplayer and server-backed
   features cannot be promised as offline equivalents. Unlocks and mod support
   also remain unverified.

This is substantial reverse engineering and may require manual reimplementation;
there is no proven automatic route from this APK's Android native code to a
faithful iOS IPA.
