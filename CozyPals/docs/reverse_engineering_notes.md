# CozyPals Reverse Engineering Notes

Use this file while running UE4SS Live Viewer and dedicated tests.

## Candidate class/object mapping
- Date:
- World:
- Location/base:
- Actor text:
- Class path:
- Components observed:

## Candidate GUID properties
- Source path:
- Property:
- Example value:
- Looks GUID-like (`yes/no`):
- Confidence notes:

Preferred first target:
- `IndividualId.InstanceId` (or component path ending with `.IndividualId.InstanceId`)

## Validation checks
- Same value after world reload:
- Same value after dedicated restart:
- Same value after base/box/party move:
- Verdict: `candidate` or `verified`

## Trust/mood/work follow-up targets (post-M1)
- Trust field path:
- Mood/SAN field path:
- Work state field path:
- Interaction function hooks:
