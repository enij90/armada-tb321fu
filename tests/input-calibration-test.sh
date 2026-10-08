#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -B - "$ROOT" "$WORK" <<'PYEOF'
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
work = Path(sys.argv[2])
sys.path.insert(0, str(root / "decky/armada-control/py_modules"))
sys.path.insert(0, str(root / "system_files/usr/lib/armada"))

from armada_control import calibration


def parameter_dir(name):
    path = work / name
    path.mkdir()
    for param in calibration.CALIBRATION_PARAMS:
        (path / param).write_text("0", encoding="utf-8")
    (path / "update_params").write_text("0", encoding="utf-8")
    return path


rsinput_params = parameter_dir("rsinput")
retroid_params = parameter_dir("retroid")
mangmi_params = parameter_dir("mangmi")
calibration.CALIBRATION_BACKENDS = {
    "mangmi": mangmi_params,
    "rsinput": rsinput_params,
    "retroid": retroid_params,
}

rsinput_event = {"name": "RSInput Gamepad", "phys": "rsinput-gamepad/input0"}
retroid_event = {"name": "Retroid Pocket Gamepad", "phys": "retroid-pocket-gamepad/input0"}
mangmi_event = {"name": "MANGMI Pocket Max Joypad", "phys": "mangmi-pocket-max/input0"}
tester_event = {"name": "AYANEO Controller", "phys": "usb-controller/input0"}
virtual_event = {"name": "Microsoft X-Box 360 pad 0", "phys": ""}

assert calibration.event_backend(rsinput_event) == "rsinput"
assert calibration.event_backend(retroid_event) == "retroid"
assert calibration.event_backend(mangmi_event) == "mangmi"
assert calibration.event_backend(tester_event) is None
assert calibration.calibration_backend(rsinput_event) == "rsinput"
assert calibration.calibration_backend(retroid_event) == "retroid"
assert calibration.calibration_backend(mangmi_event) == "mangmi"
assert calibration.calibration_backend(tester_event) is None

calibration.inputplumber_source_events = lambda: []
calibration.input_events = lambda: [virtual_event, retroid_event]
assert calibration.calibration_event() == retroid_event

values = {
    0: (10, -1408, 1408),
    1: (20, -1408, 1408),
    2: (111, 0, 1552),
    3: (30, -1408, 1408),
    4: (40, -1408, 1408),
    5: (222, 0, 1552),
    9: (666, 0, 1023),
    10: (555, 0, 1023),
    20: (333, 0, 1552),
    21: (444, 0, 1552),
}


def fake_ioctl(_fd, request, _buffer):
    code = request - 0x80184540
    if code not in values:
        raise OSError(code)
    value, minimum, maximum = values[code]
    return struct.pack("iiiiii", value, minimum, maximum, 0, 0, 0)


calibration.fcntl.ioctl = fake_ioctl
default_controls = calibration.read_backend_controls(0)
retroid_controls = calibration.read_backend_controls(0, "retroid")
mangmi_controls = calibration.read_backend_controls(0, "mangmi")
assert default_controls["left_trigger"]["value"] == 111
assert default_controls["right_trigger"]["value"] == 222
assert retroid_controls["left_trigger"]["value"] == 333
assert retroid_controls["right_trigger"]["value"] == 444
assert mangmi_controls["left_trigger"]["value"] == 333
assert mangmi_controls["right_trigger"]["value"] == 444

values[2] = (0, 0, 0)
values[5] = (0, 0, 0)
fallback_controls = calibration.read_backend_controls(0)
assert fallback_controls["left_trigger"]["value"] == 555
assert fallback_controls["right_trigger"]["value"] == 666

calls = []
calibration.call = lambda action, **payload: calls.append((action, payload)) or {}


def last_write():
    return json.loads([payload for action, payload in calls if action == "write_config"][-1]["text"])


calibration.calibration_event = lambda: retroid_event
calibration.calibration_status = lambda: {"ok": True}
calibration.reset_calibration_params()
reset_payload = last_write()
assert reset_payload["backend"] == "retroid"
assert reset_payload["axis_leftx_min"] == -1408
assert reset_payload["axis_leftx_max"] == 1408
assert reset_payload["axis_leftx_deadzone"] == 0
assert reset_payload["trigger_left_max"] == 1552

calibration.calibration_event = lambda: mangmi_event
calibration.reset_calibration_params()
reset_payload = last_write()
assert reset_payload["trigger_left_max"] == 1910
assert reset_payload["trigger_right_max"] == 1758
assert reset_payload["axis_leftx_max"] == 1408
assert reset_payload["axis_leftx_deadzone"] == 70

