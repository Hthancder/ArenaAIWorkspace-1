#!/usr/bin/env python3
"""Create an experimental iOS AIR descriptor without altering the original."""
import argparse
import sys
from pathlib import Path
from xml.dom import minidom
from xml.parsers.expat import ExpatError


def prepare(source: Path, output: Path) -> None:
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    document = minidom.parse(str(source))
    application = document.documentElement
    if application.localName != "application" or not (application.namespaceURI or "").startswith("http://ns.adobe.com/air/application/"):
        raise ValueError("Not an Adobe AIR application descriptor")
    # The referenced icon files are missing. Removing the icon block enables
    # an experiment without claiming that the descriptor will pass ADT checks.
    for node in list(application.childNodes):
        if node.nodeType == node.ELEMENT_NODE and node.localName in ("icon", "android"):
            application.removeChild(node)
            node.unlink()
    iphone = next((node for node in application.childNodes
                   if node.nodeType == node.ELEMENT_NODE and node.localName == "iPhone"), None)
    if iphone is None:
        raise ValueError("The descriptor has no iPhone settings")
    resolutions = [node for node in iphone.childNodes
                   if node.nodeType == node.ELEMENT_NODE and node.localName == "requestedDisplayResolution"]
    if len(resolutions) > 1:
        raise ValueError("The descriptor has multiple iPhone resolution settings")
    if resolutions:
        resolution = resolutions[0]
        # All devices should use high resolution, even if a prior descriptor
        # excluded particular devices from its preferred setting.
        if resolution.hasAttribute("excludeDevices"):
            resolution.removeAttribute("excludeDevices")
        while resolution.firstChild:
            resolution.removeChild(resolution.firstChild).unlink()
    else:
        resolution = document.createElementNS(application.namespaceURI, "requestedDisplayResolution")
        iphone.appendChild(resolution)
    resolution.appendChild(document.createTextNode("high"))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(document.toxml(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.source, args.output)
    except (OSError, ValueError, ExpatError) as exc:
        print(f"Descriptor preparation failed: {exc}", file=sys.stderr)
        return 1
    print("Created experimental descriptor; it has not been validated by ADT.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
