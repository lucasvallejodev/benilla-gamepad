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
/// visible sun, the hour's share of its haze and shafts ([`sun_air`]), then the mist ([`mist`])
/// and three spare lanes.
#[derive(Resource, Clone, Copy, PartialEq, Debug, Default, ExtractResource)]
pub struct SunAirLanes(pub Option<[f32; 8]>);

/// How much of the sun's haze and light shafts the hour has, from the visible sun `to_sun`: none
/// with the sun well under the horizon, all of it as it rises or sets, a third at noon.
fn sun_air(to_sun: Vec3) -> f32 {
    let e = to_sun.normalize_or_zero().y.clamp(-1.0, 1.0).asin();
    let up = ((e + 0.10) / 0.15).clamp(0.0, 1.0);
    let high = ((e - 0.25) / 0.65).clamp(0.0, 1.0);
    up * up * (3.0 - 2.0 * up) * (1.0 - 0.65 * high)
}

/// The mist over the land, 0 clear to 1 thick: on some mornings (about two days in five, the
/// day's own draw) it lies from before dawn and burns off by nine, and rain or a storm brings
/// its own. `minute` is the game minute of the day, `day` the game day, `sky_density` the
/// weather's sky channel (0 to 0.25).
fn mist(minute: f32, day: f64, sky_density: f32) -> f32 {
    let draw = ((day.floor() * 12.9898).sin() * 43_758.547).fract().abs() as f32;
    let morning = ((draw - 0.6) / 0.3).clamp(0.0, 1.0);
    let rise = ((minute - 240.0) / 90.0).clamp(0.0, 1.0);
    let burn = 1.0 - ((minute - 450.0) / 100.0).clamp(0.0, 1.0);
    let weather = (sky_density / 0.25).clamp(0.0, 1.0) * 0.8;
    (morning * rise * burn * 0.85).max(weather)
}

/// `$WOW_MIST=<0..1>` holds the mist for a session (the capture lever).
fn mist_override() -> Option<f32> {
    static HELD: std::sync::OnceLock<Option<f32>> = std::sync::OnceLock::new();
    *HELD.get_or_init(|| {
        std::env::var("WOW_MIST")
            .ok()
            .and_then(|v| v.trim().parse().ok())
    })
}

fn publish(
    model: Res<LookModel>,
    quality: Res<LookQuality>,
    lighting: Option<Res<WowLighting>>,
    time: Option<Res<crate::lighting::WorldTime>>,
    weather: Option<Res<crate::weather::WeatherState>>,
    mut lanes: ResMut<SunAirLanes>,
) {
    let wanted = model.is_modern() && *quality != LookQuality::Low;
    let next = lighting.filter(|_| wanted).map(|l| {
        let to_sun = l.celestial_dir.normalize_or_zero();
        let sky = weather.as_deref().map_or(0.0, |w| w.sky_density);
        let m = mist_override().unwrap_or_else(|| {
            time.as_deref()
                .map_or(0.0, |t| mist(t.minute_f, t.day, sky))
        });
        [
            to_sun.x,
            to_sun.y,
            to_sun.z,
            sun_air(to_sun),
            m.clamp(0.0, 1.0),
            0.0,
            0.0,
            0.0,
        ]
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

    #[test]
    fn mist_lies_on_some_mornings_and_under_a_storm() {
        // Clear at noon whatever the day, unless the weather brings it.
        assert!((0..40).all(|d| mist(720.0, f64::from(d), 0.0) == 0.0));
        assert!(mist(720.0, 3.0, 0.25) > 0.7);
        // Some mornings have it and some do not.
        let mornings: Vec<f32> = (0..40).map(|d| mist(400.0, f64::from(d), 0.0)).collect();
        let misty = mornings.iter().filter(|m| **m > 0.2).count();
        assert!(misty >= 6 && misty <= 28, "{misty} of 40");
        assert!(mornings.iter().all(|m| *m <= 0.85));
    }
}
