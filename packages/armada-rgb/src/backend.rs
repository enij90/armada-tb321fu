//! Hardware backends for RGB lighting.

use crate::{rgb_saturation, ColorCorrection, LightingConfig};
use anyhow::{bail, Context, Result};
use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::FileTypeExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus};
use std::thread;
use std::time::Duration;

const SERIAL_FRAME_GAP: Duration = Duration::from_millis(40);
const GCM_PACKET_GAP: Duration = Duration::from_millis(30);
const SERIAL_FRAME_REPEATS: usize = 3;

pub enum LightingBackend {
    GcmHid(GcmHidBackend),
    Serial(SerialBackend),
    Channels(ChannelBackend),
    Multicolor(MulticolorBackend),
    Unsupported(String),
}

impl LightingBackend {
    pub fn apply(&self, config: &LightingConfig) -> Result<()> {
        match self {
            Self::GcmHid(backend) => backend.apply(config),
            Self::Serial(backend) => backend.apply(config),
            Self::Channels(backend) => backend.apply(config),
            Self::Multicolor(backend) => backend.apply(config),
            Self::Unsupported(reason) => bail!("{reason}"),
        }
    }

    pub fn unsupported_reason(&self) -> Option<&str> {
        match self {
            Self::GcmHid(_) | Self::Serial(_) | Self::Channels(_) | Self::Multicolor(_) => None,
            Self::Unsupported(reason) => Some(reason),
        }
    }

    pub(crate) fn blanks_on_sleep(&self) -> bool {
        matches!(self, Self::Serial(_))
    }

    pub(crate) fn default_correction(&self) -> Option<ColorCorrection> {
        match self {
            Self::GcmHid(backend) => backend.correction.clone(),
            Self::Serial(backend) => backend.correction.clone(),
            Self::Channels(backend) => backend.correction.clone(),
            Self::Multicolor(backend) => backend.correction.clone(),
            Self::Unsupported(_) => None,
        }
    }
}

/// GameSir "GCM" lighting over a controller's vendor HID interface, as on the
/// Lenovo Legion G9 that docks to the Legion Tab Gen 3. Colors are HSB; each
/// strip takes `05 0C 0C 01 <strip> H S B <effect> <speed> <brightness>` plus
/// a byte sum. The controller keeps the last setting itself.
pub struct GcmHidBackend {
    hidraw_root: PathBuf,
    dev_root: PathBuf,
    hid_id: String,
    strips: Vec<u8>,
    correction: Option<ColorCorrection>,
}

const GCM_EFFECT_STATIC: u8 = 0x01;
const GCM_EFFECT_OFF: u8 = 0xFF;
const GCM_SPEED: u8 = 0x80;
const GCM_BRIGHTNESS: u8 = 0xFF;
// Usage page 0xFF7A: the interface that answers GCM commands.
const GCM_DESCRIPTOR_PREFIX: [u8; 3] = [0x06, 0x7A, 0xFF];

impl GcmHidBackend {
    pub fn new(hidraw_root: PathBuf, dev_root: PathBuf, vendor: &str, product: &str, strips: Vec<u8>) -> Self {
        Self {
            hidraw_root,
            dev_root,
            hid_id: format!(
                "HID_ID=0003:{:0>8}:{:0>8}",
                vendor.to_ascii_uppercase(),
                product.to_ascii_uppercase()
            ),
            strips,
            correction: None,
        }
    }

    pub(crate) fn with_correction(mut self, correction: Option<ColorCorrection>) -> Self {
        self.correction = correction;
        self
    }

    fn find_device(&self) -> Result<PathBuf> {
        let entries = fs::read_dir(&self.hidraw_root)
            .with_context(|| format!("read {}", self.hidraw_root.display()))?;
        let mut names: Vec<String> = entries
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .filter(|name| name.starts_with("hidraw"))
            .collect();
        names.sort();
        for name in names {
            let device: PathBuf = self.hidraw_root.join(&name).join("device");
            let uevent: String = fs::read_to_string(device.join("uevent")).unwrap_or_default();
            if !uevent.lines().any(|line| line.eq_ignore_ascii_case(&self.hid_id)) {
                continue;
            }
            let descriptor: Vec<u8> = fs::read(device.join("report_descriptor")).unwrap_or_default();
            if descriptor.starts_with(&GCM_DESCRIPTOR_PREFIX) {
                return Ok(self.dev_root.join(name));
            }
        }
        bail!("controller not connected")
    }

