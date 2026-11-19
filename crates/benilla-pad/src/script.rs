//! `WOW_PAD_SCRIPT`: a scripted pad for unattended runs (the `dev` feature only). A real pad
//! reaches the game only while its window has the focus (Windows.Gaming.Input), so a test run
//! beside a person using the machine gets no input; this one is a pad entity fed raw button and
//! axis events, which take the same road as gilrs's from there on.
//!
//! `WOW_PAD_SCRIPT="X@30;A@36-36.4;LT+A@40;LS=0,1@42-50;RS=1,0@51-52"`: items separated by `;`,
//! each `BTN[+BTN..]@t[-t2]` (pressed at `t`, released at `t2` or 0.15 s later) or
//! `LS=x,y@t-t2` / `RS=x,y@t-t2` (a stick held at a deflection). Times are seconds since the
//! world was entered (or since boot with `WOW_PAD_SCRIPT_BOOT=1`, for the login screens).
//! Buttons: A B X Y LB RB LT RT L3 R3 START BACK UP DOWN LEFT RIGHT.

use std::sync::atomic::{AtomicU32, Ordering};

use bevy::input::gamepad::{
    GamepadConnection, GamepadConnectionEvent, RawGamepadAxisChangedEvent,
    RawGamepadButtonChangedEvent, RawGamepadEvent,
};
use bevy::prelude::*;

/// `Time::elapsed_secs` at the first frame in the world, as bits; 0 before it.
static WORLD_SINCE: AtomicU32 = AtomicU32::new(0);

/// Called by the pad's driver each frame it finds the world's UI up.
pub(crate) fn mark_world(now: f32) {
    let _ = WORLD_SINCE.compare_exchange(
        0,
        now.max(0.001).to_bits(),
        Ordering::Relaxed,
        Ordering::Relaxed,
    );
}

#[derive(Clone, Debug, PartialEq)]
enum What {
    Buttons(Vec<GamepadButton>),
    Stick(GamepadAxis, GamepadAxis, Vec2),
}

#[derive(Clone, Debug, PartialEq)]
struct Step {
    from: f32,
    to: f32,
    what: What,
    down: bool,
    up: bool,
}

#[derive(Resource)]
struct PadScript {
    steps: Vec<Step>,
    pad: Option<Entity>,
    boot: bool,
}

fn button(name: &str) -> Option<GamepadButton> {
    Some(match name {
        "A" => GamepadButton::South,
        "B" => GamepadButton::East,
        "X" => GamepadButton::West,
        "Y" => GamepadButton::North,
        "LB" => GamepadButton::LeftTrigger,
        "RB" => GamepadButton::RightTrigger,
        "LT" => GamepadButton::LeftTrigger2,
        "RT" => GamepadButton::RightTrigger2,
        "L3" => GamepadButton::LeftThumb,
        "R3" => GamepadButton::RightThumb,
        "START" => GamepadButton::Start,
        "BACK" => GamepadButton::Select,
        "UP" => GamepadButton::DPadUp,
        "DOWN" => GamepadButton::DPadDown,
        "LEFT" => GamepadButton::DPadLeft,
        "RIGHT" => GamepadButton::DPadRight,
        _ => return None,
    })
}

fn stick(v: &str, x: GamepadAxis, y: GamepadAxis) -> Option<What> {
    let (a, b) = v.split_once(',')?;
    Some(What::Stick(
        x,
        y,
        Vec2::new(a.trim().parse().ok()?, b.trim().parse().ok()?),
    ))
}

fn parse_item(item: &str) -> Option<Step> {
    let (what, when) = item.split_once('@')?;
    let (from, to) = match when.split_once('-') {
        Some((a, b)) => (a.trim().parse().ok()?, b.trim().parse().ok()?),
        None => {
            let t: f32 = when.trim().parse().ok()?;
            (t, t + 0.15)
        }
    };
    let what = if let Some(v) = what.strip_prefix("LS=") {
        stick(v, GamepadAxis::LeftStickX, GamepadAxis::LeftStickY)?
    } else if let Some(v) = what.strip_prefix("RS=") {
        stick(v, GamepadAxis::RightStickX, GamepadAxis::RightStickY)?
    } else {
        What::Buttons(
            what.split('+')
                .map(|b| button(b.trim()))
                .collect::<Option<_>>()?,
        )
    };
    Some(Step {
        from,
        to,
        what,
        down: false,
        up: false,
    })
}

