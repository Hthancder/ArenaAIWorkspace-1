#!/usr/bin/env python3
"""Experimental AIR interpreter IPA with disposable self-signed credentials.

The generated inputs are not trusted by Apple and have not been verified with
ADT or Dopamine. This is a diagnostic build, not a production signing tool.
"""
import argparse
import secrets
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

if __package__:
    from .create_test_signing import generate
    from .prepare_ios_descriptor import prepare
else:
    from create_test_signing import generate
    from prepare_ios_descriptor import prepare


def build(stage: Path, output: Path, adt: str = "adt") -> None:
    stage = stage.resolve()
    output = output.resolve()
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    for required in ("application.xml", "LostLife.swf", "lib/ui.swf", "lib/m1.swf", "lib/doc/lang.xml"):
        if not (stage / required).is_file():
            raise ValueError(f"Missing staged file: {required}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="air-build-", dir=output.parent) as temp:
        work = Path(temp)
        password = secrets.token_urlsafe(24)
        generate(work / "signing", password)
        descriptor = work / "ios.xml"
        prepare(stage / "application.xml", descriptor)
        ipa = work / "test.ipa"
        # The password is for a disposable, self-signed key and is destroyed
        # with the temporary directory. Do not use real signing credentials.
        command = [adt, "-package", "-target", "ipa-test-interpreter", "-storetype", "pkcs12",
                   "-keystore", str(work / "signing" / "test.p12"), "-storepass", password,
                   "-provisioning-profile", str(work / "signing" / "test.mobileprovision"),
                   str(ipa), str(descriptor), "-C", str(stage), "LostLife.swf", "lib"]
        if (stage / "image.png").is_file():
            command.append("image.png")
        subprocess.run(command, check=True)
        with zipfile.ZipFile(ipa) as z:
            if not any(name.startswith("Payload/") and ".app/" in name for name in z.namelist()):
                raise ValueError("ADT output is not an IPA containing a Payload app bundle")
        ipa.replace(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path, help="Reconstructed asset directory")
    parser.add_argument("output", type=Path, help="New output IPA file")
    parser.add_argument("--adt", default="adt", help="Path to AIR's adt executable")
    args = parser.parse_args()
    try:
        build(args.stage, args.output, args.adt)
    except subprocess.CalledProcessError as exc:
        # Do not print the ADT command, which contains the disposable password.
        print(f"Experimental IPA build failed (tool exit code {exc.returncode}).", file=sys.stderr)
        return 1
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f"Experimental IPA build failed: {exc}", file=sys.stderr)
        return 1
    print("Created an experimental IPA. Signing and device compatibility are unverified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
