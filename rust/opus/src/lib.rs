//! Ogg Opus (.opus, RFC 7845) to 16-bit PCM at 48 kHz for the game's sounds, voice lines and music.
//! The decoder is libopus 1.3.1 transpiled to Rust (the `unsafe-libopus` crate, BSD-3-Clause), so the
//! same code builds for every platform and for wasm32 without a C toolchain. The first logical
//! stream is decoded; mono and stereo (channel mapping family 0) only. `encode` makes a mono
//! Ogg Opus voice file (the server's problem reports: the game records WAV).
use std::io::Cursor;
use unsafe_libopus::{
    opus_decode, opus_decoder_create, opus_decoder_destroy, opus_encode, opus_encoder_create, opus_encoder_destroy, OpusDecoder, OpusEncoder,
    OPUS_APPLICATION_VOIP, OPUS_SET_GAIN_REQUEST,
};

pub struct Pcm {
    pub channels: u16,
    /// always 48000 (Opus decodes at 48 kHz)
    pub rate: u32,
    /// interleaved
    pub samples: Vec<i16>,
}

/// The longest file decoded (per channel, 48 kHz): a pack's music track, not a whole album; a
/// file of tiny packets can't make it take all the memory.
pub const MAX_SAMPLES: usize = 48_000 * 60 * 15;
/// 120 ms, the longest Opus packet
const MAX_FRAME: usize = 5760;

/// Frees the decoder however `decode` ends.
struct Decoder(*mut OpusDecoder);
impl Drop for Decoder {
    fn drop(&mut self) {
        unsafe { opus_decoder_destroy(self.0) }
    }
}

pub fn decode(ogg: &[u8]) -> Result<Pcm, String> {
    let mut rd = ogg::PacketReader::new(Cursor::new(ogg));
    let next = |rd: &mut ogg::PacketReader<Cursor<&[u8]>>| rd.read_packet().map_err(|e| format!("bad ogg: {e}"));
    let head = next(&mut rd)?.ok_or("empty file")?;
    let serial = head.stream_serial();
    let h = &head.data;
    if h.len() < 19 || &h[..8] != b"OpusHead" {
        return Err("not an Ogg Opus file".into());
    }
    if h[8] >> 4 != 0 {
        return Err(format!("unsupported OpusHead version {}", h[8]));
    }
    let channels = h[9] as usize;
    let pre_skip = u16::from_le_bytes([h[10], h[11]]) as usize;
    let gain = i16::from_le_bytes([h[16], h[17]]); // Q7.8 dB, what OPUS_SET_GAIN takes
    if h[18] != 0 || !(1..=2).contains(&channels) {
        return Err(format!("only mono and stereo are supported (mapping {}, {channels} channels)", h[18]));
    }
    let mut err = 0;
    let dec = Decoder(unsafe { opus_decoder_create(48000, channels as i32, &mut err) });
    if dec.0.is_null() || err != 0 {
        return Err(format!("opus decoder: error {err}"));
    }
    if gain != 0 {
        unsafe { unsafe_libopus::opus_decoder_ctl!(dec.0, OPUS_SET_GAIN_REQUEST, gain as i32) };
    }
    let mut out: Vec<i16> = Vec::new();
    // room for the whole track at once (no doubling: the browser's memory never shrinks): the
    // granule position of the last page of this stream ("OggS" at its start, RFC 3533)
    if let Some(i) = ogg.windows(4).rposition(|w| w == b"OggS").filter(|&i| ogg.len() >= i + 18) {
        let g = u64::from_le_bytes(ogg[i + 6..i + 14].try_into().unwrap()) as usize;
        if ogg[i + 14..i + 18] == serial.to_le_bytes() && g <= MAX_SAMPLES + pre_skip {
            out.reserve_exact(g * channels);
        }
    }
    let mut frame = vec![0i16; MAX_FRAME * channels];
    let mut tags_seen = false;
    let mut end: Option<u64> = None; // the granule position of the last page
    while let Some(p) = next(&mut rd)? {
        if p.stream_serial() != serial {
            continue;
        }
        if !tags_seen {
            tags_seen = true; // OpusTags
            continue;
        }
        if p.last_in_page() {
            end = Some(p.absgp_page());
        }
        if p.data.is_empty() {
            continue;
        }
        let n = unsafe { opus_decode(dec.0, p.data.as_ptr(), p.data.len() as i32, frame.as_mut_ptr(), MAX_FRAME as i32, 0) };
        if n < 0 {
            return Err(format!("bad opus packet (error {n})"));
        }
        out.extend_from_slice(&frame[..n as usize * channels]);
        if out.len() > (MAX_SAMPLES + pre_skip) * channels {
            return Err("longer than 15 minutes".into());
        }
    }
    // RFC 7845 4.: pre_skip samples are dropped at the start; the last page's granule position
    // (counted from the start, pre_skip included) is where the audio ends.
    let mut frames = out.len() / channels;
    if let Some(g) = end.filter(|&g| g != u64::MAX) {
        frames = frames.min(g as usize);
    }
    let start = pre_skip.min(frames);
    out.truncate(frames * channels);
    out.drain(..start * channels);
    if out.is_empty() {
        return Err("no audio".into());
    }
    Ok(Pcm { channels: channels as u16, rate: 48000, samples: out })
}

