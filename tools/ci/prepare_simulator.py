#!/usr/bin/env python3
# Copyright 2026 Outfox, Inc.
# Licensed under the Apache License, Version 2.0.

"""Prepare a concrete simulator destination for the active Xcode installation."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
from uuid import UUID

# Minimum runtime versions match Package.swift's deployment targets.
PLATFORMS = {
    "ios": ("iOS", "iphonesimulator", "iPhone", (18, 0)),
    "tvos": ("tvOS", "appletvsimulator", "Apple TV", (18, 0)),
    "watchos": ("watchOS", "watchsimulator", "Apple Watch", (11, 0)),
    "visionos": ("visionOS", "xrsimulator", "Apple Vision", (2, 0)),
}


def version_tuple(value):
    """Normalize numeric versions so 26.0 and 26.0.0 compare equally."""
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * max(0, 3 - len(parts))


def inventory_summary(inventory):
    """Describe runtime availability and devices when setup cannot proceed."""
    return json.dumps(
        [
            {
                "runtime": runtime["identifier"],
                "available": runtime.get("isAvailable", False),
                "error": runtime.get("availabilityError"),
                "devices": [
                    {key: device.get(key) for key in ("name", "udid", "isAvailable", "state")}
                    for device in inventory.get("devices", {}).get(runtime["identifier"], [])
                ],
            }
            for runtime in inventory.get("runtimes", [])
        ],
        indent=2,
    )


def select_device(inventory, platform, sdk_version):
    """Select a supported installed runtime, device type, and optional existing device."""
    name, _, family, minimum = PLATFORMS[platform]
    minimum = minimum + (0,)
    maximum = version_tuple(sdk_version)
    runtime_name = "xrOS" if platform == "visionos" else name
    prefix = f"com.apple.CoreSimulator.SimRuntime.{runtime_name}-"
    runtimes = sorted(
        (
            runtime
            for runtime in inventory.get("runtimes", [])
            if runtime["identifier"].startswith(prefix)
            and runtime.get("isAvailable", False)
            and minimum <= version_tuple(runtime["version"]) <= maximum
        ),
        key=lambda runtime: version_tuple(runtime["version"]),
        reverse=True,
    )
    for runtime in runtimes:
        types = [
            device_type
            for device_type in runtime.get("supportedDeviceTypes", [])
            if device_type.get("productFamily") == family
        ]
        if not types:
            continue
        type_ids = {device_type["identifier"] for device_type in types}
        devices = sorted(
            (
                device
                for device in inventory.get("devices", {}).get(runtime["identifier"], [])
                if device.get("isAvailable", False) and device.get("deviceTypeIdentifier") in type_ids
            ),
            key=lambda device: (device.get("state") != "Booted", device["name"], device["udid"]),
        )
        return runtime, types[0], devices[0] if devices else None
    raise RuntimeError(
        f"No compatible {name} simulator runtime/device type is available for SDK {sdk_version}. "
        f"Install a compatible runtime for the selected Xcode (xcodebuild -downloadPlatform {name}).\n"
        + inventory_summary(inventory)
    )


def run_command(arguments, timeout=60):
    """Run an Xcode tool with a bounded wait and keep diagnostics out of the destination output."""
    print("+ " + " ".join(arguments), file=sys.stderr)
    result = subprocess.run(arguments, check=True, stdout=subprocess.PIPE, text=True, timeout=timeout)
    return result.stdout.strip()


def simulator_inventory(run=run_command):
    """Retry read-only discovery while CoreSimulator starts, within three bounded attempts."""
    arguments = ["xcrun", "simctl", "list", "--json"]
    for attempt in range(1, 4):
        try:
            return json.loads(run(arguments, timeout=60))
        except subprocess.TimeoutExpired as error:
            print(f"Simulator inventory attempt {attempt}/3 timed out after 60 seconds", file=sys.stderr)
            if attempt == 3:
                raise RuntimeError("Simulator inventory unavailable after three 60-second attempts") from error


def prepare_simulator(platform, run=run_command):
    """Reuse or create a compatible device and wait until it has finished booting."""
    name, sdk, _, _ = PLATFORMS[platform]
    sdk_version = run(["xcrun", "--sdk", sdk, "--show-sdk-version"])
    inventory = simulator_inventory(run)
    runtime, device_type, device = select_device(inventory, platform, sdk_version)
    if device:
        udid = device["udid"]
    else:
        udid = run(
            ["xcrun", "simctl", "create", f"Sunday CI {name}", device_type["identifier"], runtime["identifier"]]
        )
    # Only a concrete device identifier may become an xcodebuild destination or an Actions output.
    UUID(udid)
    print(f"Using {runtime['identifier']} / {udid}", file=sys.stderr)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=300)
    return f"platform={name} Simulator,id={udid}"


def main():
    """Print the prepared destination and optionally expose it to a following Actions step."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=PLATFORMS)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    try:
        destination = prepare_simulator(args.platform)
    except (RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Simulator preparation failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stdout:
            print(error.stdout, file=sys.stderr)
        return 1
    if args.github_output:
        with args.github_output.open("a") as output:
            output.write(f"destination={destination}\n")
    print(destination)
    return 0


if __name__ == "__main__":
    sys.exit(main())
