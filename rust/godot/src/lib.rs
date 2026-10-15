//! The rules engine for Godot (desktop, Android): `RulesEngine.call_json(request) -> reply`,
//! the JSON API of `classichs_engine::Engine` (rust/engine/README.md).
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
