#!/usr/bin/env python3
"""Create disposable self-signed inputs for an experimental jailbroken-iOS build.

These are not Apple-issued credentials. They cannot be used for App Store or
normal device distribution. Whether a particular AIR SDK accepts them is
unknown until an actual packaging attempt is made.
"""
import argparse
import datetime as dt
import os
import plistlib
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


def generate(output: Path, password: str) -> None:
    if not password:
        raise ValueError("Set a nonempty AIR_TEST_P12_PASSWORD environment variable")
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="air-signing-", dir=output.parent) as temp:
        work = Path(temp)
        config = work / "openssl.cnf"
        config.write_text("""[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = iPhone Developer: AIR Experimental
O = Local Test Only
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning,emailProtection
subjectKeyIdentifier = hash
""")
        key, cert, der = work / "key.pem", work / "cert.pem", work / "cert.der"
        def run(*args: str) -> None:
            subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "365",
            "-sha256", "-keyout", str(key), "-out", str(cert), "-config", str(config))
        run("openssl", "x509", "-in", str(cert), "-outform", "DER", "-out", str(der))
        result = work / "result"
        result.mkdir(mode=0o700)
        # Pass the password through the environment, not the process argument.
        env = {**os.environ, "AIR_TEST_P12_PASSWORD": password}
        subprocess.run(["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
                        "-name", "AIR Experimental", "-out", str(result / "test.p12"),
                        "-passout", "env:AIR_TEST_P12_PASSWORD"],
                       check=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        now = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
        team = "LOCALDEV01"
        profile = {
            "AppIDName": "Experimental local test only",
            "ApplicationIdentifierPrefix": [team],
            "CreationDate": now,
            "DeveloperCertificates": [der.read_bytes()],
            "Entitlements": {
                "application-identifier": team + ".*",
                "com.apple.developer.team-identifier": team,
                "get-task-allow": True,
                "keychain-access-groups": [team + ".*"],
            },
            "ExpirationDate": now + dt.timedelta(days=365),
            "Name": "Untrusted AIR test profile",
            "Platform": ["iOS"],
            "ProvisionsAllDevices": True,
            "TeamIdentifier": [team],
            "TeamName": "Local Test Only",
            "TimeToLive": 365,
            "UUID": str(uuid.uuid4()).upper(),
            "Version": 1,
        }
        plist = work / "profile.plist"
        plist.write_bytes(plistlib.dumps(profile))
        run("openssl", "smime", "-sign", "-binary", "-nodetach", "-outform", "DER",
            "-in", str(plist), "-signer", str(cert), "-inkey", str(key),
            "-out", str(result / "test.mobileprovision"))
        result.rename(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New private output directory; never commit these files")
    args = parser.parse_args()
    try:
        generate(args.output, os.environ.get("AIR_TEST_P12_PASSWORD", ""))
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"Test signing setup failed: {exc}", file=sys.stderr)
        return 1
    print("Created self-signed test inputs. AIR acceptance and device installation are unverified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
