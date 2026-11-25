#!/usr/bin/env python3
"""Spoken dialogue: every story line recorded with Piper (neural text to
speech, offline), one voice per character.

    ~/.local/share/space-atrapos-tts/venv/bin/python tools/voice_lines.py [--force] [--only <speaker>]

Setup (once; outside the project, not in builds):
    uv venv -p 3.12 ~/.local/share/space-atrapos-tts/venv
    uv pip install -p ~/.local/share/space-atrapos-tts/venv/bin/python piper-tts==1.8.0 onnxruntime==1.31.0
    the voice models (VOICES below) in ~/.local/share/space-atrapos-tts/models/
      from https://huggingface.co/rhasspy/piper-voices (each with its MODEL_CARD)

The lines: the main quest's dialogue (data/main_quest.json - every stage's
lines, Kilon Alios's offer / replies, his "where it leads now" for every
objective) plus EXTRA. Each becomes voices/lines/<key>.ogg, key = the first
16 hex digits of sha1("<speaker>|<text without BBCode, trimmed>") - the game
(scripts/core/voice.gd) works the same key out from the line it shows, so a line
plays only its own recording. Edit a line and it falls silent until this is
run again (lines already recorded are skipped; recordings no line uses any
more are deleted). Each voice is recorded, then given its colour with ffmpeg
(pitch, a metallic edge, a radio band) and levelled to -14.5 LUFS (was -18: 50 % louder, peaks held under -1 dBFS).

Writes external/voices/lines.md (every line, its voice, length) and
external/voices/CREDITS.md (the voices' licences).
"""
import argparse, hashlib, json, os, re, subprocess, sys, tempfile, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "voices", "lines")
REPORT = os.path.join(ROOT, "external", "voices")
MODELS = os.path.expanduser("~/.local/share/space-atrapos-tts/models")

# Voices: the model, how fast (length scale: >1 slower), and the colour
# (an ffmpeg filter chain; "" = as recorded). Licences: commercial use allowed.
PITCH = "asetrate=22050*{k},aresample=22050,atempo={t}"
VOICES = {
    "kilon":    {"model": "en_US-norman-medium", "length": 1.08,
                 "fx": PITCH.format(k=0.86, t=round(1 / 0.86, 4)) + ",aecho=0.8:0.5:7|13:0.22|0.12,highpass=f=70"},
    "ariadne":  {"model": "en_GB-cori-high", "length": 1.0, "fx": ""},
    "daidalos": {"model": "en_GB-northern_english_male-medium", "length": 1.05, "fx": ""},
    "asterion": {"model": "en_US-joe-medium", "length": 1.08,
                 "fx": PITCH.format(k=0.8, t=1.25) + ",aecho=0.7:0.4:35:0.18,lowpass=f=6500"},
    "narrator": {"model": "en_GB-alba-medium", "length": 1.08, "fx": ""},
    "radio":    {"model": "en_US-norman-medium", "length": 0.98,
                 "fx": "highpass=f=380,lowpass=f=3200,acompressor=threshold=0.1:ratio=6:attack=5:release=60,volume=1.6"},
}
SPEAKERS = {"Kilon Alios": "kilon", "Dr. Ariadne Kephala": "ariadne", "Nikos Daidalos": "daidalos",
            "Asterion": "asterion", "Narrator": "narrator", "Kephala Outpost": "radio"}
