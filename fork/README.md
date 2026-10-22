# JustinKWalton/carlink — fork notes

A fork of [lvalen91/carlink](https://github.com/lvalen91/carlink) for one truck: a 2025 GMC
Sierra 2500 (gminfo3.7, Android 12) with a Carlinkit CPC200-CCPA. It is installed through a
personal Play Console internal-testing track (`com.justinwalton.carlink`), because GM radios
have no ADB.

Upstream's own docs (`README.md`, `documents/`) still apply. Fork changes, all marked `FORK`
in the code:

| Area | Change |
|---|---|
| Package | `ownerApplicationId = "com.justinwalton.carlink"` |
| Versioning | `versionCode = upstream * 100 + forkRevision` (bottom of `app/build.gradle.kts`), name `1.61-j1` |
| Audio | **Audio Buffer** setting (Settings › Adapter Configuration › Audio): Normal (upstream) / Large (default) / Extra large. Sizes the radio-side AudioTrack, prefill and media ring on GM AAOS only |
| Audio logs | `[AUDIO_STUTTER]` WARN line per 30 s window with any underrun/overflow, with session totals, visible under the Normal log preset |
| Cluster / HUD | **Cluster Navigation** defaults ON on gminfo3.7. Next step's distance = remaining + route-plan segment (was the trip total); `Step.setRoad` carries the road after the turn |
| Auto-connect | "Box not found" keeps retrying; reconnect cap 5 → 20 (~9 min); WIFI_CONNECT re-sent every 20 s while the box scans with no phone; a refused background foreground-service start no longer aborts the session |

Limits a fork can't lift: the cluster gets maneuver type + text, not the composed arrow
bitmaps (the GM icon-provider authority belongs to upstream's Play package); no video while
moving; no vehicle data.

## Updating

On the PC, in Git Bash at `C:\carlink`:

```bash
bash fork/update.sh            # merge upstream/main, run unit tests, build the signed Play bundle
```

It writes `carlink-play-v<code>.aab` to `C:\Users\justi\Documents\carlink-signing\`. Upload it
in Play Console › Carlink › Test and release › Internal testing › Create new release. After
merging a new upstream release, reset `forkRevision` to 1; bump it for fork-only changes.
