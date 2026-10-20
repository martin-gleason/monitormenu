#!/bin/zsh
# C1-T4: scripts/mutate.sh M<n> — apply the named break, run the catching test (expect red), restore.
# Rows mirror the Mutations register; a test is not evidence until this shows it fail.
set -uo pipefail
cd "$(dirname "$0")/.."
id="${1:-}"
case "$id" in
  M1) file=Sources/SwitchCore/Monitor.swift
      from='guard let caps = capabilities, caps.advertises(code) else'
      to='guard let caps = capabilities, true || caps.advertises(code) else'
      filter=WhitelistTests/testUnadvertisedCodeIsRefusedBeforeAnyI2C ;;
  M2) file=Sources/SwitchCore/Capabilities.swift
      from='case "(": flushToken(); depth += 1; values = []'
      to='case "(": flushToken(); values = []'
      filter=CapabilitiesTests/testParsesG3223DFixture ;;
  M3) file=Sources/SwitchCore/DDCProtocol.swift
      from='let current = UInt16(r[8]) << 8 | UInt16(r[9])'
      to='let current = UInt16(r[6]) << 8 | UInt16(r[7])'
      filter=DDCFrameTests/testCurrentInputIsLowByte ;;
  M4) file=Sources/SwitchCore/Monitor.swift
      from='if VCP.factoryResets.contains(code) { throw'
      to='if false { throw'
      filter=WhitelistTests/testFactoryResetCodesAreNeverOffered ;;
  *) echo "usage: scripts/mutate.sh M1|M2|M3|M4"; exit 2 ;;
esac
if ! git diff --quiet -- "$file"; then echo "$file has uncommitted changes; refusing to mutate"; exit 2; fi
if ! grep -qF -- "$from" "$file"; then echo "$id: pattern not found in $file — the mutation no longer applies"; exit 2; fi
python3 -c 'import sys,pathlib; p=pathlib.Path(sys.argv[1]); t=p.read_text(); p.write_text(t.replace(sys.argv[2], sys.argv[3], 1))' "$file" "$from" "$to"
grep -qF -- "$to" "$file" || { git checkout -- "$file"; echo "$id: mutation did not apply"; exit 2; }
echo "== $id applied to $file; running $filter (expect failures) =="
out=$(swift test --filter "$filter" 2>&1); rc=$?
git checkout -- "$file"
summary=$(printf '%s\n' "$out" | grep -E "Executed [0-9]+ test" | tail -1)
if [[ $rc -ne 0 ]]; then echo "== $id KILLED: $summary"; exit 0
else echo "== $id SURVIVED (test did not fail): $summary"; exit 1; fi