    fn apply(&self, config: &LightingConfig) -> Result<()> {
        let path: PathBuf = self.find_device()?;
        let [hue, saturation, value]: [u8; 3] = if config.enabled {
            let [h, s, v] = gcm_hsb(corrected_rgb(config, self.correction.as_ref()));
            [h, s, scale(config.brightness, u32::from(v)) as u8]
        } else {
            [0, 0, 0]
        };
        let effect: u8 = if config.enabled { GCM_EFFECT_STATIC } else { GCM_EFFECT_OFF };
        let mut device: File = OpenOptions::new()
            .write(true)
            .open(&path)
            .with_context(|| format!("open {}", path.display()))?;
        for (index, strip) in self.strips.iter().enumerate() {
            if index > 0 {
                thread::sleep(GCM_PACKET_GAP);
            }
            let packet: [u8; 13] = gcm_strip_packet(*strip, [hue, saturation, value], effect);
            device
                .write_all(&packet)
                .with_context(|| format!("write {}", path.display()))?;
        }
        Ok(())
    }
}

/// RGB to the controller's HSB: hue scaled to a byte, saturation and
/// brightness in percent.
fn gcm_hsb([red, green, blue]: [u8; 3]) -> [u8; 3] {
    let (r, g, b) = (f64::from(red), f64::from(green), f64::from(blue));
    let max: f64 = r.max(g).max(b);
    let min: f64 = r.min(g).min(b);
    let delta: f64 = max - min;
    let hue: f64 = if delta == 0.0 {
        0.0
    } else if max == r {
        60.0 * (((g - b) / delta).rem_euclid(6.0))
    } else if max == g {
        60.0 * ((b - r) / delta + 2.0)
    } else {
        60.0 * ((r - g) / delta + 4.0)
    };
    let saturation: f64 = if max == 0.0 { 0.0 } else { delta / max * 100.0 };
    let value: f64 = max / 255.0 * 100.0;
    [
        ((hue / 360.0 * 255.0).round() as u32 % 256) as u8,
        saturation.round() as u8,
        value.round() as u8,
    ]
}

/// Report-ID-less output report: a leading 0 for hidraw, then the command.
fn gcm_strip_packet(strip: u8, [hue, saturation, value]: [u8; 3], effect: u8) -> [u8; 13] {
    let mut packet: [u8; 13] = [
        0x00, 0x05, 0x0C, 0x0C, 0x01, strip, hue, saturation, value, effect, GCM_SPEED,
        GCM_BRIGHTNESS, 0,
    ];
    packet[12] = packet[1..12]
        .iter()
        .fold(0u8, |sum, byte| sum.wrapping_add(*byte));
    packet
}

pub struct SerialBackend {
    root: PathBuf,
    device: String,
    correction: Option<ColorCorrection>,
}

impl SerialBackend {
    pub fn new(root: PathBuf, device: String) -> Self {
        Self {
            root,
            device,
            correction: None,
        }
    }

    pub(crate) fn with_correction(mut self, correction: Option<ColorCorrection>) -> Self {
        self.correction = correction;
        self
    }

    fn apply(&self, config: &LightingConfig) -> Result<()> {
        validate_names(std::slice::from_ref(&self.device))?;
        let path: PathBuf = self.root.join(&self.device);
        let rgb: [u8; 3] = if config.enabled {
            corrected_rgb(config, self.correction.as_ref())
                .map(|channel| scale(config.brightness, u32::from(channel)) as u8)
        } else {
            [0, 0, 0]
        };
        let frame: [u8; 11] = serial_frame(rgb);
        let name: &str = &self.device;
        let mut device: File = OpenOptions::new()
            .write(true)
            .open(&path)
            .with_context(|| format!("open {name}"))?;

        if device
            .metadata()
            .with_context(|| format!("stat {name}"))?
            .file_type()
            .is_char_device()
        {
            configure_serial(&path)?;
        }
        for index in 0..SERIAL_FRAME_REPEATS {
            if index > 0 {
                thread::sleep(SERIAL_FRAME_GAP);
            }
            device
                .write_all(&frame)
                .with_context(|| format!("write {name}"))?;
        }
        device.flush().with_context(|| format!("write {name}"))
    }
}

