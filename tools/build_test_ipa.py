#!/usr/bin/env python3
"""Experimental AIR interpreter IPA with disposable self-signed credentials.

The generated inputs are not trusted by Apple and have not been verified with
ADT or Dopamine. This is a diagnostic build, not a production signing tool.
"""
import argparse
import os
import secrets
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def report_error(message: str) -> None:
    """Show diagnostics and expose them as annotations in GitHub Actions."""
    message = message[-6000:]
    print(message, file=sys.stderr)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error::{escaped}", flush=True)

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
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
        output_text = (result.stdout or "").replace(password, "[REDACTED]")
        if result.returncode:
            report_error(output_text or f"ADT exited with status {result.returncode} without diagnostics.")
            debug_path = os.environ.get("AIR_DEBUG_LOG")
            if debug_path and Path(debug_path).is_file():
                debug = Path(debug_path).read_text(encoding="utf-8", errors="replace")
                report_error(debug.replace(password, "[REDACTED]")[-5000:])
            raise subprocess.CalledProcessError(result.returncode, "adt")
        print(output_text)
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
        # Do not print commands, which may contain the disposable password.
        stderr = exc.stderr.decode("utf-8", "replace") if isinstance(exc.stderr, bytes) else exc.stderr
        report_error(f"Experimental IPA build failed (tool exit code {exc.returncode}). {stderr or ''}")
        return 1
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        report_error(f"Experimental IPA build failed: {exc}")
        return 1
    print("Created an experimental IPA. Signing and device compatibility are unverified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
