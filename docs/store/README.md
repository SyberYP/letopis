# Материалы для RuStore и Google Play

Всё, что нужно для карточки приложения. Публикация — только по явному «да» автора.

| Файл | Что |
|---|---|
| `icon-512.png` | Иконка 512×512, без прозрачности (магазин сам скругляет углы) |
| `feature-1024x500.png` | Баннер Google Play |
| `phone/1-timeline.png`, `10-tiles.png`, `2-entry.png`, `3-editor.png`, `4-calendar.png`, `11-stats.png`, `7-lock.png`, `8-timeline-dark.png` | Скриншоты RuStore 1080×1920 (9:16, в этом порядке) |
| `../screenshots/en/…` | Те же скриншоты на английском (README, Google Play для других стран) |
| `build/app/outputs/flutter-apk/app-rustore-release.apk` | Сборка для загрузки: `flutter build apk --release --flavor rustore` (нужен `android/key.properties`) |
| <https://letopis.recalltwin.com/privacy/> | Политика конфиденциальности (исходник `deploy/privacy.html`) |

- Пакет: `com.bylinsky.letopis`. Версия 1.4.2 (versionCode 9). minSdk 24, targetSdk 36.
- Категории RuStore: «Образ жизни» и «Полезные инструменты»; Google Play: Lifestyle.
- Цена: бесплатно, без рекламы. Встроенные покупки (RuStore) — только добровольная поддержка автора, ничего не открывают.
- Почта для связи (карточка, политика, SECURITY.md): sybberr@gmail.com.
- Разработчик: Александр Былинский (Alexander Bylinsky).
- Ключ загрузки: `~/.letopis/letopis-upload.jks`, alias `upload`.
  SHA-256 сертификата: `99:97:A4:16:64:F1:54:0A:66:92:92:DD:F2:09:E9:5C:73:A6:C4:E7:70:8A:F5:4E:11:98:F4:2A:7D:0C:1E:25`.

## Тексты карточки — русский

**Название** (≤ 50): Летопись — личный дневник

**Краткое описание** (≤ 80):
Дневник с шифрованием: записи, фото, голос и теги. Без рекламы и регистрации.

**Полное описание** (≤ 4000):

Летопись — дневник, который остаётся только вашим. Все записи хранятся на телефоне в зашифрованном виде
(AES-256), ключ — ваш пароль. Ни регистрации, ни рекламы, ни аналитики.

Записывайте быстро
• Открыли — нажали «Новая запись» — пишете. Дата и время ставятся сами.
• Форматирование Markdown: заголовки, списки, чек-листы, цитаты.
• Фото, видео, голосовые заметки и файлы прямо в записи.
• Теги: #хэштегом в тексте или чипами. По желанию — подбор тегов нейросетью (ваш ключ OpenRouter или
  любого совместимого сервиса).
• Настроение дня — по желанию.

Перечитывайте
• Лента по месяцам — карточками или плитками.
• «В этот день» — что вы писали год, три, десять лет назад.
• Календарь, поиск по тексту и тегам.
• Статистика: сколько записей и слов, серии дней подряд.

Ваши данные — ваши
• Шифрование AES-256-GCM, ключ из пароля через Argon2id.
• Разблокировка отпечатком, автоблокировка, запрет скриншотов.
• Корзина: удалённую запись можно вернуть в течение 30 дней.
• Резервная копия и второй телефон — через ваше облако (Яндекс Диск, Облако Mail.ru, Nextcloud — по
  WebDAV) или репозиторий GitHub; записи уходят туда зашифрованными.
• Экспорт в PDF — книга для чтения и печати: год или одна запись, с фотографиями.
• Экспорт всего дневника в ZIP с обычными Markdown-файлами.
• Импорт старого дневника из текстовой выгрузки и MyDiary.

Все функции бесплатны. Поддержка автора ничего не открывает.

Важно: пароль нельзя восстановить. Если вы его забудете, записи не откроет никто — ни вы, ни мы.

**Что нового в 1.4.2**:
Добавлена добровольная поддержка автора через RuStore. Все функции остаются бесплатными, покупка ничего не
открывает.

**Что нового в 1.4.1**:
Исправлена автоблокировка при сворачивании и быстром повторном открытии приложения.

**Что нового в 1.4.0**:
Выбор шрифта: семь вариантов, включая рукописный. 15 языков интерфейса — от китайского и хинди до арабского
(справа налево). PDF печатает арабский, хинди и другие письменности системными шрифтами телефона.

**Что нового в 1.3.0**:
Синхронизация и восстановление через ваше облако (Яндекс Диск, Облако Mail.ru, Nextcloud — по WebDAV),
экспорт в PDF — весь дневник, год или одна запись, с фотографиями.

## Store listing — English

**Title** (≤ 30): Letopis — Private Diary

**Short description** (≤ 80):
Encrypted diary with photos, voice notes and tags. No ads, no sign-up.

**Full description** (≤ 4000):

Letopis is a diary that stays yours. Every entry is stored on your phone encrypted (AES-256), and the key
is your password. No sign-up, no ads, no analytics.