fn serial_frame([red, green, blue]: [u8; 3]) -> [u8; 11] {
    let mut frame: [u8; 11] = [0xF7, 0x01, red, green, blue, 0, 0, 0, 0, 0, 0xED];
    frame[9] = frame[1..9]
        .iter()
        .fold(0u8, |sum, byte| sum.wrapping_add(*byte));
    frame
}

fn configure_serial(path: &Path) -> Result<()> {
    let status: ExitStatus = Command::new("stty")
        .arg("-F")
        .arg(path)
        .args(["115200", "-clocal", "-opost", "-isig", "-icanon", "-echo"])
        .status()
        .context("run stty")?;
    if !status.success() {
        bail!("stty failed for {}", path.display());
    }
    Ok(())
}

pub struct ChannelBackend {
    root: PathBuf,
    targets: Vec<String>,
    correction: Option<ColorCorrection>,
}

impl ChannelBackend {
    pub fn new(root: PathBuf, targets: Vec<String>) -> Self {
        Self {
            root,
            targets,
            correction: None,
        }
    }

    pub(crate) fn with_correction(mut self, correction: Option<ColorCorrection>) -> Self {
        self.correction = correction;
        self
    }

    fn apply(&self, config: &LightingConfig) -> Result<()> {
        let mut targets: Vec<PreparedChannel> = self.prepare(config)?;

        if let Err(error) = write_channels(&mut targets) {
            blank_channels_best_effort(&targets);
            return Err(error);
        }
        Ok(())
    }

    fn prepare(&self, config: &LightingConfig) -> Result<Vec<PreparedChannel>> {
        let [red, green, blue]: [u8; 3] = corrected_rgb(config, self.correction.as_ref());
        let mut channels: Vec<(String, u8)> = Vec::new();

        for target in &self.targets {
            let (channel, name): (&str, &str) = target
                .split_once('=')
                .with_context(|| format!("invalid RGB channel target '{target}'"))?;
            let value: u8 = match channel {
                "red" => red,
                "green" => green,
                "blue" => blue,
                _ => bail!("invalid RGB channel '{channel}'"),
            };
            channels.push((name.into(), value));
        }

        let names: Vec<String> = channels.iter().map(|(name, _)| name.clone()).collect();
        validate_names(&names)?;

        let mut targets: Vec<PreparedChannel> = Vec::new();

        for (name, channel) in channels {
            let path: PathBuf = self.root.join(&name);
            let brightness_path: PathBuf = path.join("brightness");
            let brightness: File = OpenOptions::new()
                .write(true)
                .open(&brightness_path)
                .with_context(|| format!("open {name} brightness"))?;
            let value: u32 = if config.enabled {
                let maximum: u32 = read_maximum(&path.join("max_brightness"))?;
                scale(config.brightness, gamma(channel, maximum))
            } else {
                0
            };

            targets.push(PreparedChannel {
                name,
                brightness_path,
                brightness,
                value: value.to_string(),
            });
        }
        Ok(targets)
    }
}

pub struct MulticolorBackend {
    root: PathBuf,
    targets: Vec<String>,
    correction: Option<ColorCorrection>,
}

impl MulticolorBackend {
    pub fn new(root: PathBuf, targets: Vec<String>) -> Self {
        Self {
            root,
            targets,
            correction: None,
        }
    }

    pub(crate) fn with_correction(mut self, correction: Option<ColorCorrection>) -> Self {
        self.correction = correction;
        self
    }