# The empires' stories (data/scenarios.json, tools/empire_quests.py): who speaks with which voice.
SPEAKERS.update({
    # women
    "Diotima": "ariadne", "Ephor Chilonis": "ariadne", "Theano of Samos": "ariadne", "Priestess of Artemis": "ariadne",
    "Quarry-mother of Melos": "ariadne", "Maenad of Naxos": "ariadne", "Hierophant Anthousa": "ariadne", "Hera's Voice": "ariadne",
    # men
    "Archon Kallias": "daidalos", "Priest of Poseidon": "daidalos", "Navarch Themistios": "daidalos", "Priest of Apollo": "daidalos",
    "Polemarch Dienekes": "daidalos", "Wanax Agapenor": "daidalos", "Kalchas": "daidalos", "Hekataios the Chronicler": "daidalos",
    "Speaker of the Panionion": "daidalos", "Melesigenes the Singer": "daidalos", "Elder of Siphnos": "daidalos",
    "Arkesilas the Sculptor": "daidalos",
    # the old powers, and the raiders over the radio
    "Brontes": "asterion", "The Bronze Owl": "kilon",
    "Raider chief": "radio", "Leotychidas": "radio", "Herostratos": "radio",
})
# Lines spoken outside the quest file (speaker, text).
EXTRA = [("Kilon Alios", "The thread is in your hands.")]   # the Voices volume slider's sample
# How some names are said (the text shown is unchanged).
SAY = {"Kephala": "Kefala", "Daidalos": "Dye-dah-los", "Phaistos": "Fysstos", "Knossos": "Nossos",
       "Ka-no-so": "Kah, no, so", "labrys": "lab-ris", "Keftiu": "Keftyoo", "Thera": "Theera",
       "Asterion": "Asteerion", "Kilon Alios": "Keelon Aleeos", "Moirai": "Moyray",
       "Chilonis": "Keelonis", "Dienekes": "Dee-en-eh-kees", "Leotychidas": "Leo-tee-kee-das", "Agapenor": "Aga-pay-nor",
       "Kalchas": "Kal-kas", "Hekataios": "Heka-tay-os", "Theano": "Thay-ah-no", "Herostratos": "Hero-strah-tos",
       "Melesigenes": "Meleh-see-geh-nees", "Anthousa": "An-thoo-sa", "Diotima": "Dee-o-tee-ma", "Amyklai": "Ah-mee-klye",
       "Tainaron": "Tie-nah-ron", "Lakedaimon": "Lakeh-dye-mon", "Mykenai": "Mee-keh-nay", "wanax": "wah-nax",
       "Polydeukes": "Polly-dew-kees", "Panionion": "Pan-ee-o-nee-on", "Siphnos": "Seef-nos", "Siphnians": "Seef-nee-ans",
       "Leto": "Lee-toh", "Keros": "Keh-ros", "Ephesos": "Effesoss", "Lerna": "Lair-na", "Kallias": "Kah-lee-as",
       "Themistios": "The-mis-tee-os", "Brontes": "Bron-tees", "Atreus": "Ate-ree-us", "Laurion": "Lav-ree-on",
       # (checked with Piper's own phonemizer: espeak said these wrong)
       "Thales": "Thaylees", "Cyclopes": "Sigh-klo-peez", "Piraeus": "Pie-ree-us", "Cetus": "Seetus", "Ugarit": "Ooga-rit",
       "Kleisthenes": "Klicethineez", "Perikles": "Perry-kleez", "Sophokles": "Soff-oh-kleez", "Cyclades": "Sick-la-deez"}

BB = re.compile(r"\[[^\]]*\]")


def plain(text):
    return BB.sub("", text).strip()


def key(speaker, text):
    return hashlib.sha1(("%s|%s" % (speaker, plain(text))).encode("utf-8")).hexdigest()[:16]


def voice_for(speaker):
    if speaker in SPEAKERS:
        return SPEAKERS[speaker]
    for w in ["Station", "Outpost", "Dock", "Relay"]:
        if w in speaker:
            return "radio"
    return None


def spoken(text):
    t = plain(text)
    for a, b in SAY.items():
        t = t.replace(a, b)
    return t.replace(" - ", ", ")


