//! benilla-gamepad fork: **the Modern look's screen meter**. The light rows are the same in
//! Elwynn and Booty Bay at noon, so a meter that reads them cannot tell a bright zone from a
//! dim one. This one reads the picture: the FFXGlow node resamples the frame's decoded,
//! unexposed blur into a 32×16 float image ([`LookMeterTarget`]), a GPU readback returns it a few
//! frames later, and its log-average luminance ([`MeterReading`]) drives the exposure in
//! [`super::look`]. It meters the scene before the exposure is applied, so there is no loop.

use bevy::asset::RenderAssetUsages;
use bevy::image::Image;
use bevy::prelude::*;
use bevy::render::extract_resource::{ExtractResource, ExtractResourcePlugin};
use bevy::render::gpu_readback::{Readback, ReadbackComplete};
use bevy::render::render_resource::{Extent3d, TextureDimension, TextureFormat, TextureUsages};

/// The meter image's size: a row is 256 bytes of `Rgba16Float`, the copy's row alignment, so the
/// readback carries no padding.
pub const METER_SIZE: (u32, u32) = (32, 16);

/// The image the FFXGlow node draws the frame's blur into, while the Modern look runs.
#[derive(Resource, Clone, ExtractResource)]
pub struct LookMeterTarget(pub Handle<Image>);

/// The last frame the readback returned: its log-average linear luminance (the scene as decoded,
/// before exposure), and the `Time::elapsed_secs` it arrived at. `None` until one has.
#[derive(Resource, Clone, Copy, Debug, Default, PartialEq)]
pub struct MeterReading(pub Option<(f32, f32)>);

/// An IEEE half as an `f32`.
fn half(bits: u16) -> f32 {
    let sign = if bits & 0x8000 != 0 { -1.0 } else { 1.0 };
    let exp = ((bits >> 10) & 0x1f) as i32;
    let frac = (bits & 0x3ff) as f32;
    let v = match exp {
        0 => frac * 2.0f32.powi(-24),
        31 => {
            if frac == 0.0 {
                f32::INFINITY
            } else {
                f32::NAN
            }
        }
        e => (1.0 + frac / 1024.0) * 2.0f32.powi(e - 15),
    };
    sign * v
}

/// The log-average luminance of a tightly packed `Rgba16Float` image's bytes, `None` when there
/// is no finite texel. The geometric mean, so a strip of bright sky does not carry the picture.
pub fn log_average(bytes: &[u8]) -> Option<f32> {
    let (mut sum, mut n) = (0.0f64, 0u32);
    for px in bytes.as_chunks::<8>().0 {
        let c = |i: usize| half(u16::from_le_bytes([px[i], px[i + 1]]));
        let l = 0.2126 * c(0) + 0.7152 * c(2) + 0.0722 * c(4);
        if l.is_finite() {
            sum += f64::from(l.max(1.0e-4).ln());
            n += 1;
        }
    }
    (n > 0).then(|| (sum / f64::from(n)).exp() as f32)
}

fn setup(mut commands: Commands, mut images: ResMut<Assets<Image>>) {
    let mut image = Image::new_fill(
        Extent3d {
            width: METER_SIZE.0,
            height: METER_SIZE.1,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        &[0; 8],
        TextureFormat::Rgba16Float,
        RenderAssetUsages::RENDER_WORLD,
    );
    image.texture_descriptor.usage = TextureUsages::RENDER_ATTACHMENT
        | TextureUsages::COPY_SRC
        | TextureUsages::TEXTURE_BINDING
        | TextureUsages::COPY_DST;
    let handle = images.add(image);
    commands.insert_resource(LookMeterTarget(handle.clone()));
    commands.spawn(Readback::texture(handle)).observe(
        |done: On<ReadbackComplete>, time: Res<Time>, mut reading: ResMut<MeterReading>| {
            if let Some(l) = log_average(&done.data) {
                // An image nothing has drawn into yet reads as the floor: not a reading.
                if l > 2.0e-4 {
                    reading.0 = Some((l, time.elapsed_secs()));
                }
            }
        },
    );
}

pub(super) fn plugin(app: &mut App) {
    app.init_resource::<MeterReading>()
        .add_plugins(ExtractResourcePlugin::<LookMeterTarget>::default())
        .add_systems(Startup, setup);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn halves_decode() {
        assert_eq!(half(0x3c00), 1.0);
        assert_eq!(half(0x0000), 0.0);
        assert_eq!(half(0x4000), 2.0);
        assert_eq!(half(0x3800), 0.5);
        assert_eq!(half(0xc000), -2.0);
    }

    #[test]
    fn the_log_average_is_the_geometric_mean() {
        // Two texels, luminance 1 and 0.25 (grey): the geometric mean is 0.5.
        let px = |h: u16| {
            let b = h.to_le_bytes();
            [b[0], b[1], b[0], b[1], b[0], b[1], 0, 0x3c]
        };
        let mut bytes = Vec::new();
        bytes.extend(px(0x3c00));
        bytes.extend(px(0x3400));
        let l = log_average(&bytes).unwrap();
        assert!((l - 0.5).abs() < 1e-3, "{l}");
        assert_eq!(log_average(&[]), None);
    }
}
