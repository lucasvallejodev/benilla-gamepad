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
        exposure: 1.2,
        // The reference frame is dim (on a noon capture under 3% of pixels pass gamma 0.73): a
        // threshold at linear 0.3 lets lit stone, sky and lamps bloom, faintly.
        bloom: 0.4,
        bloom_threshold: 0.3,
        // Tuned by capture from benilla-bourbon's neutral zone look (1.12, 0.86, 0.3, 1.03),
        // whose muted colour suits its linear lighting; the reference's gamma lighting wants its
        // colour kept, a little more of it.
        contrast: 1.15,
        saturation: 1.08,
        vignette: 0.2,
        toe: 1.0,
    };

    /// The combine's two lanes at the auto-exposure's `lift`.
    pub fn lanes(&self, lift: f32) -> [f32; 8] {
        [
            self.exposure * lift,
            self.bloom,
            self.bloom_threshold,
            0.0,
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

/// The lanes this frame asks for: none in a Classic frame. The first Modern frame takes the lift
/// whole, so entering the world at night opens on the adapted picture; after it the lift eases.
fn update_lanes(
    model: Res<LookModel>,
    look: Res<ActiveLook>,
    auto: Res<AutoExposure>,
    lighting: Option<Res<WowLighting>>,
    time: Res<Time>,
    mut adapted: Local<Option<f32>>,
    mut lanes: ResMut<LookLanes>,
) {
    let next = if model.is_modern() {
        let lift = match (lighting.as_deref(), auto.0) {
            (Some(l), true) => auto_exposure(l.ambient, l.diffuse),
            _ => 1.0,
        };
        let eye = adapted.get_or_insert(lift);
        *eye += (lift - *eye) * (1.0 - (-time.delta_secs() / AUTO_EXPOSURE_SECONDS).exp());
        LookLanes(Some(look.0.lanes(*eye)))
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
    fn the_lift_moves_the_exposure_lane_alone() {
        let (a, b) = (Look::NEUTRAL.lanes(1.0), Look::NEUTRAL.lanes(1.5));
        assert_eq!(b[0], a[0] * 1.5);
        assert_eq!(a[1..], b[1..]);
    }
}
