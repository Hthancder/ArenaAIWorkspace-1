# Dead Town iOS port investigation

## Scope and source

Upstream: https://github.com/kjs104901/deadtown, commit
`5e3d798f914c8cd3b066c8289323005d63111f37`. Its README identifies it
as the Lemon Puppy Games Dead Town source and explicitly says it cannot be
built in its current state. This is a GameMaker Studio 1-era `.project.gmx`
project, not the Unity/IL2CPP `com.Ccentury.DeadTownSurvival` APK. The two
are different games. Do not assume the Android APK is a source build of this
project or that its assets are drop-in replacements.

The checkout used for the audit is `.cache/deadtown` (ignored, disposable):

```sh
git clone https://github.com/kjs104901/deadtown.git .cache/deadtown
python tools/audit_deadtown_gmx.py .cache/deadtown/deadtown.gmx
```

The upstream `LICENSE` file merely points back to the repository, and does
not state clear terms for reuse or redistribution. Verify rights separately
before distributing a modified game or its assets.

## Static audit at the commit above

For resources listed in the project, descriptor files exist for all 291
sprites, 29 backgrounds, 124 scripts, 150 objects and 7 rooms. All 746
referenced sprite frames and 29 background images exist. The 89 listed
sound descriptors exist, but all 89 referenced audio files under
`sound/audio/` are missing. The project refers to two missing extension
project files: GooglePlayServicesExtension and UnityAds. A file named
`datafiles/UnityAdsExt.gmez` exists; its contents and suitability have not
been verified. The presence of an extension archive alone does not restore
or validate the missing extension project files.

The source has iOS-specific code, but also calls Unity Ads and in-app purchase
APIs. Whether the original services are required for a playable offline
build is not established. Replacing them requires careful changes and tests,
not simply removing all calls. The audit covers selected file references only:
it does not establish that the GML compiles, that config files are complete,
or that runtime logic and services work.

## Next steps / blockers

1. The user confirmed the goal is the original Dead Town, not the distinct
   Unity game. Audio has now been recovered from the supplied APK as described
   below. Investigate the two missing project extensions; do not replace or
   disable functionality without testing the consequences.
2. Test importing the GMX in a compatible GameMaker installation and inspect
   its diagnostics. Modern GameMaker migration, legacy APIs and third-party
   extensions may require significant changes. Investigate disabling or
   adapting platform services for a local test without faking purchases.
3. An iOS-capable GameMaker toolchain and appropriate export access, plus a
   supported macOS/Xcode environment, will be needed to attempt an iOS build.
   No compatible GameMaker or Xcode toolchain is available in this sandbox;
   no import, compile, IPA or on-device test has been performed.
4. If a build is achieved, check device iOS 15 support, controls, sound,
   save data and performance. TrollStore can install a suitable IPA, but does
   not provide the engine or solve build and platform compatibility issues.

## Staging and toolchain research

The isolated staging tool copies the original GMX project to a new directory
and can copy exact-name audio files byte-for-byte, without conversion. It
reports missing references and does not alter the upstream checkout:

```sh
python tools/stage_deadtown_gmx.py .cache/deadtown/deadtown.gmx .cache/deadtown-staged
# Or use a fresh destination when original audio is available:
python tools/stage_deadtown_gmx.py .cache/deadtown/deadtown.gmx .cache/deadtown-with-audio --audio-dir /path/to/original-audio
```

A staged copy without audio currently reports 89 missing audio files and two
missing extension descriptors. It is not a buildable or imported project.

