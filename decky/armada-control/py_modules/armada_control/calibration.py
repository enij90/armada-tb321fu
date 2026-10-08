import copy
import fcntl
import json
import struct
import subprocess
import time
from pathlib import Path

from .privileged import call
from .proc import clean_env
from .system import read_text

INPUT_CALIBRATION_CONFIG = Path("/etc/armada/input-calibration.json")
CALIBRATION_BACKENDS = {
    "mangmi": Path("/sys/module/mangmi_pocket_max/parameters"),
    "rsinput": Path("/sys/module/rsinput/parameters"),
    "retroid": Path("/sys/module/retroid/parameters"),
}
INPUTPLUMBER_INTERCEPT = Path("/usr/libexec/armada/inputplumber-intercept")
INPUTPLUMBER_SERVICE = "org.shadowblip.InputPlumber"
INPUTPLUMBER_COMPOSITE_IFACE = "org.shadowblip.Input.CompositeDevice"
ABS_CODES = {
    "left_x": 0,
    "left_y": 1,
    "right_x": 3,
    "right_y": 4,
}
TRIGGER_CODES = {
    "default": {"left_trigger": (2, 10), "right_trigger": (5, 9)},
    "mangmi": {"left_trigger": (20,), "right_trigger": (21,)},
    "retroid": {"left_trigger": (20,), "right_trigger": (21,)},
}
CALIBRATION_PARAMS = (
    "axis_leftx_min",
    "axis_leftx_center",
    "axis_leftx_max",
    "axis_leftx_deadzone",
    "axis_leftx_antideadzone",
    "axis_lefty_min",
    "axis_lefty_center",
    "axis_lefty_max",
    "axis_lefty_deadzone",
    "axis_lefty_antideadzone",
    "axis_rightx_min",
    "axis_rightx_center",
    "axis_rightx_max",
    "axis_rightx_deadzone",
    "axis_rightx_antideadzone",
    "axis_righty_min",
    "axis_righty_center",
    "axis_righty_max",
    "axis_righty_deadzone",
    "axis_righty_antideadzone",
    "trigger_left_max",
    "trigger_left_deadzone",
    "trigger_left_antideadzone",
    "trigger_right_max",
    "trigger_right_deadzone",
    "trigger_right_antideadzone",
)
# Driver defaults: 0x610 in rsinput and retroid, MCU_BRAKE_MAX/MCU_GAS_MAX in mangmi.
TRIGGER_DEFAULT_MAX = {
    "mangmi": {"trigger_left": 1910, "trigger_right": 1758},
    "retroid": {"trigger_left": 1552, "trigger_right": 1552},
    "rsinput": {"trigger_left": 1552, "trigger_right": 1552},
}
# Driver defaults as (range, deadzone); rsinput device trees may override them.
STICK_DEFAULTS = {
    "mangmi": (1408, 70),
    "retroid": (1408, 0),
    "rsinput": (1408, 0),
}
STICK_MIN_TRAVEL = 256
# 2: trigger deadzones are relative to the driver's fixed release reference.
CALIBRATION_VERSION = 2
TRIGGER_MIN_TRAVEL = 256
# The saved extreme is a single peak sample that a normal full push falls just short of.
OUTER_MARGIN_PERCENT = 3
_inputplumber_events_cache = {"time": 0, "events": []}
_calibration_session_token = None
_session_device = None
_session_fd = None
_ranges_stale = False


def input_events():
    events = []
    for event in sorted(Path("/sys/class/input").glob("event*")):
        name = read_text(event / "device/name")
        phys = read_text(event / "device/phys")
        dev = Path("/dev/input") / event.name
        if name and dev.exists():
            events.append(input_event_from_path(dev, name=name, phys=phys, source="sysfs"))
    return events


def input_event_from_path(path, name=None, phys=None, source="sysfs"):
    dev = Path(path)
    sysfs = Path("/sys/class/input") / dev.name
    return {
        "event": dev.name,
        "path": str(dev),
        "name": name if name is not None else read_text(sysfs / "device/name"),
        "phys": phys if phys is not None else read_text(sysfs / "device/phys"),
        "source": source,
    }


