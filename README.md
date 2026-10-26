# AyuGram для iOS

Аналог AyuGram на базе открытого [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) (GPL-2.0).
Функции взяты из разбора Android-сборки `vanilla-AyuGram-lite-20261005.apk`, подробности в
[docs/APK_ANALYSIS.md](docs/APK_ANALYSIS.md).

Репозиторий не содержит кода Telegram: в нём только патч к тегу `release-13.0.0`
([patches/0001-ayugram.patch](patches/0001-ayugram.patch)). GitHub Actions скачивает Telegram-iOS,
накладывает патч и собирает `.ipa`.

## Что умеет

**Режим призрака** (Настройки → AyuGram). Пока он включён, на сервер не уходят:
- отметки о прочтении (`readHistory`, `readDiscussion`, `readMessageContents` и др.);
- просмотры историй (`stories.readStories`, `incrementStoryViews`);
- статус «в сети»;
- «печатает…» и статус загрузки.

Есть опция «Не в сети» после «в сети»: если «в сети» всё-таки отправляется, сразу за ним
уходит «не в сети».

**Сохранение сообщений:**
- сообщения, удалённые собеседником, остаются в чате с меткой 🗑 и могут быть полупрозрачными;
- при каждой правке сохраняется прежний текст. Меню сообщения → «История правок».

Всё хранится локально, в базе Telegram на устройстве.

Сообщение сохраняется, только если приложение успело его получить. Свёрнутое приложение iOS
усыпляет через десятки секунд или несколько минут. Опция «Держать в фоне» (Настройки → AyuGram)
проигрывает беззвучное аудио, чтобы iOS не усыпляла приложение и соединение не обрывалось.
Батарея расходуется быстрее. Приложение, закрытое смахиванием, не работает в любом случае.

**Интерфейс:**
- блокировка рекламы: спонсорские сообщения в каналах и реклама в поиске не загружаются (включена по умолчанию);
- скрытие историй: чужие истории убираются из списка чатов и архива, в профиле их можно открыть.

## Сборка через GitHub

1. Создайте на GitHub **приватный** репозиторий и загрузите в него эту папку.
2. Получите `api_id` и `api_hash` на https://my.telegram.org → *API development tools*.
3. В репозитории откройте *Settings → Secrets and variables → Actions* и добавьте секреты
   `TELEGRAM_API_ID` и `TELEGRAM_API_HASH`.
4. *Actions → Build AyuGram iOS → Run workflow*.
5. Когда сборка закончится, скачайте `AyuGram-iOS-*.ipa` из раздела *Artifacts* этого запуска.

Первая сборка идёт долго, 1,5–3 часа. Повторные быстрее благодаря кэшу Bazel.

### Если сборка падает на версии Xcode

Telegram-iOS 13.0.0 рассчитан на Xcode 26.6 (`versions.json`), он есть на раннере `macos-26`.
Workflow выбирает самый новый Xcode на раннере и передаёт `--overrideXcodeVersion`.
Теги 13.1 и новее требуют Xcode 27.1 и API iOS 27.1: на `macos-26` они не собираются
(`value of type 'UIView' has no member 'reservedRegions'`). Для них нужен раннер с Xcode 27
(например `macos-27`, когда он появится на GitHub) и патч, перенесённый на этот тег.

## Установка на iPhone

`.ipa` подписан фейковым сертификатом, перед установкой его нужно переподписать:
- **AltStore / SideStore**: бесплатный Apple ID, подпись на 7 дней, потом приложение нужно обновить;
- **Sideloadly** (Windows/macOS): то же самое; можно сменить bundle id, чтобы AyuGram
  стоял рядом с официальным Telegram;
- **TrollStore**: только на поддерживаемых версиях iOS, без ограничения по сроку.

Пуш-уведомления в переподписанной сборке работать не будут: для них нужен APNs-сертификат,
выданный на тот же bundle id, что у официального клиента.

Если при переподписи не выдана группа приложений `group.<bundle id>`, AyuGram хранит данные в
собственной папке приложения. Тогда не работают расширения: «Поделиться», виджеты и обработка
уведомлений.

## Изменение патча

```sh
git clone --depth 1 --branch release-13.0.0 https://github.com/TelegramMessenger/Telegram-iOS tg
cd tg && git apply ../patches/0001-ayugram.patch
# …правки…
../scripts/make-patch.sh .
```

Код AyuGram в патче:

| Файл | Что делает |
|---|---|
| `submodules/AyuGram/AyuGramSettings` | Настройки (UserDefaults) и список подавляемых TL-функций |
| `TelegramCore/Sources/AyuGram/AyuMessageAttributes.swift` | Атрибуты «удалено» и «история правок» |
| `TelegramCore/.../Network.swift` | Фильтр режима призрака на уровне запросов |
| `TelegramCore/.../ManagedAccountPresence.swift` | Статус «в сети» |
| `TelegramCore/.../AccountStateManagementUtils.swift` | Пометка вместо удаления, запись правок |
| `TelegramCore/.../SyncCore_StandaloneAccountTransaction.swift` | Сохранение атрибутов при обновлении сообщения |
| `SettingsUI/Sources/AyuGram/AyuGramSettingsController.swift` | Экран настроек |
| `ChatMessageBubbleItemNode`, `StringForMessageTimestampStatus` | Полупрозрачность и метка 🗑 |
| `ChatInterfaceStateContextMenus.swift` | Пункт «История правок» |

## Ограничения

- Настройки общие для всех аккаунтов (в AyuGram4A они задаются для каждого аккаунта отдельно).
- Медиа удалённых сообщений остаётся только если оно уже было в кэше.
- Если Telegram заново загрузит историю чата после очистки кэша, удалённые сообщения пропадут.
- Режим призрака не скрывает реакции, ответы и отправку сообщений: это видно собеседнику.
- Скрытие историй не убирает кольца историй вокруг аватарок в списке чатов.
- Не перенесены: отложенная отправка, regex-фильтры, shadow ban, локальный Premium.
