# Word Lyrics — DMS desktop widget

Apple Music-style synced lyrics for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell):
word-by-word fill, smooth staggered scrolling, blurred inactive lines, interlude dots, click-to-seek.

## Lyrics sources

`lyrics.py` tries, in order:

1. **NetEase YRC** — real word timings, no token needed
2. **Musixmatch richsync** — word timings (anonymous token; not issued from every network, or set your own in settings)
3. **LRCLIB** — line timings, words interpolated by length
4. **Musixmatch subtitles** — line timings
5. **NetEase LRC** — line timings

Results are cached in `~/.cache/dms-word-lyrics/`.

## Requirements

- DMS ≥ 1.2 (tested on 1.6.2, Hyprland)
- `python3` with `cryptography` (for NetEase)
- `busctl` (systemd) — position is polled over D-Bus because some players
  (e.g. Cassette) send broken `Seeked` signals

## Install

```bash
git clone https://github.com/yaskorinov/dms-lyrics.git ~/.config/DankMaterialShell/plugins/wordLyrics
dms ipc call plugin-scan scan
dms ipc call plugins enable wordLyrics
```

Then add **Word Lyrics** in DMS Settings → Desktop Widgets.

## Settings

Alignment, font, active line position, colors, dim/blur of inactive lines, text shadow,
edge fade, scroll curve (ease in-out / sine / quart / Apple bezier / spring), scroll duration,
line stagger, scroll lead, sync offset, hide on pause, preferred player, Musixmatch token.

## Shaders

`shaders/*.frag` are compiled to `.qsb` with:

```bash
/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o shaders/wordfill.frag.qsb shaders/wordfill.frag
/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o shaders/edgefade.frag.qsb shaders/edgefade.frag
```