def busctl_get_property(path, interface, prop):
    try:
        result = subprocess.run(
            ["busctl", "--system", "--json=short", "get-property", INPUTPLUMBER_SERVICE, path, interface, prop],
            check=True,
            capture_output=True,
            text=True,
            timeout=1,
            env=clean_env(),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    try:
        payload = json.loads(result.stdout)
    except ValueError:
        return None
    data = payload.get("data")
    if str(payload.get("type", "")).startswith("a"):
        return data if isinstance(data, list) else []
    if isinstance(data, list):
        return data[0] if len(data) == 1 else data
    return data


def begin_calibration_intercept():
    try:
        call("inputplumber_intercept", mode="overlay")
        return True
    except Exception:
        pass
    try:
        subprocess.run(
            [str(INPUTPLUMBER_INTERCEPT), "overlay"],
            check=True,
            capture_output=True,
            text=True,
            timeout=1,
            env=clean_env(),
        )
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def end_calibration_intercept():
    try:
        call("inputplumber_intercept", mode="reset")
        return True
    except Exception:
        pass
    try:
        subprocess.run(
            [str(INPUTPLUMBER_INTERCEPT), "reset"],
            check=True,
            capture_output=True,
            text=True,
            timeout=1,
            env=clean_env(),
        )
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def inputplumber_source_events():
    now = time.monotonic()
    if now - _inputplumber_events_cache["time"] < 2:
        return copy.deepcopy(_inputplumber_events_cache["events"])

    try:
        result = subprocess.run(
            ["busctl", "--system", "--list", "--no-pager", "--no-legend"],
            check=True,
            capture_output=True,
            text=True,
            timeout=1,
            env=clean_env(),
        )
    except (OSError, subprocess.SubprocessError):
        _inputplumber_events_cache.update({"time": now, "events": []})
        return []
    if INPUTPLUMBER_SERVICE not in result.stdout:
        _inputplumber_events_cache.update({"time": now, "events": []})
        return []

    try:
        tree = subprocess.run(
            ["busctl", "--system", "tree", INPUTPLUMBER_SERVICE],
            check=True,
            capture_output=True,
            text=True,
            timeout=1,
            env=clean_env(),
        )
    except (OSError, subprocess.SubprocessError):
        _inputplumber_events_cache.update({"time": now, "events": []})
        return []

    events = []
    seen = set()
    for line in tree.stdout.splitlines():
        path = line.strip(" │├─└")
        if not path.startswith("/org/shadowblip/InputPlumber/CompositeDevice"):
            continue
        paths = busctl_get_property(path, INPUTPLUMBER_COMPOSITE_IFACE, "SourceDevicePaths")
        if not isinstance(paths, list):
            continue
        for source_path in paths:
            dev = Path(source_path)
            if dev.name in seen or not str(dev).startswith("/dev/input/event") or not dev.exists():
                continue
            event = input_event_from_path(dev, source="inputplumber")
            if event["name"]:
                events.append(event)
                seen.add(dev.name)
    _inputplumber_events_cache.update({"time": now, "events": copy.deepcopy(events)})
    return events


def calibration_event():
    events = inputplumber_source_events()
    if not events:
        events = input_events()
    preferred = (
        lambda event: "mangmi-pocket-max" in event["phys"].casefold()
        or "mangmi pocket max joypad" in event["name"].casefold(),
        lambda event: "rsinput-gamepad" in event["phys"].casefold() or "rsinput" in event["name"].casefold(),
        lambda event: "retroid-pocket-gamepad" in event["phys"].casefold()
        or "retroid pocket gamepad" in event["name"].casefold(),
        lambda event: "AYANEO Controller" in event["name"],
        lambda event: event["name"] == "Microsoft X-Box 360 pad",
    )
    ignored = ("InputPlumber", "DualSense", "Keyboard", "Touchpad", "Motion Sensors", "Headset")
    for match in preferred:
        for event in events:
            if any(token in event["name"] for token in ignored):
                continue
            if match(event):
                return event
    for event in events:
        if any(token in event["name"] for token in ignored):
            continue
        if "pad" in event["name"].casefold() or "controller" in event["name"].casefold() or "gamepad" in event["name"].casefold():
            return event
    return None


def eviocgabs(code):
    return 0x80184540 + code


def read_abs(fd, code):
    data = fcntl.ioctl(fd, eviocgabs(code), b"\0" * 24)
    if len(data) != 24:
        raise OSError(f"unexpected EVIOCGABS response length for code {code}")
    value, minimum, maximum, fuzz, flat, resolution = struct.unpack("iiiiii", data)
    if minimum == maximum:
        raise OSError(f"analog control {code} has no range")
    return {
        "value": value,
        "min": minimum,
        "max": maximum,
        "flat": flat,
        "fuzz": fuzz,
        "resolution": resolution,
    }


def event_backend(event):
    if not event:
        return None
    name = str(event.get("name", "")).casefold()
    phys = str(event.get("phys", "")).casefold()
    if "mangmi pocket max joypad" in name or "mangmi-pocket-max" in phys:
        return "mangmi"
    if "rsinput" in name or "rsinput-gamepad" in phys:
        return "rsinput"
    if "retroid pocket gamepad" in name or "retroid-pocket-gamepad" in phys:
        return "retroid"
    return None


def calibration_backend(event=None):
    if event is None:
        event = calibration_event()
    backend = event_backend(event)
    if backend and CALIBRATION_BACKENDS[backend].exists():
        return backend
    return None


def read_backend_controls(fd, backend=None):
    controls = {}
    for name, code in ABS_CODES.items():
        try:
            controls[name] = read_abs(fd, code)
        except OSError:
            pass
    trigger_codes = TRIGGER_CODES.get(backend, TRIGGER_CODES["default"])
    for name, codes in trigger_codes.items():
        for code in codes:
            try:
                controls[name] = read_abs(fd, code)
                break
            except OSError:
                pass
    return controls


def build_state(event, controls):
    backend = calibration_backend(event)
    return {
        "supported": bool(controls),
        "reason": "" if controls else "Controller has no readable analog controls",
        "controls": controls,
        "event": event,
        "canApply": bool(backend),
        "backend": backend or "tester",
    }


def open_session_device():
    # Resolve the controller once per modal session and hold the fd open so each
    # ~50ms poll is a couple of ioctls, not a fresh device-enumeration + open.
    global _session_device, _session_fd
    close_session_device()
    event = calibration_event()
    if not event:
        return None
    try:
        _session_fd = open(event["path"], "rb", buffering=0)
        _session_device = event
    except OSError:
        _session_fd = None
        _session_device = None
    return _session_device


def close_session_device():
    global _session_device, _session_fd
    if _session_fd is not None:
        try:
            _session_fd.close()
        except OSError:
            pass
    _session_fd = None
    _session_device = None


def controller_state():
    if _session_fd is not None and _session_device is not None:
        try:
            return build_state(
                _session_device,
                read_backend_controls(_session_fd.fileno(), event_backend(_session_device)),
            )
        except OSError:
            # Node went away (device re-registered); re-resolve once.
            if open_session_device() and _session_fd is not None:
                try:
                    return build_state(
                        _session_device,
                        read_backend_controls(_session_fd.fileno(), event_backend(_session_device)),
                    )
                except OSError:
                    close_session_device()
    event = calibration_event()
    if not event:
        return {"supported": False, "reason": "No controller input device found", "controls": {}, "event": None}
    try:
        with open(event["path"], "rb", buffering=0) as f:
            controls = read_backend_controls(f.fileno(), event_backend(event))
    except OSError as exc:
        return {"supported": False, "reason": str(exc), "controls": {}, "event": event}
    return build_state(event, controls)


def read_calibration_params(backend=None):
    params = {}
    if backend is None:
        backend = calibration_backend()
    parameters = CALIBRATION_BACKENDS.get(backend)
    if parameters is None or not parameters.exists():
        return params
    for name in CALIBRATION_PARAMS:
        text = read_text(parameters / name)
        if text:
            try:
                params[name] = int(text)
            except ValueError:
                pass
    return params


def device_tree_u32(event, name):
    node = Path("/sys/class/input") / str(event.get("event", "")) / "device/device/of_node" / name
    try:
        data = node.read_bytes()
    except OSError:
        return None
    return int.from_bytes(data[:4], "big") if len(data) >= 4 else None


def stick_defaults(event, backend):
    axis_range, axis_deadzone = STICK_DEFAULTS[backend]
    if backend == "rsinput":
        axis_range = device_tree_u32(event, "axis-range") or axis_range
        axis_deadzone = device_tree_u32(event, "axis-deadzone") or axis_deadzone
    return axis_range, axis_deadzone


def reset_calibration_params():
    global _ranges_stale
    event = calibration_event()
    backend = calibration_backend(event)
    if backend is None:
        raise RuntimeError("controller calibration is not supported on this device")
    params = {}
    axis_range, axis_deadzone = stick_defaults(event, backend)
    trigger_deadzone = {"trigger_left": 0, "trigger_right": 0}
    if backend == "rsinput":
        trigger_deadzone["trigger_left"] = device_tree_u32(event, "trigger-left-deadzone") or 0
        trigger_deadzone["trigger_right"] = device_tree_u32(event, "trigger-right-deadzone") or 0
    for axis in ("axis_leftx", "axis_lefty", "axis_rightx", "axis_righty"):
        params[f"{axis}_min"] = -axis_range
        params[f"{axis}_center"] = 0
        params[f"{axis}_max"] = axis_range
        params[f"{axis}_deadzone"] = axis_deadzone
        params[f"{axis}_antideadzone"] = 0
    for trigger in ("trigger_left", "trigger_right"):
        params[f"{trigger}_max"] = TRIGGER_DEFAULT_MAX[backend][trigger]
        params[f"{trigger}_deadzone"] = trigger_deadzone[trigger]
        params[f"{trigger}_antideadzone"] = 0
    params["backend"] = backend
    params["version"] = CALIBRATION_VERSION
    call("write_config", name="calibration", text=json.dumps(params, indent=2, sort_keys=True) + "\n")
    _ranges_stale = True
    return calibration_status()


def calibration_from_capture(capture, current=None, stick_deadzone=0):
    current = current or {}

    def axis_params(prefix, x_key, y_key):
        result = {}
        for suffix, key in (("x", x_key), ("y", y_key)):
            values = capture.get(key) or {}
            axis = f"{prefix}{suffix}"
            antideadzone = int(current.get(f"{axis}_antideadzone", 0))
            fuzz = int(values.get("fuzz", 0))

            def unshaped(value):
                # The driver subtracts the antideadzone; evdev fuzz can hold a released axis off zero.
                value = int(value)
                if abs(value) <= fuzz:
                    return 0
                return value + antideadzone if value > 0 else value - antideadzone

            minimum = unshaped(values.get("min", 0))
            maximum = unshaped(values.get("max", 0))
            center = unshaped(values.get("center", 0))
            inner = min(center - minimum, maximum - center)
            if inner < STICK_MIN_TRAVEL:
                for name in ("min", "center", "max", "deadzone", "antideadzone"):
                    if f"{axis}_{name}" in current:
                        result[f"{axis}_{name}"] = int(current[f"{axis}_{name}"])
                continue
            inner = inner * (100 - OUTER_MARGIN_PERCENT) // 100
            result[f"{axis}_min"] = -inner
            result[f"{axis}_center"] = int(current.get(f"{axis}_center", 0)) - center
            result[f"{axis}_max"] = inner
            deadzone = stick_deadzone
            if center == 0:
                # The active deadzone may be hiding a resting offset, so never shrink it.
                deadzone = max(deadzone, int(current.get(f"{axis}_deadzone", 0)))
            result[f"{axis}_deadzone"] = deadzone
            result[f"{axis}_antideadzone"] = deadzone
        return result
    params = {}
    params.update(axis_params("axis_left", "left_x", "left_y"))
    params.update(axis_params("axis_right", "right_x", "right_y"))
    for name, key in (("trigger_left", "left_trigger"), ("trigger_right", "right_trigger")):
        values = capture.get(key) or {}
        minimum = int(values.get("min", 0))
        maximum = int(values.get("max", 0))
        current_deadzone = int(current.get(f"{name}_deadzone", 0))
        current_antideadzone = int(current.get(f"{name}_antideadzone", 0))
        if minimum <= int(values.get("fuzz", 0)):
            # evdev fuzz filtering can hold a released trigger slightly above zero.
            minimum = 0
        if maximum - minimum < TRIGGER_MIN_TRAVEL:
            for suffix in ("max", "deadzone", "antideadzone"):
                if f"{name}_{suffix}" in current:
                    params[f"{name}_{suffix}"] = int(current[f"{name}_{suffix}"])
            continue
        # Samples arrive with the active antideadzone already subtracted.
        full = maximum + current_antideadzone
        rest = minimum + current_antideadzone if minimum > 0 else 0
        margin = max(int((full - rest) * 0.03), 4)
        # A rest reading of 0 may be hidden by the active deadzone, so never shrink it.
        deadzone = rest + margin if minimum > 0 else max(current_deadzone, margin)
        params[f"{name}_max"] = full * (100 - OUTER_MARGIN_PERCENT) // 100
        params[f"{name}_deadzone"] = deadzone
        params[f"{name}_antideadzone"] = deadzone
    return params


def merge_capture_sample(capture, state):
    merged = copy.deepcopy(capture or {})
    for name, control in state.get("controls", {}).items():
        if name not in merged:
            continue
        value = int(control.get("value", 0))
        merged[name]["min"] = min(int(merged[name].get("min", value)), value)
        merged[name]["max"] = max(int(merged[name].get("max", value)), value)
        merged[name]["fuzz"] = int(control.get("fuzz", 0))
    return merged


def calibration_status():
    state = controller_state()
    state["saved"] = INPUT_CALIBRATION_CONFIG.exists()
    backend = state.get("backend") if state.get("canApply") else None
    state["params"] = read_calibration_params(backend) if backend else {}
    if state.get("supported") and not state.get("canApply"):
        state["reason"] = "Live tester only on this device"
    return state


def save_calibration(capture):
    global _ranges_stale
    state = controller_state()
    backend = state.get("backend") if state.get("canApply") else None
    if backend not in CALIBRATION_BACKENDS:
        raise RuntimeError("controller calibration is not supported on this device")
    capture = merge_capture_sample(capture, state)
    current = read_calibration_params(backend)
    if any(name not in current for name in CALIBRATION_PARAMS):
        # Untouched controls are saved from these; a partial read would drop them at boot.
        raise RuntimeError("could not read the current controller calibration")
    _, stick_deadzone = stick_defaults(state.get("event") or {}, backend)
    params = calibration_from_capture(capture, current, stick_deadzone)
    params["backend"] = backend
    params["version"] = CALIBRATION_VERSION
    call("write_config", name="calibration", text=json.dumps(params, indent=2, sort_keys=True) + "\n")
    _ranges_stale = True
    return calibration_status()


def begin_session(token=None):
    global _calibration_session_token
    _calibration_session_token = str(token or "default")
    open_session_device()
    return begin_calibration_intercept()


def end_session(token=None):
    global _calibration_session_token, _ranges_stale
    if _calibration_session_token != str(token or "default"):
        return False
    _calibration_session_token = None
    close_session_device()
    ended = end_calibration_intercept()
    if _ranges_stale:
        # Restarting InputPlumber any earlier would drop the calibration intercept.
        call("reload_input_ranges")
        _ranges_stale = False
    return ended