    fn apply(&self, config: &LightingConfig) -> Result<()> {
        let mut targets: Vec<PreparedTarget> = self.prepare(config)?;

        if !config.enabled {
            return blank(&mut targets);
        }

        if let Err(error) = write_colors(&mut targets) {
            blank_best_effort(&mut targets);
            return Err(error);
        }
        if let Err(error) = write_brightness(&mut targets) {
            blank_best_effort(&mut targets);
            return Err(error);
        }
        Ok(())
    }

    fn prepare(&self, config: &LightingConfig) -> Result<Vec<PreparedTarget>> {
        validate_names(&self.targets)?;
        let mut targets: Vec<PreparedTarget> = Vec::new();
        let rgb: [u8; 3] = corrected_rgb(config, self.correction.as_ref());

        for name in &self.targets {
            let path: PathBuf = self.root.join(name);
            let brightness_path: PathBuf = path.join("brightness");
            let blank: File = OpenOptions::new()
                .write(true)
                .open(&brightness_path)
                .with_context(|| format!("open {name} brightness"))?;

            if !config.enabled {
                targets.push(PreparedTarget {
                    name: name.clone(),
                    brightness_path,
                    blank,
                    brightness: None,
                    color: None,
                });
                continue;
            }

            let order: Vec<String> = read_order(&path.join("multi_index"))?;
            let maximum: u32 = read_maximum(&path.join("max_brightness"))?;
            let values: Vec<String> = order
                .iter()
                .map(|channel| channel_value(channel, rgb, maximum).to_string())
                .collect();
            let intensity: File = OpenOptions::new()
                .write(true)
                .open(path.join("multi_intensity"))
                .with_context(|| format!("open {name} multi_intensity"))?;
            let brightness: File = OpenOptions::new()
                .write(true)
                .open(&brightness_path)
                .with_context(|| format!("open {name} brightness"))?;
            let brightness_value: String = scale(config.brightness, maximum).to_string();

            targets.push(PreparedTarget {
                name: name.clone(),
                brightness_path,
                blank,
                brightness: Some((brightness, brightness_value)),
                color: Some((intensity, values.join(" "))),
            });
        }
        Ok(targets)
    }
}

struct PreparedTarget {
    name: String,
    brightness_path: PathBuf,
    blank: File,
    brightness: Option<(File, String)>,
    color: Option<(File, String)>,
}

struct PreparedChannel {
    name: String,
    brightness_path: PathBuf,
    brightness: File,
    value: String,
}

fn blank(targets: &mut [PreparedTarget]) -> Result<()> {
    for target in targets {
        write_attr(&mut target.blank, "0")
            .with_context(|| format!("write {} brightness", target.name))?;
    }
    Ok(())
}

fn blank_best_effort(targets: &mut [PreparedTarget]) {
    for target in targets {
        let _ = fs::write(&target.brightness_path, b"0\n");
    }
}

fn blank_channels_best_effort(targets: &[PreparedChannel]) {
    for target in targets {
        let _ = fs::write(&target.brightness_path, b"0\n");
    }
}

fn write_channels(targets: &mut [PreparedChannel]) -> Result<()> {
    for target in targets {
        write_attr(&mut target.brightness, &target.value)
            .with_context(|| format!("write {} brightness", target.name))?;
    }
    Ok(())
}

fn write_colors(targets: &mut [PreparedTarget]) -> Result<()> {
    for target in targets {
        let (file, value) = target.color.as_mut().expect("prepared color");
        write_attr(file, value).with_context(|| format!("write {} color", target.name))?;
    }
    Ok(())
}

fn write_brightness(targets: &mut [PreparedTarget]) -> Result<()> {
    for target in targets {
        let (file, value) = target.brightness.as_mut().expect("prepared brightness");
        write_attr(file, value).with_context(|| format!("write {} brightness", target.name))?;
    }
    Ok(())
}

fn write_attr(file: &mut File, value: &str) -> std::io::Result<()> {
    let output: String = format!("{value}\n");
    file.write_all(output.as_bytes())?;
    file.flush()
}

