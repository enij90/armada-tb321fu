#!/usr/bin/env python3
import importlib.machinery
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "system_files/usr/lib/armada"))
loader = importlib.machinery.SourceFileLoader(
    "screen_flip_control", str(ROOT / "system_files/usr/libexec/armada/armada-control"),
)
spec = importlib.util.spec_from_loader(loader.name, loader)
control = importlib.util.module_from_spec(spec)
loader.exec_module(control)
base_matrices = control.touch_base_matrices
APPLY = [
    ["/usr/bin/udevadm", "control", "--reload"],
    ["/usr/bin/udevadm", "trigger", "--action=change", "--subsystem-match=input"],
    ["/usr/bin/systemctl", "restart", "inputplumber"],
]


class ScreenFlipTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.dir = Path(directory.name)
        self.flip = self.dir / "environment.d/90-armada-screen-flip.conf"
        self.gyro = self.dir / "gyro.conf"
        self.touch = self.dir / "91-armada-screen-flip.rules"
        self.touch_devices = {}
        (self.dir / "ssc/lenovo-legion-tab").mkdir(parents=True)
        self.env = {"ARMADA_DEVICE_ID": "lenovo-legion-tab", "ARMADA_PANEL_ORIENTATION": "right"}
        self.commands = []
        for target, replacement in (
            ("SCREEN_FLIP_CONFIG", self.flip),
            ("GYRO_CONFIG", self.gyro),
            ("SSC_DATA", self.dir / "ssc"),
            ("TOUCH_FLIP_RULES", self.touch),
            ("SCREEN_FLIP_PENDING", self.dir / "flip-pending"),
            # udev reports the applied matrix; the rule file keeps the device's own.
            ("touch_devices", lambda: base_matrices() or dict(self.touch_devices)),
            ("device_env", lambda: dict(self.env)),
            ("run", lambda command, timeout=20: self.commands.append(command)),
        ):
            mock = patch.object(control, target, replacement)
            mock.start()
            self.addCleanup(mock.stop)

    def set(self, flipped):
        return control.action_set_screen_flip({"flipped": flipped})

    def test_flip_writes_the_opposite_orientation_and_reverses_the_gyro(self):
        self.assertEqual(control.action_get_screen_flip({}), {"supported": True, "flipped": False})
        state = self.set(True)
        self.assertTrue(state["flipped"])
        self.assertEqual(self.flip.read_text(), "ORIENTATION=left\n")
        self.assertEqual(state["gyro"]["orientation"], "pitch-yaw")
        state = self.set(False)
        self.assertFalse(state["flipped"])
        self.assertFalse(self.flip.exists())
        self.assertEqual(state["gyro"]["orientation"], "default")
        self.assertEqual(self.gyro.read_text(), "")
        # Touch and gyro wait for Game Mode, like the screen.
        self.assertEqual(self.commands, [])
        control.apply_pending_screen_flip()
        self.assertEqual(self.commands, APPLY)
        self.commands.clear()
        control.apply_pending_screen_flip()
        self.assertEqual(self.commands, [])

    def test_game_mode_restart_applies_the_flip_first(self):
        self.set(True)
        control.action_restart_game_mode({})
        self.assertEqual(self.commands, APPLY + [["/usr/bin/systemctl", "--no-block", "restart", "sddm.service"]])

    def test_setting_the_current_state_changes_nothing(self):
        self.set(False)
        self.set(True)
        self.set(True)
        self.assertEqual(self.gyro.read_text(), "ARMADA_GYRO_CORRECTION=-1,0,0;0,-1,0;0,0,1\n")
        self.assertEqual(self.commands, [])

    def test_gyro_presets_compose_with_the_flip(self):
        self.gyro.write_text("ARMADA_GYRO_CORRECTION=1,0,0;0,-1,0;0,0,-1\n")
        self.assertEqual(self.set(True)["gyro"]["orientation"], "roll-yaw")
        self.gyro.write_text("ARMADA_GYRO_CORRECTION=0,1,0;-1,0,0;0,0,1\n")
        self.assertEqual(self.set(False)["gyro"]["orientation"], "custom")
        self.assertEqual(self.gyro.read_text(), "ARMADA_GYRO_CORRECTION=0,1,0;-1,0,0;0,0,1\n")

    def test_flip_turns_each_touch_device_on_top_of_its_matrix(self):
        self.touch_devices = {"NVTCapacitiveTouchScreen": "0 1 0 -1 0 1", "Plain Touch": "1 0 0 0 1 0"}
        self.set(True)
        rules = self.touch.read_text()
        self.assertIn('ATTRS{name}=="NVTCapacitiveTouchScreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 -1 1 1 0 0"', rules)
        self.assertIn('ATTRS{name}=="Plain Touch", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"', rules)
        control.apply_pending_screen_flip()
        # Now udev reports the flipped matrices: off and on again must not stack.
        self.touch_devices = {"NVTCapacitiveTouchScreen": "0 -1 1 1 0 0", "Plain Touch": "-1 0 1 0 -1 1"}
        self.set(False)
        self.assertIn('ATTRS{name}=="Plain Touch", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0"', self.touch.read_text())
        self.set(True)
        self.assertEqual(self.touch.read_text(), rules)
        self.set(False)
        control.apply_pending_screen_flip()
        self.assertFalse(self.touch.exists())

    def test_off_before_game_mode_restarts_leaves_no_rule(self):
        self.touch_devices = {"Plain Touch": "1 0 0 0 1 0"}
        self.set(True)
        self.set(False)
        control.apply_pending_screen_flip()
        self.assertFalse(self.touch.exists())

    def test_orientations(self):
        for panel, flipped in (("left", "right"), ("normal", "upsidedown"), ("", "upsidedown")):
            self.env["ARMADA_PANEL_ORIENTATION"] = panel
            self.flip.unlink(missing_ok=True)
            self.set(True)
            self.assertEqual(self.flip.read_text(), f"ORIENTATION={flipped}\n")

    def test_another_device_flip_file_reads_as_not_flipped(self):
        self.flip.parent.mkdir(parents=True)
        self.flip.write_text("ORIENTATION=right\n")
        self.assertFalse(control.action_get_screen_flip({})["flipped"])

    def test_dual_screen_and_bad_input(self):
        self.env["ARMADA_SECONDARY_CONNECTOR"] = "DSI-2"
        self.assertEqual(control.action_get_screen_flip({}), {"supported": False, "flipped": False})
        with self.assertRaises(RuntimeError):
            self.set(True)
        for bad in (None, 1, "true"):
            with self.assertRaises(ValueError):
                control.action_set_screen_flip({"flipped": bad})


if __name__ == "__main__":
    unittest.main()
