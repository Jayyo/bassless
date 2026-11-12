#!/usr/bin/env bash
# Tests on synthetic audio. Needs ffmpeg (with librubberband for the --slow test);
# Demucs is replaced by tests/fake-demucs.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export DEMUCS="$PWD/tests/fake-demucs" FAKE_DEMUCS_LOG="$TMP/demucs-calls"
OUT="$TMP/out"
: > "$FAKE_DEMUCS_LOG"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
synth() {  # synth <out.wav> <expression> [seconds] [rate] [channels]
  local layout=stereo; [[ "${5:-2}" == 1 ]] && layout=mono
  local exprs="$2|$2"; [[ $layout == mono ]] && exprs="$2"
  ffmpeg -loglevel error -y -f lavfi -i "aevalsrc=exprs='$exprs':s=${4:-44100}:d=${3:-3}:c=$layout" -c:a pcm_f32le "$1"
}
astat() {  # astat <file> <Peak_level|RMS_level>: overall value in dB
  ffmpeg -hide_banner -nostats -i "$1" -af "astats=measure_perchannel=none:measure_overall=$2" -f null - 2>&1 \
    | sed -n "s/.*$(tr _ ' ' <<< "$2") dB: \([^ ]*\).*/\1/p" | tail -n 1
}
residual() {  # residual <a> <b>: RMS of a - b in dBFS
  ffmpeg -loglevel error -y -i "$1" -i "$2" \
    -filter_complex "[0][1]amerge=inputs=2,aformat=sample_fmts=flt,pan=stereo|c0=c0-c2|c1=c1-c3" -c:a pcm_f32le "$TMP/res.wav"
  astat "$TMP/res.wav" RMS_level
}
below() { LC_ALL=C awk -v a="$1" -v b="$2" 'BEGIN { exit !(a == "-inf" || a < b) }'; }
calls() { wc -l < "$FAKE_DEMUCS_LOG" | tr -d ' '; }
duration() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
run() { ./bassless --out "$OUT" "$@"; }

# 1. The no-bass track is the original minus the stem: 55 Hz + 1 kHz minus the 55 Hz part.
synth "$TMP/exact.wav" '0.3*sin(2*PI*55*t)+0.3*sin(2*PI*1000*t)'
synth "$TMP/expected.wav" '0.3*sin(2*PI*1000*t)'
FAKE_BASS='0.3*sin(2*PI*55*t)' run "$TMP/exact.wav" > /dev/null
r=$(residual "$OUT/exact/no bass.flac" "$TMP/expected.wav")
below "$r" -80 || fail "residual $r dBFS"
[[ $(calls) == 1 ]] || fail "expected one separation, got $(calls)"
ok "subtraction leaves the 1 kHz tone (residual $r dBFS)"

# 2. A second run reuses the stems.
run "$TMP/exact.wav" > /dev/null
[[ $(calls) == 1 ]] || fail "stems were not reused"
ok "second run reuses the stems"

# 3. A track that would overshoot is scaled down as a whole, not clipped and then scaled.
#    Mix 0.78, "bass" -0.52: mix minus bass peaks at 1.30 (+2.3 dB).
synth "$TMP/loud.wav" '0.78*sin(2*PI*220*t)'
log=$(FAKE_BASS='-0.52*sin(2*PI*220*t)' run "$TMP/loud.wav")
gain=$(sed -n 's/.*no bass: turned down \([0-9.]*\) dB.*/\1/p' <<< "$log")
[[ -n "$gain" ]] || fail "expected the no-bass track to be turned down"
synth "$TMP/loud-expected.wav" "1.30*pow(10,-$gain/20)*sin(2*PI*220*t)"
r=$(residual "$OUT/loud/no bass.flac" "$TMP/loud-expected.wav")
below "$r" -70 || fail "loud track is not a scaled copy (residual $r dBFS)"
p=$(astat "$OUT/loud/no bass.flac" Peak_level)
LC_ALL=C awk -v p="$p" 'BEGIN { exit !(p < -0.05 && p > -0.3) }' || fail "peak $p dB"
ok "overshooting track turned down $gain dB, peak $p dB, waveform intact (residual $r dBFS)"

