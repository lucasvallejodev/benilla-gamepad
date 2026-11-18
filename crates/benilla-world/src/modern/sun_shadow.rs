//! benilla-gamepad fork: **sun shadows** for the Modern look. A camera at the lighting sun draws
//! the world round the viewer a second time ([`SunShadowCamera`], a long lens, the water mirror's
//! view shape); its depth is the shadow map. The FFXGlow combine (`ffx_glow`, `mfx_sun_map`)
//! finds each pixel's world point from the linear depth, asks the map whether the sun reaches it,
//! and where it does not, takes the sun's share out of the picture: the lit colour is
//! `ambient + diffuse · n·l`, so a shadowed pixel keeps `ambient / (ambient + diffuse · n·l)` of
//! it. Night falls out of that by itself (the moon's diffuse is small).
//!
//! The shadows are cast from the visible sun ([`caster`]), which shares the lighting sun's
//! bearing: short at noon, long toward dusk, gone at night.
//!
//! No ray is traced and no vendor feature is used: one more depth draw and a 3x3 compare.

use bevy::asset::RenderAssetUsages;
use bevy::camera::{ClearColorConfig, RenderTarget};
use bevy::core_pipeline::core_3d::Transparent3d;
use bevy::prelude::*;
use bevy::render::extract_component::{ExtractComponent, ExtractComponentPlugin};
use bevy::render::extract_resource::{ExtractResource, ExtractResourcePlugin};
use bevy::render::render_phase::ViewSortedRenderPhases;
use bevy::render::render_resource::{
    Extent3d, TextureDimension, TextureFormat, TextureUsages, TextureView,
};
use bevy::render::view::{ExtractedView, ViewDepthTexture};
use bevy::render::{Render, RenderApp, RenderSystems};

use super::{LookModel, LookQuality};
use crate::lighting::WowLighting;
use crate::view::WorldCamera;

/// The map's edge in texels.
const MAP_SIZE: u32 = 2048;
/// Half the square of world the map covers, yards.
const HALF_EXTENT: f32 = 72.0;
/// How far ahead of the viewer, along its level heading, the square is centred.
const AHEAD: f32 = 46.0;
/// How far up the sun's ray the camera stands, and its far plane.
const STANDOFF: f32 = 320.0;
const FAR: f32 = 760.0;

/// Whether sun shadows run. CVar `sunShadows`; `$WOW_SUN_SHADOWS=0|1` for a session.
#[derive(Resource, Clone, Copy, PartialEq, Eq, Debug)]
pub struct SunShadows(pub bool);

impl Default for SunShadows {
    fn default() -> Self {
        Self(std::env::var("WOW_SUN_SHADOWS").as_deref() != Ok("0"))
    }
}

/// Marks the camera at the sun, in both worlds.
#[derive(Component, Clone, Copy, Default, ExtractComponent)]
pub struct SunShadowCamera;

/// The combine's sun block this frame (`SunLanes` in `ffx_glow.wgsl`), `None` in a Classic or
/// Low frame: the map's clip-from-world matrix, the direction to the casting sun and the shadows'
/// strength (0 with them off or at night), the ambient and diffuse colours (the map's texel in
/// yards in `ambient.w`, the visible sun's height in `diffuse.w`), then the direction to the
/// lighting sun and the hour's share of sun haze and shafts.
#[derive(Resource, Clone, Copy, PartialEq, Debug, Default, ExtractResource)]
pub struct SunShadowLanes(pub Option<[f32; 32]>);

/// Render world: the shadow camera's depth this frame, while it drew.
#[derive(Resource, Default)]
pub(crate) struct SunShadowDepth(pub Option<TextureView>);

