//! benilla-gamepad fork: the Modern look's numbers, published each frame as [`LookLanes`]:
//! `look` = (exposure, bloom strength, bloom threshold in linear units, spare) and `grade` =
//! (contrast, saturation, vignette, toe).

use bevy::prelude::*;

use super::{LookLanes, LookModel};
use crate::lighting::WowLighting;

/// The `autoExposure` CVar: the Modern look's exposure follows the light (the default), or holds
/// at 1. A Classic frame has no exposure and ignores it.
#[derive(Resource, Clone, Copy, Debug, PartialEq, Eq)]
pub struct AutoExposure(pub bool);

impl Default for AutoExposure {
    fn default() -> Self {
        Self(true)
    }
}

/// The look's constants.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Look {
    pub exposure: f32,
    /// The share of the blur's light above [`Self::bloom_threshold`] added back as bloom.
    pub bloom: f32,
    /// Linear. The reference frame's white is 1, so a threshold under it blooms the brightest lit
    /// surfaces as well as the additive light above white.
    pub bloom_threshold: f32,
    /// The grade on the tonemapped picture. Above 1, an S-curve's share of the midtones,
    /// `(contrast - 1) * 2`; 0 turns the whole grade off.
    pub contrast: f32,
    /// About the luma: 1 keeps the colour, under 1 mutes it.
    pub saturation: f32,
    /// How much the corners darken.
    pub vignette: f32,
    /// A gamma on the graded picture; above 1 deepens the shadows.
    pub toe: f32,
}

impl Look {
    /// The one look every zone gets.
    pub const NEUTRAL: Self = Self {
        // The grade's S-curve pivots on mid grey, under which most of the reference frame sits:
        // a fifth more exposure keeps a noon frame's mean level where the reference's is.
        exposure: 1.1,
        // The reference frame is dim (on a noon capture under 3% of pixels pass gamma 0.73): a
        // threshold at linear 0.3 lets lit stone, sky and lamps bloom, faintly.
        bloom: 0.4,
        bloom_threshold: 0.3,
        // Tuned by capture from benilla-bourbon's neutral zone look (1.12, 0.86, 0.3, 1.03),
        // whose muted colour suits its linear lighting; the reference's gamma lighting wants its
        // colour kept, a little more of it.
        contrast: 1.12,
        saturation: 1.04,
        vignette: 0.2,
        toe: 1.0,
    };

    /// The combine's two lanes at the auto-exposure's `lift`; `depth_fx` arms the depth effects
    /// where the combine has a depth: 1 the far focus and the haze, 2 the crease shade too.
    pub fn lanes(&self, lift: f32, depth_fx: f32) -> [f32; 8] {
        [
            self.exposure * lift,
            self.bloom,
            self.bloom_threshold,
            depth_fx,
            self.contrast,
            self.saturation,
            self.vignette,
            self.toe,
        ]
    }
}

/// The look the Modern frames take: [`Look::NEUTRAL`], or `$WOW_LOOK_TUNE` over it.
#[derive(Resource, Clone, Copy, Debug, PartialEq)]
pub struct ActiveLook(pub Look);

/// `$WOW_LOOK_TUNE="bloom=0.5,threshold=0.6"` overrides the look's constants for the session (keys
/// `exposure`, `bloom`, `threshold`, `contrast`, `saturation`, `vignette`, `toe`), the lever for
/// tuning them by capture.
impl Default for ActiveLook {
    fn default() -> Self {
        let mut look = Look::NEUTRAL;
        let tune = std::env::var("WOW_LOOK_TUNE").unwrap_or_default();
        for (key, value) in tune.split(',').filter_map(|kv| kv.split_once('=')) {
            let Ok(v) = value.trim().parse::<f32>() else {
                warn!("WOW_LOOK_TUNE: {key}={value} is not a number");
                continue;
            };
            match key.trim() {
                "exposure" => look.exposure = v,
                "bloom" => look.bloom = v,
                "threshold" => look.bloom_threshold = v,
                "contrast" => look.contrast = v,
                "saturation" => look.saturation = v,
                "vignette" => look.vignette = v,
                "toe" => look.toe = v,
                other => warn!("WOW_LOOK_TUNE: no constant named {other}"),
            }
        }
        Self(look)
    }
}

/// **The auto-exposure from the light rows**, the Low tier's meter (and every tier's until a
/// screen meter exists). It lifts only a very dark light: below a deep dusk
/// ([`AUTO_EXPOSURE_DARK`]) it makes up a share ([`AUTO_EXPOSURE_STRENGTH`]) of the shortfall,
/// in stops; at and above it, every day and every dusk, it is exactly 1; and it never passes
/// [`AUTO_EXPOSURE_MAX`], so a night still reads as night. It meters the authored rows (the
/// ambient whole, the sun or moon diffuse at a typical incidence), not the screen, so a camera
/// turn never moves it. Ported from benilla-bourbon's first light auto-exposure.
const AUTO_EXPOSURE_STRENGTH: f32 = 0.5;
/// The sRGB light rows (ambient, diffuse) below which the lift begins: a deep dusk.
const AUTO_EXPOSURE_DARK: ([f32; 3], [f32; 3]) = ([0.25; 3], [0.3; 3]);
/// The ceiling on the lift, one stop.
const AUTO_EXPOSURE_MAX: f32 = 2.0;
/// The time constant the lift eases with, in seconds: an eye adapting, not a meter snapping.
const AUTO_EXPOSURE_SECONDS: f32 = 1.5;

