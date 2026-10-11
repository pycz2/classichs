#!/usr/bin/env python3
"""Generates card voice lines with Chatterbox Multilingual (local, offline after the first download).

Input: {card_id: {kind: {lang: text}}} (kind = play/attack/death for minions, emote keys for heroes; other
non-dict keys such as "source" are ignored), lang = en ru de fr es pt_BR it pl (or enUS, ruRU, ...).
Output: <out>/<lang>/<card_id>_<kind>.ogg (mono 24 kHz Vorbis ~32 kbps, -16 LUFS), the raw take in
<out>/raw/ (so effects can be redone with --refx), Whisper scores in <out>/scores.json and the listening
page <out>/index.html. Order: heroes in every language, then English, then ru de fr es pt it pl one
language at a time. Existing clips are skipped, so a killed run just restarts.

Usage: tools/tts/.venv/bin/python tools/tts/gen_voice.py [--lines F] [--out DIR] [--langs en,ru]
       [--cards ID,ID] [--force] [--refx] [--page-only] [--tries 2] [--no-check] [--device mps|cpu]
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
OUT = os.path.join(ROOT, "build", "voice")  # --out replaces it
REFS = os.path.join(HERE, "refs")
LANG_ORDER = ["en", "ru", "de", "fr", "es", "pt", "it", "pl"]
HS_LANG = {"en": "enUS", "ru": "ruRU", "de": "deDE", "fr": "frFR", "es": "esES", "pt": "ptBR", "it": "itIT",
           "pl": "plPL"}
ACCEPT = 0.75  # Whisper similarity that accepts a take
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
    def __init__(self, device, refs):
        os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        import torch
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        if device == "mps" and not torch.backends.mps.is_available():
            device = "cpu"
        self.torch = torch
        m = self.model = ChatterboxMultilingualTTS.from_pretrained(device=device)
        self.conds = {}
        for ref in sorted(refs):  # all up front: a long run then needs no files from disk
            m.prepare_conditionals(os.path.join(REFS, ref + ".wav"))
            self.conds[ref] = m.conds
        # generate() always allows 1000 speech tokens (40 s); a rambling take then costs minutes. Cap it.
        self.max_tokens = 1000
        t3_inference = m.t3.inference
        m.t3.inference = lambda **kw: t3_inference(**{**kw, "max_new_tokens": self.max_tokens})
        log(f"chatterbox multilingual loaded on {device}")

    @staticmethod
    def max_seconds(text):
        return 2.5 + len(text) / 6

    def say(self, text, lang, ref, style, seed):
        """-> (samples, sample_rate)"""
        m = self.model
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
        chain += ["apad=pad_dur=0.3"] + [cfg["effects"][n] for n in voice["fx"]] + ["areverse", trim, "areverse"]
    chain.append("loudnorm=I=-16:TP=-1.5:LRA=11")
    return ",".join(chain)


def encode(src, dst, filt):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-af", filt, "-ar", "24000", "-ac", "1",
                    "-c:a", "libvorbis", "-b:a", "32k", "-f", "ogg", dst + ".tmp"], check=True)
    os.replace(dst + ".tmp", dst)


def clip_path(lang, cid, kind, raw=False):
    if raw:
        return os.path.join(OUT, "raw", lang, f"{cid}_{kind}.flac")
    return os.path.join(OUT, lang, f"{cid}_{kind}.ogg")


def jobs_of(lines, langs, cards):
    for cid in sorted(lines):
        if cards and cid not in cards:
            continue
        for kind, texts in sorted(lines[cid].items()):
            if not isinstance(texts, dict):
                continue
            for lang, text in sorted(texts.items()):
                if text and (not langs or lang in langs):
                    yield cid, kind, lang, text


def phase(card, lang):
    """0 = heroes (all languages), 1 = English, 2.. = the other languages one at a time."""
    if card["type"] == "HERO":
        return 0
    code = lang[:2].lower()
    return 1 + (LANG_ORDER.index(code) if code in LANG_ORDER else len(LANG_ORDER))


def write_page(lines, all_cards, cfg, overrides, scores):
    rows, e = [], html.escape
    for cid, kind, lang, text in jobs_of(lines, None, None):
        if not os.path.exists(clip_path(lang, cid, kind)) or cid not in all_cards:
            continue
        card = all_cards[cid]
        vid, sname = cast(card, cfg["voices"], overrides)
        sc = scores.get(f"{lang}/{cid}_{kind}") or {}
        if sc.get("score") is None:
            asr = "-"
        else:
            asr = f"{sc['score']:.2f}" + (f"<br><small>{e(sc['heard'])}</small>" if sc["score"] < ACCEPT else "")
        name = card["name"].get(HS_LANG.get(lang[:2].lower(), lang), card["name"]["enUS"])
        rows.append(f"<tr data-lang='{e(lang)}'><td><img loading='lazy' src='../../art/cards/{e(cid)}.jpg' alt=''></td>"
                    f"<td><b>{e(name)}</b><br><small>{e(cid)}</small></td>"
                    f"<td>{e(kind)}</td><td>{e(vid)}</td><td>{e(sname)}</td>"
                    f"<td>{e(', '.join(cfg['voices'][vid]['fx']) or '-')}</td><td>{e(lang)}</td><td>{e(text)}</td>"
                    f"<td>{asr}</td><td><audio controls preload='none' src='{e(lang)}/{e(cid)}_{e(kind)}.ogg'>"
                    f"</audio></td></tr>")
    langs = sorted({r.split("'")[1] for r in rows})
    options = "".join(f"<option>{e(x)}</option>" for x in langs)
    page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Voice lines</title>
<style>body{{font:14px system-ui;margin:16px;background:#fff;color:#222}}table{{border-collapse:collapse}}
td,th{{border-bottom:1px solid #ddd;padding:4px 8px;text-align:left;vertical-align:middle}}img{{height:64px}}
@media (prefers-color-scheme:dark){{body{{background:#1b1b1b;color:#ddd}}td,th{{border-color:#444}}}}</style>
<h1>Voice lines ({len(rows)} clips)</h1>
<p>Language <select id="lang"><option value="">all</option>{options}</select>
Search <input id="q" placeholder="card, voice, text"></p>
<div style="overflow-x:auto"><table><tr><th></th><th>Card</th><th>Kind</th><th>Voice</th><th>Style</th>
<th>Effects</th><th>Lang</th><th>Text</th><th title="how well Whisper understood the raw take (1 = word for word; - = not checked)">ASR</th><th>Listen</th></tr>
{chr(10).join(rows)}
</table></div>
<script>
const lang = document.getElementById("lang"), q = document.getElementById("q");
function filter() {{
  const s = q.value.toLowerCase();
  for (const tr of document.querySelectorAll("tr[data-lang]"))
    tr.hidden = (lang.value && tr.dataset.lang !== lang.value) || (s && !tr.textContent.toLowerCase().includes(s));
}}
lang.onchange = filter; q.oninput = filter;
</script>"""
    with open(os.path.join(OUT, "index.html.tmp"), "w", encoding="utf-8") as f:
        f.write(page)
    os.replace(os.path.join(OUT, "index.html.tmp"), os.path.join(OUT, "index.html"))
    log(f"page: {os.path.join(OUT, 'index.html')} ({len(rows)} clips)")


