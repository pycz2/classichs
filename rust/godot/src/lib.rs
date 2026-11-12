//! The rules engine for Godot (desktop, Android): `RulesEngine.call_json(request) -> reply`,
//! the JSON API of `classichs_engine::Engine` (rust/engine/README.md); and the game's own bot,
//! `RulesBrain.think_json(request) -> reply` (classichs_brain::think; it keeps no state, so a Thread
//! may call it while the game goes on); and `OpusDecoder.decode(bytes)`, the game's .opus audio.
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

/// Ogg Opus files (classichs_opus) as an AudioStreamWAV (16-bit PCM, 48 kHz), null on a bad file
/// (the reason in the error log): at once, `OpusDecoder.decode(bytes)`, or in a thread of its own
/// (a long music track takes a few hundred ms), `start(bytes)`, then `stream()` once `done()`.
/// game/opus.gd uses it.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
struct OpusDecoder {
    job: Option<std::sync::mpsc::Receiver<Result<(u16, Vec<u8>), String>>>,
    result: Option<Result<(u16, Vec<u8>), String>>,
}

/// channels and the samples as little-endian bytes (every platform the game runs on is little-endian)
fn decode_bytes(ogg: &[u8]) -> Result<(u16, Vec<u8>), String> {
    let pcm = classichs_opus::decode(ogg)?;
    Ok((pcm.channels, pcm.samples.iter().flat_map(|s| s.to_le_bytes()).collect()))
}

fn wav(r: Result<(u16, Vec<u8>), String>) -> Option<Gd<godot::classes::AudioStreamWav>> {
    use godot::classes::audio_stream_wav::Format;
    let (channels, data) = r.inspect_err(|e| {
        godot_error!("opus: {e}");
    })
    .ok()?;
    let mut s = godot::classes::AudioStreamWav::new_gd();
    s.set_format(Format::FORMAT_16_BITS);
    s.set_mix_rate(48000);
    s.set_stereo(channels == 2);
    s.set_data(&PackedByteArray::from(data.as_slice()));
    Some(s)
}

#[godot_api]
impl OpusDecoder {
    #[func]
    fn decode(bytes: PackedByteArray) -> Option<Gd<godot::classes::AudioStreamWav>> {
        wav(decode_bytes(bytes.as_slice()))
    }

    #[func]
    fn start(&mut self, bytes: PackedByteArray) {
        let (tx, rx) = std::sync::mpsc::channel();
        let ogg = bytes.to_vec();
        std::thread::spawn(move || {
            let _ = tx.send(decode_bytes(&ogg));
        });
        self.job = Some(rx);
        self.result = None;
    }

    #[func]
    fn done(&mut self) -> bool {
        if let Some(rx) = &self.job {
            match rx.try_recv() {
                Ok(r) => self.result = Some(r),
                Err(std::sync::mpsc::TryRecvError::Empty) => return false,
                Err(_) => self.result = Some(Err("the decoding thread stopped".into())),
            }
            self.job = None;
        }
        true
    }

    #[func]
    fn stream(&mut self) -> Option<Gd<godot::classes::AudioStreamWav>> {
        wav(self.result.take()?)
    }
}