calibration.calibration_event = lambda: rsinput_event
calibration.reset_calibration_params()
reset_payload = last_write()
assert reset_payload["axis_leftx_max"] == 1408
assert reset_payload["axis_leftx_deadzone"] == 0
assert reset_payload["trigger_left_deadzone"] == 0

device_tree = {"axis-range": 1024, "trigger-left-deadzone": 100}
calibration.device_tree_u32 = lambda _event, name: device_tree.get(name)
calibration.reset_calibration_params()
reset_payload = last_write()
assert reset_payload["axis_righty_min"] == -1024
assert reset_payload["axis_righty_max"] == 1024
assert reset_payload["axis_righty_deadzone"] == 0
assert reset_payload["trigger_left_deadzone"] == 100
assert reset_payload["trigger_right_deadzone"] == 0
calibration.calibration_event = lambda: retroid_event

state = {
    "supported": True,
    "canApply": True,
    "backend": "retroid",
    "controls": {},
}
capture = {
    "left_x": {"center": 0, "min": -1200, "max": 1250},
    "left_y": {"center": 0, "min": -1210, "max": 1230},
    "right_x": {"center": 0, "min": -1220, "max": 1240},
    "right_y": {"center": 0, "min": -1230, "max": 1260},
    "left_trigger": {"center": 0, "min": 0, "max": 1500},
    "right_trigger": {"center": 0, "min": 0, "max": 1510},
}
calibration.controller_state = lambda: state
calibration.save_calibration(capture)
save_payload = last_write()
assert save_payload["backend"] == "retroid"
assert save_payload["axis_leftx_min"] == -1164
assert save_payload["axis_leftx_deadzone"] == 0
assert save_payload["axis_leftx_antideadzone"] == 0
assert save_payload["trigger_right_max"] == 1464
assert save_payload["trigger_right_deadzone"] == 45
assert save_payload["trigger_right_antideadzone"] == 45

sticks = {key: capture[key] for key in ("left_x", "left_y", "right_x", "right_y")}
shaped = {"axis_leftx_min": -1200, "axis_leftx_center": 5, "axis_leftx_max": 1200,
          "axis_leftx_deadzone": 84, "axis_leftx_antideadzone": 84}
unmoved = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 0, "min": -3, "max": 4}}, shaped
)
assert {key: unmoved[key] for key in shaped} == shaped
again = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 0, "min": -1116, "max": 1166}}, shaped
)
assert again["axis_leftx_max"] == 1164
assert again["axis_leftx_center"] == 5
assert again["axis_leftx_deadzone"] == 84
repeated = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 0, "min": -1116, "max": 1166}}, again
)
assert {key: repeated[key] for key in shaped} == {key: again[key] for key in shaped}
threshold = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 0, "min": -256, "max": 256}}, {}
)
assert threshold["axis_leftx_max"] == 248

legacy_stick = {"axis_leftx_center": 0, "axis_leftx_deadzone": 84, "axis_leftx_antideadzone": 0}
masked = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 0, "min": -1140, "max": 1260}}, legacy_stick
)
assert masked["axis_leftx_center"] == 0
assert masked["axis_leftx_deadzone"] == 84
assert masked["axis_leftx_antideadzone"] == 84
visible = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 60, "min": -1140, "max": 1260}}, {}
)
assert visible["axis_leftx_center"] == -60
assert visible["axis_leftx_max"] == 1164
assert visible["axis_leftx_deadzone"] == 0
default_deadzone = calibration.calibration_from_capture(capture, {}, 70)
assert default_deadzone["axis_leftx_deadzone"] == 70
assert default_deadzone["axis_leftx_antideadzone"] == 70
assert calibration.stick_defaults(mangmi_event, "mangmi") == (1408, 70)
offset = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 40, "min": -960, "max": 1140}}, {}
)
assert offset["axis_leftx_center"] == -40
assert offset["axis_leftx_max"] == 970
resting = calibration.calibration_from_capture(
    {**sticks, "left_trigger": {"min": 60, "max": 1100}, "right_trigger": {"min": 0, "max": 40}},
    {"trigger_right_max": 1400, "trigger_right_deadzone": 50, "trigger_right_antideadzone": 50},
)
assert resting["trigger_left_max"] == 1067
assert resting["trigger_left_deadzone"] == 60 + 31
assert resting["trigger_left_antideadzone"] == 60 + 31
assert resting["trigger_right_max"] == 1400
assert resting["trigger_right_deadzone"] == 50
assert resting["trigger_right_antideadzone"] == 50