/// **The screen meter's exposure** (`super::meter`), the Medium and High tiers' meter: the
/// picture's log-average luminance against [`METER_KEY`] (an Elwynn noon in the trees' shade,
/// 0.052 by capture). A brighter picture is held back by [`METER_BRIGHT`]'s share of the
/// difference in stops, never under its floor: Booty Bay's planks (0.10) take 0.86, the Barrens
/// at noon (0.20) 0.72, the floor. A darker one is lifted by [`METER_DARK`]'s share up to its cap, so
/// a gloomy zone or a room stays gloomy; the night's own lift is the light rows'
/// ([`auto_exposure`]), and the larger of the two is taken.
const METER_KEY: f32 = 0.055;
/// (strength, floor).
const METER_BRIGHT: (f32, f32) = (0.25, 0.72);
/// (strength, cap).
const METER_DARK: (f32, f32) = (0.3, 1.2);
/// The dark cap at full night.
const METER_NIGHT_CAP: f32 = 2.0;
/// A reading older than this many seconds is stale (the world is not drawing: a loading screen).
const METER_FRESH_SECONDS: f32 = 1.0;

/// The exposure a metered log-average luminance asks for, given the light rows' lift `rows`.
fn meter_exposure(log_average: f32, rows: f32) -> f32 {
    let ratio = METER_KEY / log_average.max(1e-4);
    if ratio < 1.0 {
        ratio.powf(METER_BRIGHT.0).max(METER_BRIGHT.1)
    } else {
        // By day the cap keeps a gloomy zone gloomy; as the light rows say night (`rows` over
        // 1) it opens to [`METER_NIGHT_CAP`], so a night under trees is lifted as far as an
        // open moonlit field needs no lift at all, and both stay readable.
        let night = ((rows - 1.0) / 0.4).clamp(0.0, 1.0);
        let cap = METER_DARK.1 + (METER_NIGHT_CAP - METER_DARK.1) * night;
        ratio.powf(METER_DARK.0).min(cap).max(rows)
    }
}

fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

/// The linear luminance a pair of sRGB light rows lights a surface with: the ambient whole, the
/// diffuse at half (a typical N·L).
fn light_key(ambient: [f32; 3], diffuse: [f32; 3]) -> f32 {
    let lum = |c: [f32; 3]| {
        0.2126 * srgb_to_linear(c[0])
            + 0.7152 * srgb_to_linear(c[1])
            + 0.0722 * srgb_to_linear(c[2])
    };
    lum(ambient) + 0.5 * lum(diffuse)
}

/// The lift a light asks for: 1 at [`AUTO_EXPOSURE_DARK`] and above, rising toward
/// [`AUTO_EXPOSURE_MAX`] as the light falls.
fn auto_exposure(ambient: [f32; 3], diffuse: [f32; 3]) -> f32 {
    let reference = light_key(AUTO_EXPOSURE_DARK.0, AUTO_EXPOSURE_DARK.1);
    (reference / light_key(ambient, diffuse).max(1e-4))
        .powf(AUTO_EXPOSURE_STRENGTH)
        .clamp(1.0, AUTO_EXPOSURE_MAX)
}

/// Whether the crease shade (ambient occlusion) runs. CVar `ambientOcclusion`; `$WOW_LOOK_AO=0|1`
/// picks it for a session.
#[derive(Resource, Clone, Copy, PartialEq, Eq, Debug)]
pub struct CreaseShade(pub bool);

impl Default for CreaseShade {
    fn default() -> Self {
        Self(std::env::var("WOW_LOOK_AO").as_deref() != Ok("0"))
    }
}

/// How much the bloom grows at full night.
const NIGHT_GLOW: f32 = 1.5;

/// How much of the night it is, 0 by day to 1 with the visible sun `to_sun` well under the
/// horizon.
fn night(to_sun: Vec3) -> f32 {
    let y = to_sun.normalize_or_zero().y;
    ((0.02 - y) / 0.14).clamp(0.0, 1.0)
}

