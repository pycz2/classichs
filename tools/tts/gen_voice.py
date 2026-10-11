#!/usr/bin/env python3
"""Generates minion voice lines with Chatterbox Multilingual (local, offline after the first download).

Input: {card_id: {"play"|"attack"|"death": {lang: text}}}, lang = "enUS", "ruRU", "deDE", "frFR", "esES",
"ptBR", "itIT", "plPL". Output: build/voice/<lang>/<card_id>_<kind>.ogg (mono 24 kHz Vorbis, -16 LUFS)
and the listening page build/voice/index.html. Existing clips are skipped, so a killed run just restarts.

Usage: tools/tts/.venv/bin/python tools/tts/gen_voice.py [--lines F] [--langs enUS,ruRU] [--cards ID,ID]
       [--force] [--page-only] [--device mps|cpu]
"""
import argparse
import difflib
import html
import json
import os
import re
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "build", "voice")
REFS = os.path.join(HERE, "refs")
sys.path.insert(0, HERE)
from cast import cast, load_cards, load_overrides  # noqa: E402


def log(msg):
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "gen.log"), "a", encoding="utf-8") as f:
        f.write(line + "\n")


def ref_voice(voices, vid):
    """The voice whose reference clip vid uses."""
    return voices[vid].get("base", vid)


def make_refs(voices, ids):
    """Kokoro reads each voice's ref_text once; the clip is the voice for every language."""
    todo = [v for v in sorted(ids) if not os.path.exists(os.path.join(REFS, v + ".wav"))]
    if not todo:
        return
    import numpy as np
    import soundfile as sf
    from kokoro import KPipeline
    os.makedirs(REFS, exist_ok=True)
    pipes = {}
    for v in todo:
        spk = voices[v]["ref"]
        lang = spk[0]  # Kokoro speaker names start with their language: a = US English, b = British
        if lang not in pipes:
            pipes[lang] = KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M")
        audio = np.concatenate([r.audio.numpy() for r in pipes[lang](voices[v]["ref_text"], voice=spk)])
        sf.write(os.path.join(REFS, v + ".wav"), audio, 24000)
        log(f"reference {v} <- kokoro {spk} ({len(audio) / 24000:.1f}s)")


class Speaker:
    def __init__(self, device):
        os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        import torch
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        if device == "mps" and not torch.backends.mps.is_available():
            device = "cpu"
        self.torch = torch
        self.model = ChatterboxMultilingualTTS.from_pretrained(device=device)
        self.conds = {}
        # generate() always allows 1000 speech tokens (40 s); a rambling take then costs minutes. Cap it.
        self.max_tokens = 1000
        t3_inference = self.model.t3.inference
        self.model.t3.inference = lambda **kw: t3_inference(**{**kw, "max_new_tokens": self.max_tokens})
        log(f"chatterbox multilingual loaded on {device}")

    @staticmethod
    def max_seconds(text):
        return 2.5 + len(text) / 6

    def say(self, text, lang, ref, style, seed):
        """-> (samples, sample_rate)"""
        m = self.model
        if ref not in self.conds:
            m.prepare_conditionals(os.path.join(REFS, ref + ".wav"), exaggeration=style["exaggeration"])
            self.conds[ref] = m.conds
        m.conds = self.conds[ref]
        self.torch.manual_seed(seed)
        self.max_tokens = int(25 * self.max_seconds(text)) + 1  # 25 speech tokens per second
        wav = m.generate(text, language_id=lang, exaggeration=style["exaggeration"],
                         cfg_weight=style["cfg_weight"], temperature=style["temperature"])
        return wav.squeeze(0).numpy(), m.sr


ASR_MODEL = "mlx-community/whisper-small-mlx"


def heard(samples, sr, code):
    """Whisper's transcript of the raw take (before effects)."""
    import librosa
    import mlx_whisper
    audio = librosa.resample(samples, orig_sr=sr, target_sr=16000) if sr != 16000 else samples
    return mlx_whisper.transcribe(audio.astype("float32"), path_or_hf_repo=ASR_MODEL, language=code)["text"].strip()


def similarity(a, b):
    norm = lambda s: re.sub(r"[\W_]+", " ", s.lower()).strip()
    return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio()


