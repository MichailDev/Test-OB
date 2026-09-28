# OverBet 6.0 — W1 file map

## Что сделано

Текущие большие файлы разделены по ответственностям. Старые `Models.swift`, `APIClient.swift`, `QuantEngine.swift`, `BacktestEngine.swift` и `SyndicateQuantApp.swift` удалены из корня target и заменены структурированными файлами.

### App
- `App/OverBetApp.swift` — точка входа
- `App/AppSettings.swift` — пользовательские настройки
- `App/AppDependencies.swift` — зависимости приложения
- `App/AppDelegate.swift` — lifecycle/background

### Domain
- `Domain/LeagueModels.swift`
- `Domain/SignalModels.swift`
- `Domain/BetTier.swift`

### Analytics
- `Analytics/QuantEngine.swift`
- `Analytics/QuantEngineSupport.swift`
- `Analytics/Quote+Analysis.swift`
- `Analytics/QuantMath.swift`
- `Analytics/BacktestEngine.swift`
- `Analytics/ValidationModels.swift`
- `Analytics/MetricsModels.swift`

### Data/API
- `Data/API/SStatsClient.swift`
- `Data/API/APITransport.swift`

### Persistence
- `Persistence/AppSchema.swift`
- `Persistence/PersistenceController.swift`
- `Persistence/AppMigrationPlan.swift`
- `Persistence/AnalysisPersistenceModels.swift`
- `Persistence/JournalPersistenceModels.swift`
- `Persistence/BacktestPersistenceModels.swift`
- `Persistence/BacktestSnapshot+Decoding.swift`

### Services
- `Services/ScanCoordinator.swift`
- `Services/JournalService.swift`
- `Services/BacktestService.swift`
- `Services/LiveMonitor.swift`
- `Services/HistoricalMarketCacheService.swift`
- `Services/LineSnapshotService.swift`
- `Services/TeamRatingService.swift`
- `Services/TuningService.swift`
- `Services/SubscriptionService.swift`
- `Services/AdminAccessService.swift`

### Client
- `Features/Client/Forecast/ForecastView.swift`
- `Features/Client/Forecast/ForecastRow.swift`
- `Features/Client/Forecast/ForecastDetailView.swift`
- `Features/Client/Statistics/StatisticsView.swift`
- `Features/Client/Journal/JournalView.swift`
- `Features/Client/Journal/JournalEntryDetailView.swift`
- `Features/Client/Settings/SettingsView.swift`

### Admin
- `Features/Admin/AdminConsoleView.swift`
- `Features/Admin/Tuning/SelfTuningView.swift`

## Следующие волны
1. W2: полноценная VersionedSchema/MigrationPlan и перенос HistoricalMarketCache из SwiftData в disk cache.
2. W3: Repository layer и единый DataPipeline.
3. W4: production Goals/Corners/Cards models и market probability/vig normalization.
4. W5: Calibration/OOS/CLV/Bollinger/portfolio risk.
5. W6: ForecastSnapshot + автоматический ежедневный scan около 11:00 + foreground fallback.
6. W7: StoreKit 2 subscription и реальная блокировка S BET.
7. W8: server-backed admin authorization.
8. W9: полный Admin UI.
9. W10: удаление оставшегося dead code и legacy документации.
10. W11: CI, migration tests, model self-tests и Release IPA.
