# bassless

Practice tracks from your own songs with the bass taken out, plus a bass-only
track and slowed-down copies. [Demucs](https://github.com/adefossez/demucs)
does the separation; bassless is the bash script around it that I use for
practice.

I'm teaching myself bass and wanted to play along with songs with the bass
taken out. My first version separated the song with Demucs and mixed the
saved drums, vocals and other stems back together; it sounded worse than the
original and the vocals didn't sound like the record. Now it subtracts the
bass stem from the original instead. Bass that Demucs misses stays in the mix,
and anything else that ended up in the bass stem is subtracted too.

The no-bass track is essentially what `demucs --two-stems bass --other-method minus`
(Demucs 4.1) writes. What the script adds is the practice side: a bass-only
track, slowed copies with the pitch kept, Korean file names if you want them,
stems that are kept and reused, and a peak check on every file it writes.

## Use

```bash
bassless "song.flac"                    # -> ~/Music/bassless/song/
bassless "song.flac" --slow 0.8         # also 0.8x copies, pitch kept
bassless "song.flac" --stem bass,drums  # a no-bass and a no-drums track
bassless "song.flac" --ko               # 원곡, 베이스 없음, 베이스만
```

```
~/Music/bassless/song/
  original.flac
  no bass.flac      play along with this
  bass only.flac    for learning the line
  slow 0.8x/        with --slow
  .stems/           Demucs output, reused on the next run
```

Other options: `--name`, `--out`, `--shifts` (passed to Demucs, default 2),
`--device cuda|cpu|mps`, and `--fresh` to throw away an output folder and start
over. `--stem` takes `bass`, `drums`, `vocals` and `other` (the 4-stem
`htdemucs_ft` model) or `guitar` and `piano` (the 6-stem `htdemucs_6s`; Demucs'
own README says its piano stem is weak).

The stems are kept as 32-bit float WAV; with the 4-stem model `.stems` takes
about 115 MB per minute of audio. bassless remembers the SHA-256 of the file it separated, so
a different song under the same name stops with an error instead of reusing
the old stems. The first Demucs run downloads the model weights.

## Install

- bash 4 or newer and ffmpeg 6 (with ffprobe; `--slow` needs librubberband,
  which Ubuntu's package has).
- Demucs 4.1: `pip install demucs` in a virtualenv. If `demucs` isn't on your
  PATH, point to it: `DEMUCS=~/.venvs/demucs/bin/demucs bassless song.flac`.
- Copy `bassless` somewhere on your PATH.
- `tools/compare.py` needs numpy, scipy and soundfile.

Tested on Ubuntu 24.04 with ffmpeg 6.1.1, Demucs 4.1.0 and an RTX 3090.

## Re-summed stems vs. subtraction

Two songs I practise with, `htdemucs_ft` with shifts 2 and float32 stems,
measured with `tools/compare.py` (the audio isn't in this repo). Both tracks
are compared with the original before bassless turns anything down. "Difference
from original" is the energy of (original - track) in that band relative to the
original: lower is closer. A track that removed nothing would score best on
that row, which is why the bass-range row is there.

| | DAY6 - 예뻤어 | | Aimyon - 愛を伝えたいだとか | |
|---|---:|---:|---:|---:|
| | re-summed | subtracted | re-summed | subtracted |
| difference from original, 300 Hz-4 kHz | -24.0 dB | -35.2 dB | -13.6 dB | -16.7 dB |
| difference from original, 1-8 kHz | -25.0 dB | -41.6 dB | -21.6 dB | -28.8 dB |
| level change, 40-250 Hz | -2.40 dB | -2.43 dB | -3.09 dB | -2.99 dB |

Both take about the same out of the bass range. Above it, the subtracted track
stays closer to the original: by 11.2 and 16.6 dB on 예뻤어, by 3.1 and 7.2 dB
on the Aimyon song. Two songs and one model, measured, not a listening test. The
40-250 Hz row also holds kick drum and the low end of other instruments, so it
doesn't say how much bass is left.

Part of what I heard in my first version came from the files, not the method.
Demucs saves 16-bit stems by default and rescales any stem that would clip,
each by its own factor, so saved stems no longer add up. Three of the four
16-bit stems of 예뻤어 and all four of the Aimyon song peaked at exactly 0.990
(1/1.01, the mark of that rescaling). Summed back, the 16-bit stems of 예뻤어
were off from the original by -14.8 dB and came out 1.7 dB quieter in the vocal
range; separated again and kept as float, they are off by -23.8 dB. If you
re-sum stems yourself, save them as float.

Float isn't enough on its own: Demucs 4.1's float32 writer clamps to +-1
whatever `--clip-mode` says, and on the Aimyon song that cut 287 drum samples.
bassless hands Demucs the song 6 dB down instead and doubles the stems when it
uses them. Demucs normalises its input level, so this is exact in practice: on
the Aimyon song the doubled stems matched a full-level run within -75 dB
(shifts 0), and the drums came out peaking at 1.13 instead of being cut at 1.

## Clipping

Taking a loud bass out of a loud master pushes the peaks past full scale: 1.39
and 1.35 times full scale on the two songs above. My first version wrote that
straight to 16-bit FLAC and clipped about 50,000 samples of 예뻤어. Now every
file is rendered once in float, its peak measured with ffmpeg's `astats`, and
the file turned down just enough to peak at -0.1 dBFS (2.95 dB on 예뻤어).
The slowed copies need their own check: rubberband raised the peak again, and
the 0.8x no-bass copy of 예뻤어 needed 5.10 dB. On the Aimyon song even the bass
stem alone peaks at about 1.03, so the bass-only track was turned down 0.34 dB.
`volumedetect` can't be used for the measurement: it converts to 16-bit first
and reports 0 dB.

## Timing

RTX 3090, the 4:43 예뻤어:

| | time |
|---|---:|
| Demucs alone, shifts 2, float32 | 49.7 s, 49.8 s |
| first run, `--slow 0.8` | 75.3 s |
| first run, `--shifts 0` | 33.3 s |
| stems already there | 3.9 s |
| stems already there, `--slow 0.8` | 24.1 s |

The models were already downloaded. I haven't timed it on a CPU.

## Tests

```bash
tests/run.sh
```

They need ffmpeg but not Demucs: `tests/fake-demucs` stands in for it and
writes known stems. They check that a 55 Hz + 1 kHz mix comes back as the
1 kHz tone (residual around -92 dBFS) and the bass-only track at the song's
level, that a track that would overshoot is scaled down as a whole rather
than clipped, that a stem louder than full scale still subtracts out (the fake
clamps at +-1 like Demucs does), that a Demucs crash leaves no stems behind, that incomplete or mismatched stems are separated again, mono
48 kHz input in a path with spaces and Korean, several stems with `--slow` and
`--ko`, silence, and bad arguments.

## Related

[guitar-station](https://github.com/Jayyo/guitar-station) is how I hear the bass
through the computer while I play along.

## 한국어

베이스를 뺀 연습용 트랙, 베이스만 남긴 트랙, 피치를 유지한 느린 버전을 만들어
주는 스크립트입니다. 분리는 Demucs가 하고, 베이스 없는 트랙은 다른 스템을 다시
합치지 않고 원곡에서 베이스 스템을 빼서 만듭니다. 처음엔 저장된 스템을 다시
합쳤는데 보컬이 원곡과 다르게 들려서 바꿨습니다. 재 보니 그 원인 중 일부는
Demucs가 16비트로 저장하면서 스템마다 따로 줄인 레벨이었습니다. 지금은 스템을
float로 받고(Demucs의 float 저장도 ±1에서 잘라서, 원곡을 6dB 낮춰 넣고 두 배로
씁니다), 위 표처럼 제가 연습하는 두 곡에서 빼는 쪽이 고음역에서 원곡에 더
가까웠습니다. 저음역(40-250 Hz)에서 줄어드는 양은 두 방식이 거의 같습니다.
`--ko`를 주면 파일 이름이 원곡, 베이스 없음, 베이스만, 느리게 0.8x로 나옵니다.

## License

MIT
