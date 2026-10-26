# Материалы для RuStore и Google Play

Всё, что нужно для карточки приложения. Публикация — только по явному «да» автора.

| Файл | Что |
|---|---|
| `icon-512.png` | Иконка 512×512, без прозрачности (магазин сам скругляет углы) |
| `feature-1024x500.png` | Баннер Google Play |
| `../screenshots/1-timeline.png`, `10-tiles.png`, `2-entry.png`, `3-editor.png`, `4-calendar.png`, `11-stats.png`, `7-lock.png`, `8-timeline-dark.png` | Скриншоты телефона 1080×2340 (в этом порядке) |
| `build/app/outputs/bundle/release/app-release.aab` | Сборка для загрузки: `flutter build appbundle --release` (нужен `android/key.properties`) |
| <https://letopis.recalltwin.com/privacy/> | Политика конфиденциальности (исходник `deploy/privacy.html`) |

- Пакет: `com.bylinsky.letopis`. Версия 1.1.0 (versionCode 2). minSdk 24, targetSdk 36.
- Категория: «Образ жизни» (Google Play: Lifestyle; RuStore: «Образ жизни» или «Продуктивность»).
- Цена: бесплатно, без рекламы, без встроенных покупок.
- Почта для связи (карточка, политика, SECURITY.md): sybberr@gmail.com.
- Разработчик: Александр Былинский (Alexander Bylinsky).
- Ключ загрузки: `~/.letopis/letopis-upload.jks`, alias `upload`.
  SHA-256 сертификата: `99:97:A4:16:64:F1:54:0A:66:92:92:DD:F2:09:E9:5C:73:A6:C4:E7:70:8A:F5:4E:11:98:F4:2A:7D:0C:1E:25`.

## Тексты карточки — русский

**Название** (≤ 30): Летопись — личный дневник

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
• Резервная копия и второй телефон — через ваш собственный репозиторий GitHub, записи уходят туда
  зашифрованными.
• Экспорт всего дневника в ZIP с обычными Markdown-файлами.
• Импорт старого дневника из текстовой выгрузки и MyDiary.

Важно: пароль нельзя восстановить. Если вы его забудете, записи не откроет никто — ни вы, ни мы.

**Что нового в 1.1.0**:
Режим плиток в ленте, корзина на 30 дней с отменой удаления, настроение, статистика, «Поделиться»
вложением, улучшения безопасности.

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
• Backup and a second phone through your own GitHub repository; entries are uploaded encrypted.
• Export the whole diary as a ZIP of plain Markdown files.

Note: the password cannot be recovered. If you forget it, nobody can open the entries — not you, not us.

## Google Play: Data safety (Безопасность данных)

- По определению Google «сбор» — любая передача данных с устройства приложением, даже на аккаунт самого
  пользователя. Поэтому честный ответ — **Yes, collects** (только по желанию пользователя):
  - *Personal info → Other info*: текст записей (синхронизация GitHub, подбор тегов ИИ).
  - *Photos and videos → Photos, Videos*; *Audio → Voice or sound recordings*; *Files and docs*
    (только синхронизация GitHub).
  - Для каждого: **optional** (пользователь включает сам), purpose — **App functionality**,
    **not shared** (передача по действию пользователя на его собственный сервис — исключение из «sharing»),
    не обрабатывается эфемерно.
  - Разработчик эти данные не получает — это стоит написать в описании.
- **Is all data encrypted in transit?** — Yes (HTTPS only).
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

- Регистрация через VK ID, разработчик — физлицо/самозанятый/ИП (уточнить актуальные условия в
  консоли: по публикациям 2026 года платёжные инструменты — только ИП и юрлица, нам они не нужны).
- Загружается AAB или APK из `flutter build apk --release` (подписан ключом загрузки). Версия с сайта
  подписана тем же ключом — установки из RuStore и с сайта обновляют друг друга.
- Модерация — до нескольких дней. Те же тексты, иконка 512, скриншоты.

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
flutter build appbundle --release        # для сторов
flutter build apk --release && deploy/deploy.sh   # для сайта (+ ротация с личного ключа)
SCREENSHOTS=1 flutter test test/ui/screenshots_test.dart --update-goldens   # если менялся интерфейс
```
