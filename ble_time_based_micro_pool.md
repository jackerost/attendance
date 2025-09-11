# BLE Time-Based Micro-Pool (No Client Secrets)

Authoritative guide for proximity via BLE using time-aligned minor rotation with a short, server-issued pool. Keeps DB out of the hot path, removes race conditions, and improves UX.

## Goals
- No secrets on client devices.
- No per-roll database writes; validation is local after BLE detection.
- Clock-aligned rotation with 8s/3s (interval/grace) and heartbeat liveness.

## App Constants (hardcode)
- ROTATION_INTERVAL_MS = 8000
- GRACE_PERIOD_MS = 3000
- HEARTBEAT_FRESHNESS_SEC = 35
- PRE_ROLL_TOLERANCE_MS = 300
- MINOR_POOL_SIZE = 12
- REFRESH_BUFFER_SLOTS = 2

## Session Document (Firestore)
- rollingStartAt (Timestamp): canonical origin for slot math.
- poolStartSlot (int): slot index where the current pool begins.
- minorPool (int[]): short list of random 16-bit minors (e.g., 12).
- poolVersion (int): increment to force client refresh.
- beaconUpdatedAt (Timestamp): heartbeat; broadcaster updates every 20–30s.
- Optional: beaconMajor (int), beaconMode ("entry" | "exit").

## Cloud Functions / Edge Functions
1) startRolling(sessionId)
- AuthZ: only session owner.
- If rollingStartAt missing => set serverTimestamp().
- Compute serverSlot from rollingStartAt + ROTATION_INTERVAL_MS.
- Generate minorPool (MINOR_POOL_SIZE unique random minors, 0-65535 range).
- Write rollingStartAt (if set), poolStartSlot = serverSlot, minorPool, poolVersion += 1, beaconUpdatedAt.

2) refreshMinorPool(sessionId)
- AuthZ: only session owner.
- Compute current serverSlot; set poolStartSlot = serverSlot.
- Generate new minorPool (MINOR_POOL_SIZE unique random minors); write; poolVersion += 1; update beaconUpdatedAt.

3) rotateHeartbeat(sessionId) [optional]
- Update beaconUpdatedAt = serverTimestamp(); call every 20–30s.

## Broadcaster (Lecturer) Flow
- On session start: call startRolling. Fetch config; compute serverTimeOffset.
- Every 8s: alignedNow = deviceNow + offset; currentSlot = floor((alignedNow − rollingStartAt)/8000);
  - poolIndex = currentSlot − poolStartSlot;
  - If poolIndex >= MINOR_POOL_SIZE − REFRESH_BUFFER_SLOTS: call refreshMinorPool and refetch.
  - Advertise minor = minorPool[clamp(poolIndex, 0..MINOR_POOL_SIZE−1)].
- Every 20–30s: call rotateHeartbeat.

## Receiver (Student) Flow
- On open: fetch config; compute serverTimeOffset; cache pool + fields.
- On BLE detect:
  - alignedNow = deviceNow + offset; currentSlot = floor((alignedNow − rollingStartAt)/8000);
  - poolIndex = currentSlot − poolStartSlot;
  - expectedCurrent = minorPool[poolIndex] if in range;
  - expectedPrev = minorPool[poolIndex−1] if in range and within GRACE_PERIOD_MS;
  - Accept if detected == expectedCurrent OR (== expectedPrev within grace) OR within PRE_ROLL_TOLERANCE_MS around boundary;
  - Liveness: reject if now − beaconUpdatedAt > HEARTBEAT_FRESHNESS_SEC.
- Refresh config if poolIndex >= MINOR_POOL_SIZE − REFRESH_BUFFER_SLOTS OR poolVersion changed.

## Security Notes
- Do NOT ship secrets to clients. No rollingKey on devices.
- Keep pools short-lived; refresh early; protect with Auth/RLS.
- Combine with device integrity (Play Integrity/SafetyNet) for higher assurance.

## Telemetry
- Log: currentSlot, poolIndex, poolVersion, acceptedAs (current/previous), heartbeatAgeSec, offsetMs, rssiAtAccept.

## Rollout
- Add new fields; keep legacy path behind a feature flag.
- Implement receiver local-validation; fallback to legacy if config missing.
- Switch broadcaster to time-driven; remove beaconMinorCurrent writes after validation window.

## Known Limits
- BLE scan variance (OS-level) remains.
- Clock drift exists; 3s grace + 300ms pre-roll tolerance mask most cases.
- Slightly more code: offset math, pool refresh, telemetry.
