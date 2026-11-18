//! benilla-gamepad fork: **the Modern look**, a post look over the reference's picture. The world
//! still draws the reference's gamma frame; the FFXGlow combine (`ffx_glow`) decodes it once, then
//! exposes, blooms, tonemaps and grades it before its own glow, haze and death math. The Classic
//! look is the reference's frame, bit for bit: every Modern line in the shader sits under
//! `MODERN_LOOK`, a pipeline of its own.
//!
//! The settings are three CVars (`lookModel`, `lookQuality`, `autoExposure`) whose knobs are the
//! resources here; [`look`] turns them into the combine's lanes each frame ([`LookLanes`]).

use bevy::prelude::*;
use bevy::render::extract_resource::{ExtractResource, ExtractResourcePlugin};

pub mod look;

/// Which look the world's frame is presented with. CVar `lookModel`: `0` Classic, `1` Modern.
#[derive(Resource, Clone, Copy, PartialEq, Eq, Debug)]
pub enum LookModel {
    /// The reference's picture: the FFXGlow combine as 1.12 runs it.
    Classic,
    /// The fork's: the combine exposes, blooms, tonemaps and grades the decoded frame.
    Modern,
}

/// `$WOW_LOOK_MODEL=0` boots the Classic look, anything else the Modern one, which is the fork's
/// `lookModel` default (the CVar applies only on a change, so the two must agree at boot).
/// Session-only: `cvars` marks the row env-overridden so a run cannot pin itself into the file.
impl Default for LookModel {
    fn default() -> Self {
        match std::env::var("WOW_LOOK_MODEL").as_deref() {
            Ok("0") => Self::Classic,
            _ => Self::Modern,
        }
    }
}

impl LookModel {
    /// The CVar's parse: 0 is the Classic look, anything else the Modern one.
    pub fn from_cvar(v: f32) -> Self {
        if v != 0.0 {
            Self::Modern
        } else {
            Self::Classic
        }
    }

    /// What `GetCVar("lookModel")` answers for this state.
    pub fn cvar(self) -> &'static str {
        match self {
            Self::Classic => "0",
            Self::Modern => "1",
        }
    }

    pub fn is_modern(self) -> bool {
        self == Self::Modern
    }
}

/// How much the Modern look spends. CVar `lookQuality`: `0` Low, `1` Medium, `2` High. Low meters
/// the exposure from the light rows; the costlier passes key on Medium and High.
#[derive(Resource, Clone, Copy, PartialEq, Eq, Debug)]
pub enum LookQuality {
    Low,
    /// The default.
    Medium,
    High,
}

/// Medium, the `lookQuality` default, unless `$WOW_LOOK_QUALITY=0|1|2` picks a tier for the
/// session (the capture lever: a capture loads no config).
impl Default for LookQuality {
    fn default() -> Self {
        match std::env::var("WOW_LOOK_QUALITY").as_deref() {
            Ok("0") => Self::Low,
            Ok("2") => Self::High,
            _ => Self::Medium,
        }
    }
}

impl LookQuality {
    /// The CVar's parse: the integer part, below 1 Low and from 2 High.
    pub fn from_cvar(v: f32) -> Self {
        if v < 1.0 {
            Self::Low
        } else if v < 2.0 {
            Self::Medium
        } else {
            Self::High
        }
    }

    /// What `GetCVar("lookQuality")` answers for this state.
    pub fn cvar(self) -> &'static str {
        match self {
            Self::Low => "0",
            Self::Medium => "1",
            Self::High => "2",
        }
    }
}

/// The Modern look's lanes for the FFXGlow combine this frame, `None` in a Classic frame. The
/// combine binds them as `ffx.look` and `ffx.grade` (`shaders/ffx_glow.wgsl`), and only the world
/// view's pass pair reads them: the glue screens and the portrait bakes stay Classic.
#[derive(Resource, Clone, Copy, PartialEq, Debug, Default, ExtractResource)]
pub struct LookLanes(pub Option<[f32; 8]>);

pub(crate) fn plugin(app: &mut App) {
    app.init_resource::<LookModel>()
        .init_resource::<LookQuality>()
        .init_resource::<LookLanes>()
        .add_plugins(ExtractResourcePlugin::<LookLanes>::default())
        .add_plugins(look::plugin);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_cvars_round_trip() {
        for m in [LookModel::Classic, LookModel::Modern] {
            assert_eq!(LookModel::from_cvar(m.cvar().parse().unwrap()), m);
        }
        for q in [LookQuality::Low, LookQuality::Medium, LookQuality::High] {
            assert_eq!(LookQuality::from_cvar(q.cvar().parse().unwrap()), q);
        }
    }
}