def lines():
    d = json.load(open(os.path.join(ROOT, "data", "main_quest.json")))
    out = []
    for st in d["stages"]:
        out += [tuple(l) for l in st.get("dialogue", [])]
    g = d.get("giver", {})
    for k in ["offer", "accepted", "declined", "later", "done", "greeting", "farewell"]:
        out += [tuple(l) for l in g.get(k, [])]
    for t in g.get("topics", []) + g.get("hellas", []):   # (his conversation's answers)
        out += [tuple(l) for l in t.get("lines", [])]
    for emp in g.get("empires", {}).values():   # (what he tells on each people's worlds)
        out += [tuple(l) for l in emp.get("greeting", [])]
        for t in emp.get("topics", []):
            out += [tuple(l) for l in t.get("lines", [])]
    name = g.get("name", "Kilon Alios")
    for st in d["stages"]:   # his "where it leads now" (planet_surface.gd talk_to_quest_giver)
        out.append((name, "Where it leads now: [b]%s[/b]." % st["objective"]))
    # The empires' stories, and any other scenario's dialogue with a voice.
    sc = json.load(open(os.path.join(ROOT, "data", "scenarios.json")))
    for scen in sc.get("scenarios", []):
        if not scen.get("enabled", True):
            continue
        for r in scen.get("rules", []):
            for a in r.get("then", []):
                if a.get("action") == "dialogue":
                    out += [tuple(l) for l in a.get("args", {}).get("lines", []) if isinstance(l, list) and len(l) == 2]
    out += EXTRA
    seen, uniq = set(), []
    for sp, tx in out:
        if (sp, tx) not in seen and voice_for(sp):
            seen.add((sp, tx))
            uniq.append((sp, tx))
    return uniq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--redo", default="", help="comma-separated words: re-record lines containing them (a pronunciation fixed)")
    a = ap.parse_args()
    # What each recording says (its spoken form, after SAY): a line is recorded
    # again when that changes - a pronunciation fixed - though its text didn't.
    man_path = os.path.join(REPORT, "spoken.json")   # (beside lines.md: not in the game)
    manifest = json.load(open(man_path)) if os.path.exists(man_path) else {}
    redo = [w for w in a.redo.split(",") if w]
    from piper import PiperVoice, SynthesisConfig
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REPORT, exist_ok=True)
    todo = lines()
    loaded = {}
    rows = []
    keep = set()
    for sp, tx in todo:
        vid = voice_for(sp)
        k = key(sp, tx)
        keep.add(k)
        path = os.path.join(OUT, k + ".ogg")
        said = spoken(tx)
        if k not in manifest and os.path.exists(path) and not any(w in tx for w in redo):
            manifest[k] = said   # (made before the manifest: taken as it is)
        stale = manifest.get(k) != said
        if (a.force or stale or not os.path.exists(path)) and (not a.only or a.only == sp):
            v = VOICES[vid]
            if v["model"] not in loaded:
                loaded[v["model"]] = PiperVoice.load(os.path.join(MODELS, v["model"] + ".onnx"))
            with tempfile.TemporaryDirectory() as tmp:
                raw = os.path.join(tmp, "raw.wav")
                with wave.open(raw, "wb") as w:
                    loaded[v["model"]].synthesize_wav(spoken(tx), w, syn_config=SynthesisConfig(length_scale=v["length"]))
                chain = (v["fx"] + "," if v["fx"] else "") + "loudnorm=I=-14.5:LRA=7:TP=-1,aresample=22050"
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-af", chain, "-ac", "1",
                                "-c:a", "libvorbis", "-q:a", "4", path], check=True)
            manifest[k] = said
            print("recorded", vid, k, plain(tx)[:60])
        dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                                   capture_output=True, text=True).stdout or 0)
        rows.append("| %s | %s | %.1f s | %s |" % (vid, k, dur, plain(tx).replace("|", "/")))
    with open(man_path, "w") as f:
        json.dump({k: v for k, v in manifest.items() if k in keep}, f, indent=0, ensure_ascii=False)
    removed = 0
    for f in os.listdir(OUT):
        if f.endswith(".ogg") and f[:-4] not in keep:
            os.remove(os.path.join(OUT, f))
            imp = os.path.join(OUT, f + ".import")
            if os.path.exists(imp):
                os.remove(imp)
            removed += 1
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    with open(os.path.join(REPORT, "lines.md"), "w") as f:
        f.write("# Spoken lines\n\nMade by tools/voice_lines.py (Piper). %d lines, %.1f MB.\n\n| voice | file | length | line |\n|---|---|---|---|\n"
                % (len(rows), size / 1e6) + "\n".join(rows) + "\n")
    with open(os.path.join(REPORT, "CREDITS.md"), "w") as f:
        f.write("# Voice credits\n\nSpoken dialogue made with Piper (https://github.com/OHF-Voice/piper1-gpl) and these voices "
                "(https://huggingface.co/rhasspy/piper-voices):\n\n")
        for vid, v in VOICES.items():
            card = os.path.join(MODELS, v["model"] + ".MODEL_CARD")
            lic = ""
            if os.path.exists(card):
                m = re.search(r"License:\s*(.*)", open(card).read())
                lic = m.group(1).strip() if m else ""
            f.write("- %s: %s - %s\n" % (vid, v["model"], lic))
    print("%d lines, %.1f MB, %d old recordings removed" % (len(rows), size / 1e6, removed))


if __name__ == "__main__":
    main()
