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
}

impl Look {
    /// The one look every zone gets.
    pub const NEUTRAL: Self = Self {
        exposure: 1.0,
        // The reference frame is dim (on a noon capture under 3% of pixels pass gamma 0.73): a
        // threshold at linear 0.3 lets lit stone, sky and lamps bloom, faintly.
        bloom: 0.4,
        bloom_threshold: 0.3,
    };

    /// The combine's two lanes.
    pub fn lanes(&self) -> [f32; 8] {
        [
            self.exposure,
            self.bloom,
            self.bloom_threshold,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        ]
    }
}

/// The look the Modern frames take: [`Look::NEUTRAL`], or `$WOW_LOOK_TUNE` over it.
#[derive(Resource, Clone, Copy, Debug, PartialEq)]
pub struct ActiveLook(pub Look);

/// `$WOW_LOOK_TUNE="bloom=0.5,threshold=0.6"` overrides the look's constants for the session (keys
/// `exposure`, `bloom`, `threshold`), the lever for tuning them by capture.
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
