//! benilla-gamepad fork: the Modern look's numbers, published each frame as [`LookLanes`]:
//! `look` = (exposure, bloom strength, bloom threshold in linear units, spare) and `grade` =
//! (contrast, saturation, vignette, toe).

use bevy::prelude::*;

use super::{LookLanes, LookModel};

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

    /// The combine's two lanes.
    pub fn lanes(&self) -> [f32; 8] {
        [
            self.exposure,
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
/// `exposure`, `bloom`, `threshold`, `contrast`, `saturation`, `vignette`, `toe`), the lever for tuning them by capture.
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

/// The lanes this frame asks for: none in a Classic frame.
fn update_lanes(model: Res<LookModel>, look: Res<ActiveLook>, mut lanes: ResMut<LookLanes>) {
    let next = LookLanes(model.is_modern().then(|| look.0.lanes()));
    if *lanes != next {
        *lanes = next;
    }
}

pub(super) fn plugin(app: &mut App) {
    app.init_resource::<AutoExposure>()
        .init_resource::<ActiveLook>()
        .add_systems(Last, update_lanes);
}
