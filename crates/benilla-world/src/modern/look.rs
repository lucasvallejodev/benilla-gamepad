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

/// The lanes this frame asks for: none in a Classic frame.
fn update_lanes(model: Res<LookModel>, mut lanes: ResMut<LookLanes>) {
    let next = LookLanes(
        model
            .is_modern()
            .then_some([1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
    );
    if *lanes != next {
        *lanes = next;
    }
}

pub(super) fn plugin(app: &mut App) {
    app.init_resource::<AutoExposure>()
        .add_systems(Last, update_lanes);
}
