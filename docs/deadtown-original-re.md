# Dead Town 1.4.2: original APK investigation

Vietnamese consolidated handoff and current readiness gate:
[`deadtown-ho-so-phuc-hoi.md`](deadtown-ho-so-phuc-hoi.md).

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
retains existing config.

The GMX's `sys_UI` KeyPress event 81 (Q) contains exactly
`ui_message_type("str:"+string(random(100000)))`. It puts a random debug
message into the same on-screen queue used by item pickups, which the screenshot
closely resembles. The exported native event list has no `sys_UI:KeyPress:81`.
The experimental build linked this source-only event, and the runner can map
virtual buttons to detected keyboard keys. That makes the event a strong
explanation; without input tracing on the pictured iPhone, the exact input path
and screenshot version remain unconfirmed. Names such as `Shotgun ammo X9` are
normal messages produced by the old source's `item_get`, not this debug string.
The offline preparation now removes only the precisely checked Q event from its
copy; it leaves `ui_message_type`, item messages and other events intact. In
[probe run 44517643086](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44517643086),
a forced gameplay transition followed by a scripted Q press caused the old
build to call `draw_text_transformed` with `str:43680.18`; the patched build
made no `str:` draw call in the same test. This does not reproduce the iPhone
touch path or prove that all `str:` reports have this cause.

