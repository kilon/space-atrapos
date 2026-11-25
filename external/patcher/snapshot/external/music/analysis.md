# The music - analysis

tools/music_gen.py: stereo 44.1 kHz, Vorbis q4, each a seamless 120 s loop.
seam = the jump across the loop point in units of a typical sample step (~1 = seamless);
corr = left/right correlation (1 = mono, lower = wider).

| track | RMS dBFS | peak | level range (1 s) | seam | corr | sub | bass | low-mid | mid | high | size |
|---|---|---|---|---|---|---|---|---|---|---|---|
| menu "Atrapos" | -17.2 | -4.6 | -20.4 .. -16.5 | 1.85 | 0.65 | 0.11 | 0.49 | 0.35 | 0.05 | 0.00 | 1468 KB |
| space "Deep Drift" | -17.2 | -4.0 | -21.0 .. -17.7 | 0.26 | 0.40 | 0.04 | 0.32 | 0.54 | 0.09 | 0.00 | 1435 KB |
| surface "Minoan Shores" | -17.2 | -3.6 | -20.4 .. -16.4 | 3.62 | 0.75 | 0.03 | 0.76 | 0.18 | 0.02 | 0.00 | 1570 KB |
