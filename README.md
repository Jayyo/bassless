# bassless

Practice tracks from your own songs with the bass taken out, plus a bass-only
track and slowed-down copies. [Demucs](https://github.com/adefossez/demucs)
does the separation; bassless is the bash script around it that I use for
practice.

I'm teaching myself bass and wanted to play along with songs with the bass
taken out. My first version separated the song with Demucs and mixed the
drums, vocals and other stems back together; it sounded worse than the
original and the vocals didn't sound like the record. Now it subtracts the
estimated bass stem from the original instead. Bass that Demucs misses stays
in the mix, and anything else that ended up in the bass stem is subtracted too.

Demucs 4.1 can do the same subtraction itself with
`demucs --two-stems bass --other-method minus`; its default (`add`) is the
re-summing I started with. The numbers below are why I switched.

## Use

```bash
bassless "song.flac"                    # -> ~/Music/bassless/song/
bassless "song.flac" --slow 0.8         # also 0.8x copies, pitch kept
bassless "song.flac" --stem bass,drums  # mute more than one instrument
bassless "song.flac" --ko               # Korean file names (원곡, 베이스 없음, 베이스만)
```

```
~/Music/bassless/song/
  original.flac
  no bass.flac      play along with this
  bass only.flac    for learning the line
  slow 0.8x/        with --slow
  .stems/           Demucs output, reused on the next run
```

Other options: `--name`, `--out`, `--shifts` (Demucs' shift trick, default 2),
`--device cuda|cpu`. `--stem` takes `bass`, `drums`, `vocals` and `other`
(the 4-stem `htdemucs_ft` model) or `guitar` and `piano` (the 6-stem
`htdemucs_6s`, which separates those two less cleanly).

## Install

- ffmpeg. `--slow` needs it built with librubberband, which Ubuntu's package is.
- Demucs: `pip install demucs` in a virtualenv. If `demucs` isn't on your
  PATH, point to it: `DEMUCS=~/.venvs/demucs/bin/demucs bassless song.flac`.
- Copy `bassless` somewhere on your PATH.

Tested on Ubuntu 24.04 with ffmpeg 6.1.1, Demucs 4.1.0 and an RTX 3090.

## Re-summed stems vs. subtraction

Measured on two songs I practise with, using `tools/compare.py` (the audio
isn't in this repo). "Difference from original" is the energy of
(original - track) relative to the original in that band: lower means the
track is closer to the original there. Vocals and cymbals should stay as they
are, so the 300 Hz-4 kHz and 1-8 kHz rows are the ones that tell the two
methods apart.

| | DAY6 - 예뻤어 | | Aimyon - 愛を伝えたいだとか | |
|---|---:|---:|---:|---:|
| | re-summed | subtracted | re-summed | subtracted |
| difference from original, 300 Hz-4 kHz | -14.5 dB | **-35.4 dB** | -13.0 dB | **-17.1 dB** |
| difference from original, 1-8 kHz | -14.2 dB | **-41.5 dB** | -19.8 dB | **-29.4 dB** |
| level change, 40-250 Hz (bass range) | **-4.35 dB** | -2.43 dB | **-4.14 dB** | -2.97 dB |

- The four stems don't add back up to the original: summed, they are off by
  -14.8 dB and -17.5 dB. Re-summing carries that error into the parts you
  wanted to keep.
- Subtracting keeps the top end much closer to the original, but it takes
  less out of the bass range. Part of that range is kick drum and the low end
  of other instruments, so this measurement can't say how much of the
  difference is bass left behind.
- Two songs, one model (`htdemucs_ft`, shifts 2). This is not a listening test
  and says nothing about other genres.

## Clipping

Taking a loud bass out of a loud master can push the peaks past full scale:
1.39 and 1.35 times full scale on the two songs above. Written straight to
16-bit FLAC, about 50,000 samples of 예뻤어 were clipped. bassless measures the
peak in float with ffmpeg's `astats` first and turns the track down just
enough (2.9 dB on 예뻤어). `volumedetect` can't be used for this: it converts
to 16-bit before it measures and reports 0 dB.

## Timing

RTX 3090, the 4:43 예뻤어, wall time of the `demucs` command including loading
the four models of `htdemucs_ft`:

| | time |
|---|---:|
| `--shifts 2` (default) | 51.2 s, 51.8 s |
| `--shifts 0` | 28.5 s |
| whole `bassless --slow 0.8` run | 70 s |

I haven't timed it on a CPU.

## Tests

```bash
tests/run.sh
```

The tests write the stems in advance, so they need ffmpeg but not Demucs. They
check that the no-bass track is the original minus the stem (a 55 Hz + 1 kHz
mix comes back as the 1 kHz tone, with the residual around -98 dBFS), that a track that would
overshoot is turned down to about -0.1 dBFS, and the `--ko` file names.

## Related

[guitar-station](https://github.com/Jayyo/guitar-station) is how I hear the bass
through the computer while I play along.

## 한국어

베이스를 뺀 연습용 트랙, 베이스만 남긴 트랙, 피치를 유지한 느린 버전을 만들어
주는 스크립트입니다. 분리는 Demucs가 하고, 베이스 없는 트랙은 다른 스템을 다시
합치지 않고 원곡에서 베이스 스템을 빼서 만듭니다. 처음엔 다시 합치는 방식이었는데
보컬이 원곡과 다르게 들려서 바꿨습니다. 위 표처럼 제가 연습하는 두 곡에서 보컬
대역이 원곡에 훨씬 가까워졌고, 대신 베이스가 조금 더 남습니다. `--ko`를 주면 파일
이름이 원곡, 베이스 없음, 베이스만, 느리게 0.8x로 나옵니다.

## License

MIT
