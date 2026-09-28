# OverBet 6.2.0 — release hardening

Последняя пачка после W7-W11: production hardening без изменения публичной схемы прогноза.

## Сделано
- SwiftData schema version выровнена с приложением: 6.2.0. Добавлен явный V3 → V4 lightweight migration.
- Диагностика ScanCoordinator теперь отдельно считает матчи, исключённые как friendlies/women, и уже начавшиеся/завершённые.
- Устранена утечка SStats API key в сетевой консоли: URL с query-параметрами больше не печатается.
- Исправлен 429 cooldown: retry не удваивает задержку.
- Keychain хранит API/admin secrets с `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Admin API принимается только по HTTPS.

## Проверка
- Python files: 0
- Swift parse: OK
- Schema 6.2.0 зарегистрирована в migration plan
- Все Swift-файлы присутствуют в project.pbxproj

Реальный xcodebuild/runtime должен быть подтверждён GitHub Actions и установкой IPA.
