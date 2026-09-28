# Corpus

Real call recordings used to measure ASR, diarization and analysis quality (Phase 1).
**Nothing in this folder except this README is committed** (see `.gitignore`); recordings contain
private conversations and must not leave the machine. Get the participants' consent before using a call here.

## Layout

```
Corpus/
  clip01-ru/
    app.caf                # stream of the other participants (from the spike recorder)
    mic.caf                # the author's microphone
    session.json           # written by the recorder
    ref.txt                # hand-corrected transcript of the labelled excerpt (2–3 minutes)
    ref.speakers.csv       # start,end,speaker   (seconds, one row per turn of the app stream)
  clip02-en/ …
  synthetic/               # text-to-speech smoke tests, not representative of real calls
```

Target set: 5 clips — 2 Russian, 2 English, 1 mixed; at least one recorded badly (headset, noise, no headphones).

## Scoring

```bash
Tools/eval/.venv/bin/python Tools/eval/wer.py clip01-ru/ref.txt clip01-ru/hyp.txt          # WER, percent
Tools/eval/.venv/bin/python Tools/eval/der.py clip01-ru/ref.speakers.csv clip01-ru/hyp.csv # attribution accuracy 0..1
```

`spike diarize <audio> <out.csv>` writes the hypothesis CSV in the same format.
Spell numbers the way the recogniser writes them (`10`, not `десять`) in `ref.txt`, or normalise both sides:
the scorer does not convert digits to words.