def main():
    global OUT
    ap = argparse.ArgumentParser()
    default_lines = os.path.join(ROOT, "data", "voice_lines.json")
    if not os.path.exists(default_lines):
        default_lines = os.path.join(HERE, "sample_lines.json")
    ap.add_argument("--lines", default=default_lines)
    ap.add_argument("--out", default=OUT, help="output folder (default build/voice of this checkout)")
    ap.add_argument("--langs", default="", help="comma list as written in the lines file, e.g. en,ru")
    ap.add_argument("--cards", default="", help="comma list of card ids (default: all in the file)")
    ap.add_argument("--force", action="store_true", help="regenerate existing clips")
    ap.add_argument("--refx", action="store_true", help="only redo effects/encoding from the saved raw takes")
    ap.add_argument("--page-only", action="store_true")
    ap.add_argument("--device", default="mps")
    ap.add_argument("--tries", type=int, default=2, help="takes per line; the best by Whisper is kept")
    ap.add_argument("--no-check", action="store_true", help="skip the Whisper check (one take per line)")
    a = ap.parse_args()
    OUT = os.path.abspath(a.out)

    cfg = json.load(open(os.path.join(HERE, "voices.json"), encoding="utf-8"))
    lines = json.load(open(a.lines, encoding="utf-8"))
    all_cards, overrides = load_cards(), load_overrides()
    langs = set(filter(None, a.langs.split(",")))
    pick = set(filter(None, a.cards.split(",")))
    scores_path = os.path.join(OUT, "scores.json")
    scores = json.load(open(scores_path, encoding="utf-8")) if os.path.exists(scores_path) else {}
    every = list(jobs_of(lines, langs, pick))
    unknown = sorted({j[0] for j in every if j[0] not in all_cards})
    if unknown:
        log(f"skipping unknown card ids: {', '.join(unknown)}")
    every = [j for j in every if j[0] in all_cards]

    if a.refx:
        done = 0
        for cid, kind, lang, text in every:
            if os.path.exists(clip_path(lang, cid, kind, raw=True)):
                vid, sname = cast(all_cards[cid], cfg["voices"], overrides)
                encode(clip_path(lang, cid, kind, raw=True), clip_path(lang, cid, kind),
                       fx_filter(cfg, cfg["voices"][vid], cfg["styles"][sname]))
                done += 1
        log(f"effects redone for {done} clips")
    jobs = [j for j in every if a.force or not os.path.exists(clip_path(j[2], j[0], j[1]))]
    if not a.page_only and not a.refx and jobs:
        jobs.sort(key=lambda j: (phase(all_cards[j[0]], j[2]), j[0], j[1]))
        counts = {}
        for j in jobs:
            p = phase(all_cards[j[0]], j[2])
            counts[p] = counts.get(p, 0) + 1
        log(f"{a.lines}: {len(jobs)} clips to make; per phase (0 heroes, 1 en, 2.. {' '.join(LANG_ORDER[1:])}): "
            f"{counts}")
        casting = {cid: cast(all_cards[cid], cfg["voices"], overrides) for cid in {j[0] for j in jobs}}
        refs = {ref_voice(cfg["voices"], v) for v, _ in casting.values()}
        make_refs(cfg["voices"], refs)
        speaker = Speaker(a.device, refs)
        import soundfile as sf
        t0 = time.time()
        for i, (cid, kind, lang, text) in enumerate(jobs, 1):
            vid, sname = casting[cid]
            style = cfg["styles"][sname]
            code = lang[:2].lower()
            t = time.time()
            seed = zlib.crc32(f"{cid}/{kind}/{lang}".encode())
            checked = not a.no_check and len(text.split()) > 3  # Whisper is unreliable on a word or two
            best = None
            for attempt in range(a.tries):
                take = dict(style)
                if code != "en" and attempt % 2 == 0:
                    # The reference clips are English; cfg 0 keeps their accent out (Chatterbox docs), but
                    # sometimes mumbles, so every other take keeps the style's cfg.
                    take["cfg_weight"] = cfg["cross_lang_cfg_weight"]
                samples, sr = speaker.say(text, code, ref_voice(cfg["voices"], vid), take, seed + attempt)
                got = heard(samples, sr, code) if checked else ""
                score = similarity(text, got) if checked else None
                rambled = len(samples) / sr > 0.95 * Speaker.max_seconds(text)  # hit the token cap
                rank = (1.0 if score is None else score) - (0.5 if rambled else 0)
                if best is None or rank > best[0]:
                    best = (rank, score, got, samples, sr)
                if not rambled and (score is None or score >= ACCEPT):
                    break
            _, score, got, samples, sr = best
            raw, dst = clip_path(lang, cid, kind, raw=True), clip_path(lang, cid, kind)
            os.makedirs(os.path.dirname(raw), exist_ok=True)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            sf.write(raw + ".tmp.flac", samples, sr)
            os.replace(raw + ".tmp.flac", raw)
            encode(raw, dst, fx_filter(cfg, cfg["voices"][vid], style))
            scores[f"{lang}/{cid}_{kind}"] = {"score": None if score is None else round(score, 2), "heard": got}
            with open(scores_path + ".tmp", "w", encoding="utf-8") as f:
                json.dump(scores, f, ensure_ascii=False, indent=0)
            os.replace(scores_path + ".tmp", scores_path)
            eta = (time.time() - t0) / i * (len(jobs) - i)
            asr = "-" if score is None else f"{score:.2f}"
            log(f"[{i}/{len(jobs)}] {lang} {cid}_{kind} {vid}/{sname} {len(samples) / sr:.1f}s audio "
                f"in {time.time() - t:.1f}s (try {attempt + 1}, asr {asr}), eta {eta / 3600:.1f} h: {text}"
                + (f" | heard: {got}" if score is not None and score < ACCEPT else ""))
            if i % 25 == 0:
                write_page(lines, all_cards, cfg, overrides, scores)
    write_page(lines, all_cards, cfg, overrides, scores)


if __name__ == "__main__":
    main()