fn read_order(path: &Path) -> Result<Vec<String>> {
    let input: String =
        fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let order: Vec<String> = input.split_whitespace().map(str::to_lowercase).collect();
    let channels: HashSet<&str> = order.iter().map(String::as_str).collect();

    if order.len() != 3 || channels != HashSet::from(["red", "green", "blue"]) {
        bail!(
            "{} is not an RGB multi_index: '{}'",
            path.display(),
            input.trim()
        );
    }
    Ok(order)
}

fn read_maximum(path: &Path) -> Result<u32> {
    let input: String =
        fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let maximum: u32 = input
        .trim()
        .parse()
        .with_context(|| format!("parse {}", path.display()))?;

    if maximum == 0 {
        bail!("{} is zero", path.display());
    }
    Ok(maximum)
}

fn validate_names(targets: &[String]) -> Result<()> {
    let mut seen: HashSet<&String> = HashSet::new();

    if targets.is_empty() {
        bail!("RGB target list is empty");
    }
    for target in targets {
        let valid: bool = !target.is_empty()
            && target
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b":_.-".contains(&c))
            && target != "."
            && target != "..";
        if !valid {
            bail!("invalid target name '{target}'");
        }
        if !seen.insert(target) {
            bail!("duplicate target '{target}'");
        }
    }
    Ok(())
}

fn channel_value(channel: &str, [red, green, blue]: [u8; 3], maximum: u32) -> u32 {
    match channel {
        "red" => gamma(red, maximum),
        "green" => gamma(green, maximum),
        "blue" => gamma(blue, maximum),
        _ => unreachable!("validated channel"),
    }
}

fn corrected_rgb(config: &LightingConfig, profile: Option<&ColorCorrection>) -> [u8; 3] {
    let rgb: [u8; 3] = rgb_saturation::rgb_after_saturation(config.rgb(), config.saturation);
    let correction: Option<&ColorCorrection> = config.correction.as_ref().or(profile);
    let Some(correction) = correction else {
        return rgb;
    };
    correction.apply(rgb)
}

fn gamma(channel: u8, maximum: u32) -> u32 {
    let value: f64 = f64::from(channel) / 255.0;
    let linear: f64 = if value <= 0.04045 {
        value / 12.92
    } else {
        ((value + 0.055) / 1.055).powf(2.4)
    };
    (linear * f64::from(maximum)).round() as u32
}

fn scale(percent: u8, maximum: u32) -> u32 {
    ((u64::from(percent) * u64::from(maximum) + 50) / 100) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scales_channels_and_brightness() {
        assert_eq!(gamma(0, 255), 0);
        assert_eq!(gamma(128, 100), 22);
        assert_eq!(gamma(255, 255), 255);
        assert_eq!(scale(25, 255), 64);
    }

    #[test]
    fn converts_rgb_to_gcm_hsb() {
        assert_eq!(gcm_hsb([255, 0, 0]), [0, 100, 100]);
        assert_eq!(gcm_hsb([0, 255, 0]), [85, 100, 100]);
        assert_eq!(gcm_hsb([0, 0, 255]), [170, 100, 100]);
        assert_eq!(gcm_hsb([255, 255, 255]), [0, 0, 100]);
        assert_eq!(gcm_hsb([0, 0, 0]), [0, 0, 0]);
    }

    #[test]
    fn builds_gcm_strip_packets() {
        // Left strip red, solid (effect 1, the code the Legion app uses).
        assert_eq!(
            gcm_strip_packet(1, [0, 100, 100], GCM_EFFECT_STATIC),
            [0x00, 0x05, 0x0C, 0x0C, 0x01, 0x01, 0x00, 0x64, 0x64, 0x01, 0x80, 0xFF, 0x67]
        );
    }

    #[test]
    fn builds_serial_frames() {
        assert_eq!(
            serial_frame([0x10, 0, 0]),
            [0xF7, 0x01, 0x10, 0, 0, 0, 0, 0, 0, 0x11, 0xED]
        );
        assert_eq!(
            serial_frame([0xFF, 0xFF, 0xFF]),
            [0xF7, 0x01, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0xFE, 0xED]
        );
    }
}