# 4. Demucs failing halfway leaves nothing behind that a later run would reuse.
synth "$TMP/crash.wav" '0.2*sin(2*PI*80*t)'
before=$(calls)
if FAKE_DEMUCS_FAIL=1 run "$TMP/crash.wav" > /dev/null 2>&1; then fail "a Demucs failure was ignored"; fi
[[ ! -e "$OUT/crash/.stems/htdemucs_ft" ]] || fail "partial stems were kept"
run "$TMP/crash.wav" > /dev/null
[[ $(calls) == $((before + 2)) ]] || fail "expected a fresh separation after the failure"
ok "Demucs failure stops the run and leaves no partial stems"

# 5. An incomplete stem folder is separated again.
rm "$OUT/crash/.stems/htdemucs_ft/vocals.wav"
before=$(calls); run "$TMP/crash.wav" > /dev/null
[[ $(calls) == $((before + 1)) ]] || fail "incomplete stems were reused"
ok "incomplete stems are separated again"

# 6. A different file under the same name is refused unless --fresh.
synth "$TMP/other.wav" '0.2*sin(2*PI*90*t)'
if run "$TMP/other.wav" --name crash > /dev/null 2>&1; then fail "reused another song's folder"; fi
before=$(calls); run "$TMP/other.wav" --name crash --fresh > /dev/null
[[ $(calls) == $((before + 1)) ]] || fail "--fresh did not separate again"
ok "a different song under the same name needs --fresh"

# 7. Spaces and Korean in paths; 48 kHz mono input comes out 44.1 kHz stereo and aligned.
mkdir -p "$TMP/입력 폴더"
synth "$TMP/입력 폴더/연습 곡 1.wav" '0.25*sin(2*PI*60*t)+0.25*sin(2*PI*700*t)' 3 48000 1
synth "$TMP/mono-expected.wav" '0.25*sin(2*PI*700*t)'
OUT="$TMP/출력 폴더" FAKE_BASS='0.25*sin(2*PI*60*t)' run "$TMP/입력 폴더/연습 곡 1.wav" > /dev/null
f="$TMP/출력 폴더/연습 곡 1/no bass.flac"
[[ -f "$f" ]] || fail "no output for a path with spaces and Korean"
info=$(ffprobe -v error -show_entries stream=sample_rate,channels -of csv=p=0 "$f")
[[ "$info" == "44100,2" ]] || fail "expected 44100 Hz stereo, got $info"
r=$(residual "$f" "$TMP/mono-expected.wav")
below "$r" -60 || fail "48 kHz mono input: residual $r dBFS"
ok "48 kHz mono input in a Korean path with spaces (residual $r dBFS)"

# 8. Several stems, --slow, --ko.
synth "$TMP/multi.wav" '0.3*sin(2*PI*110*t)' 4
FAKE_BASS='0.5*val(ch)' run "$TMP/multi.wav" --stem bass,drums --slow 0.8 --ko > /dev/null
d="$OUT/multi"
for f in "원곡" "베이스 없음" "베이스만" "드럼 없음" "드럼만" "느리게 0.8x/베이스 없음" "느리게 0.8x/드럼만"; do
  [[ -f "$d/$f.flac" ]] || fail "missing $f.flac"
done
LC_ALL=C awk -v a="$(duration "$d/느리게 0.8x/베이스 없음.flac")" 'BEGIN { exit !(a > 4.9 && a < 5.1) }' \
  || fail "slow copy should last about 5 s"
for f in "$d"/*.flac "$d"/느리게*/*.flac; do
  p=$(astat "$f" Peak_level); below "$p" -0.05 || fail "$(basename "$f") peaks at $p dB"
done
ok "--stem bass,drums --slow 0.8 --ko: all files, 5 s slow copy, no peaks above -0.1 dB"

# 9. Silence goes through without a gain change.
synth "$TMP/silent.wav" '0'
log=$(FAKE_BASS='0' run "$TMP/silent.wav")
grep -q "turned down" <<< "$log" && fail "silence was turned down"
ok "silent input"

# 10. Bad arguments exit with 2 before doing anything.
for args in "--slow" "--slow 9" "--shifts x" "--stem bass,,drums" "--stem banjo" "a.wav b.wav"; do
  set +e; ./bassless $args "$TMP/exact.wav" > /dev/null 2>&1; code=$?; set -e
  [[ $code == 2 ]] || fail "'$args' exited $code, expected 2"
done
ok "bad arguments are rejected"
