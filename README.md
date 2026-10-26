# Летопись

Личный дневник для Android (iOS — позже). Каждая запись — Markdown со временем создания, тегами,
настроением и вложениями (фото, видео, голос, файлы). Всё на устройстве зашифровано. Лента — карточками
или плитками, есть корзина на 30 дней и статистика. Записи можно синхронизировать с
GitHub, теги — ставить вручную или через нейросеть (OpenRouter или любой OpenAI-совместимый API).

![Лента](docs/screenshots/1-timeline.png)

| | | |
|---|---|---|
| ![](docs/screenshots/2-entry.png) | ![](docs/screenshots/3-editor.png) | ![](docs/screenshots/4-calendar.png) |
| ![](docs/screenshots/10-tiles.png) | ![](docs/screenshots/11-stats.png) | ![](docs/screenshots/8-timeline-dark.png) |

ТЗ — [docs/SPEC.md](docs/SPEC.md), что сделано и что дальше — [docs/TODO.md](docs/TODO.md).

## Установка на телефон

1. Последняя сборка: <https://letopis.recalltwin.com> — открыть на телефоне и скачать `letopis.apk`.
2. Собрать самому: `flutter build apk --release`, выложить: `deploy/deploy.sh` (APK, страница
   скачивания и политика конфиденциальности). Сборка только локальная, GitHub Actions не используется.
3. Новая версия ставится поверх старой, записи сохраняются: все сборки подписаны одним ключом
   (`android/app/letopis-dev.jks`, см. «Подпись»).

## Как это устроено

| Что | Где |
|---|---|
| Шифрование: Argon2id → KEK, случайный DEK, AES-256-GCM блоками по 1 МиБ (формат `LTP1`) | `lib/core/crypto.dart`, `lib/core/vault.dart` |
| Запись: Markdown + YAML-шапка, хэштеги, превью | `lib/core/entry.dart`, `lib/core/markdown_io.dart` |
| Хранилище: зашифрованные файлы, индекс для быстрого открытия, вложения, корзина | `lib/core/store.dart` |
| Синхронизация с GitHub, открытое зеркало Markdown | `lib/services/git_remote.dart`, `lib/services/sync.dart` |
| ИИ-теги | `lib/services/ai_tagger.dart` |
| Импорт старого дневника, экспорт ZIP | `lib/services/importer.dart`, `lib/services/exporter.dart` |
| Состояние приложения: блокировка, настройки, синхронизация | `lib/state/app_state.dart` |
| Экраны | `lib/ui/` |
| Тексты интерфейса (ru, en) | `lib/l10n/strings.dart` |
| Запрет скриншотов (`FLAG_SECURE`) | `android/app/src/main/kotlin/.../MainActivity.kt` |

Данные на устройстве (`<app support>/letopis/`):

```
vault.json             соль и параметры Argon2id, завёрнутый ключ данных (без пароля бесполезен)
settings.enc           настройки, ключи API и токен GitHub
index.enc              кэш всех записей для быстрого открытия (не синхронизируется)
trash.enc, trash/      корзина: удалённые записи и их вложения, 30 дней (не синхронизируется)
entries/<uuid>.md.enc  записи
media/<uuid>.enc       вложения
thumbs/<uuid>.enc      миниатюры фото
```

### Синхронизация
- **Зашифрованный режим** (по умолчанию): в папку репозитория уходят те же `.enc`-файлы и `vault.json`.
  Сравнение трёхстороннее по SHA git-блобов (локально, удалённо, на момент прошлой синхронизации).
  Правки в обе стороны; если запись менялась на двух устройствах — побеждает более поздняя, вторая
  версия сохраняется отдельной записью с тегом `#конфликт`. Правка сильнее удаления.
  Новый телефон: «Восстановить из GitHub» на первом экране + пароль.
- **Открытый Markdown** (только отправка): `entries/ГГГГ/ММ/ГГГГ-ММ-ДД-ЧЧММ-заголовок.md` + `media/`.
  Только для приватного репозитория.
- Токен: fine-grained, один репозиторий, *Contents: Read and write*.
- Ограничение GitHub API: файл не больше 95 МБ (длинные видео не уйдут в git).

### Импорт
Настройки → Импорт: текстовая выгрузка дневника («27 Сентября 2026 Воскресенье 01:44 / Заголовок
(Категория) / текст / -----», категория становится тегом), выгрузка MyDiary («2025/05/03 текст»), файлы
`.md`. Дубликаты пропускаются.

## Разработка

Безопасность — [SECURITY.md](SECURITY.md). Материалы для сторов — [docs/store/](docs/store/).

```bash
flutter pub get
flutter analyze
flutter test                     # ядро, синхронизация, ИИ, импорт, сценарии интерфейса
SCREENSHOTS=1 flutter test test/ui/screenshots_test.dart --update-goldens   # docs/screenshots/
flutter build apk --release      # нужен Android SDK
```

Тест `real export parses completely` разбирает настоящую выгрузку дневника, если рядом лежит
`../источники/дневник/allentries.txt`; в отдельном репозитории он пропускается.

### Подпись
Два ключа, выбираются в `android/app/build.gradle.kts` автоматически:

| Сборка | Ключ | Где |
|---|---|---|
| `flutter build apk --release` — личная, для сайта | `android/app/letopis-dev.jks` (пароль `android`, ключ `letopis`) | в репозитории, не секрет |
| `flutter build appbundle --release` или любая с `LETOPIS_STORE=1` — для сторов | ключ загрузки (`upload`) | `android/key.properties` → файл `.jks` вне репозитория |

Без `key.properties` сборка для стора падает, а не подписывается личным ключом. Формат файла:

```
storeFile=C:/Users/<имя>/.letopis/letopis-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Ключ загрузки и пароль хранить в менеджере паролей и в резервной копии: без них не выпустить
обновление в RuStore (в Google Play ключ загрузки можно сбросить через поддержку, ключ подписи
приложения хранит Google). Приложения с разными ключами не ставятся друг поверх друга: перед
переходом с версии с сайта на версию из стора — синхронизировать с GitHub или сделать экспорт.
