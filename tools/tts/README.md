# Minion voice lines (local TTS)

Offline, free text-to-speech for the minions' play / attack / death lines in all 8 game languages
(enUS, ruRU, deDE, frFR, esES, ptBR, itIT, plPL). Not wired into the game yet.

## The model: Chatterbox Multilingual (Resemble AI)

- 23 languages, all 8 of ours included (Polish too, which Qwen3-TTS lacks), one model for all of them.
- Zero-shot voice cloning from a ~5-10 s reference clip, so any number of voices.
- Emotion control: `exaggeration` (0.25 flat ... 1.0+ very expressive) and `cfg_weight` (pacing), set per style.
- MIT licence, so no licence trouble at all (XTTS-v2's Coqui Public Model License forbids commercial
  use; Fish Speech / OpenAudio weights are CC-BY-NC-SA; Kokoro and Piper are fast but have no Russian /
  German / Polish (Kokoro) or only fixed voices (Piper)).
- Runs on Apple Silicon (MPS or CPU) in PyTorch.

The reference clips are made by **Kokoro-82M** (Apache-2.0) from its built-in speakers: each voice in
`voices.json` names a Kokoro speaker and a short English text it reads once (into `tools/tts/refs/`,
git-ignored, recreated on demand). No clips from Hearthstone or any other game.

Licences: Chatterbox code and weights are MIT; Kokoro-82M is Apache-2.0. Chatterbox adds Resemble's
inaudible "Perth" watermark to every clip (it marks the audio as AI-made; it cannot be heard). This is a
free fan project, so commercial terms do not matter, but both licences would allow it anyway.

## Install (macOS, Apple Silicon)

```sh
brew install ffmpeg            # needs the rubberband filter (ffmpeg-full has it: brew install ffmpeg-full)
uv venv -p 3.11 tools/tts/.venv
VIRTUAL_ENV=tools/tts/.venv uv pip install chatterbox-tts kokoro soundfile mlx-whisper "setuptools<81" pip
```

`setuptools<81` is needed because the watermarker still imports `pkg_resources`; `pip` lets Kokoro
download its spaCy English model on the first run. The models (~3 GB Chatterbox, ~0.3 GB Kokoro, ~0.5 GB Whisper; the venv is ~1.5 GB) go
into the normal Hugging Face cache (`~/.cache/huggingface`), not the repo; after that it works offline.

## Run

```sh
tools/tts/.venv/bin/python tools/tts/gen_voice.py                 # data/voice_lines.json, or the sample
tools/tts/.venv/bin/python tools/tts/gen_voice.py --lines tools/tts/sample_lines.json --langs ruRU,plPL
tools/tts/.venv/bin/python tools/tts/gen_voice.py --cards VAN_EX1_313 --force   # remake one card
tools/tts/.venv/bin/python tools/tts/gen_voice.py --page-only                   # just rebuild the page
python3 tools/tts/cast.py      # self-check + who speaks with which voice (no venv needed)
```

Input is `{card_id: {"play"|"attack"|"death": {lang: text}}}`. Output goes to
`build/voice/<lang>/<card_id>_<kind>.ogg` (Vorbis, mono, 24 kHz, -16 LUFS, silence trimmed). Existing
clips are skipped, so a stopped run simply continues; `--force` remakes them. Progress (with ETA) is
printed and appended to `build/voice/gen.log`. Each clip has a fixed seed, so a remake gives the same take;
change the text or the voice to get another one.

Quality check: takes vary a lot (sometimes mumbled, accented or rambling), so each line gets up to
`--tries 3` takes, Whisper (`whisper-small`, MLX, ~0.5 GB) transcribes the raw take, and the first take
it understands (similarity >= 0.85) or else the best one is kept. Scores and what Whisper heard go to
`build/voice/scores.json` and the page's ASR column, so weak clips are easy to find and remake.
`--no-check` makes one take per line without Whisper. Nonsense lines (murloc gurgles) always score low
and use all tries; that is harmless, only slower.

Listening page: `build/voice/index.html` (card, voice, style, effects, text, player). Serve it from the repo root:
`python3 -m http.server 8790` and open http://127.0.0.1:8790/build/voice/index.html.

Speed on an M1 Pro: roughly 20-60 s per short line (the model is about 10x slower than real time here,
more when the machine is busy), so the full game (~280 minions x 3 lines x 8 languages) is a long
overnight job; run it per language with `--langs`.

## Voices, styles, effects (`voices.json`)

- `styles`: Chatterbox settings per mood (`neutral heroic cheerful gruff menacing eerie calm`), plus
  optional `tempo` (ffmpeg atempo). For non-English lines `cfg_weight` is replaced by
  `cross_lang_cfg_weight` (0), which Chatterbox recommends to keep the English reference's accent out.
- `effects`: named ffmpeg filter chains (`deep deeper high hall cave echo growl robot ghost`).
- `voices`: 8 human voices (`m_hero m_gruff m_old m_rogue`, `f_hero f_mystic f_noble f_bright`), each a
  Kokoro speaker + reference text + default style; and creature voices that reuse one of them through
  effects (`giant beast demon dragon dragon_f elemental mech spirit_m spirit_f small small_f`).

To add a voice: add an entry with `ref` (a Kokoro speaker such as `af_sky`, `bm_lewis`; the list is in
the Kokoro-82M model card) and `ref_text`, or with `base` (an existing voice) and `fx`. Any other
reference clip you are allowed to use also works: drop it in `tools/tts/refs/<voice>.wav` and give the
voice a dummy `ref`. Changing a voice does not remake old clips; use `--force`.

## Who gets which voice (`cast.py`, `cast_overrides.json`)

Rules, first match wins: mechanical -> `mech`; murlocs, imps, gnomes, goblins, kobolds, whelps -> `small`;
demons -> `demon`; dragons -> `dragon`/`dragon_f`; undead and spirits -> `spirit_*`; elementals and
totems -> `elemental`; giants, ogres, golems, ancients -> `giant`; beasts -> `beast`; pirates -> `m_gruff`;
then name hints (knight/champion -> `m_hero`, mage/priest -> `m_old`, ...), the card's class, and a stable
spread over the human voices. Female characters are found by name (`FEMALE` in cast.py). Names with
doom/dread/shadow/fel/... get the `menacing` style. Fix any card in `cast_overrides.json`:
`"VAN_EX1_116": {"voice": "m_rogue", "style": "cheerful"}`.