/// The script's steps; an item that does not parse is dropped with a warning.
fn parse(spec: &str) -> Vec<Step> {
    let mut steps = Vec::new();
    for item in spec.split(';').map(str::trim).filter(|s| !s.is_empty()) {
        match parse_item(item) {
            Some(step) => steps.push(step),
            None => warn!("WOW_PAD_SCRIPT: unparseable item {item:?}, skipped"),
        }
    }
    steps
}

/// Connect the scripted pad at the first frame, then feed each step's events at its times.
fn run_script(
    mut commands: Commands,
    mut script: ResMut<PadScript>,
    time: Res<Time>,
    mut connections: MessageWriter<GamepadConnectionEvent>,
    mut raw: MessageWriter<RawGamepadEvent>,
) {
    let Some(pad) = script.pad else {
        let pad = commands.spawn_empty().id();
        script.pad = Some(pad);
        connections.write(GamepadConnectionEvent::new(
            pad,
            GamepadConnection::Connected {
                name: crate::SCRIPTED_PAD.into(),
                vendor_id: None,
                product_id: None,
            },
        ));
        info!(
            "pad script: a scripted pad is connected ({} steps)",
            script.steps.len()
        );
        return;
    };
    let since = if script.boot {
        0.0
    } else {
        match WORLD_SINCE.load(Ordering::Relaxed) {
            0 => return,
            bits => f32::from_bits(bits),
        }
    };
    let t = time.elapsed_secs() - since;
    for step in &mut script.steps {
        let (start, end) = (!step.down && t >= step.from, !step.up && t >= step.to);
        if !(start || end) {
            continue;
        }
        // A step due both ways at once (a long frame) goes down this frame and up the next.
        let value = if start { 1.0 } else { 0.0 };
        match &step.what {
            What::Buttons(buttons) => {
                for &b in buttons {
                    raw.write(RawGamepadEvent::Button(RawGamepadButtonChangedEvent::new(
                        pad, b, value,
                    )));
                }
            }
            What::Stick(ax, ay, v) => {
                raw.write(RawGamepadEvent::Axis(RawGamepadAxisChangedEvent::new(
                    pad,
                    *ax,
                    v.x * value,
                )));
                raw.write(RawGamepadEvent::Axis(RawGamepadAxisChangedEvent::new(
                    pad,
                    *ay,
                    v.y * value,
                )));
            }
        }
        if start {
            step.down = true;
            info!("pad script: {:?} at {t:.2}s", step.what);
        } else {
            step.up = true;
        }
    }
}

/// Arms the script when `WOW_PAD_SCRIPT` is set.
pub(crate) fn plugin(app: &mut App) {
    let Ok(spec) = std::env::var("WOW_PAD_SCRIPT") else {
        return;
    };
    let steps = parse(&spec);
    if steps.is_empty() {
        return;
    }
    app.insert_resource(PadScript {
        steps,
        pad: None,
        boot: std::env::var_os("WOW_PAD_SCRIPT_BOOT").is_some(),
    })
    .add_systems(PreUpdate, run_script.before(bevy::input::InputSystems));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_script_parses_buttons_chords_and_sticks() {
        let steps = parse("X@30; LT+A@40-41 ;LS=0,1@42-50;bogus;Q@3");
        assert_eq!(steps.len(), 3);
        assert_eq!(steps[0].what, What::Buttons(vec![GamepadButton::West]));
        assert!((steps[0].to - 30.15).abs() < 1e-4);
        assert_eq!(
            steps[1].what,
            What::Buttons(vec![GamepadButton::LeftTrigger2, GamepadButton::South])
        );
        assert_eq!(
            steps[2].what,
            What::Stick(
                GamepadAxis::LeftStickX,
                GamepadAxis::LeftStickY,
                Vec2::new(0.0, 1.0)
            )
        );
    }
}