def fx_filter(cfg, voice, style):
    trim = "silenceremove=start_periods=1:start_threshold=-50dB"
    chain = [trim, "areverse", trim, "areverse"]  # trim both ends before echoes add tails
    if style.get("tempo"):
        chain.append(f"atempo={style['tempo']}")
    if voice["fx"]:  # room for echo tails, then cut what stays silent
        chain += ["apad=pad_dur=0.8"] + [cfg["effects"][n] for n in voice["fx"]] + ["areverse", trim, "areverse"]
    chain.append("loudnorm=I=-16:TP=-1.5:LRA=11")
    return ",".join(chain)


def encode(samples, sr, dst, filt):
    import soundfile as sf
    tmp_wav = dst + ".wav"
    sf.write(tmp_wav, samples, sr)
    try:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp_wav, "-af", filt, "-ar", "24000", "-ac", "1",
                        "-c:a", "libvorbis", "-q:a", "4", "-f", "ogg", dst + ".tmp"], check=True)
        os.replace(dst + ".tmp", dst)
    finally:
        os.remove(tmp_wav)


def clip_path(lang, cid, kind):
    return os.path.join(OUT, lang, f"{cid}_{kind}.ogg")


def jobs_of(lines, langs, cards):
    for cid in sorted(lines):
        if cards and cid not in cards:
            continue
        for kind, texts in sorted(lines[cid].items()):
            for lang, text in sorted(texts.items()):
                if text and (not langs or lang in langs):
                    yield cid, kind, lang, text


def write_page(lines, all_cards, cfg, overrides, scores):
    rows = []
    for cid, kind, lang, text in jobs_of(lines, None, None):
        if not os.path.exists(clip_path(lang, cid, kind)) or cid not in all_cards:
            continue
        card = all_cards[cid]
        vid, sname = cast(card, cfg["voices"], overrides)
        e = html.escape
        sc = scores.get(f"{lang}/{cid}_{kind}")
        asr = "-" if not sc else f"{sc['score']:.2f}" + (
            f"<br><small>{e(sc['heard'])}</small>" if sc["score"] < 0.85 else "")
        rows.append(f"<tr><td><img src='../../art/cards/{e(cid)}.jpg' alt=''></td>"
                    f"<td><b>{e(card['name'].get(lang, card['name']['enUS']))}</b><br><small>{e(cid)}</small></td>"
                    f"<td>{e(kind)}</td><td>{e(vid)}</td><td>{e(sname)}</td>"
                    f"<td>{e(', '.join(cfg['voices'][vid]['fx']) or '-')}</td><td>{e(lang)}</td><td>{e(text)}</td><td>{asr}</td>"
                    f"<td><audio controls preload='none' src='{e(lang)}/{e(cid)}_{e(kind)}.ogg'></audio></td></tr>")
    page = f"""<!doctype html><meta charset="utf-8"><title>Voice lines</title>
<style>body{{font:14px system-ui;margin:16px;background:#fff;color:#222}}table{{border-collapse:collapse}}
td,th{{border-bottom:1px solid #ddd;padding:4px 8px;text-align:left;vertical-align:middle}}img{{height:64px}}
@media (prefers-color-scheme:dark){{body{{background:#1b1b1b;color:#ddd}}td,th{{border-color:#444}}}}</style>
<h1>Voice lines ({len(rows)} clips)</h1><div style="overflow-x:auto"><table><tr><th></th><th>Card</th><th>Kind</th><th>Voice</th><th>Style</th>
<th>Effects</th><th>Lang</th><th>Text</th><th title="how well Whisper understood the raw take (1 = word for word)">ASR</th><th>Listen</th></tr>
{chr(10).join(rows)}
</table></div>"""
    with open(os.path.join(OUT, "index.html"), "w", encoding="utf-8") as f:
        f.write(page)
    log(f"page: {os.path.join(OUT, 'index.html')} ({len(rows)} clips)")


