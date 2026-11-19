# AIR iOS compatibility investigation

This branch tracks a static compatibility investigation of an existing Adobe AIR game. The game files themselves are on `origin/main`, not this branch.

## Findings

The supplied application descriptor declares the AIR 32.0 namespace and identifies `LostLife.swf` as the initial content. It includes iOS settings, but this does not establish iOS compatibility. Its icon paths refer to an `icons/` directory absent from the reported file listing.

Static inspection of commit `4291b63` on `origin/main` found:

- `LostLife.swf` is a compressed SWF version 43, declares ActionScript 3, and contains ActionScript bytecode (DoABC).
- Bytecode inspection of `swf.init` confirms that it loads `./lib/ui.swf` and `./lib/sound.swf` through `swf.LDRC`. `swf.LDRC` creates a `LoaderContext` with `ApplicationDomain.currentDomain`, as required on iOS.
- `swf.LoadScene` removes the current scene, calls `LDR_SC.unload()`, then loads `./lib/` plus the selected scene name and `.swf`. Several scene SWFs contain code. Loading the same code-bearing SWF again after unloading it can fail on iOS in compiled mode (error 3764). A scene that does not contain ABC is not subject to that specific restriction. This needs an actual device test and possibly a change to scene management.
- The main SWF also references touch-related APIs and `SharedObject`; device testing is required to determine whether touch input and saves work correctly.
- `bath.swf`, `d1.swf`, `fe.swf`, `m1.swf`, `sound.swf`, `top.swf`, and `ui.swf` contain DoABC tags. `logo.swf`, `sle.swf`, and `tv.swf` have no DoABC tag in this inspection.
- The four `lib.zip.001`–`.004` files concatenate into a ZIP containing `m1.swf` and `ui.swf`. Both extracted successfully with ZIP CRC verification. The other files on `origin/main` are flattened, whereas the observed paths expect `lib/` and `lib/doc/`.

AIR on iOS restricts the loading and reloading of SWFs that contain code. Relevant files must be included in the package and loaded into the correct application domain; inspection of the `swf` class does not prove every loader meets these requirements. See the [AIR SDK loading documentation](https://airsdk.dev/docs/development/display/display-programming/loading-display-content-dynamically) and [Loader reference](https://airsdk.dev/reference/actionscript/3.0/flash/display/Loader.html). The latter says the restrictions do not apply to AIR's interpreter-mode test targets, but feasibility, device compatibility, and performance have not been verified.

This is a static inspection only: no game files were executed and no iOS build or device test was performed. Selected methods were inspected using `pyflashkit` 1.3.0 and cross-checked against its disassembly; the rest of the bytecode has not been fully analyzed for platform-specific API usage. ADT's documented iOS packaging requires a provisioning profile and signing credentials ([ADT signing options](https://airsdk.dev/docs/building/air-developer-tool/option-sets/code-signing-options)); jailbreak installation alone does not establish that ADT can build without them. Alternatives have not been tested.

## Reconstruct the asset layout

`tools/stage_air_game.py` reconstructs the expected layout from a directory containing the flattened files and ZIP parts. It checks the part sequence and ZIP CRCs, rejects unexpected archive members, and leaves the source unchanged. The destination must not already exist. For example, from this branch:

```sh
git fetch origin main
mkdir -p .cache/air-source
git archive origin/main | tar -x -C .cache/air-source
python3 tools/stage_air_game.py .cache/air-source .cache/air-staged
```

The staged descriptor is an unchanged copy for investigation, **not a verified iOS build descriptor**. Its referenced icons are still missing. A separate experimental descriptor can be prepared without editing the original:

```sh
python3 tools/prepare_ios_descriptor.py .cache/air-staged/application.xml .cache/experimental-ios.xml
```

This removes the Android section and the icon block that refers to missing files and changes the iPhone `requestedDisplayResolution` from `standard` to `high` to use the device's high-resolution display. Other iPhone settings are retained. This can improve rendering sharpness but cannot add detail to low-resolution artwork; layout, touch behavior, performance and save retention need device testing. Run the preparation tests with `python3 -m unittest discover -s tests -v`.

## Device and build research

The reported target is iOS 15 with Dopamine and TrollStore. The documented `ipa-test-interpreter` target avoids the standard AOT reload restriction, though performance may be worse.

On GitHub Actions, AIR SDK 51.1.3.12 successfully packaged an experimental interpreter IPA using the generated self-signed certificate and profile in [run 44480837903](https://github.com/Hthancder/ArenaAIWorkspace-1/actions/runs/44480837903). Adding a team identifier to the certificate subject resolved the earlier `Using old Signing Certificate` packaging failure. This establishes packaging success only: the IPA has not been installed or tested on a device. It is not an Apple-signed or App Store build, and game functionality, performance, and TrollStore compatibility remain unverified. The run's artifact is retained for three days.

`tools/build_test_ipa.py` prepares an experimental descriptor and disposable, self-signed test credentials and attempts to run ADT. These credentials are not issued by Apple, are not suitable for normal distribution, and may be rejected during packaging or device installation. The script removes the temporary private key and signing files after the build. Unit tests use a mocked ADT and do not establish actual IPA compatibility. Locally, with a separately installed AIR SDK and OpenSSL:

```sh
python3 tools/build_test_ipa.py .cache/air-staged .cache/experimental.ipa --adt /path/to/adt
```

An experimental GitHub Actions workflow is provided in `.github/workflows/experimental-ios.yml`, pinned to the investigated game-asset commit. It does **not** run the build on a push unless repository variable `AIR_SDK_LICENSE_ACCEPTED` equals `true`. Set that variable only after reading and accepting the [AIR SDK license agreement](https://airsdk.wxlift.com/assets/pdfs/HARMAN%20AIR%20SDK%20License%20Agreement.pdf); then push a commit on this branch. Manual dispatch asks for explicit agreement and requires that GitHub recognize the workflow for dispatch. The workflow uses a macOS runner, which may consume billable minutes, and uploads only the experimental IPA if ADT succeeds. Scene loading, performance, and device installation remain unverified.

## Next steps

1. Investigate scene reload handling and platform-specific API dependencies. Resolve missing icons and check native extensions.
2. Verify an iOS packaging/signing approach and the AIR SDK license requirements. Jailbreak may affect installation but does not automatically remove ADT's build-time requirements.
3. If feasible, prepare an AIR iOS descriptor and a GitHub Actions build, then test on the target iOS device. An interpreter test build may avoid the reload restriction, but has not been validated and may be slower.

Do not commit game files unless you have the rights to store and distribute them. Do not commit signing credentials or provisioning profiles.
