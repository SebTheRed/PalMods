# CozyPals Milestone 1 Test Checklist (Dedicated)

## Startup
- Dedicated server starts with CozyPals loaded.
- Log shows authority mode as server-authoritative.

## Discovery
- Pal actor candidates are logged.
- Top GUID-like property candidates are ranked and printed.
- Confirm whether `IndividualId.InstanceId` appears as the top candidate source.
- Structured discovery report line is printed per candidate actor.

## Verification gates
- Candidate GUID remains blocked until run/world-cycle/context requirements are met.
- Verified GUID transitions to `[M1][GUID VERIFIED]` once requirements pass.

## Persistence
- On first verified GUID sighting, personality seed is rolled and record is created.
- Restart and reload recover the same seed for same GUID.
- Multiple pals of same species produce distinct GUID records.

## Safety
- If no verified GUID exists, no pal record is persisted.
- Save writes create backup and temp file flow without corrupting last good save.
