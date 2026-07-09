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

1. Validates that the selected database contains LogTen flight rows.
2. Creates a timestamped backup of the current Blackbox working database.
3. Clears the Blackbox working tables.
4. Imports LogTen flights, places, aircraft, crew, times, landings, passenger counts, distance, notes, and simulator data.
5. Rebuilds CAA checks, summaries, map coordinates, and comparison totals.

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
| Multi-pilot | `ZFLIGHT_MULTIPILOT` plus crew count | `operation` |
| Total | `ZFLIGHT_TOTALTIME` | `total_minutes` |
| PIC | `ZFLIGHT_PIC` | `pic_minutes` |
| PIC night | `ZFLIGHT_PICNIGHT` | `pic_night_minutes` |
| P1US / PICUS | `ZFLIGHT_P1US` | `picus_minutes` and `pilot_function = PICUS` |
| P1US night | `ZFLIGHT_P1USNIGHT` | co-pilot night allocation where relevant |
| SIC / co-pilot | `ZFLIGHT_SIC` | `copilot_minutes` |
| SIC night | `ZFLIGHT_SICNIGHT` | `copilot_night_minutes` |
| Dual received | `ZFLIGHT_DUALRECEIVED` | `dual_minutes` |
| Instructor / dual given / SFI | `ZFLIGHT_DUALGIVEN`, `ZFLIGHT_SFI` | `instructor_minutes` |
| Night | `ZFLIGHT_NIGHT` | `night_minutes` |
| Instrument / IFR | `ZFLIGHT_TOTALINSTRUMENT` | `instrument_minutes` |
| Cross-country | `ZFLIGHT_CROSSCOUNTRY` | `cross_country_minutes` |
| Simulator / FSTD | `ZFLIGHT_SIMULATOR` | `fstd_minutes` and `entry_kind = Simulator` |
| Pilot flying | `ZFLIGHT_PILOTFLYINGCAPACITY` | `pilot_flying` |
| Day takeoffs | `ZFLIGHT_DAYTAKEOFFS` | `day_takeoffs` |
| Night takeoffs | `ZFLIGHT_NIGHTTAKEOFFS` | `night_takeoffs` |
| Total takeoffs | `ZFLIGHT_TOTALTAKEOFFS` | `total_takeoffs` |
| Day landings | `ZFLIGHT_DAYLANDINGS` | `day_landings` |
| Night landings | `ZFLIGHT_NIGHTLANDINGS` | `night_landings` |
| Total landings | `ZFLIGHT_TOTALLANDINGS` | `total_landings` |
| Passengers | `ZFLIGHT_PAXCOUNT` | `passenger_count` |
| Distance | `ZFLIGHT_DISTANCE` | `distance_nm` |
| Crew | `ZFLIGHTCREW` + `ZPERSON` | `crew_names`, `crew_roles` |
| Remarks / notes | `ZFLIGHT_REMARKS` | `remarks` |

## Day / Night Handling

For imported LogTen rows, Blackbox preserves LogTen night values.

For new Blackbox flights, Blackbox calculates night minutes from:

- departure time in Zulu
- flight duration
- departure airport coordinates
- arrival airport coordinates
- great-circle position sampled through the route
- solar elevation threshold

## Safety Checks

After importing, open the `Compare` tab. A clean import should show:

- LogTen Pro rows matching Blackbox imported rows.
- Any Blackbox-only flights separately, usually roster imports or manually created entries.
- No real LogTen database changes.
