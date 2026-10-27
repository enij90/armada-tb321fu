#!/usr/bin/env python3
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader(
    "panel_calibration", str(ROOT / "system_files/usr/libexec/armada/panel-calibration"),
)
spec = importlib.util.spec_from_loader(loader.name, loader)
calibration = importlib.util.module_from_spec(spec)
loader.exec_module(calibration)


class SolveTest(unittest.TestCase):
    # Odin 3 ICNA3520 measurements: frame_len_120 -> Hz.
    ODIN3 = {76: 118.84, 64: 119.58, 58: 119.93, 57: 119.98, 56: 120.03, 52: 120.29}

    def test_odin3_two_points_land_next_to_the_measured_answer(self):
        value = calibration.solve([(76, self.ODIN3[76]), (64, self.ODIN3[64])], 120.0)
        self.assertIn(value, (56, 57))

    def test_wide_probe_lands_on_the_measured_answer(self):
        value = calibration.solve([(76, self.ODIN3[76]), (52, self.ODIN3[52])], 120.0)
        self.assertIn(value, (56, 57))

    def test_rate_rising_with_value_is_handled(self):
        value = calibration.solve([(100, 119.0), (120, 121.0)], 120.0)
        self.assertEqual(value, 111)


class ConfigTest(unittest.TestCase):
    def test_round_trip_ignores_other_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            calibration.CONFIG = str(Path(directory) / "panel.conf")
            key = "ARMADA_PANEL_CHIPONE_ICNA3520_FRAME_LEN_120"
            Path(calibration.CONFIG).write_text(f"junk\n{key}=56\nARMADA_PANEL_CHIPONE_ICNA3520_FRAME_LEN_60=abc\n")
            self.assertEqual(calibration.read_config(), {key: 56})
            calibration.write_config({key: 57})
            self.assertEqual(Path(calibration.CONFIG).read_text(), f"{key}=57\n")

    def test_panel_id_from_compatible(self):
        with tempfile.TemporaryDirectory() as directory:
            node = Path(directory) / "of_node"
            node.mkdir()
            (node / "compatible").write_bytes(b"chipone,icna3512\0")
            self.assertEqual(calibration.panel_id(directory), "CHIPONE_ICNA3512")
            self.assertEqual(calibration.config_key(directory, "frame_len_120"),
                             "ARMADA_PANEL_CHIPONE_ICNA3512_FRAME_LEN_120")


class ModeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.ctrl = root / "dsi"
        (self.ctrl / "of_node").mkdir(parents=True)
        (self.ctrl / "of_node" / "compatible").write_bytes(b"chipone,icna3512\0")
        (self.ctrl / "frame_len_120").write_text("156\n")
        self.saved = {name: getattr(calibration, name)
                      for name in ("CONFIG", "DEFAULTS", "controls", "calibrate", "current_rate")}
        calibration.current_rate = lambda: 120.63
        calibration.CONFIG = str(root / "panel.conf")
        calibration.DEFAULTS = str(root / "defaults.json")
        calibration.controls = lambda: [str(self.ctrl)]

    def tearDown(self):
        for name, value in self.saved.items():
            setattr(calibration, name, value)
        self.directory.cleanup()

    def status(self, mode="status", *args):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(calibration.main(["x", mode, *args]), 0)
        return json.loads(out.getvalue())

    def test_status_without_a_panel(self):
        calibration.controls = lambda: []
        self.assertEqual(self.status(), {"supported": False})

    def test_apply_writes_the_saved_value(self):
        key = "ARMADA_PANEL_CHIPONE_ICNA3512_FRAME_LEN_120"
        Path(calibration.CONFIG).write_text(f"{key}=165\n")
        self.assertEqual(calibration.main(["x"]), 0)
        self.assertEqual((self.ctrl / "frame_len_120").read_text(), "165\n")
        self.assertEqual(self.status()["saved"]["frame_len_120"], 165)
        self.assertEqual(self.status("rate"), {"hz": 120.63, "attr": "frame_len_120"})
        self.assertEqual(self.status()["defaults"]["frame_len_120"], 156)
        self.assertEqual(self.status()["live"]["frame_len_120"], 165)

    def test_step_moves_past_the_default_in_both_directions(self):
        # The Portal starts fast (120.6 Hz at 156) and calibrates slower.
        calibration.current_rate = lambda: 120.05
        self.assertEqual(calibration.main(["x"]), 0)
        self.assertEqual(self.status("step", "frame_len_120", "slower")["value"], 157)
        self.assertEqual(self.status("step", "frame_len_120", "faster")["value"], 156)
        self.assertEqual(self.status("step", "frame_len_120", "faster")["value"], 155)
        self.assertEqual((self.ctrl / "frame_len_120").read_text(), "155\n")

    def test_step_faster_has_no_ceiling(self):
        calibration.current_rate = lambda: 120.15
        self.assertEqual(self.status("step", "frame_len_120", "faster"), {"value": 155, "hz": 120.15, "limit": None})
        self.assertEqual((self.ctrl / "frame_len_120").read_text(), "155\n")

    def test_save_stores_the_live_value_and_drops_the_default(self):
        key = "ARMADA_PANEL_CHIPONE_ICNA3512_FRAME_LEN_120"
        self.assertEqual(calibration.main(["x"]), 0)
        self.assertEqual(calibration.main(["x", "set", "frame_len_120", "160"]), 0)
        self.assertEqual(self.status("save", "frame_len_120"), {"saved": 160})
        self.assertEqual(calibration.read_config(), {key: 160})
        calibration.main(["x", "set", "frame_len_120", "156"])
        self.assertEqual(self.status("save", "frame_len_120"), {"saved": None})
        self.assertEqual(calibration.read_config(), {})

    def test_calibrate_does_not_save(self):
        calibration.calibrate = lambda ctrl: (150, 120.05)
        self.assertEqual(self.status("calibrate"), {"value": 150, "hz": 120.05})
        self.assertFalse(Path(calibration.CONFIG).exists())

    def test_rate_does_not_apply_saved_values(self):
        key = "ARMADA_PANEL_CHIPONE_ICNA3512_FRAME_LEN_120"
        Path(calibration.CONFIG).write_text(f"{key}=165\n")
        self.status("rate")
        self.assertEqual((self.ctrl / "frame_len_120").read_text(), "156\n")

    def test_calibrate_failure_exits_with_the_reason(self):
        calibration.calibrate = lambda ctrl: "The display is off."
        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(calibration.main(["x", "calibrate"]), 1)
        self.assertEqual(err.getvalue(), "The display is off.\n")

    def test_unknown_mode_is_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(calibration.main(["x", "calibrat"]), 2)
            self.assertEqual(calibration.main(["x", "step", "frame_len_120", "up"]), 2)
            self.assertEqual(calibration.main(["x", "set", "brightness", "5"]), 2)


class ProbeTest(unittest.TestCase):
    def test_locked_value_is_not_calibratable(self):
        saved = calibration.read_attr, calibration.write_attr, calibration.measure
        try:
            calibration.read_attr = lambda ctrl, attr: 200

            def write(ctrl, attr, value):
                if value != 200:
                    raise OSError("locked")
            calibration.write_attr = write
            calibration.measure = lambda fd, pipe: 60.0
            self.assertIs(calibration.probe_panel(None, "dsi", "frame_len_60", 0, 60.0), False)
        finally:
            calibration.read_attr, calibration.write_attr, calibration.measure = saved



class ConvergeTest(unittest.TestCase):
    # Thor ICNA3520: the kernel refuses values below 44.
    THOR = {44: 120.02, 45: 119.95, 46: 119.89}
    # Odin 3 ICNA3520: 54 and below turn the picture gray.
    ODIN3 = {54: 120.15, 55: 120.12, 56: 120.05, 57: 119.98}

    def run_converge(self, start, rates=None):
        rates = rates or self.THOR
        saved = calibration.write_attr, calibration.measure
        current = {}

        def write(ctrl, attr, value):
            if value < 44:
                raise OSError("out of range")
            current["value"] = value
        try:
            calibration.write_attr = write
            calibration.measure = lambda fd, pipe: rates[current["value"]]
            return calibration.converge(None, "dsi", "frame_len_120", 0, start, -1, 120.012, 120.096, 120.0)
        finally:
            calibration.write_attr, calibration.measure = saved

    def test_lands_inside_the_window(self):
        self.assertEqual(self.run_converge(45), (44, 120.02))

    def test_backs_off_rates_above_the_ceiling(self):
        self.assertEqual(self.run_converge(54, self.ODIN3), (56, 120.05))

    def test_settles_on_the_floor_when_the_window_is_out_of_range(self):
        self.assertEqual(self.run_converge(45, {44: 120.005, 45: 119.95}), (44, 120.005))

    def test_backs_off_an_estimate_below_the_floor(self):
        self.assertEqual(self.run_converge(41), (44, 120.02))


if __name__ == "__main__":
    unittest.main()
