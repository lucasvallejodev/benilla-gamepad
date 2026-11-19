//! benilla-gamepad fork: **the sun in the air** for the Modern look. Where the visible sun stands
//! and how much of its haze and light shafts the hour has, published each frame for the FFXGlow
//! combine (`ffx_glow`, `SunAir` in `ffx_glow.wgsl`): the distance haze warms and thickens toward
//! the sun, and trees and roofs cut its glow into shafts (`mfx_shafts`). Screen space only: no
//! shadow is cast and nothing is drawn twice.

use bevy::prelude::*;
use bevy::render::extract_resource::{ExtractResource, ExtractResourcePlugin};

use super::{LookModel, LookQuality};
use crate::lighting::WowLighting;

/// The combine's sun block this frame, `None` in a Classic or Low frame: the direction to the
/// visible sun, then the hour's share of its haze and shafts ([`sun_air`]).
#[derive(Resource, Clone, Copy, PartialEq, Debug, Default, ExtractResource)]
pub struct SunAirLanes(pub Option<[f32; 4]>);

/// How much of the sun's haze and light shafts the hour has, from the visible sun `to_sun`: none
/// with the sun well under the horizon, all of it as it rises or sets, a third at noon.
fn sun_air(to_sun: Vec3) -> f32 {
    let e = to_sun.normalize_or_zero().y.clamp(-1.0, 1.0).asin();
    let up = ((e + 0.10) / 0.15).clamp(0.0, 1.0);
    let high = ((e - 0.25) / 0.65).clamp(0.0, 1.0);
    up * up * (3.0 - 2.0 * up) * (1.0 - 0.65 * high)
}

fn publish(
    model: Res<LookModel>,
    quality: Res<LookQuality>,
    lighting: Option<Res<WowLighting>>,
    mut lanes: ResMut<SunAirLanes>,
) {
    let wanted = model.is_modern() && *quality != LookQuality::Low;
    let next = lighting.filter(|_| wanted).map(|l| {
        let to_sun = l.celestial_dir.normalize_or_zero();
        [to_sun.x, to_sun.y, to_sun.z, sun_air(to_sun)]
    });
    if lanes.0 != next {
        lanes.0 = next;
    }
}

pub(super) fn plugin(app: &mut App) {
    app.init_resource::<SunAirLanes>()
        .add_plugins(ExtractResourcePlugin::<SunAirLanes>::default())
        .add_systems(Last, publish);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_air_is_full_at_the_horizon_a_third_at_noon_and_none_at_night() {
        assert!((sun_air(Vec3::new(0.7, 0.05, 0.7)) - 1.0).abs() < 0.01);
        let noon = sun_air(Vec3::new(0.05, 1.0, 0.05));
        assert!((noon - 0.35).abs() < 0.02, "{noon}");
        assert_eq!(sun_air(Vec3::new(0.7, -0.3, 0.7)), 0.0);
    }
}
