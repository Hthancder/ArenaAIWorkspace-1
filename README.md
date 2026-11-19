# AIR iOS compatibility investigation

This repository tracks an investigation into building an existing Adobe AIR game for iOS. The game files are not included.

## Known information

- The supplied application descriptor declares the AIR 32.0 namespace and identifies `LostLife.swf` as the initial content.
- The reported game directory contains additional SWF files in `lib/` and data files in `lib/doc/`.
- The descriptor references icon files under `icons/`, which are absent from the reported directory listing.
- The descriptor includes iOS settings, but this alone does not establish iOS compatibility.

## Next steps

1. Inspect the actual SWF files and their ActionScript versions and dependencies.
2. Determine how the main SWF loads secondary SWFs; AIR for iOS imposes restrictions on loading SWFs containing code.
3. Check the missing icons and any platform-specific APIs or native extensions.
4. If feasible, prepare and test an AIR iOS build and a GitHub Actions workflow. Packaging and installation requirements depend on the SDK and target device.

Do not commit game files unless you have the rights to store and distribute them. Do not commit signing credentials or provisioning profiles.
