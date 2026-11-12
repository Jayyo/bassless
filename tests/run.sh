#!/usr/bin/env bash
# Checks the subtraction and the clipping guard on synthetic audio.
# Needs only ffmpeg: stems are written in advance, so Demucs never runs.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export DEMUCS=false   # fail loudly if the script ever tries to separate

synth() {  # synth <out.wav> <expression>, 3 s stereo float at 44.1 kHz
  ffmpeg -loglevel error -y -f lavfi -i "aevalsrc=exprs='$2|$2':s=44100:d=3" -c:a pcm_f32le "$1"
}
level() {  # level <file> <astats key>: overall value in dB
  ffmpeg -hide_banner -nostats -i "$1" -af "astats=measure_perchannel=none:measure_overall=$2" -f null - 2>&1 \
    | sed -n "s/.*$(echo "$2" | tr _ ' ') dB: \(-\{0,1\}[0-9.inf]*\).*/\1/p" | tail -1
}
prepare() {  # prepare <name> <mix expression> <bass expression>
  local dir="$TMP/out/$1"
  mkdir -p "$dir/.stems/htdemucs_ft"
  synth "$TMP/$1-mix.wav" "$2"
  ffmpeg -loglevel error -y -i "$TMP/$1-mix.wav" -c:a pcm_s16le "$dir/.stems/reference.wav"
  synth "$dir/.stems/htdemucs_ft/bass.wav" "$3"
}
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. The no-bass track is the mix minus the stem: 55 Hz + 1 kHz, minus the 55 Hz part.
prepare exact '0.3*sin(2*PI*55*t)+0.3*sin(2*PI*1000*t)' '0.3*sin(2*PI*55*t)'
./bassless "$TMP/exact-mix.wav" --name exact --out "$TMP/out" >/dev/null
synth "$TMP/expected.wav" '-0.3*sin(2*PI*1000*t)'
ffmpeg -loglevel error -y -i "$TMP/out/exact/no bass.flac" -i "$TMP/expected.wav" \
  -filter_complex "amerge=inputs=2,pan=stereo|c0=c0+c2|c1=c1+c3" -c:a pcm_f32le "$TMP/residual.wav"
res=$(level "$TMP/residual.wav" RMS_level)
awk -v r="$res" 'BEGIN { exit !(r < -70) }' || fail "residual $res dB, expected below -70 dB"
echo "ok  subtraction leaves the 1 kHz tone (residual $res dB)"

# 2. If the subtracted track would peak above full scale, it is turned down instead of clipped.
#    Mix 0.78 = rest 1.30 + "bass" -0.52, so mix minus bass peaks at 1.30 (+2.3 dB).
prepare loud '0.78*sin(2*PI*220*t)' '-0.52*sin(2*PI*220*t)'
log=$(./bassless "$TMP/loud-mix.wav" --name loud --out "$TMP/out")
grep -q "turning it down" <<<"$log" || fail "expected the level to be lowered"
peak=$(level "$TMP/out/loud/no bass.flac" Peak_level)
awk -v p="$peak" 'BEGIN { exit !(p < -0.05 && p > -0.3) }' || fail "peak $peak dB, expected about -0.1 dB"
echo "ok  overshooting track is turned down (peak $peak dB)"

# 3. Korean names and the bass-only track.
./bassless "$TMP/exact-mix.wav" --name exact --out "$TMP/out" --ko >/dev/null
[[ -f "$TMP/out/exact/베이스 없음.flac" && -f "$TMP/out/exact/베이스만.flac" ]] || fail "--ko file names"
echo "ok  --ko writes Korean file names"
