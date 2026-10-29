//! The rules engine for Godot (desktop, Android): `RulesEngine.call_json(request) -> reply`,
//! the JSON API of `classichs_engine::Engine` (rust/engine/README.md); and the game's own bot,
//! `RulesBrain.think_json(request) -> reply` (classichs_brain::think; it keeps no state, so a Thread
//! may call it while the game goes on).
use godot::prelude::*;

struct Rules;

#[gdextension]
unsafe impl ExtensionLibrary for Rules {}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
struct RulesEngine {
    engine: classichs_engine::Engine,
}

#[godot_api]
impl RulesEngine {
    #[func]
    fn call_json(&mut self, request: GString) -> GString {
        GString::from(&self.engine.call(&request.to_string()))
    }
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
struct RulesBrain {
    /// the answer of the thinking started by `start`
    job: Option<std::sync::mpsc::Receiver<String>>,
}

fn think_text(request: &str) -> String {
    match serde_json::from_str(request) {
        Ok(v) => classichs_brain::think(&v),
        Err(e) => serde_json::json!({"ok": false, "error": format!("bad json: {e}")}),
    }
    .to_string()
}

#[godot_api]
impl RulesBrain {
    /// The answer at once.
    #[func]
    fn think_json(&self, request: GString) -> GString {
        GString::from(&think_text(&request.to_string()))
    }

    /// Thinks in a thread of its own (Godot objects stay on the main thread); `poll` gives the answer.
    #[func]
    fn start(&mut self, request: GString) {
        let (tx, rx) = std::sync::mpsc::channel();
        let text = request.to_string();
        std::thread::spawn(move || {
            let _ = tx.send(think_text(&text));
        });
        self.job = Some(rx);
    }

    /// The answer of `start`, or "" while it still thinks.
    #[func]
    fn poll(&mut self) -> GString {
        let Some(rx) = &self.job else { return GString::from("") };
        match rx.try_recv() {
            Ok(s) => {
                self.job = None;
                GString::from(&s)
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => GString::from(""),
            Err(_) => {
                self.job = None;
                GString::from(r#"{"ok": false, "error": "the bot's thread stopped"}"#)
            }
        }
    }
}