/// Frees the encoder however `encode` ends.
struct Encoder(*mut OpusEncoder);
impl Drop for Encoder {
    fn drop(&mut self) {
        unsafe { opus_encoder_destroy(self.0) }
    }
}

/// Mono 16-bit PCM at `rate` (8000, 12000, 16000, 24000 or 48000) to an Ogg Opus file (RFC 7845):
/// 20 ms frames, libopus's voice mode at its default bitrate.
pub fn encode(samples: &[i16], rate: u32) -> Result<Vec<u8>, String> {
    if ![8000, 12000, 16000, 24000, 48000].contains(&rate) {
        return Err(format!("Opus takes 8, 12, 16, 24 or 48 kHz, not {rate} Hz"));
    }
    let mut err = 0;
    let enc = Encoder(unsafe { opus_encoder_create(rate as i32, 1, OPUS_APPLICATION_VOIP, &mut err) });
    if enc.0.is_null() || err != 0 {
        return Err(format!("opus encoder: error {err}"));
    }
    // libopus's look-ahead at 48 kHz (what opusenc writes for its voice mode)
    const PRE_SKIP: u64 = 312;
    let frame = rate as usize / 50;
    let mut out = Vec::new();
    let mut w = ogg::PacketWriter::new(Cursor::new(&mut out));
    let serial = 0x4348_5352; // "CHSR"
    let io = |e: std::io::Error| e.to_string();
    let mut head = b"OpusHead\x01\x01".to_vec();
    head.extend_from_slice(&(PRE_SKIP as u16).to_le_bytes());
    head.extend_from_slice(&rate.to_le_bytes());
    head.extend_from_slice(&[0, 0, 0]); // gain 0, mapping family 0
    w.write_packet(head, serial, ogg::PacketWriteEndInfo::EndPage, 0).map_err(io)?;
    let vendor = b"classichs";
    let mut tags = b"OpusTags".to_vec();
    tags.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
    tags.extend_from_slice(vendor);
    tags.extend_from_slice(&0u32.to_le_bytes());
    w.write_packet(tags, serial, ogg::PacketWriteEndInfo::EndPage, 0).map_err(io)?;
    // the look-ahead's samples at the end come out in one more frame
    let frames = (samples.len() + PRE_SKIP as usize * rate as usize / 48000).div_ceil(frame).max(1);
    let mut pcm = vec![0i16; frame];
    let mut packet = vec![0u8; 4000];
    for i in 0..frames {
        let chunk = &samples[(i * frame).min(samples.len())..((i + 1) * frame).min(samples.len())];
        pcm.fill(0);
        pcm[..chunk.len()].copy_from_slice(chunk);
        let n = unsafe { opus_encode(enc.0, pcm.as_ptr(), frame as i32, packet.as_mut_ptr(), packet.len() as i32) };
        if n < 0 {
            return Err(format!("opus encoder: error {n}"));
        }
        let last = i + 1 == frames;
        // granule positions count 48 kHz samples; the last page's says where the audio ends (RFC 7845 4.)
        let done = if last { samples.len() * 48000 / rate as usize } else { (i + 1) * 960 };
        let end = if last {
            ogg::PacketWriteEndInfo::EndStream
        } else if (i + 1) % 50 == 0 {
            ogg::PacketWriteEndInfo::EndPage
        } else {
            ogg::PacketWriteEndInfo::NormalPacket
        };
        w.write_packet(packet[..n as usize].to_vec(), serial, end, PRE_SKIP + done as u64).map_err(io)?;
    }
    drop(w);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    const MONO: &[u8] = include_bytes!("../tests/fixtures/tone_mono.opus");
    const STEREO: &[u8] = include_bytes!("../tests/fixtures/tone_stereo.opus");

    fn rms(s: &[i16]) -> f64 {
        (s.iter().map(|&x| (x as f64).powi(2)).sum::<f64>() / s.len() as f64).sqrt()
    }

    /// libopus itself (ffmpeg -c:a libopus) on the same file, when this machine has it.
    fn reference(file: &str) -> Option<Vec<i16>> {
        let path = format!("{}/tests/fixtures/{file}", env!("CARGO_MANIFEST_DIR"));
        let o = std::process::Command::new("ffmpeg")
            .args(["-v", "error", "-c:a", "libopus", "-i", &path, "-f", "s16le", "-"])
            .output()
            .ok()
            .filter(|o| o.status.success())?;
        Some(o.stdout.chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]])).collect())
    }

    fn check(bytes: &[u8], file: &str, channels: u16) {
        let pcm = decode(bytes).unwrap();
        assert_eq!((pcm.channels, pcm.rate), (channels, 48000));
        // the fixtures are 0.5 s tones (ffmpeg's sine source, encoded by libopus)
        assert_eq!(pcm.samples.len(), 24000 * channels as usize);
        assert!(rms(&pcm.samples) > 1000.0, "silent: {}", rms(&pcm.samples));
        match reference(file) {
            Some(r) => {
                assert_eq!(r.len(), pcm.samples.len());
                let worst = r.iter().zip(&pcm.samples).map(|(a, b)| (*a as i32 - *b as i32).abs()).max().unwrap();
                assert!(worst <= 2, "{file}: differs from libopus by up to {worst}");
            }
            None => eprintln!("no ffmpeg with libopus: {file} not compared with libopus"),
        }
    }

    #[test]
    fn mono() {
        check(MONO, "tone_mono.opus", 1);
    }

    #[test]
    fn stereo() {
        check(STEREO, "tone_stereo.opus", 2);
    }

    #[test]
    fn encodes_voice() {
        // 1.5 s of a 440 Hz tone at 16 kHz: back as 1.5 s at 48 kHz, not silent, small
        let pcm: Vec<i16> = (0..24000).map(|i| ((i as f64 * 440.0 * std::f64::consts::TAU / 16000.0).sin() * 8000.0) as i16).collect();
        let ogg = encode(&pcm, 16000).unwrap();
        assert!(ogg.len() < 20_000, "{} bytes", ogg.len());
        let back = decode(&ogg).unwrap();
        assert_eq!((back.channels, back.samples.len()), (1, 72000));
        assert!(rms(&back.samples) > 2000.0, "{}", rms(&back.samples));
        assert!(encode(&pcm, 44100).is_err());
    }

    #[test]
    fn garbage_is_an_error() {
        assert!(decode(b"").is_err());
        assert!(decode(b"definitely not ogg at all, just some bytes").is_err());
        let _ = decode(&STEREO[..STEREO.len() / 2]); // a cut file: no panic
        assert!(decode(&STEREO[..60]).is_err()); // the header page only: no audio
        let mut broken = STEREO.to_vec();
        for i in (200..broken.len()).step_by(7) {
            broken[i] ^= 0x5a;
        }
        assert!(decode(&broken).is_err()); // the pages' checksums
        // pseudo-random bytes after a real header: no panic, whatever comes out
        let mut x = 12345u32;
        let mut noise = STEREO[..100].to_vec();
        noise.extend((0..5000).map(|_| {
            x = x.wrapping_mul(1103515245).wrapping_add(12345);
            (x >> 16) as u8
        }));
        let _ = decode(&noise);
    }
}
