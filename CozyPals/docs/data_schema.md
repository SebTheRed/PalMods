# CozyPals Data Schema (Milestone 1)

## Root object
- `data_schema_version` (number)
- `world_key` (string)
- `meta` (object)
- `pals` (map: `guid -> pal_record`)
- `guid_verification` (object)

## pal_record
- `version` (number)
- `species` (string)
- `personality.seed` (number)
- `personality.work_attitude` (string)
- `personality.social_preference` (string)
- `personality.temperament` (string)
- `meta.first_seen` (unix timestamp)
- `meta.last_seen` (unix timestamp)
- `meta.home_base_id` (string or null)
- `verification.guid_source` (string)

## guid_verification
- `version` (number)
- `sources` (map of source records)
- `report` (human-readable summary for logs/debug)