fn setup(mut commands: Commands, mut images: ResMut<Assets<Image>>) {
    let mut image = Image::new_fill(
        Extent3d {
            width: MAP_SIZE,
            height: MAP_SIZE,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &[0; 8],
        TextureFormat::Rgba16Float,
        RenderAssetUsages::default(),
    );
    image.texture_descriptor.usage =
        TextureUsages::TEXTURE_BINDING | TextureUsages::COPY_DST | TextureUsages::RENDER_ATTACHMENT;
    let mut shape = Camera3d::default();
    shape.depth_texture_usages =
        (TextureUsages::RENDER_ATTACHMENT | TextureUsages::TEXTURE_BINDING).into();
    commands.spawn((
        Name::new("sun shadow camera"),
        // The water mirror's view shape (`liquid::mirror_view_shape`), with a bindable depth.
        shape,
        bevy::render::view::Msaa::Off,
        bevy::render::view::Hdr,
        bevy::core_pipeline::tonemapping::Tonemapping::None,
        SunShadowCamera,
        RenderTarget::Image(images.add(image).into()),
        Camera {
            // Ahead of the mirrors and the world camera, whose combine reads this frame's depth.
            order: -3,
            clear_color: ClearColorConfig::Custom(Color::NONE),
            is_active: false,
            ..default()
        },
        // A long lens, not an orthographic one: the view's pipelines are then the water mirror's,
        // which the client compiles before the world shows (`pipe_warm`), and the combine
        // projects with the camera's own matrix either way.
        Projection::Perspective(PerspectiveProjection {
            fov: 2.0 * (HALF_EXTENT / STANDOFF).atan(),
            aspect_ratio: 1.0,
            near: 20.0,
            far: FAR,
            ..default()
        }),
        Transform::default(),
    ));
}

/// How much of the sun's share a shadow takes away at full strength.
const STRENGTH: f32 = 0.8;
/// The lowest the shadow-casting sun stands, so a sunset's shadows are long and not endless.
const MIN_ELEVATION: f32 = 0.38;

/// The direction to the light that casts the shadows and its strength (0 off), from the visible
/// sun `to_sun` (camera to sun): the visible sun itself, never lower than [`MIN_ELEVATION`], fading
/// out as it nears the horizon. The lighting sun never sets and stands low all day
/// (`lighting::sun_direction`), which would leave every street in its buildings' shadow; the
/// visible sun shares its bearing, so the shadows still fall the way the shading says.
fn caster(to_sun: Vec3) -> (Vec3, f32) {
    let to_sun = to_sun.normalize_or_zero();
    let elevation = to_sun.y.clamp(-1.0, 1.0).asin();
    let strength = ((elevation - 0.03) / 0.14).clamp(0.0, 1.0);
    let level = Vec3::new(to_sun.x, 0.0, to_sun.z).normalize_or_zero();
    if elevation >= MIN_ELEVATION || level == Vec3::ZERO {
        return (to_sun, strength);
    }
    (
        level * MIN_ELEVATION.cos() + Vec3::Y * MIN_ELEVATION.sin(),
        strength,
    )
}

/// How much of the sun's haze and light shafts the hour has, from the visible sun `to_sun`: none
/// with the sun well under the horizon, all of it as it rises or sets, a third at noon.
fn sun_air(to_sun: Vec3) -> f32 {
    let e = to_sun.normalize_or_zero().y.clamp(-1.0, 1.0).asin();
    let up = ((e + 0.10) / 0.15).clamp(0.0, 1.0);
    let high = ((e - 0.25) / 0.65).clamp(0.0, 1.0);
    up * up * (3.0 - 2.0 * up) * (1.0 - 0.65 * high)
}

/// The camera's pose for a viewer at `eye` heading `fwd` under a sun whose light travels along
/// `sun_dir`: the square centred ahead of the viewer, snapped to the map's texels so a moving
/// viewer does not make the shadows' edges swim.
fn pose(eye: Vec3, fwd: Vec3, sun_dir: Vec3) -> Transform {
    let level = Vec3::new(fwd.x, 0.0, fwd.z).normalize_or_zero();
    let focus = eye + level * AHEAD;
    let aim = Transform::default().looking_to(sun_dir, Vec3::Y);
    let (right, up) = (aim.rotation * Vec3::X, aim.rotation * Vec3::Y);
    let texel = 2.0 * HALF_EXTENT / MAP_SIZE as f32;
    let snap = |v: f32| (v / texel).round() * texel;
    let along = focus.dot(sun_dir);
    let at =
        right * snap(focus.dot(right)) + up * snap(focus.dot(up)) + sun_dir * (along - STANDOFF);
    aim.with_translation(at)
}

/// Aim the camera and publish the combine's block; idle (and unpublished) while the look, its
/// quality or the setting has shadows off.
fn drive(
    on: Res<SunShadows>,
    model: Res<LookModel>,
    quality: Res<LookQuality>,
    lighting: Option<Res<WowLighting>>,
    viewer: Query<&GlobalTransform, With<WorldCamera>>,
    mut cam: Query<(&mut Camera, &mut Transform, &Projection), With<SunShadowCamera>>,
    mut lanes: ResMut<SunShadowLanes>,
    claim: Option<Res<crate::wmo_portal::CameraInteriorClaim>>,
    time: Res<Time>,
    mut indoors: Local<f32>,
) {
    let Ok((mut camera, mut transform, projection)) = cam.single_mut() else {
        return;
    };
    // A room is lit by its own baked light, not the sun: the shadows ease out over a second and
    // a half as the viewer steps inside, and back as it leaves.
    let inside = claim.is_some_and(|c| c.0.is_some());
    let step = time.delta_secs() / 1.5;
    *indoors = if inside {
        (*indoors + step).min(1.0)
    } else {
        (*indoors - step).max(0.0)
    };
    let wanted = model.is_modern() && *quality != LookQuality::Low;
    let mut shadows = false;
    let next = match (wanted, lighting, viewer.iter().next()) {
        (true, Some(l), Some(v)) => {
            let (to_sun, strength) = caster(l.celestial_dir);
            let strength = if on.0 {
                strength * STRENGTH * (1.0 - *indoors)
            } else {
                0.0
            };
            shadows = strength > 0.0;
            let sun_dir = -to_sun;
            let tf = pose(v.translation(), Vec3::from(v.forward()), sun_dir);
            if *transform != tf {
                *transform = tf;
            }
            let clip_from_world = projection.get_clip_from_view() * tf.to_matrix().inverse();
            let mut out = [0.0; 32];
            out[..16].copy_from_slice(&clip_from_world.to_cols_array());
            out[16..19].copy_from_slice(&(-sun_dir).to_array());
            out[19] = strength;
            out[20..23].copy_from_slice(&l.ambient);
            out[23] = 2.0 * HALF_EXTENT / MAP_SIZE as f32;
            out[24..27].copy_from_slice(&l.diffuse);
            // The visible sun's true height (the caster's is held off the horizon) and how much
            // of the sun's haze and shafts the hour has.
            out[27] = l.celestial_dir.normalize_or_zero().y;
            out[31] = sun_air(l.celestial_dir);
            // The lighting sun, whose share of the light a shadow takes away.
            out[28..31].copy_from_slice(&(-l.sun_dir.normalize_or_zero()).to_array());
            Some(out)
        }
        _ => None,
    };
    if camera.is_active != shadows {
        camera.is_active = shadows;
    }
    if lanes.0 != next {
        lanes.0 = next;
    }
}

/// Render world: nothing blended casts a shadow (a lamp's glow card, the water, a spell).
fn drop_blended(
    views: Query<&ExtractedView, With<SunShadowCamera>>,
    mut phases: ResMut<ViewSortedRenderPhases<Transparent3d>>,
) {
    for view in &views {
        if let Some(phase) = phases.get_mut(&view.retained_view_entity) {
            phase.items.clear();
        }
    }
}

/// Render world: the camera's depth for the combine, on the frames the block is published.
fn publish_depth(
    lanes: Res<SunShadowLanes>,
    views: Query<&ViewDepthTexture, With<SunShadowCamera>>,
    mut depth: ResMut<SunShadowDepth>,
) {
    depth.0 = lanes
        .0
        .filter(|l| l[19] > 0.0)
        .and_then(|_| views.iter().next())
        .map(|d| d.view().clone());
}

pub(super) fn plugin(app: &mut App) {
    app.init_resource::<SunShadows>()
        .init_resource::<SunShadowLanes>()
        .add_plugins((
            ExtractComponentPlugin::<SunShadowCamera>::default(),
            ExtractResourcePlugin::<SunShadowLanes>::default(),
        ))
        .add_systems(Startup, setup)
        .add_systems(
            PostUpdate,
            // After the viewer has moved for the frame and before transforms propagate, as the
            // water's mirrors are aimed.
            drive
                .before(bevy::transform::TransformSystems::Propagate)
                .before(bevy::camera::CameraUpdateSystems),
        );
    let Some(render_app) = app.get_sub_app_mut(RenderApp) else {
        return;
    };
    render_app.init_resource::<SunShadowDepth>().add_systems(
        Render,
        (
            drop_blended.in_set(RenderSystems::PhaseSort),
            publish_depth.in_set(RenderSystems::PrepareBindGroups),
        ),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_caster_is_the_visible_sun_held_off_the_horizon() {
        let high = Vec3::new(0.3, 0.9, 0.3).normalize();
        assert_eq!(caster(high), (high, 1.0));
        let low = Vec3::new(0.7, 0.1, 0.7).normalize();
        let (dir, strength) = caster(low);
        assert!((dir.y.asin() - MIN_ELEVATION).abs() < 1e-4);
        assert!(dir.x > 0.0 && (dir.x - dir.z).abs() < 1e-5);
        assert!(strength > 0.0 && strength < 1.0);
        assert_eq!(caster(Vec3::new(0.7, -0.2, 0.7).normalize()).1, 0.0);
    }

    #[test]
    fn the_square_sits_ahead_of_the_viewer_and_snaps_to_texels() {
        let sun = Vec3::new(-0.5, -0.6, -0.62).normalize();
        let eye = Vec3::new(1234.56, 80.0, -4321.0);
        let tf = pose(eye, Vec3::NEG_Z, sun);
        // The camera looks down the sun's ray, and the focus projects onto its axis.
        assert!((tf.rotation * Vec3::NEG_Z).dot(sun) > 0.999);
        let focus = eye + Vec3::NEG_Z * AHEAD;
        let off = focus - tf.translation;
        let texel = 2.0 * HALF_EXTENT / MAP_SIZE as f32;
        assert!(off.dot(tf.rotation * Vec3::X).abs() <= texel);
        assert!(off.dot(tf.rotation * Vec3::Y).abs() <= texel);
        assert!((off.dot(sun) - STANDOFF).abs() < 1e-2);
        // A step smaller than a texel leaves the pose where it was, sideways.
        let nudged = pose(
            eye + (tf.rotation * Vec3::X) * (0.2 * texel),
            Vec3::NEG_Z,
            sun,
        );
        assert!(
            (nudged.translation - tf.translation)
                .dot(tf.rotation * Vec3::X)
                .abs()
                < 1.01 * texel
        );
    }
}
