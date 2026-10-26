# Летопись — разработка

[← README](../README.md) · ТЗ — [SPEC.md](SPEC.md) · что сделано и что дальше — [TODO.md](TODO.md) ·
правила для участников и ИИ-агентов — [AGENTS.md](../AGENTS.md)

## Установка и обновление

1. Последняя сборка: <https://letopis.recalltwin.com> — открыть на телефоне и скачать `letopis.apk`.
2. Собрать самому: `flutter build apk --release --flavor site`, выложить: `deploy/deploy.sh` (APK, страница
   скачивания и политика конфиденциальности). Сборка только локальная, GitHub Actions не используется.
3. Новая версия ставится поверх старой, записи сохраняются (см. «Подпись»). Версия с сайта — Android 9+.
   В ней есть кнопка «Настройки → Проверить обновления»: по нажатию спрашивает
   `letopis.recalltwin.com/version.json` и предлагает открыть сайт. Само приложение в сеть не ходит;
   в сборках для сторов кнопки нет (обновляет магазин).

### Варианты сборки (flavors)
| Flavor | Куда | Что отличается | Команда |
|---|---|---|---|
| `site` | letopis.recalltwin.com | «Проверить обновления», «Поддержать» → CloudTips; компоненты RuStore SDK вырезаны из манифеста | `deploy/deploy.sh` |
| `rustore` | RuStore | «Поддержать» → RuStore Pay | `flutter build appbundle --release --flavor rustore` |
| `play` | Google Play (после 15.01.2027) | без обновлений и поддержки; SDK вырезан | `flutter build appbundle --release --flavor play` |

Dart узнаёт вариант через `appFlavor` (`lib/services/channel.dart`).

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

Безопасность — [SECURITY.ru.md](../SECURITY.ru.md). Материалы для сторов — [docs/store/](store/).

```bash
flutter pub get
flutter analyze
flutter test                     # ядро, синхронизация, ИИ, импорт, сценарии интерфейса
SCREENSHOTS=1 flutter test test/ui/screenshots_test.dart --update-goldens   # docs/screenshots/
flutter build apk --release --flavor site   # нужен Android SDK; без --flavor сборка не пойдёт
```

Тест `real export parses completely` разбирает настоящую выгрузку дневника, если рядом лежит
`../источники/дневник/allentries.txt`; в отдельном репозитории он пропускается.

### Подпись
Все release-сборки (`flutter build apk|appbundle --release --flavor …`) подписываются
**ключом загрузки** (`upload`) из `android/key.properties`; сам файл ключа лежит вне репозитория. Без
`key.properties` release-сборка падает. Debug-сборки — стандартным debug-ключом Android.

| Куда | Что | Команда |
|---|---|---|
| RuStore | AAB или APK flavor `rustore` | `flutter build appbundle --release --flavor rustore` |
| Google Play | AAB flavor `play` (Google переподписывает своим ключом, Play App Signing) | `flutter build appbundle --release --flavor play` |
| Сайт | APK flavor `site` + доказательство ротации ключа, подпись v3 (Android 9+) | `deploy/deploy.sh` (сам собирает, вызывает `deploy/sign-site.sh`, пишет `version.json`) |

**Ротация.** До 1.1.1 личные сборки подписывались ключом `letopis-dev.jks` с публичным паролем
`android` (он остался в истории git). С 1.1.1 ключ выведен: `deploy/signing-lineage.bin` — подписанное
старым ключом разрешение перейти на ключ загрузки (APK Signature Scheme v3). Телефон со старой версией
принимает новую как обычное обновление, данные сохраняются; после этого старый ключ обновить
приложение не может (у него нет права отката). Проверено на эмуляторе Android 14, 26.10.2026.
Сайт и RuStore подписаны одним ключом и ставятся друг поверх друга; версия из Google Play — нет (другой ключ).

Формат `key.properties`:

```
storeFile=C:/Users/<имя>/.letopis/letopis-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Ключ загрузки и пароль хранить в менеджере паролей и в резервной копии: без них не выпустить
обновление в RuStore (в Google Play ключ загрузки можно сбросить через поддержку, ключ подписи
приложения хранит Google). Перед переходом на версию из Google Play — синхронизировать с GitHub
или сделать экспорт: её ключ другой, поверх не встанет.

## Поддержка автора: как устроено
Всё в приложении бесплатно, платных функций нет. «Настройки → Поддержать проект»:
- версия с сайта — страница CloudTips (разовый платёж любой суммы картой);
- версия из RuStore — разовые покупки `support_99`, `support_299`, `support_999` через RuStore Pay
  (`lib/services/support.dart`). Покупка ничего не открывает. Нужны: ИП с подключённой монетизацией в
  RuStore Консоли, эти три товара (тип «потребляемый»), id приложения из консоли в
  `android/gradle.properties` → `letopisRustoreAppId`;
- версия для Google Play — кнопки нет (правила Play; выплаты на российские счета закрыты).