/// The lanes this frame asks for: none in a Classic frame. The first Modern frame takes the lift
/// whole, so entering the world at night opens on the adapted picture; after it the lift eases.
fn update_lanes(
    model: Res<LookModel>,
    look: Res<ActiveLook>,
    auto: Res<AutoExposure>,
    quality: Res<super::LookQuality>,
    crease: Res<CreaseShade>,
    reading: Res<super::meter::MeterReading>,
    lighting: Option<Res<WowLighting>>,
    time: Res<Time>,
    mut adapted: Local<Option<f32>>,
    mut log_sec: Local<u32>,
    mut lanes: ResMut<LookLanes>,
) {
    let next = if model.is_modern() {
        let rows = match (lighting.as_deref(), auto.0) {
            (Some(l), true) => auto_exposure(l.ambient, l.diffuse),
            _ => 1.0,
        };
        // The screen meter where it runs and has a fresh reading; the light rows otherwise.
        let metered = reading
            .0
            .filter(|&(_, at)| time.elapsed_secs() - at < METER_FRESH_SECONDS)
            .filter(|_| auto.0 && *quality != super::LookQuality::Low)
            .map(|(l, _)| meter_exposure(l, rows));
        let lift = metered.unwrap_or(rows);
        // `$WOW_LOOK_LOG=1`: the light rows and the key the meter read, once a second.
        static LOG: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
        if *LOG.get_or_init(|| std::env::var_os("WOW_LOOK_LOG").is_some()) {
            if let Some(l) = lighting.as_deref() {
                let sec = time.elapsed_secs() as u32;
                if *log_sec != sec {
                    *log_sec = sec;
                    info!(
                        "look: ambient {:?} diffuse {:?} key {:.3} rows {rows:.3} meter {:?} lift {lift:.3}",
                        l.ambient,
                        l.diffuse,
                        light_key(l.ambient, l.diffuse),
                        reading.0.map(|r| r.0),
                    );
                }
            }
        }
        let eye = adapted.get_or_insert(lift);
        *eye += (lift - *eye) * (1.0 - (-time.delta_secs() / AUTO_EXPOSURE_SECONDS).exp());
        // The depth effects are the Medium and High tiers'; Low keeps the picture's cost flat.
        // 2 adds the crease shade's pass (`ffx_glow`'s `fs_mfx_ao`).
        let depth_fx = match *quality {
            super::LookQuality::Low => 0.0,
            _ if crease.0 => 2.0,
            _ => 1.0,
        };
        let mut out = look.0.lanes(*eye, depth_fx);
        // At night the lit things (a lamp, a window, a clock's face, a torch) glow wider: the
        // bloom grows as the visible sun goes under the horizon.
        if let Some(l) = lighting.as_deref() {
            out[1] *= 1.0 + NIGHT_GLOW * night(l.celestial_dir);
        }
        LookLanes(Some(out))
    } else {
        *adapted = None;
        LookLanes(None)
    };
    if *lanes != next {
        *lanes = next;
    }
}

pub(super) fn plugin(app: &mut App) {
    app.init_resource::<AutoExposure>()
        .init_resource::<CreaseShade>()
        .init_resource::<ActiveLook>()
        .add_systems(Last, update_lanes);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn day_and_dusk_keep_an_exposure_of_one() {
        // A forest noon, and the deep dusk itself.
        assert_eq!(auto_exposure([0.4, 0.45, 0.5], [0.9, 0.8, 0.6]), 1.0);
        assert_eq!(
            auto_exposure(AUTO_EXPOSURE_DARK.0, AUTO_EXPOSURE_DARK.1),
            1.0
        );
    }

    #[test]
    fn a_dark_night_lifts_but_never_past_the_ceiling() {
        let night = auto_exposure([0.12, 0.14, 0.2], [0.15, 0.17, 0.25]);
        assert!(night > 1.0 && night < AUTO_EXPOSURE_MAX, "{night}");
        // Darker light, more lift; a black light sits at the ceiling.
        assert!(auto_exposure([0.05; 3], [0.05; 3]) > night);
        assert_eq!(auto_exposure([0.0; 3], [0.0; 3]), AUTO_EXPOSURE_MAX);
    }

    #[test]
    fn the_meter_holds_a_glare_back_and_lifts_gloom_a_little() {
        // The key itself is 1; a glare is held back, never under the floor.
        assert_eq!(meter_exposure(METER_KEY, 1.0), 1.0);
        let bay = meter_exposure(0.10, 1.0);
        assert!(bay < 0.9 && bay > METER_BRIGHT.1, "{bay}");
        assert_eq!(meter_exposure(1.0, 1.0), METER_BRIGHT.1);
        // Gloom lifts to the cap at most; a night keeps the light rows' larger lift.
        assert_eq!(meter_exposure(0.01, 1.0), METER_DARK.1);
        // At night the cap opens: a black wood lifts past the rows' own lift, a moonlit field
        // that already meters near the key does not.
        let wood = meter_exposure(0.006, 1.45);
        assert!(wood > 1.8 && wood <= METER_NIGHT_CAP, "{wood}");
        assert_eq!(meter_exposure(0.04, 1.45), 1.45);
    }

    #[test]
    fn the_lift_moves_the_exposure_lane_alone() {
        let (a, b) = (Look::NEUTRAL.lanes(1.0, 0.0), Look::NEUTRAL.lanes(1.5, 0.0));
        assert_eq!(b[0], a[0] * 1.5);
        assert_eq!(a[1..], b[1..]);
    }
}
