# OverBet 6.2.0 — финальный пакет W7–W11

## W7 — StoreKit 2

`SubscriptionService` теперь работает через StoreKit 2: загрузка продукта, проверка `Transaction.currentEntitlements`, обработка `Transaction.updates`, покупка и восстановление. Идентификаторы продукта не выдумываются и не вшиваются в код: они задаются в `Info.plist` через `SBetSubscriptionProductIDs` или временно через окружение `OVERBET_S_BET_PRODUCT_IDS`. Apple рекомендует использовать `currentEntitlements` для определения текущего доступа и проверять транзакции перед выдачей доступа.

Пока массив Product ID пуст, S BET остаётся закрыт — это fail-closed поведение.

## W8 — Server-backed Admin Auth

`AdminAccessService` больше не имеет режима с локальным «секретным паролем». Авторизация проверяется сервером по `GET /v1/admin/me` с `Authorization: Bearer <token>`. Токен сохраняется только после успешного ответа сервера и хранится в Keychain. При HTTP 401/403 credentials удаляются.

В `Info.plist` добавлен `AdminAPIBaseURL`. До подключения реального backend URL Admin остаётся закрытым.

### Контракт ответа

Минимально сервер может вернуть:

```json
{
  "authorized": true,
  "role": "admin",
  "expiresAt": "2026-12-31T23:59:59Z"
}
```

Достаточно `authorized=true` или `role=admin`. `expiresAt` опционален.

## W9 — Admin Console

Admin-консоль теперь дополнительно защищена `AdminAccessService`. При потере серверной авторизации интерфейс автоматически закрывается. Разделы Admin структурированы как `Model Lab`, `Data Health`, `Controls`; существующие backtest, OOS, CLV, Bollinger, correlation, team ratings, live monitor и Self-Tuning остаются внутри Admin.

## W10 — Cleanup

Удалены из Admin-консоли старые дублированные клиентские представления прогноза/журнала и устаревшая логика автодобавления ставки при открытии карточки. Клиентский Journal теперь получает записи из Forecast pipeline, а Admin не дублирует Client UI.

## W11 — CI / verification

CI обновлён до 6.2.0, проверяет:

- отсутствие Python-engine;
- наличие versioned SwiftData migration chain;
- отделение HistoricalMarketCache от SwiftData;
- наличие StoreKit/Admin конфигурации;
- отсутствие очевидных секретов в исходниках;
- версию 6.2.0 итогового bundle.

Реальная `xcodebuild`/runtime-проверка должна выполняться GitHub Actions на macOS.