An isolated [RE test 3 IPA](https://github.com/Hthancder/ArenaAIWorkspace-1/releases/tag/deadtown-ios15-re-test-3)
was packaged in [run 44517874289](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44517874289)
using the tested data. It has a different bundle ID, so it installs separately
and does not overwrite the previous app's saves/config/mods. Saves do not move
across automatically. It remains an incomplete experiment, not a faithful
port, and has not been tested on an iPhone. The extracted translation candidates
below are not inserted into this test.

### Candidate original translation literals

`tools/deadtown_native_lang.py` scans the pinned library for a specific ARM/GOT
pattern in `sys_global` Create. It resolves C string symbols used by four
successive `YYSetString` calls before a `lang_add` call, then records addresses,
symbols and candidate strings. With this particular APK it finds 465 candidate
calls, with zero unresolved patterns: 362 distinct tuples exactly match the 362
literal tuples parsed from the old GMX, and 103 distinct tuples are not in that
source. Examples of candidate English text not present there include `Shortcut`,
`Delete the save file`, and `Enter the sewer?#Using the small key`.

This is strong cross-checking but **not a decompilation**: the scanner is a
linear disassembly, does not recover control flow or verify the argument array,
and assumes that construction order equals argument order. Literal pools can
look like instructions. Do not automatically inject these candidates into a game
or treat all as proven dynamically executed entries. Validate argument order and
behavior before applying them. Example run (dependencies are optional and
installed outside the repository's tracked files):

```sh
python -m pip install --target .cache/re-pylibs capstone==5.0.6 pyelftools==0.32
PYTHONPATH=.cache/re-pylibs python tools/deadtown_native_lang.py /path/to/original.apk \
  --compare-gmx /path/to/deadtown/deadtown.gmx --output candidates.json
```

`lang_get` in GMX returns the English key for language 0 but directly calls
`ds_map_find_value` for languages 1–3. A new targeted static inspection
(`tools/deadtown_lang_fallback_evidence.py`) identifies the native switch in
`gml_Script_lang_get` at `0x2df86c`, resolves GOT references to
`g_FUNC_ds_map_exists` and `g_FUNC_ds_map_find_value` for cases 1–3, and pins
the branch and return instructions: when the existence result is not above
0.5, the branch returns argument 0. Case 0 also returns argument 0. The global
selector and map indices (62–65) are identified by their use here, not by a
verified global-name registration. This is strong static evidence of a
missing-key fallback, **not** native runtime execution or a proof for other
selector values.

A forced side-by-side experiment in the disposable desktop VM
[44641496464](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44641496464)
compared the old script with a candidate that checks existence first. For each
selector 0–3 it used synthetic known, empty and missing entries: the old
script produced undefined for missing keys in modes 1–3, while the candidate
returned the key; a present entry containing an empty string remained empty.
That checks this candidate and this runner only, not Android or iOS. It does
not establish that missing translations caused the user's screenshot; the old
`str:` debug event remains a direct, independently reproduced cause of a
`str:` message. The candidate is not included in any IPA pipeline.

`tools/deadtown_lang_coverage.py` compares name/description fields of the
static native table candidates using the old source schema. Of 344 candidate
references (340 distinct keys), **52** distinct keys are absent from the old
GMX translation literals, including `Gas mask`, while all 340 occur among the
native translation candidates. This is a static cross-check, not proof of
native control flow or runtime use. All 465 candidate `lang_add` calls have
empty Chinese and Japanese fields; all 362 old-source literal calls do too.
An existing-but-empty translation is **not** a missing key and the observed
fallback must not automatically replace it. Two candidate English keys are
duplicated (`Light machine gun`, `Heavy machine gun`); map insertion order and
actual outcome need separate validation. Neither audit injects translations or
claims that all UI text has been recovered.

The static inspector additionally follows `gml_Script_lang_add` (`0x2df3cc`):
arguments 0–3 are copied to separate values, then three `g_FUNC_ds_map_add`
legacy calls at `0x2df548`, `0x2df5d8`, and `0x2df660` use global indices
63, 64, 65 respectively, argument 0 as the key, and arguments 1, 2, 3 as
values. This supports the candidate field mapping and matches the three indices
used by `lang_get`; it still does not prove registration names, dynamic call
order, native duplicate-key semantics, or execution.

The strictly disposable language-table probe replaces the 362 literal calls
in the event JSON (not the project or release) with the 465 static candidates,
keeping extracted linear order. In forced desktop VM run
[44669577897](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44669577897),
the candidate initialized three 463-key maps; an independent parser compared
**every key and value** in the runner's `GMRM` serializations with candidates
under gmrunner's first-insertion rule. It also checked known/missing synthetic
keys, the actual Korean `Gas mask` and `Splint` values, present empty Chinese
and Japanese entries, and both duplicate Korean keys. The runner kept
`라이트 머신건` and `헤비 머신건`, the first values in the inferred order.
These are observations of a forced, incomplete desktop VM using an assumed
linear insertion order. They do **not** establish which calls the Android APK
executes or what its runner does with duplicate keys, nor do they validate iOS,
the UI, or a playable build. The disposable serialized maps are not artifacts.

### Original table arguments: deeper static analysis

`tools/deadtown_native_tables.py` follows static GOT relocations, `YYSetString`
constructions, pointer copies and the stack argument vector into table calls in
`sys_global` Create. For the pinned library it resolves the arguments of all
observed calls in these groups: weapons 35, equipment 27, consumables 22,
recipes 91, miscellaneous items 65, skills 23, spawn entries 129, and translations
465. For each value the output records its type, native symbol, relocation and
call address. The argument vector order of all 465 translations agrees with the
independent earlier string-construction scanner. Neither analyzer executes the
APK; they do not prove runtime control flow or that globals stay unchanged.

Concrete old-source differences are not just missing entries. Native candidates
for `Dagger` damage and `Cotton clothes` defense are 45 and 2 respectively,
while the GMX has 40 and 1. The third native spawn call is `(0,4,25,3,5)`
versus `(0,4,25,2,5)` in the GMX. The native consumable calls have ten arguments;
the GMX `db_use_add` accepts only nine, and the two new native entries include
`Gas mask` with a nonzero tenth value. Native `db_use_add` copies `argument9`
from the tenth argument pointer at `0x1bc380` into a local RValue at `0x1bc384`,
then assigns it at array column 9 (`0x1bc5a4`–`0x1bc5b4`) using the same row
index and array used for columns 0–8. The targeted inspector
`tools/deadtown_poison_evidence.py` also verifies that native `item_use` calls
`db_info_get` with field 9 at `0x1a572c`, multiplies the value by 30 and 60, and
sets variable index 32 at `0x1a57d4`; the native `sys_player_buff` Step retrieves,
adds, and sets index 32 on APK object 142 (`obj_player`) at
`0x6022c0`–`0x6022e0`. Independent evidence now comes from normal protect-mode
save/load: in `game_save_protect`, getters for player object 142 at `0x1dc3e8`
and `0x1dc444` read indices 171 and 32, respectively, and pass them to
`ini_write_real` with GOT-relocated section/key strings `player`/`buffpoison`
and `player`/`buffpoisonprotect`. In `game_load_protect`, the corresponding
`ini_read_real` results feed setters for the same indices at `0x221060` and
`0x2210f0`. The inspector resolves the actual strings and checks the relevant
instructions and calls; this is stronger independent evidence for the purpose
of the two indices, but is not a runtime persistence test. The inspector now
also resolves the `player`/`buffpoisonprotect` strings and follows the relevant
getter/writer or reader/setter in all three additional routine pairs: sewer,
defence and defence multiplayer. It does not verify every saved field, branch
reachability or actual persistence in those modes. The old GMX saves
`buffpoison` but lacks the protection field.

Relocations show that slot 32 of the exported `g_Vars` pointer array is
`g_VAR_pointer`, not `g_VAR_buff_poison_protect`. The array contains more than
one kind of variable and must not be used as a direct instance-index lookup.
The registration/slot mechanism remains to be traced; projecting offsets from
one known-looking region onto the rest of the symbol table is unsafe.

Further static checks in `obj_player` Step find a block using index 32. It
compares against zero with a runtime-loaded tolerance; on one path it subtracts
1 (for the real-number case) and sets index 171 to zero; on the other it sets
index 32 to zero. The tolerance resolves through a GOT relocation to
`g_GMLMathEpsilon`, initialized to `1e-10`; its runtime value may be changed.
The following block conditionally copies index 911 into index 32 after a
comparison. Create initializes index 32 to zero and index 911 to the real value
18,000; index 911 is therefore a candidate upper bound, though its registered
name is not independently established. Earlier in the same native Step,
index 171 has a similar real-number subtraction-by-one/zero-and-cap block;
its candidate bound is index 910, initialized to 1,800. The representative
checks do not prove that all intervening branches execute in a particular game.

The original APK's 15 `ROOM` resource headers all declare default speed 30,
including the three gameplay rooms. At a steady 30 Steps per second, 1,800
Steps would correspond to 60 seconds, and the Gas mask's candidate 3 × 30 × 60
would correspond to 180 seconds. These are **nominal calculations**, not a
measured duration: room speed, event execution and scheduling can differ at
runtime. In a separate native
`obj_zombie5` Step block, index 171 is compared using -900 and, on one branch,
assigned 900. This alone does not establish the surrounding hit conditions,
frame rate, runtime tolerance, or combat ordering. A scan for an immediate
`0x20` in `obj_boss2` was a false lead: that occurrence is an argument to
`view_effect_closeup`, not a variable lookup.

The native Step block around `0x5cea50` also checks index 171 and invokes
`rpg_skill_get_level` with a GOT-resolved real argument 20. On the real-number
arithmetic paths it subtracts index 914, or index 914 divided by 2 when the
skill result is above 0.5, from index 28. The native normal save routine
associates index 28 with `player`/`hp`, via a separately checked string
relocation. In Create, index 914 is initialized using the current value at
index 169 divided by 4,500; the normal save routine associates index 169 with
`player`/`hp_max`, and Create initially assigns it 100. This is materially
different evidence from the old GMX's literal `buff_poison_hurt = 0.06`;
intervening writes, exact event ordering, skill semantics and observed damage
still require verification. None of these indices is assigned a registered
name merely by guessing from `g_Vars` layout.

These checks cover representative exact instructions, relocations and calls,
not complete control flow or a runtime trace. No behavior should be patched
from this alone. Appending these tables to
the old source would shift item/recipe indices and could silently break crafting,
saving and gameplay: **none are injected into the IPA/release pipeline**.
Recover the corresponding data consumers, ordering and original schema first.

#### Disposable candidate VM experiment (not an APK comparison)

`tools/prepare_deadtown_poison_probe.py` creates a new, clearly marked research
copy from the pinned offline project and original APK. It applies the 22
candidate use rows and selected candidate poison changes only in that copy;
it refuses to overwrite or nest the source. The dedicated
`.github/workflows/deadtown-poison-probe.yml` compiles an incomplete VM, forces
a desktop headless scenario and uploads logs only, not a game or IPA.

The first run ([44560854662](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44560854662))
found a material compatibility failure: after an original-source compound
`target_inven[? pointer] -= 1`, `item_use` passed an array instead of the map
handle to `ds_map_delete`; the item remained and protection was zero. This is
observed in the UTMT-compiled, incomplete gmrunner VM, **not** in the APK; it
is not evidence of behavior on the APK. A follow-up disassembly in
[44562684960](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44562684960)
compiled the untouched old `item_use` into an unlinked diagnostic entry: the
accessor lowered to `[array]stack.target_inven` reads and writes before the
`ds_map_delete` call, whereas the workaround emits explicit DS-map calls.
The Underanalyzer submodule pinned by UTMT 0.9.2.0 at
[`4ff50a8`](https://github.com/UnderminersTeam/Underanalyzer/blob/4ff50a866b4c1a7acee8cebe6a56d6a48709b453/Underanalyzer/Compiler/Nodes/AccessorNode.cs)
has a TODO to convert non-array accessors to function calls. This supports a
compiler-lowering cause for this observed case, without proving that the runner
has no independent bugs. The same `[? ...]` syntax appears in 17 lines across
five old-source inventory/crafting scripts (`item_use`, `item_get`, `item_drop`,
`item_equip`, `item_make`); their semantics and runtime are not established by
this one test. `tools/check_deadtown_accessor_bytecode.py` checks only this
specific legacy/candidate disassembly, not general compiler support.

The follow-up [44671590170](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44671590170)
compiled untouched `item_get`, `item_drop`, `item_equip`, and `item_make` as
unlinked entries and confirmed each has `[array]...target_inven` in its bytecode.
A separate candidate generated from exact hashed source scripts uses explicit
`ds_map_find_value` and `ds_map_replace` at the affected sites; its disassembly
has those calls and no target-inventory array accessor. In a disposable VM,
forced scenarios observed: add 2 then 3 -> 5; drop missing -> 0, existing -> 1
and 4 remaining, final drop deletes the entry; equip and swap return the old
weapon; insufficient ingredients leave three stacks unchanged, and a synthetic
three-ingredient recipe removes exact stacks and produces two items. A second
synthetic recipe with two zero-quantity slots consumes its one ingredient and
adds to an existing output stack. These are narrow tests of the **old-source
candidate**, not proof of native semantics, equipment varieties, item IDs,
input, UI, or iOS. In particular, the native implementations differ in size
and may differ in logic; no candidate here is included in release workflows.
The probe output and saves are disposable, and only diagnostics are uploaded.

#### Native item-drop path and comparison tolerance

`tools/deadtown_item_drop_evidence.py` pins the original `gml_Script_item_drop`
(`0x1a31e0`, 2,100 bytes) and traces exact ARM instructions, the switch table,
GOT and PLT. It converts argument 0 to an integer for cases 1–4, which copy
`g_pGlobal` indices 0–3 respectively into instance slot 7; argument 1 is the
map key. This use does not independently prove the names registered for those
indices or slot 7, or behavior for invalid selectors. The defined-key path
reads via `ds_map_find_value`, subtracts integer 1, calls **`ds_map_set`** with
map/key/result, reads again and conditionally calls `ds_map_delete`; it returns
1. If `is_undefined` after the first read is above 0.5, it returns 0. This
supports a correspondence with the old-source candidate for ordinary positive
integer stacks, but does not execute the native function or verify native DS
implementation, global registration or all value types.

For finite values, the native deletion branch uses the runtime
`g_GMLMathEpsilon` directly as its upper threshold; its value in the ELF is
initially `1e-10`, but can change at runtime. The pinned gmrunner instead
initializes its comparison epsilon to `1e-5`, uses it for numeric VM
comparisons, and aliases its `ds_map_set` to `ds_map_replace`. Run
[44681106676](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44681106676)
forced the candidate to drop synthetic fractional stacks of `1.000001`: at
the observed VM default `1e-5` it deleted the remaining near-zero stack, while
setting the VM epsilon to `1e-10` retained it; the diagnostic restored the old
epsilon afterward. If the APK epsilon remained at its ELF initializer, its
pinned finite-value branch would take the latter route; that is a conditional
inference, **not an observed Android result**. Real inventory quantities may
be integers, so this synthetic case is a comparison-semantic probe, not a claim
that ordinary gameplay exhibits fractional stacks. The run also exercised the
four old-source candidate selectors using separate maps. No project-wide
change to epsilon has been made: it could affect many other comparisons.

#### Native `item_get` special ammunition/resource pickups

`tools/deadtown_item_get_evidence.py` pins the APK's 4,952-byte
`gml_Script_item_get` at `0x19f528`, including selector jump table, argument
copies, `g_pGlobal` relocations, comparisons and five early-return paths.
Selector 1–4 copies global index 0–3 respectively into a local target. The
script calls `ui_message_type` at `0x19fb00` before comparing the selected
target against global index 3 using `YYCompareVal` with the runtime epsilon.
When that comparison reports equality, it checks argument 1 against these
numeric values; on a match it adds argument 2 to the indicated global RValue,
sets the caller's return value to 0 and goes to cleanup, bypassing the ordinary
inventory-map loop:

| Item index | Updated global index | Addition call |
|---:|---:|---|
| 44 | 12 | `0x1a037c` |
| 45 | 13 | `0x1a03c0` |
| 46 | 14 | `0x1a0404` |
| 47 | 15 | `0x1a0448` |
| 48 | 16 | `0x1a04a4` |

Each comparison converts argument 1 to real and, for finite numeric values,
checks the absolute difference against mutable `g_GMLMathEpsilon` (ELF
initially `1e-10`). This is not strictly integer identity for arbitrary inputs;
nonfinite behavior and epsilon changes are not tested. The old GMX names these
five counters normal, shotgun, machinegun, arrow and oil, and uses the same
indices, but the native global-index registration/names have not been proven.
Selector 4 selects index 3 on the checked jump table, but whether target values
compare equal in all runtime states is not established. Invalid selector,
`YYCompareVal`/`RValue +=` internals, execution order across all branches,
regular map loop, actual Android behavior and iOS remain unproven. This is a
static observation, not a release patch.

In the separate forced, disposable old-source VM candidate run
[44715781079](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44715781079),
initial counter values 100/200/300/400/500 became 102/203/304/405/506 after
five `item_get(4, index, amount)` calls for indices 44–48 and amounts 2–6.
All five returned 0 and the temporary `etc` map remained empty; the probe
restored the prior counters and map handles afterward. This verifies only those
forced calls in the old-source candidate and gmrunner, not the native names,
all branches or execution on Android/iOS. Static verifier CI run
[44715781099](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44715781099)
passed independently.

#### Corroborating inventory selection against native save keys

`tools/deadtown_inventory_save_evidence.py` independently traces native normal
save `gml_Script_game_save_protect` (`0x1d97f8`) through the global getters,
string literals, `ds_map_write` and `ini_write_string` call vectors. The same
global indices used by `item_drop` are serialized under these keys:

| `item_drop` selector | Global index | Normal save key | `ds_map_write` call | `ini_write_string` call |
|---:|---:|---|---|---|
| 1 | 0 | `inventory/weapon` | `0x1dab04` | `0x1dab44` |
| 2 | 1 | `inventory/equip` | `0x1dac6c` | `0x1dacac` |
| 3 | 2 | `inventory/use` | `0x1dadd4` | `0x1dae14` |
| 4 | 3 | `inventory/etc` | `0x1daf3c` | `0x1daf7c` |

The same SHA-pinned verifier now also traces normal load
`gml_Script_game_load_protect` (`0x21a4a8`, 208,304 bytes). Its getter results
for indices 0–3 are stored at stack offsets `0xec`, `0xe8`, `0xe4`, `0xe0`.
In the following observed code sequence each is supplied to `ds_map_clear`,
and then paired with a three-argument `ini_read_string` result passed into
`ds_map_read`:

| Global index | Normal load key | `ds_map_clear` | `ini_read_string` | `ds_map_read` |
|---:|---|---|---|---|
| 0 | `inventory/weapon` | `0x21e410` | `0x21e6d4` | `0x21e718` |
| 1 | `inventory/equip` | `0x21e4a4` | `0x21e868` | `0x21e8ac` |
| 2 | `inventory/use` | `0x21e538` | `0x21ea00` | `0x21ea44` |
| 3 | `inventory/etc` | `0x21e5cc` | `0x21eb98` | `0x21ebdc` |

The verifier checks the GOT relocations, strings, vector base/argument counts,
map pointers and returned values, plus the nearby conditional cleanup branches.
The four default-string relocations each point to a one-byte `SHT_NOBITS` BSS
symbol: the ELF loader initially zeroes these bytes, consistent with an empty
default, but BSS is writable and **its contents at the calls are not observed**.
Unlike the old GMX script, the native inventory block appears after other load
operations; do not infer the full native load order from GMX. The local branches
checked skip RValue cleanup, not a clear/read call, but this is not a complete
control-flow or exception analysis, and reaching the block is unproven.

Together these corroborate the old-source categories with independent string
keys, not symbol-name registration or native execution. They cover normal
save/load only, not other modes, and do not recover or validate the original
`ds_map_write`/`ds_map_read` encoding or behavior on missing/malformed keys.

In disposable VM run [44683394932](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44683394932),
the candidate saved four synthetic map entries `(0 -> 11, 22, 33, 44)`,
replaced them with `-1` and inserted a temporary key 900, then loaded the
throwaway save: all four original values returned and each temporary key was
absent. The separate checker decoded the base64 INI and inspected the four
serialized maps. The pinned gmrunner writes its **own `GMRM` representation**;
this round trip tests only that runner and candidate, not interoperability with
an Android/GameMaker save or the behavior of an iOS build. Neither the save nor
game data is published, and user saves are never used for this diagnostic.

For the isolated probe only, `item_use` uses explicit DS-map operations for an
existing numeric key. The run [44562072708](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44562072708)
then observed the candidate mask entry 3, consumed a one-item mask, transferred
5,400 to the player, decremented and capped protection, counted poison down,
and consumed one from a two-item stack. In the same forced desktop scenario,
the reconstructed normal save/load scripts round-tripped protection 321 and
poison 2; the checker independently decoded those fields from the disposable
save.

A further forced run ([44565506937](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44565506937))
measured HP immediately before and after the candidate poison-damage block,
before hunger/regeneration. With the candidate's initially computed poison
rate `100/4500`, the HP change multiplied by 4,500 was 100 at skill 20 level 0
and 50 at level 1. When poison and protection were deliberately set together,
the candidate took that damage in the first step and none in the next: its
poison block precedes its protection timer/clear block. These are forced VM
measurements; although static ARM evidence has similar candidate operations,
this does **not** establish the native branch reachability, timing or exact
ordering under real gameplay. This validates only this candidate in this
runner under these conditions, not original runtime equivalence, general map
behavior, other save modes, audio, graphics or iOS. No result from this probe
is packaged for users.

Reproduce independently with the same optional dependencies as above:

```sh
PYTHONPATH=.cache/re-pylibs python tools/deadtown_native_tables.py /path/to/original.apk \
  --output native-table-candidates.json
PYTHONPATH=.cache/re-pylibs python -m unittest discover -s tests -p 'test_deadtown_native_tables.py' -v
```

### Sprite metadata comparison: visual and collision risks

`tools/deadtown_sprite_metadata.py` compares the pinned APK's bytecode-15
SPRT metadata with project-declared GMX sprites, without changing either. It
compares sizes, origin, bounding-box numbers, separate-mask flag (GMX `-1`
normalized to true) and frame counts; the parser checks frame pointers refer
to TPAG. The two formats' numeric `bbox_mode` values are compared as stored,
so differences are leads, not proof that runtime collision behavior differs.

The APK has **402** sprite names versus **291** declared in GMX; all 291 GMX
names exist in the APK, and 111 APK sprites have no same-named GMX declaration.
Of the shared names, **24** differ in at least one compared metadata field and
267 match those selected fields. In 17 shared sprites, the frame counts differ:
`spr_item_use` is 22 vs 20, `spr_item_etc` 65 vs 49, `spr_item_weapon` 35 vs
30, `spr_ui_buff` 7 vs 6, `spr_action_button` 11 vs 10 and
`spr_ui_health` 6 vs 4 (APK vs GMX). `spr_setting_cradits` width is 107 vs
247, with different origin and bounding box. These mismatches explain why
injecting newer table indices into the older art without analysis is unsafe;
they do not establish what any specific rendered screen looks like.

Reproduce with `python tools/deadtown_sprite_metadata.py APK PROJECT --output
sprite-metadata.json`; the native research workflow also generates the full
report. The metadata report does **not** compare decoded pixels, transparency,
mask bits, animation rates, positions or UI logic. Matching metadata is not
visual or collision equivalence.

A separate analysis, `tools/deadtown_sprite_pixels.py`, decodes the six APK PNG
atlases and reconstructs unscaled TPAG frame regions on their original-sized
transparent canvases, then compares the same frame index of shared sprite names
against the GMX PNGs (Pillow 11.3.0). Of 746 shared-index frame pairs, **221**
are exactly RGBA-identical, **517** differ only in RGB at alpha zero, **5**
have RGBA differences at pixels not both fully transparent, and **3** have
different canvas dimensions. The five visible-RGBA differences are
`ih_dagger[0]`, `spr_event_eng[0]`, `spr_event_kor[0]`, `spr_gps_sign[0]`,
and `spr_ui_day[0]`; the three size mismatches are `spr_part_bull[0]` and both
`spr_setting_cradits` frames. Across shared names, the APK has **63 additional
frames** not present in GMX; APK-only sprite names are not included in this
count. Transparent RGB can still affect texture filtering: classification is
not a promise of pixel-identical rendering. No collision masks, animation
rates, placement, device scaling, UI logic, or runtime drawing are compared.
Neither comparison report modifies the 111 APK-only assets.

#### Recovering sprite data into an isolated research export

`tools/recover_deadtown_sprites.py` can extract the APK's resource IDs, sprite
metadata, atlas coordinates, packed mask bytes and PNG frame candidates into a
**new disposable directory**. On the pinned APK, extraction and independent
read-back verification cover **402 sprites, 1,029 atlas frame references and
402 original packed masks**. For 1,028 unscaled references it crops the atlas
and places the decoded RGBA rectangle at the TPAG target offset on a
transparent canvas. Outside the stored rectangle the original transparent RGB
is unknowable; PNGs are newly encoded, not original atlas bytes. The remaining
reference, `mask_noone[0]`, has a 32×32 source and a 1×1 target: it is saved as
the untouched 32×32 decoded atlas region and explicitly marked **not
reconstructed**, rather than inventing a scaling filter. The byte-for-byte
mask export preserves raw packed data but does not assert the runtime's mask
interpretation. The manifest records resource ID, metadata, TPAG values,
per-frame RGBA/PNG hashes and raw-mask hashes.

The `verify` command rebuilds expectations from the pinned APK, checks every
frame's decoded RGBA and every raw mask, validates the manifest and rejects
symlinked export entries. This is research data, not a GMX or IPA; no existing
project or assets are overwritten. It does not restore missing logic, prove
animation/collision/UI equivalence or modify original audio. Reproduce (Pillow
11.3.0 required):

```sh
python tools/recover_deadtown_sprites.py extract APK new-research-output
python tools/recover_deadtown_sprites.py verify APK new-research-output
```

The workflow runs extraction and tampering checks in a temporary test directory;
it uploads reports only, not exported assets.

`tools/deadtown_sprite_masks.py` independently summarizes the packed masks
using the MSB-first, row-padded bit interpretation in the pinned gmrunner's
`Collision.cpp`; Android's native interpretation has **not** been separately
verified. Under that interpretation, the 402 stored bitmaps comprise 62 full
canvases, 302 smaller rectangles, 37 irregular shapes, and one empty mask
(`mask_noone`). All row-padding bits are zero. For 398 nonempty masks the
set-bit bounding rectangle matches the sprite's stored bbox; three differ:
`mask_zombie` has mask bounds 0–36 vs stored bbox 0–37, `mask_boss3` 0–118 vs
0–119, and `mask_boss4` 0–48 vs 0–49 on both axes. The empty mask has no
set-bit bounds. For example, `mask_player` has 225 set bits in a 15×15 canvas.
This is a static bitmap reading, not proof of transformed, scaled, animated or
device-runtime collision behavior; it does not justify changing those bounds.

### UI/input investigation: coordinate spaces

The pinned third-party runner returns `os_type = 0` (Windows) even on its mobile
build. Its `display_get_width/height` report the SDL desktop display mode,
while touch positions go through `screenToWindow` and `device_mouse_raw_x/y`
return those transformed window coordinates. The old source's `sys_view` uses
both `display_get_width/height` and raw touch coordinates for its on-screen
controls, and uses display dimensions when drawing buttons in Draw GUI. A
mismatch among display, window, GUI and actual drawable sizes could therefore
misplace controls or touch hitboxes. In an instrumented headless run of the
incomplete VM build, [run 44547797982](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44547797982)
measured `display=1280x720`, `gui=1334x750`, `window=1334x750`,
`viewport=1232x693`, `os_type=0` during `sys_view` Create. This establishes a
coordinate-space difference in that desktop run, but it does not establish how
much of the user's iOS screenshot it explains. The actual iOS values and original
APK's coordinate semantics have not yet been measured; no unverified UI fix
has been applied. The instrumentation changes only a disposable VM-data copy,
not an IPA.

### Native GML call graph

`tools/deadtown_native_callgraph.py` finds candidate direct calls to GML exports
and writes callsite addresses for all 1,051 exported game functions. For
example, native `sys_view` Step has direct calls to absent `gp_*` scripts, while
native `sys_UI` Draw GUI calls `get_enchant_price` and `get_enchant_my_money`,
also absent from the old source. This helps prioritize reconstruction, but it
is not equivalent to GML or a complete control-flow graph: indirect calls and
non-exported code are omitted, and decoded literal data may be false positives.
These callsite inventories cannot establish that a whole feature was restored.

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

## Readiness gate requested by the user

Do not ask the user to test another IPA merely because it packages or fixes one
issue. Before inviting a device test, the work must show evidence for:

- Restored or intentionally excluded functionality accounted for against the
  original, including matching-name functions whose behavior differs. An export
  name count alone is not evidence of equivalence.
- Single-player progression, crafting, spawning, inventory, equipment, combat,
  save/load and offline/unlock behavior tested on representative scenarios,
  with no unhandled functions or critical errors in the tested paths.
- UI/layout and multi-touch tested against original reference frames and hitbox
  behavior at multiple aspect ratios; display, GUI, viewport and touch spaces
  verified together, including rotation and safe areas.
- Original audio bytes retained and playback checked; install/update preserves
  user saves and mods without inadvertently retaining obsolete game code.
- An actual iOS build and runtime/device validation where available. Desktop
  headless tests and metadata checks cannot establish iPhone correctness.

This is substantial reverse engineering and may require manual reimplementation;
there is no proven automatic route from this APK's Android native code to a
faithful iOS IPA. A claim of zero bugs or full equivalence cannot be guaranteed
by static analysis or CI alone. Multiplayer/server behavior also conflicts with
the requested offline-only scope and must be explicitly accounted for.
