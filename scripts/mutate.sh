#!/bin/zsh
# Created: 2026-10-19 19:22 -05:00 · Edited: 2026-10-27 09:26 -05:00
# C1-T4: scripts/mutate.sh M<n> — apply the named break, run the catching test (expect red), restore.
# Rows mirror the Mutations register; a test is not evidence until this shows it fail.
set -uo pipefail
cd "$(dirname "$0")/.."
id="${1:-}"
case "$id" in
  M1) file=Sources/MonitorCore/Monitor.swift
      from='guard let caps = capabilities, caps.advertises(code) else'
      to='guard let caps = capabilities, true || caps.advertises(code) else'
      filter=WhitelistTests/testUnadvertisedCodeIsRefusedBeforeAnyI2C ;;
  M2) file=Sources/MonitorCore/Capabilities.swift
      from='case "(": flushToken(); depth += 1; values = []'
      to='case "(": flushToken(); values = []'
      filter=CapabilitiesTests/testParsesG3223DFixture ;;
  M3) file=Sources/MonitorCore/DDCProtocol.swift
      from='let current = UInt16(v[8]) << 8 | UInt16(v[9])'
      to='let current = UInt16(v[6]) << 8 | UInt16(v[7])'
      filter=DDCFrameTests/testCurrentInputIsLowByte ;;
  M4) file=Sources/MonitorCore/Monitor.swift
      from='if VCP.factoryResets.contains(code) { throw'
      to='if false { throw'
      filter=WhitelistTests/testFactoryResetCodesAreNeverOffered ;;
  M5) file=Sources/MonitorCore/DDCProtocol.swift
      from='guard replyChecksum(r[0..<(total - 1)]) == r[total - 1] else'
      to='guard true else'
      filter=DDCFrameTests/testChecksumMismatchIsRejected ;;
  M6) file=Sources/MonitorCore/I2CChannel.swift
      from='guard done.wait(timeout: .now() + timeout) == .success, let r = result else'
      to='done.wait(); guard let r = result else'
      filter=DDCFrameTests/testDeadlineChannelTimesOut ;;
  M7) file=Sources/MonitorCore/MonitorNames.swift
      from='let n = all[identity.key]?'
      to='let n = all["\(identity.displayID ?? 0)"]?'
      filter=MonitorNamesTests/testNamesAreKeyedBySerialNotDisplayID ;;
  M8) file=Sources/MonitorCore/DDCProtocol.swift
      from='if case DDCError.timeout = error { throw error }'
      to='if case DDCError.timeout = error { _ = error }'
      filter=DDCFrameTests/testTimeoutIsNotRetried ;;
  M9) file=Sources/MonitorCore/Monitor.swift
      from='if max == nil { max = try get(code).maximum }'
      to='if max == nil { max = nil }'
      filter=WhitelistTests/testContinuousWriteReadsTheMaximumFirst ;;
  M10) file=Sources/MonitorCore/Monitor.swift
      from='guard let p = VCP.lockingPreset(vendor: identity.vendor), capabilities?.advertises(p.code) == true else {'
      to='guard let p = VCP.lockingPreset(vendor: 0x10AC), capabilities?.advertises(p.code) == true else {'
      filter=LockTests/testLockIsVendorKeyed ;;
  M11) file=Sources/MonitorCore/Monitor.swift
      from='if let by { throw DDCError.locked(code: code, by: by) }'
      to='if let by { _ = by }'
      filter=LockTests/testLockedCodesAreNotWritten ;;
  M13) file=Sources/MonitorCore/Monitor.swift
      from='let by = lockState == .unknown ? try pictureLock() : lockedBy'
      to='let by = lockState == .unknown ? nil : lockedBy'
      filter=LockTests/testFailedLockReadIsNotStale ;;
  M12) file=Sources/MonitorCore/CapabilitiesCache.swift
      from='guard let raw = all[identity.key], !Capabilities.parse(raw).vcp.isEmpty else { return nil }'
      to='guard let raw = all.values.first, !Capabilities.parse(raw).vcp.isEmpty else { return nil }'
      filter=CapabilitiesCacheTests/testCacheIsPerMonitor ;;
  *) echo "usage: scripts/mutate.sh M1|M2|M3|M4|M5|M6|M7|M8|M9|M10|M11|M12|M13"; exit 2 ;;
esac
if ! git diff --quiet -- "$file"; then echo "$file has uncommitted changes; refusing to mutate"; exit 2; fi
if ! grep -qF -- "$from" "$file"; then echo "$id: pattern not found in $file — the mutation no longer applies"; exit 2; fi
trap 'git checkout -- "$file" 2>/dev/null' EXIT INT TERM   # never leave the break applied (review X3)
python3 -c 'import sys,pathlib; p=pathlib.Path(sys.argv[1]); t=p.read_text(); p.write_text(t.replace(sys.argv[2], sys.argv[3], 1))' "$file" "$from" "$to"
grep -qF -- "$to" "$file" || { git checkout -- "$file"; echo "$id: mutation did not apply"; exit 2; }
echo "== $id applied to $file; running $filter (expect failures) =="
out=$(swift test --filter "$filter" 2>&1); rc=$?
git checkout -- "$file"
summary=$(printf '%s\n' "$out" | grep -E "Executed [0-9]+ test" | tail -1)
if [[ $rc -ne 0 ]]; then echo "== $id KILLED: $summary"; exit 0
else echo "== $id SURVIVED (test did not fail): $summary"; exit 1; fi
