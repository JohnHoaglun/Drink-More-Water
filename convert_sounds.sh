#!/usr/bin/env bash
# Converts .m4a/.mp3 to notification-ready .caf (linear PCM, 44.1kHz, stereo)
# Uses two-step conversion because afconvert can't read AAC directly on some macOS versions.

set -euo pipefail

SOUNDS=(
  "audio/Small/Drink1.m4a"
  "audio/Small/Drink2.m4a"
  "audio/Small/Drink3.m4a"
  "audio/Small/Drink4.mp3"
  "audio/Small/Drum1.m4a"
  "audio/Small/Drum2.m4a"
  "audio/Small/Drum3.m4a"
)

for src in "${SOUNDS[@]}"; do
  base=$(basename "$src" | sed 's/\.[^.]*$//')
  caf="audio/Small/${base}.caf"
  alac="/tmp/_notify_${base}.m4a"

  if [ ! -f "$src" ]; then
    echo "SKIP: $src not found"
    continue
  fi

  echo "Converting: $src -> $caf"

  # Step 1: Convert to lossless ALAC (ensures clean decode)
  afconvert -f m4af -d alac -b 44100 -c 2 "$src" "$alac" 2>&1 || {
    echo "  Step 1 FAILED for $src, trying without rate constraint..."
    afconvert -f m4af -d alac -c 2 "$src" "$alac" 2>&1 || {
      echo "  ERROR: Step 1 failed for $src"
      continue
    }
  }

  # Step 2: ALAC -> CAF linear PCM (iOS notification sound format)
  afconvert -f caff -d 'lpcm' -b 16 -c 2 -r 44100 "$alac" "$caf" 2>&1 || {
    echo "  Step 2 FAILED for $caf, trying mono..."
    afconvert -f caff -d 'lpcm' -b 16 -c 1 -r 44100 "$alac" "$caf" 2>&1 || {
      echo "  ERROR: Step 2 failed for $src"
      rm -f "$alac"
      continue
    }
  }

  rm -f "$alac"

  # Verify the output
  if afinfo "$caf" 2>&1 | grep -q "44100 Hz"; then
    echo "  OK: $caf (44.1kHz)"
  else
    echo "  WARN: $caf may have wrong sample rate"
  fi
done

echo ""
echo "Done."