recalibrated = calibration.calibration_from_capture(
    {**sticks, "left_trigger": {"min": 0, "max": 1009}, "right_trigger": {"min": 20, "max": 1009}},
    {
        "trigger_left_max": 1100,
        "trigger_left_deadzone": 91,
        "trigger_left_antideadzone": 91,
        "trigger_right_max": 1100,
        "trigger_right_deadzone": 91,
        "trigger_right_antideadzone": 91,
    },
)
assert recalibrated["trigger_left_max"] == 1067
assert recalibrated["trigger_left_deadzone"] == 91
assert recalibrated["trigger_left_antideadzone"] == 91
assert recalibrated["trigger_right_max"] == 1067
assert recalibrated["trigger_right_deadzone"] == 111 + 29


def defuzz(value, old, fuzz):
    # Mirrors input_defuzz_abs_event() in drivers/input/input.c.
    if fuzz:
        if old - fuzz // 2 < value < old + fuzz // 2:
            return old
        if old - fuzz < value < old + fuzz:
            return (old * 3 + value) // 4
        if old - 2 * fuzz < value < old + 2 * fuzz:
            return (old + value) // 2
    return value


def pull_trigger(current, reference, rest_raw, full_raw, fuzz):
    deadzone = current.get("trigger_left_deadzone", 0)
    antideadzone = current.get("trigger_left_antideadzone", 0)
    sweep = list(range(rest_raw, full_raw, -25)) + [full_raw] * 20
    sweep += list(range(full_raw, rest_raw, 25)) + [rest_raw] * 20
    reported = 0
    seen = []
    for recording in (False, True):
        for raw in sweep:
            value = reference - raw
            value = 0 if value < deadzone else max(value - antideadzone, 0)
            reported = defuzz(value, reported, fuzz)
            if recording:
                seen.append(reported)
    return {"min": min(seen), "max": max(seen), "fuzz": fuzz}


fuzzy = {}
deadzones = []
for _ in range(5):
    pulled = pull_trigger(fuzzy, 1910, 1850, 800, 16)
    fuzzy = calibration.calibration_from_capture({**sticks, "left_trigger": pulled}, fuzzy)
    deadzones.append(fuzzy["trigger_left_deadzone"])
assert 0 < pulled["min"] <= 16
assert len(set(deadzones)) == 1, deadzones
assert abs(fuzzy["trigger_left_max"] - 1076) <= 8

fuzzy_stick = calibration.calibration_from_capture(
    {**capture, "left_x": {"center": 6, "min": -1130, "max": 1130, "fuzz": 16}},
    {"axis_leftx_center": 5, "axis_leftx_deadzone": 70, "axis_leftx_antideadzone": 70},
    70,
)
assert fuzzy_stick["axis_leftx_center"] == 5
assert fuzzy_stick["axis_leftx_max"] == 1164

calibration.save_calibration(capture)
assert last_write()["version"] == 2
assert calls[-1][0] == "write_config"
calibration.begin_calibration_intercept = lambda: True
calibration.end_calibration_intercept = lambda: True
calibration.open_session_device = lambda: None
record = calibration.call


def failing_call(action, **payload):
    if action == "reload_input_ranges":
        raise RuntimeError("restart failed")
    return record(action, **payload)


calibration.begin_session("modal")
calibration.save_calibration(capture)
calibration.call = failing_call
try:
    calibration.end_session("modal")
except RuntimeError:
    pass
else:
    raise AssertionError("failed range reload was reported as success")
calibration.call = record
calibration.begin_session("modal")
calibration.end_session("modal")
assert calls[-1][0] == "reload_input_ranges"
reloads = len(calls)
calibration.begin_session("modal")
calibration.end_session("modal")
assert len(calls) == reloads
saves = len(calls)
(retroid_params / "trigger_left_max").unlink()
try:
    calibration.save_calibration(capture)
except RuntimeError:
    pass
else:
    raise AssertionError("save with an unreadable current parameter was accepted")
assert len(calls) == saves
(retroid_params / "trigger_left_max").write_text("0", encoding="utf-8")

calibration.calibration_event = lambda: tester_event
try:
    calibration.reset_calibration_params()
except RuntimeError:
    pass
else:
    raise AssertionError("tester-only controller reset was accepted")

calibration.controller_state = lambda: {
    "supported": True,
    "canApply": False,
    "backend": "tester",
    "controls": {},
}
try:
    calibration.save_calibration(capture)
except RuntimeError:
    pass
else:
    raise AssertionError("tester-only controller save was accepted")


