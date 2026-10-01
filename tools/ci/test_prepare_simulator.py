# Copyright 2026 Outfox, Inc.
# Licensed under the Apache License, Version 2.0.

"""Regression coverage for hosted runners with missing or incompatible simulator devices."""

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import prepare_simulator as simulator


WATCH = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm"
PHONE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
EXISTING = "00000000-0000-4000-8000-000000000001"
CREATED = "00000000-0000-4000-8000-000000000002"


def inventory(version="26.0", available=True, devices=True):
    """Build a small simctl response retaining runtime and device compatibility metadata."""
    runtime = "com.apple.CoreSimulator.SimRuntime.watchOS-" + version.replace(".", "-")
    return {
        "runtimes": [
            {
                "identifier": runtime,
                "version": version,
                "isAvailable": available,
                "supportedDeviceTypes": [{"identifier": WATCH, "productFamily": "Apple Watch"}],
            }
        ],
        "devices": {
            runtime: [
                {
                    "udid": EXISTING,
                    "name": "Available Watch",
                    "deviceTypeIdentifier": WATCH,
                    "isAvailable": True,
                    "state": "Shutdown",
                }
            ] if devices else []
        },
    }


class SimulatorTests(unittest.TestCase):
    def test_reuses_and_waits_for_existing_device(self):
        calls = []
        data = inventory()

        def run(arguments, **kwargs):
            calls.append((arguments, kwargs))
            if "--show-sdk-version" in arguments:
                return "26.0.0"
            if "list" in arguments:
                return json.dumps(data)
            return ""

        destination = simulator.prepare_simulator("watchos", run)
        self.assertEqual(destination, f"platform=watchOS Simulator,id={EXISTING}")
        self.assertEqual(calls[-1], (["xcrun", "simctl", "bootstatus", EXISTING, "-b"], {"timeout": 300}))
        self.assertFalse(any("create" in command for command, _ in calls))

    def test_creates_missing_device_from_runtime_supported_types(self):
        calls = []
        data = inventory(devices=False)
        # A global device type can require a newer runtime; use the runtime's own compatibility list.
        data["devicetypes"] = [{"identifier": "unsupported-new-watch", "productFamily": "Apple Watch"}]

        def run(arguments, **kwargs):
            calls.append(arguments)
            if "--show-sdk-version" in arguments:
                return "26.0"
            if "list" in arguments:
                return json.dumps(data)
            return CREATED if "create" in arguments else ""

        self.assertEqual(simulator.prepare_simulator("watchos", run), f"platform=watchOS Simulator,id={CREATED}")
        self.assertEqual(calls[2], ["xcrun", "simctl", "create", "Sunday CI watchOS", WATCH, data["runtimes"][0]["identifier"]])
        self.assertEqual(calls[3], ["xcrun", "simctl", "bootstatus", CREATED, "-b"])

    def test_rejects_missing_unavailable_or_too_old_runtime(self):
        for data in ({}, inventory(available=False), inventory(version="10.0")):
            with self.subTest(data=data), self.assertRaisesRegex(RuntimeError, "downloadPlatform watchOS"):
                simulator.select_device(data, "watchos", "26.0")

    def test_ignores_newer_than_sdk_and_unavailable_runtimes(self):
        data = inventory()
        data["runtimes"] += inventory(version="27.0")["runtimes"]
        data["runtimes"] += inventory(version="26.1", available=False)["runtimes"]
        self.assertEqual(simulator.select_device(data, "watchos", "26.1")[0]["version"], "26.0")

    def test_prefers_latest_compatible_runtime(self):
        data = inventory()
        newer = inventory(version="26.1")
        data["runtimes"] += newer["runtimes"]
        data["devices"].update(newer["devices"])
        self.assertEqual(simulator.select_device(data, "watchos", "26.1")[0]["version"], "26.1")

    def test_ignores_unavailable_or_wrong_family_devices(self):
        data = inventory()
        devices = next(iter(data["devices"].values()))
        devices[0]["isAvailable"] = False
        phone = copy.deepcopy(devices[0])
        phone.update(deviceTypeIdentifier=PHONE, isAvailable=True)
        devices.append(phone)
        self.assertIsNone(simulator.select_device(data, "watchos", "26.0")[2])

    def test_prefers_already_booted_device(self):
        data = inventory()
        devices = next(iter(data["devices"].values()))
        booted = copy.deepcopy(devices[0])
        booted.update(udid=CREATED, state="Booted")
        devices.append(booted)
        self.assertEqual(simulator.select_device(data, "watchos", "26.0")[2]["udid"], CREATED)

    def test_reports_missing_device_type(self):
        data = inventory()
        data["runtimes"][0]["supportedDeviceTypes"] = []
        with self.assertRaisesRegex(RuntimeError, "No compatible watchOS"):
            simulator.select_device(data, "watchos", "26.0")

    def test_selects_each_supported_platform(self):
        for platform, (name, _, family, _) in simulator.PLATFORMS.items():
            with self.subTest(platform=platform):
                data = inventory(devices=False)
                runtime = data["runtimes"][0]
                runtime_name = "xrOS" if platform == "visionos" else name
                runtime["identifier"] = f"com.apple.CoreSimulator.SimRuntime.{runtime_name}-26-0"
                runtime["supportedDeviceTypes"] = [{"identifier": f"type-{platform}", "productFamily": family}]
                selected, device_type, device = simulator.select_device(data, platform, "26.0")
                self.assertEqual(selected, runtime)
                self.assertEqual(device_type["identifier"], f"type-{platform}")
                self.assertIsNone(device)

    def test_platforms_do_not_select_each_others_runtimes(self):
        for platform in ("ios", "tvos", "visionos"):
            with self.subTest(platform=platform), self.assertRaises(RuntimeError):
                simulator.select_device(inventory(), platform, "26.0")

    def test_boot_failure_does_not_write_a_destination(self):
        for error in (subprocess.CalledProcessError(1, "bootstatus"), subprocess.TimeoutExpired("bootstatus", 300)):
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "output"
                with patch("sys.argv", ["prepare_simulator", "watchos", "--github-output", str(output)]), patch.object(
                    simulator, "prepare_simulator", side_effect=error
                ):
                    self.assertEqual(simulator.main(), 1)
                self.assertFalse(output.exists())

    def test_outputs_concrete_destination_after_success(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            destination = f"platform=watchOS Simulator,id={EXISTING}"
            with patch("sys.argv", ["prepare_simulator", "watchos", "--github-output", str(output)]), patch.object(
                simulator, "prepare_simulator", return_value=destination
            ):
                self.assertEqual(simulator.main(), 0)
            self.assertEqual(output.read_text(), f"destination={destination}\n")


if __name__ == "__main__":
    unittest.main()
