# OverBet 6.1.0 — W3–W6

## W3 — Data pipeline
- Added `SStatsRepository` and typed `MatchAnalysisBundle`.
- Forecast scanning now consumes a single analysis bundle per match instead of orchestration of API calls in the feature flow.
- Fresh data is used for today/game/odds; historical team history remains cacheable.

## W4 — Analysis hardening
- Explicit market sample gate runs before probability calculation.
- Published probabilities are clamped to a valid numerical interval.
- GOALS now expose a real 4-model edge vote (DC/BIV/NB/ensemble).
- Forecast output is restricted to the client tiers `A BET` and `S BET`.

## W5 — Validation
- Settlement creates/updates a unique `CalibrationSample` for every closed WIN/LOSS.
- Corners CLV is measured against Pinnacle rather than an arbitrary best book; cards remain best-available.
- OOS market reports now include avg CLV, positive CLV rate, Brier, LogLoss and Profit Factor.
- OOS report decoding remains backward-compatible with pre-W3 JSON.

## W6 — Forecast snapshot and schedule
- Added persisted `ForecastSnapshot` with daily A/S signal payload.
- Forecast tab first reads a fresh same-day snapshot and falls back to live scan when stale/missing.
- Displayed A/S signals are saved to Journal immediately, not only after opening details.
- Added daily BGAppRefresh forecast trigger targeted for ~10:55 local time. iOS still controls the exact execution time; foreground fallback remains.

## Persistence
- Schema advanced from 6.0.1 to 6.1.0 with lightweight V2→V3 migration for `ForecastSnapshot`.