def load_script(path, name):
    spec = importlib.util.spec_from_loader(
        name,
        importlib.machinery.SourceFileLoader(name, str(path)),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


apply_calibration = load_script(
    root / "system_files/usr/libexec/armada/apply-input-calibration",
    "apply_input_calibration_test",
)
apply_calibration.CONFIG = work / "input-calibration.json"
apply_calibration.CALIBRATION_BACKENDS = {
    "mangmi": mangmi_params,
    "rsinput": rsinput_params,
    "retroid": retroid_params,
}

apply_calibration.CONFIG.write_text('{"axis_leftx_center": 17}\n', encoding="utf-8")
apply_calibration.main()
assert (rsinput_params / "axis_leftx_center").read_text(encoding="utf-8") == "17"
assert (retroid_params / "axis_leftx_center").read_text(encoding="utf-8") == "0"

apply_calibration.CONFIG.write_text(
    '{"backend":"retroid","axis_leftx_center":23}\n', encoding="utf-8"
)
apply_calibration.main()
assert (retroid_params / "axis_leftx_center").read_text(encoding="utf-8") == "23"
assert (retroid_params / "update_params").read_text(encoding="utf-8") == "1"


def shaped_trigger(raw, reference, params):
    value = reference - raw
    if value < params["trigger_left_deadzone"]:
        return 0
    return value - params["trigger_left_antideadzone"]


# Rest at raw 1352, full pull at raw 452.
legacy = {"backend": "retroid", "trigger_left_max": 900, "trigger_left_deadzone": 27,
          "trigger_left_antideadzone": 0}
migrated = apply_calibration.migrate(legacy, "retroid")
assert migrated["trigger_left_max"] - migrated["trigger_left_antideadzone"] == 900
for raw in range(0, 2000, 7):
    assert shaped_trigger(raw, 1552, migrated) == shaped_trigger(raw, legacy["trigger_left_max"], legacy)
assert shaped_trigger(1352, 1552, migrated) == 0
assert shaped_trigger(452, 1552, migrated) == 448

assert apply_calibration.migrate({**legacy, "version": 2}, "retroid")["trigger_left_max"] == 900
assert apply_calibration.migrate({**legacy, "backend": "rsinput"}, "rsinput")["trigger_left_max"] == 900
legacy_mangmi = apply_calibration.migrate(
    {"trigger_right_max": 1552, "trigger_right_deadzone": 0, "trigger_right_antideadzone": 0}, "mangmi"
)
assert legacy_mangmi["trigger_right_max"] == 1758
assert legacy_mangmi["trigger_right_deadzone"] == 206
assert legacy_mangmi["trigger_right_antideadzone"] == 206

apply_calibration.CONFIG.write_text(json.dumps(legacy), encoding="utf-8")
apply_calibration.main()
assert (retroid_params / "trigger_left_max").read_text(encoding="utf-8") == "1552"
assert (retroid_params / "trigger_left_deadzone").read_text(encoding="utf-8") == "679"
assert (retroid_params / "trigger_left_antideadzone").read_text(encoding="utf-8") == "652"

control = load_script(
    root / "system_files/usr/libexec/armada/armada-control",
    "armada_control_daemon_test",
)
control.CALIBRATION_BACKENDS = {
    "mangmi": mangmi_params,
    "rsinput": rsinput_params,
    "retroid": retroid_params,
}
control.CONFIG_PATHS["calibration"] = work / "daemon-calibration.json"
commands = []
control.run = lambda command, timeout=20: commands.append(command)
control.action_write_config(
    {
        "name": "calibration",
        "text": '{"backend":"retroid","axis_righty_center":29}\n',
    }
)
assert (retroid_params / "axis_righty_center").read_text(encoding="utf-8") == "29"
assert json.loads(control.CONFIG_PATHS["calibration"].read_text())["backend"] == "retroid"
assert commands == []
control.unit_active = lambda unit: False
control.action_reload_input_ranges({})
assert commands == []
control.unit_active = lambda unit: True
control.action_reload_input_ranges({})
assert commands == [
    ["/usr/bin/systemctl", "restart", "inputplumber.service"],
    ["/usr/bin/systemctl", "start", "armada-controller-type.service"],
]


def failing_run(command, timeout=20):
    raise RuntimeError("unit failed")


restart = control.run
control.run = failing_run
try:
    control.action_reload_input_ranges({})
except RuntimeError:
    pass
else:
    raise AssertionError("failed controller restart was reported as success")
control.run = restart

try:
    control.action_write_config(
        {"name": "calibration", "text": '{"backend":"unknown"}\n'}
    )
except ValueError:
    pass
else:
    raise AssertionError("unknown calibration backend was accepted")
PYEOF

echo "Input calibration tests passed"
