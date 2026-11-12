"""The one place for how the game's audio is encoded: Ogg Opus (.opus, 48 kHz), the source's channels kept
(mono stays mono, stereo stays stereo). Every tool that writes pack audio uses encode_opus().

Bit rates (kbit/s) per kind: voice lines, sounds (card and board sounds), music (menu and match tracks,
a legendary's play music).
"""
import subprocess

EXT = ".opus"
KBPS = {"voice": 48, "sound": 96, "music": 128}
FFMPEG = "ffmpeg"


def encode_opus(src, dst, kind, ffmpeg=None):
    """src (any file ffmpeg reads) -> dst (.opus) at KBPS[kind]. True when it worked."""
    channels = probe_channels(src, ffmpeg)
    cmd = [ffmpeg or FFMPEG, "-v", "error", "-y", "-i", str(src), "-vn", "-map_metadata", "-1"]
    if channels > 2:
        cmd += ["-ac", "2"]
    cmd += ["-ar", "48000", "-c:a", "libopus", "-b:a", f"{KBPS[kind]}k", "-vbr", "on", "-compression_level", "10",
            "-application", "audio", str(dst)]
    return subprocess.run(cmd).returncode == 0


def probe_channels(src, ffmpeg=None):
    probe = (ffmpeg or FFMPEG).replace("ffmpeg", "ffprobe") if (ffmpeg or FFMPEG).endswith("ffmpeg") else "ffprobe"
    r = subprocess.run([probe, "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels",
                        "-of", "csv=p=0", str(src)], capture_output=True, text=True)
    try:
        return int(r.stdout.strip().split(",")[0])
    except ValueError:
        return 2


def has_libopus(ffmpeg=None):
    r = subprocess.run([ffmpeg or FFMPEG, "-hide_banner", "-encoders"], capture_output=True, text=True)
    return r.returncode == 0 and " libopus " in r.stdout
