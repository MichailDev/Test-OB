# OverBet 6.0 — W1

Первая волна рефакторинга: новая структура проекта, Client/Admin shell, централизованный SwiftData, удалён legacy Python engine.

## Следующая волна
W2 — Persistence V1 + disk cache + migration hardening.
W3 — Data/Repository layer.
W4 — Goals/Corners/Cards engine hardening.
W5 — Calibration/OOS/CLV/Risk.
W6 — Forecast snapshot + 11:00 pipeline.
W7 — StoreKit subscription.
W8 — Admin authorization.
W9 — Admin UI completion.
W10 — cleanup.
W11 — CI/build validation.

## W2 — Persistence V2 + disk cache

В W2 постоянная SwiftData БД отделена от производного historical cache.

- `HistoricalMarketCache` больше не входит в `AppSchema` текущей версии.
- Добавлен версионный граф `V0 (5.6.0) → V1 (6.0.0) → V2 (6.0.1)`.
- `V0 → V1` — lightweight migration: добавляется `LineSnapshot` и флаги `cornersChecked/cardsChecked`.
- `V1 → V2` — custom migration: существующий historical cache переносится в `Application Support/HistoricalMarketCache/cache-v1.json`, затем старые строки удаляются из SwiftData.
- Основная БД теперь содержит только бизнес-сущности: Journal, Calibration, Backtest, TeamRating, LineSnapshot и tuning/config события.
- Historical cache имеет отдельный формат с `formatVersion`, атомарной записью и buffered upsert каждые 25 изменений; критические enrichment/failure-события сохраняются сразу.
- `BacktestService` больше не зависит от `ModelContext` для historical cache.
- Контейнер SwiftData создаётся через `SchemaMigrationPlan`, поэтому дальнейшие изменения должны добавляться новой версией схемы, а не неявно.

Проверка W2 должна выполняться на чистой установке и поверх существующей тестовой базы: приложение должно стартовать, старый Journal/Backtest/TeamRating сохраниться, а исторический cache после миграции быть доступен Авто → обогащению.