GameMaker's [migration guide](https://help.gamemaker.io/hc/en-us/articles/231719468-Porting-A-GMS-1-4-Game-To-GameMaker)
describes importing 1.4 projects into modern GameMaker, with potential fixes
and compatibility scripts. The [command-line build documentation](https://manual.gamemaker.io/monthly/en/Settings/Building_via_Command_Line.htm)
requires IDE login or an access-key service and specifies a modern `.yyp`
project. [GameMaker's pricing page](https://gamemaker.io/en/get) lists mobile
exports for non-commercial use; this is not a claim that the present project
will import or build. The [compiler documentation](https://manual.gamemaker.io/monthly/en/Introduction/Compiling.htm)
specifies a Mac for iOS. GitHub Actions may provide macOS, but it does not by
itself supply a converted project, GameMaker access, or resolve extensions,
missing audio, signing, and device compatibility.

## Audio recovery from supplied APK

The user uploaded `Dead+Town+-+Zombie+survival_1.4.2_APKPure.apk` in repository
commit `8643abd`. Its SHA-256 is
`bc8fa1990cb2cdde8d184f2a942fe4010820f0592d88a36e1cbee0a6aac081fb`.
Its `game.droid` GameMaker audio table names 90 audio resources. The two
external audiogroups and the built-in audio group contain the referenced
sound payloads. The parsed APK signature certificate names lemonpuppy, but
this has not been independently verified against a trusted signing fingerprint;
the APK's provenance and correspondence to this source version remain unproven.

Recovered 90 files: 87 Ogg and 3 WAV. All 90 decoded successfully in an
ffmpeg test to a null output; that test does not prove in-game playback.
Exactly 89 resource names match the 89 sound descriptors listed in the GMX
project; the remaining `snd_eating` is not listed by that GMX project. The
APK payloads are the versions packaged in that build, not necessarily the
original source audio files. Many are Ogg although the GMX source descriptor
names .mp3 or .wav. No audio was converted: data was extracted byte-for-byte,
and the copied project descriptors were updated to match the true file
format. Audio sounds and gameplay still need to be tested after import.

To reproduce with fresh output paths (the two output commands deliberately
refuse to overwrite existing directories):

```sh
git show '8643abd:Dead+Town+-+Zombie+survival_1.4.2_APKPure.apk' > .cache/deadtown-original.apk
python tools/recover_deadtown_audio.py extract .cache/deadtown-original.apk .cache/deadtown-audio
python tools/stage_deadtown_gmx.py .cache/deadtown/deadtown.gmx .cache/deadtown-staged
# The staging command returns 1 at this point because references are missing.
python tools/recover_deadtown_audio.py apply .cache/deadtown-staged .cache/deadtown-audio
python tools/audit_deadtown_gmx.py .cache/deadtown-staged
```

After applying the recovered audio, the audit reports zero missing listed
sound data files and two missing extension descriptors. Both the APK and all
staged/recovered files are outside the tracked patchset; regenerate from the
specified inputs if `.cache` is lost. The small reader is deliberately limited
to this APK's GameMaker bytecode and container layout, not a general APK or
GameMaker extractor. No GameMaker import, iOS build, or IPA exists yet.

## Offline experiment (not built)

The user requested no Google Play and an unlocked game. A repeatable patch
creates a separate copy of the audio-restored staging project:

```sh
python tools/prepare_deadtown_offline.py .cache/deadtown-staged .cache/deadtown-offline
python tools/audit_deadtown_gmx.py .cache/deadtown-offline
```

Use a fresh destination; the patch refuses to overwrite and validates the
SHA-256 hashes of the 16 input files it changes. It removes both missing
extension references, disables social sign-in/posting and store calls, hides
the restore button, and makes ad checks return false. Local achievement
progress is retained; no leaderboard or external achievement service is
available. Ad rewards will be unavailable. The offline copy grants the nine
non-consumable purchase flags 5–13 in memory *after* loading purchase data;
the original code grants the corresponding items on game start. The patch
also sets normal in-game shop prices to zero. It does not grant currency,
complete achievements, modify save files on the host, or establish that every
other type of in-game content is unlocked. Existing game logic still writes
saves normally at runtime; back up any previous saves before testing.

The offline file-reference audit reports no missing referenced sounds,
sprites, backgrounds, scripts, objects, rooms, or extension descriptors. All
GMX XML files parse. These are static checks only: they do not validate GML
compatibility, import, game logic, audio playback, or an iOS IPA. The project
still needs modern GameMaker import and runtime testing. The `.cache` copy is
disposable; the tools and the specified upstream/APK commits reproduce it.

## Real import and iOS build attempt

GitHub Actions run `44493423659` used GameMaker ProjectTool `2024.14.165`
to import the recovered and patched GMX into a `.yyp` project. The import job
completed and uploaded `deadtown-imported-project-untested` and its logs
(three-day retention). ProjectTool emitted 534 diagnostic lines containing
warnings/errors; all matched its `Failed to find Options property` pattern for
legacy settings. An import success and matching warning text do not establish
that GML compiles or any platform works.

The iOS job started on macOS but stopped at the explicit access check because
no GameMaker access key was configured. GameMaker's documented iOS runtime
installation requires a licence, and the attempted iOS compilation/unsigned
IPA steps have **not run or been validated**. Once access is configured outside
chat, rerun the failed job in run `44493423659`; build, packaging, TrollStore
installation, iOS 15 compatibility, restored audio, and unlocks remain untested.
No IPA was produced.

The previously supplied APK's `game.droid` contains empty `CODE`, `VARI`, and
`FUNC` chunks; its 32-bit Android `libyoyo.so` exports many `gml_Script_*` and
`gml_Object_*` native functions. This is evidence of a native-compiled game,
not a usable GML bytecode payload for a generic iOS GameMaker VM runner. The
Android ELF cannot simply be packaged as an iOS executable.
