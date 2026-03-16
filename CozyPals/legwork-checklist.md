# CozyPals Milestone 1 Legwork Checklist (Dedicated Server)

This is the exact checklist to run in-game and collect the right evidence for CozyPals GUID verification and persistence.

## 1) Set your paths once

Open PowerShell and set these variables to your actual server install:

```powershell
$SERVER_ROOT = "C:\Path\To\PalServer"               # folder containing Pal\
$WIN64_DIR   = Join-Path $SERVER_ROOT "Pal\Binaries\Win64"
$MOD_DIR     = Join-Path $WIN64_DIR "Mods\CozyPals"
$DATA_DIR    = Join-Path $MOD_DIR "data"
$SAVED_LOG   = Join-Path $SERVER_ROOT "Pal\Saved\Logs\PalServer.log"
```

## 2) Verify mod files are in the right place

Run:

```powershell
Get-Item "$MOD_DIR\enabled.txt"
Get-ChildItem "$MOD_DIR\scripts" -File
Get-Content "$MOD_DIR\enabled.txt"
```

Expected:
- `enabled.txt` exists and contains `1`
- all CozyPals scripts exist (including `main.lua`, `discovery.lua`, `identity.lua`)

## 3) Find the active UE4SS log file

UE4SS writes `UE4SS.log` in the same folder as `UE4SS.dll`. For Palworld installs this is usually under `Win64`.

Run:

```powershell
$UE4SS_LOG = Get-ChildItem $WIN64_DIR -Recurse -Filter "UE4SS.log" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName
$UE4SS_LOG
```

If this prints nothing, check both of these manually:
- `$WIN64_DIR\UE4SS.log`
- `$WIN64_DIR\ue4ss\UE4SS.log`

## 4) Start dedicated server and confirm CozyPals booted correctly

After server startup, run:

```powershell
Select-String -Path $UE4SS_LOG -Pattern "\[CozyPals\]" | Select-Object -Last 40
```

You must see:
- `Starting CozyPals ... | server_authority=true`
- `Registered BeginPlay pre-hook for actor discovery.`
- `World ready cycle started.`

You must **not** see:
- `CozyPals in observer mode (not authoritative)`

If you see observer mode, set in `Mods\CozyPals\scripts\config.lua`:
- `authority.mode = "force_server"`

Restart server after changing config.

## 5) In-game actions (exact order)

Do this as a connected player on the dedicated server.

1. Go to a base with at least 2 loaded pals.
2. Stay near the pals for 60-90 seconds (let actor BeginPlay/discovery fire).
3. Move one known pal from base -> box, then box -> base.
4. Stay near that same pal for another 60 seconds.
5. Restart dedicated server.
6. Rejoin and go to the same base/pal again for 60 seconds.

## 6) Pull the exact log evidence after each phase

Run these commands:

```powershell
# Latest CozyPals lines
Select-String -Path $UE4SS_LOG -Pattern "\[CozyPals\]" | Select-Object -Last 300

# Discovery ranking + structured report
Select-String -Path $UE4SS_LOG -Pattern "Candidate #|report actor=|best_property="

# Milestone state transitions
Select-String -Path $UE4SS_LOG -Pattern "\[M1\]\[BLOCKED\]|\[M1\]\[GUID VERIFIED\]|\[M1\]\[PASS\]"
```

What we want to see:
- Discovery top candidate includes `property=IndividualId.InstanceId` (or component path ending in `.IndividualId.InstanceId`).
- Early runs: `[M1][BLOCKED] GUID candidate not verified yet`
- After enough evidence: `[M1][GUID VERIFIED] source=...IndividualId.InstanceId`
- Then: `[M1][PASS] New persistent pal record created guid=...`
- After restart/rejoin: `[M1][PASS] Existing pal record rebound guid=...`

## 7) Confirm save file was written

Run:

```powershell
Get-ChildItem "$DATA_DIR\\cozypals_state_*.json" | Sort-Object LastWriteTime -Descending
```

Open newest file and verify:
- `guid_verification.report` exists
- `pals` contains the verified GUID key
- that pal has `personality.seed`
- that pal has `verification.guid_source`

## 8) What to send back each test loop

Send these artifacts:
- Last 300 CozyPals log lines from `UE4SS.log`
- Output of M1 transition grep (`BLOCKED`, `GUID VERIFIED`, `PASS`)
- Newest `cozypals_state_*.json`
- Short note: which pal you moved and when you restarted server

## 9) Fast fail indicators

If any of these happen, send logs immediately:
- No `UE4SS.log` found
- No `[CozyPals]` lines at all
- `server_authority=false` or observer mode
- Discovery never prints `IndividualId.InstanceId`
- `[M1][GUID VERIFIED]` never appears after move + restart cycle
- Save file never appears under `Mods\CozyPals\data`
