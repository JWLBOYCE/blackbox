# Importing From LogTen Pro

Blackbox imports LogTen Pro data from the Core Data SQLite store, usually named:

```text
LogTenCoreDataStore.sql
```

The importer opens this file read-only. It does not modify LogTen Pro.

## In-App Import

1. Quit LogTen Pro so its database is not actively changing.
2. Open Blackbox.
3. Select `Import` in the sidebar.
4. Click `Import LogTen Pro`.
5. Choose `LogTenCoreDataStore.sql`.

Blackbox then:

1. Opens the selected file read-only, validates it, and creates a private snapshot for the preview.
2. Shows additions, field-level changes, unchanged rows, duplicates, conflicts, and Blackbox rows absent from the source. This preview does not change the Blackbox database.
3. Lets you select individual fields and choose whether a duplicate is skipped, imported separately, applied to a draft, or created as an amendment to a finalised record.
4. After explicit approval, creates and verifies a self-contained recovery backup, applies the plan to a staged database, and verifies counts, totals, unchanged-row digests, revisions, foreign keys, and SQLite integrity.
5. Activates the verified stage atomically. A source omission never deletes a Blackbox record, and any failed stage restores or retains a verified recovery point.

## Typical LogTen Pro Database Locations

Common locations include:

```text
~/Library/Containers/com.coradine.LogTenPro6/Data/Documents/LogTenProData/LogTenCoreDataStore.sql
```

or a copied backup of that file.

If macOS hides `Library`, open Finder and use `Go` -> `Go to Folder...`.

## Field Mapping

Blackbox uses the same LogTen mappings as the original migration:

| LogTen heading / field | LogTen database column | Blackbox field |
| --- | --- | --- |
| Date | `ZFLIGHT_FLIGHTDATE` | `date` |
| From | `ZFLIGHT_FROMPLACE` -> `ZPLACE` | `departure` |
| To | `ZFLIGHT_TOPLACE` -> `ZPLACE` | `arrival` |
| Route | `ZFLIGHT_ROUTE` | `route` |
| Aircraft ID / registration | `ZAIRCRAFT_AIRCRAFTID` | `aircraft_id` |
| Aircraft type | `ZAIRCRAFTTYPE_TYPE` / `ZAIRCRAFTTYPE_MODEL` | `aircraft_type` |
| Flight number | `ZFLIGHT_FLIGHTNUMBER` | `flight_number` |
| Multi-pilot | `ZFLIGHT_MULTIPILOT` | `operation` |
| Total | `ZFLIGHT_TOTALTIME` | `total_minutes` |
| PIC | `ZFLIGHT_PIC` | `pic_minutes` |
| PIC night | `ZFLIGHT_PICNIGHT` | `pic_night_minutes` |
| P1US / PICUS | `ZFLIGHT_P1US` | `picus_minutes` |
| PICUS day | `ZFLIGHT_CUSTOMTIME4` | `picus_day_minutes` |
| P1US night | `ZFLIGHT_P1USNIGHT` | `picus_night_minutes` |
| Co-pilot | `ZFLIGHT_CUSTOMTIME3` | `copilot_minutes` |
| Co-pilot day | derived from `ZFLIGHT_CUSTOMTIME3` | `copilot_day_minutes` |
| Dual received | `ZFLIGHT_DUALRECEIVED` | `dual_minutes` |
| Instructor / dual given | `ZFLIGHT_DUALGIVEN` | `instructor_minutes` |
| Night | `ZFLIGHT_NIGHT` | `night_minutes` |
| Instrument / IFR | `ZFLIGHT_CUSTOMTIME2` | `instrument_minutes` |
| Cross-country | `ZFLIGHT_CROSSCOUNTRY` | `cross_country_minutes` |
| Simulator / FSTD | `ZFLIGHT_SIMULATOR` | `fstd_minutes` |
| Pilot flying | `ZFLIGHT_PILOTFLYINGCAPACITY` | `pilot_flying` |
| Day takeoffs | `ZFLIGHT_DAYTAKEOFFS` | `day_takeoffs` |
| Night takeoffs | `ZFLIGHT_NIGHTTAKEOFFS` | `night_takeoffs` |
| Total takeoffs | `ZFLIGHT_TOTALTAKEOFFS` | `total_takeoffs` |
| Day landings | `ZFLIGHT_DAYLANDINGS` | `day_landings` |
| Night landings | `ZFLIGHT_NIGHTLANDINGS` | `night_landings` |
| Total landings | `ZFLIGHT_TOTALLANDINGS` | `total_landings` |
| Passengers | `ZFLIGHT_PAXCOUNT` | `passenger_count` |
| Distance | `ZFLIGHT_DISTANCE` | `distance_nm` |
| Crew | `ZFLIGHTCREW` + `ZPERSON` | `crew_names` |
| Remarks / notes | `ZFLIGHT_REMARKS` | `remarks` |

## Day / Night Handling

For imported LogTen rows, Blackbox preserves LogTen night values. The mapped
LogTen schema supplies a co-pilot total but no separate co-pilot-night field,
so Blackbox initially assigns that total to co-pilot day and assigns zero to
co-pilot night. Review and adjust that split before finalising if the source
flight included co-pilot night time.

For new Blackbox drafts, Blackbox can suggest night minutes from:

- departure time in Zulu
- flight duration
- departure airport coordinates
- arrival airport coordinates
- great-circle position sampled through the route
- solar elevation threshold

The suggestion includes its inputs and method, is made only when the inputs are complete and unambiguous, and never overwrites a non-zero entered value. Nothing changes until the pilot explicitly accepts it.

## Safety Checks

After importing, open the `Compare` tab. A comparison reports a match only after a non-empty source has opened successfully and every LogTen-sourced persisted field has been compared. It also shows:

- LogTen Pro rows matching Blackbox imported rows.
- Any Blackbox-only flights separately, usually roster imports or manually created entries.
- No real LogTen database changes.

`Empty Source`, `Source Unavailable`, and `Comparison Failed` are explicit non-match states. Blackbox's Logbook Checks are internal completeness and consistency checks, not regulatory certification.