Write fast
• Open, tap "New entry", write. Date and time are set for you.
• Markdown formatting: headings, lists, checklists, quotes.
• Photos, videos, voice notes and files right inside an entry.
• Tags as #hashtags or chips; optional AI tag suggestions with your own OpenRouter (or compatible) key.
• Optional mood of the day.

Look back
• Timeline by month, as cards or tiles.
• "On this day": what you wrote one, three, ten years ago.
• Calendar, search by text and tags.
• Statistics: entries, words, day streaks.

Your data is yours
• AES-256-GCM encryption, key derived from your password with Argon2id.
• Fingerprint unlock, auto-lock, screenshot blocking.
• Trash: bring back a deleted entry within 30 days.
• Backup and a second phone through your own cloud (Yandex Disk, Mail.ru Cloud, Nextcloud — over WebDAV)
  or GitHub repository; entries are uploaded encrypted.
• Export to PDF: a book to read and print, a year or one entry, with photos.
• Export the whole diary as a ZIP of plain Markdown files.

Note: the password cannot be recovered. If you forget it, nobody can open the entries — not you, not us.

## Google Play: Data safety (Безопасность данных)

- По определению Google «сбор» — любая передача данных с устройства приложением, даже на аккаунт самого
  пользователя. Поэтому честный ответ — **Yes, collects** (только по желанию пользователя):
  - *Personal info → Other info*: текст записей (синхронизация с облаком или GitHub — в зашифрованном
    виде; подбор тегов ИИ).
  - *Photos and videos → Photos, Videos*; *Audio → Voice or sound recordings*; *Files and docs*
    (только синхронизация с облаком или GitHub).
  - Для каждого: **optional** (пользователь включает сам), purpose — **App functionality**,
    **not shared** (передача по действию пользователя на его собственный сервис — исключение из «sharing»),
    не обрабатывается эфемерно.
  - Разработчик эти данные не получает — это стоит написать в описании.
- **Is all data encrypted in transit?** — Yes: HTTPS. Исключение — сервер WebDAV в домашней сети по HTTP
  (выбор пользователя, файлы дневника при этом зашифрованы). Перед Google Play решить, оставлять ли его.
- **Can users request data deletion?** — Данные только на устройстве: удаление записи / приложения.
  Учётных записей нет.

## Google Play: прочие анкеты

- **Content rating (IARC):** категория «Utility, Productivity, Communication or Other». Насилия, секса,
  азартных игр нет. Обмена сообщениями между пользователями нет. Пользовательский контент не
  публикуется (личные записи) → ожидаемый рейтинг 3+ / PEGI 3.
- **Target audience:** 18+ (или 13+). Не для детей.
- **Ads:** No ads.
- **App access:** все функции доступны без входа; при первом запуске — создать пароль (любой).
- **Government / financial / health app:** No.
- **Permissions:** `RECORD_AUDIO` — голосовые заметки по нажатию «Голос»; `USE_BIOMETRIC` —
  разблокировка. Камера, медиа, местоположение, контакты не запрашиваются.

## RuStore

- Консоль: компания Bylinsky Games, приложение `2063781757`. Версия 1.4.2 (9) отправлена на модерацию
  04.11.2026, публикация после одобрения — автоматическая на 100% пользователей.
- Загружается APK flavor `rustore`: `flutter build apk --release --flavor rustore` (подписан ключом
  загрузки). Для AAB консоль требует загрузить закрытый ключ на сервер; ключ не отправляем, поэтому используем APK.
  Версия с сайта подписана тем же ключом — установки обновляют друг друга.
- **Поддержка автора (разовые покупки):** заявление с УКЭП принято, опубликованы три товара типа
  «расходуемый»: `support_99` (99 ₽, «Спасибо»), `support_299` (299 ₽, «Большое спасибо»), `support_999`
  (999 ₽, «Огромное спасибо»). Id приложения указан в `android/gradle.properties` → `letopisRustoreAppId`.
  В карточке версии 1.4.2 выбраны «Встроенные покупки → Товары». Тестовую покупку ещё нужно провести на
  Android-устройстве: 04.11.2026 консоль не смогла загрузить историю тестовых платежей, устройства не было.
- В описании для RuStore: «Все функции бесплатны. Поддержка автора ничего не открывает».
- Модерация — до нескольких дней. Те же тексты, иконка 512, скриншоты `phone/` 1080×1920.

## Google Play — порядок

1. Аккаунт разработчика ($25 разово, нужна карта, которую принимает Google, и проверка личности).
2. Личный аккаунт, созданный после 13.11.2023: **закрытый тест — минимум 12 тестировщиков, 14 дней
   подряд**, только потом заявка на продакшен.
3. Play App Signing: загрузить AAB, подписанный ключом загрузки; ключ подписи хранит Google.
4. Заполнить карточку, Data safety, рейтинг, политику → закрытый тест → продакшен.

## Перед каждым релизом

```bash
flutter analyze && flutter test
# в pubspec.yaml поднять version: X.Y.Z+N (N всегда растёт)
deploy/deploy.sh                                   # сайт: flavor site + version.json
flutter build apk --release --flavor rustore         # RuStore
SCREENSHOTS=1 flutter test test/ui/screenshots_test.dart --update-goldens   # если менялся интерфейс
```
