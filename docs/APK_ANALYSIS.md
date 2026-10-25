# Разбор `vanilla-AyuGram-lite-20261005.apk`

SHA-256: `04589f0436ba61461d52c225a7acad6c797fd0b2086cf2eca81d99e05df9c740`

## Как разбирали

- REA (`open_binary`) открыл APK как ZIP: 8415 объектов. Полную распаковку на NTFS
  REA сделать не может: в `res/` есть файлы, имена которых отличаются только регистром
  (`res/-io.webp` / `res/-Io.webp`).
- Декомпиляторы REA (JADX, apktool) на этой машине не настроены (нет `REA_JADX_MCP_JAR`,
  нет Java), поэтому из архива взяты только `classes*.dex` (7 штук), а таблицы
  строк/полей/методов DEX разобраны своим парсером (`tools/dexstr.py` плюс разбор
  `field_ids`/`method_ids`).
- Строковые литералы в коде зашифрованы LSParanoid
  (`org.lsposed.lsparanoid.Deobfuscator$AyuGram4A$TMessagesProj`), но имена
  классов, полей и методов сохранились: ProGuard/R8 их не переименовал.
- Сборка сделана на базе **exteraGram** (настройки exteraGram: `pluginsSafeMode`,
  `glassMessageMenu`, `iconPack` и т.д.) с модулем `com.radolyn.ayugram`.

## Модули AyuGram (`com.radolyn.ayugram`)

| Пакет | Назначение |
|---|---|
| `AyuGhostConfig`, `GhostModeSettings`, `controllers/AyuGhostController` | Режим призрака, настройки отдельно для каждого аккаунта |
| `controllers/AyuMessagesController`, `controllers/messages/*` | Сохранение удалённых и отредактированных сообщений |
| `database/*` (Room, схема v35) | Локальная БД: `DeletedMessage`, `EditedMessage`, `DeletedDialog`, `RegexFilter`, `Spy*` |
| `controllers/AyuSpyController`, `entities/Spy*` | Локальное «последний раз в сети» и время прочтения |
| `controllers/AyuFilterController`, `utils/filters/*` | Regex-фильтры сообщений и теневой бан (shadow ban) |
| `AyuLocalPremiumConfig` | Локальный Premium: цвета, эмодзи-статус, метки папок |
| `AyuSaveExclusions`, `AyuGhostExclusions` | Исключения для отдельных чатов |
| `ui/AyuMessageHistory` | Экран истории правок сообщения |
| `utils/AyuForward`, `AyuRichForward` | Пересылка из чатов с запретом копирования |
| `utils/network/AyuAuthLayer177`, `TLRPCWrappedBypass` | Подмена клиента при входе (`loginClientSpoof`) |

### Режим призрака (`GhostModeSettings`, на аккаунт `userId`)

| Поле | Смысл |
|---|---|
| `sendReadMessagePackets` | Отправлять серверу отметку о прочтении (`messages.readHistory`, `channels.readHistory`, `readDiscussion`) |
| `sendReadStoryPackets` | Отправлять просмотр историй (`stories.readStories`, `incrementStoryViews`) |
| `sendOnlinePackets` | Отправлять «в сети» (`account.updateStatus offline=false`) |
| `sendUploadProgress` | Отправлять «печатает…» и «отправляет файл» (`messages.setTyping`) |
| `sendOfflinePacketAfterOnline` | Сразу после «в сети» отправлять «не в сети» |
| `markReadAfterAction` | Помечать прочитанным, когда пользователь сам пишет или реагирует |
| `useScheduledMessages` | Отправлять как отложенное (+12 с), чтобы не появляться в сети |
| `sendWithoutSound` (int) | Без звука: никогда / всегда / только в режиме призрака |
| `suggestGhostModeBeforeViewingStory` | Спрашивать перед открытием истории |
| `*Locked` | Пункт заблокирован глобальным переопределением |

### Основной конфиг `AyuConfig`

Сохранение: `saveDeletedMessages`, `saveMessagesHistory` (правки), `saveMedia` с
делением на `saveMediaIn{Private,Public}{Chats,Groups,Channels}` и лимитами
`saveMediaOnWiFiLimit`, `saveMediaOnCellularDataLimit` и `saveMediaMaxCacheSize`,
`saveForBots`, `saveReadDate`, `saveLocalOnline`, исключения
`saveExclusions{Always,Never,Whitelist}`.

Отображение: `semiTransparentDeletedMessages`, `deletedIcon`, `deletedIconColor`,
`displayGhostStatus`, `showScreenshot`, `hideFromBlocked`, `forceShowDownloadButtons`,
`disableAds`, `localPremium`.

Фильтры: `filtersEnabled`, `regexFiltersInChats`, `shadowBanList`.

Прочее: `walMode`, `keepAliveService`, `loginClientSpoof`, `probeUsingOtherAccounts`,
`disableHook`.

### Схема записи удалённых и отредактированных сообщений (`AyuMessageBase`)

`userId, dialogId, peerId, fromId, topicId, messageId, date, editDate, entityCreateDate,
flags, text, textEntities, groupedId, views, postAuthor, fwd*, reply*, documentType,
documentSerialized, thumbsSerialized, mediaPath, hqThumbPath, mimeType,
replyMarkupSerialized, richMessageSerialized`; у `DeletedMessage` и `EditedMessage`
есть ещё `fakeId`.

## Перенесено в iOS-версию (этот репозиторий)

| Функция | Статус |
|---|---|
| Режим призрака: прочтение, истории, «в сети», «печатает», «не в сети» после «в сети» | ✅ (одни настройки для всех аккаунтов) |
| Сохранение удалённых сообщений (текст и метаданные) и показ с меткой 🗑 | ✅ |
| История правок сообщений | ✅ (атрибут сообщения и окно из контекстного меню) |
| Полупрозрачность удалённых | ✅ |
| Раздел настроек «AyuGram» | ✅ |
| Помечать прочитанным после своего действия (`markReadAfterAction`) | ⏳ |
| Отложенная отправка (`useScheduledMessages`), «без звука» | ⏳ |
| Медиа удалённых сообщений, regex-фильтры, shadow ban, локальный Premium, spy last seen | ⏳ |
| `loginClientSpoof`, FCM/Play Integrity, Android-утилиты | ✖ (к iOS не относится) |
