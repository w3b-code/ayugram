# AyuGram

Репозиторий разделён по платформам.

| Ветка | Платформа | Содержимое | Результат сборки |
| --- | --- | --- | --- |
| [ios](https://github.com/w3b-code/ayugram/tree/ios) | iPhone / iOS | Патчи Telegram-iOS, настройки AyuGram, исправление App Groups | IPA |
| [desktop](https://github.com/w3b-code/ayugram/tree/desktop) | Windows x64 | Закреплённый AyuGram Desktop 7.2.9, скрипты сборки и упаковки | ZIP с AyuGram.exe |
| main | Обзор | Навигация и входные workflows GitHub Actions | — |

## Собрать приложение

Откройте [Actions](https://github.com/w3b-code/ayugram/actions) и выберите:

- **Build AyuGram iOS** — iPhone; собирается ветка `ios`.
- **Build AyuGram Windows** — Windows x64; собирается ветка `desktop`.

Нажмите **Run workflow**. Можно оставить выбранной ветку `main`:
каждый workflow сам загружает исходники нужной платформы.
Готовые файлы появляются в **Artifacts** после успешного завершения запуска.

Обе версии используют существующие секреты `TELEGRAM_API_ID` и `TELEGRAM_API_HASH`.
Параметр `AYUGRAM_APP_GROUP` относится только к iOS и профилю подписи Feather.
Полные инструкции находятся в README соответствующей ветки.

## Исходники и история

Все изменения прежних веток `fix/ghost-offline-status` и `fix/notification-app-group`
включены в историю `ios`. Разработка для iPhone продолжается в `ios`, для Windows — в `desktop`.

Настольный клиент использует собственную основу C++/Qt, а iPhone — Telegram-iOS и Swift.
Локальные базы, настройки и история удалений между устройствами автоматически не переносятся.
Лицензии и уведомления upstream сохранены вместе с исходниками каждой платформы.