def main():
    ap = argparse.ArgumentParser()
    default_lines = os.path.join(ROOT, "data", "voice_lines.json")
    if not os.path.exists(default_lines):
        default_lines = os.path.join(HERE, "sample_lines.json")
    ap.add_argument("--lines", default=default_lines)
    ap.add_argument("--langs", default="", help="comma list, e.g. enUS,ruRU (default: all in the file)")
    ap.add_argument("--cards", default="", help="comma list of card ids (default: all in the file)")
    ap.add_argument("--force", action="store_true", help="regenerate existing clips")
    ap.add_argument("--page-only", action="store_true")
    ap.add_argument("--device", default="mps")
    ap.add_argument("--tries", type=int, default=3, help="takes per line; the best by Whisper is kept")
    ap.add_argument("--no-check", action="store_true", help="skip the Whisper check (one take per line)")
    a = ap.parse_args()

    cfg = json.load(open(os.path.join(HERE, "voices.json"), encoding="utf-8"))
    lines = json.load(open(a.lines, encoding="utf-8"))
    all_cards, overrides = load_cards(), load_overrides()
    langs = set(filter(None, a.langs.split(",")))
    pick = set(filter(None, a.cards.split(",")))
    jobs = [j for j in jobs_of(lines, langs, pick) if a.force or not os.path.exists(clip_path(j[2], j[0], j[1]))]
    unknown = sorted({j[0] for j in jobs if j[0] not in all_cards})
    if unknown:
        log(f"skipping unknown card ids: {', '.join(unknown)}")
        jobs = [j for j in jobs if j[0] in all_cards]
    log(f"{a.lines}: {len(jobs)} clips to make")
    scores_path = os.path.join(OUT, "scores.json")
    scores = json.load(open(scores_path, encoding="utf-8")) if os.path.exists(scores_path) else {}
    if jobs and not a.page_only:
        casting = {cid: cast(all_cards[cid], cfg["voices"], overrides) for cid in {j[0] for j in jobs}}
        make_refs(cfg["voices"], {ref_voice(cfg["voices"], v) for v, _ in casting.values()})
        speaker = Speaker(a.device)
        jobs.sort(key=lambda j: ref_voice(cfg["voices"], casting[j[0]][0]))  # fewer reference switches
        t0 = time.time()
        for i, (cid, kind, lang, text) in enumerate(jobs, 1):
            vid, sname = casting[cid]
            style = cfg["styles"][sname]
            code = lang[:2].lower()
            t = time.time()
            seed = zlib.crc32(f"{cid}/{kind}/{lang}".encode())
            best = None
            # Takes vary a lot: keep the one Whisper understands best; a too-long take means the model rambled.
            # ponytail: nonsense lines (murloc gurgles) always use all tries; add a per-card "check": false if it hurts.
            for attempt in range(a.tries):
                take = dict(style)
                if code != "en" and attempt % 2 == 0:
                    # The reference clips are English; cfg 0 keeps their accent out (Chatterbox docs), but
                    # sometimes mumbles, so every other take keeps the style's cfg.
                    take["cfg_weight"] = cfg["cross_lang_cfg_weight"]
                samples, sr = speaker.say(text, code, ref_voice(cfg["voices"], vid), take, seed + attempt)
                got = "" if a.no_check else heard(samples, sr, code)
                score = 1.0 if a.no_check else similarity(text, got)
                if len(samples) / sr > 0.95 * Speaker.max_seconds(text):  # hit the cap: rambled
                    score -= 0.5
                if best is None or score > best[0]:
                    best = (score, got, samples, sr)
                if score >= 0.85:
                    break
            score, got, samples, sr = best
            dst = clip_path(lang, cid, kind)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            encode(samples, sr, dst, fx_filter(cfg, cfg["voices"][vid], style))
            scores[f"{lang}/{cid}_{kind}"] = {"score": round(score, 2), "heard": got}
            with open(scores_path + ".tmp", "w", encoding="utf-8") as f:
                json.dump(scores, f, ensure_ascii=False, indent=0)
            os.replace(scores_path + ".tmp", scores_path)
            eta = (time.time() - t0) / i * (len(jobs) - i)
            log(f"[{i}/{len(jobs)}] {lang} {cid}_{kind} {vid}/{sname} {len(samples) / sr:.1f}s audio "
                f"in {time.time() - t:.1f}s (try {attempt + 1}, asr {score:.2f}), eta {eta / 60:.0f} min: {text}"
                + (f" | heard: {got}" if score < 0.85 and got else ""))
    write_page(lines, all_cards, cfg, overrides, scores)


if __name__ == "__main__":
    main()
