# Abaküs — Project Tree

> **HISTORICAL (marked 2026-08-26, AP-1).** This document's own listed `docs/` directory (6 files) and
> `lib/features/` list are far smaller than the current repository (23+ `docs/` files; Admin, POS,
> courier, CRM, marketplace, and fraud features all now exist, none listed here). Do not use this
> document as a current project-structure source. Preserved below unedited as a historical record.

Bu belge Gemini'ye mevcut proje sınırlarını ve dosyaların görevlerini anlatır.

```text
abakus_one_v2/
├── android/
├── ios/
├── web/
├── windows/
├── linux/
├── macos/
├── assets/
│   ├── animations/
│   ├── fonts/
│   ├── icons/
│   └── images/
│       ├── branding/
│       ├── campaigns/
│       ├── home/
│       ├── loyalty/
│       ├── menu/
│       ├── onboarding/
│       ├── placeholders/
│       ├── products/
│       └── profile/
├── docs/
│   ├── architecture_bible.md
│   ├── project_tree.md
│   ├── design_system.md
│   ├── gemini_master_prompt.md
│   ├── feature_status.md
│   └── decisions.md
├── integration_test/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── bootstrap/
│   │   ├── app_bootstrap.dart
│   │   └── app_environment.dart
│   ├── core/
│   │   ├── config/
│   │   │   ├── app_constants.dart
│   │   │   ├── app_environment_config.dart
│   │   │   └── asset_paths.dart
│   │   ├── errors/
│   │   │   ├── app_exception.dart
│   │   │   ├── error_mapper.dart
│   │   │   └── failure.dart
│   │   ├── extensions/
│   │   │   ├── context_extensions.dart
│   │   │   ├── date_extensions.dart
│   │   │   └── string_extensions.dart
│   │   ├── router/
│   │   │   ├── app_router.dart
│   │   │   ├── app_routes.dart
│   │   │   └── app_shell.dart
│   │   ├── theme/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_radius.dart
│   │   │   ├── app_shadows.dart
│   │   │   ├── app_spacing.dart
│   │   │   ├── app_theme.dart
│   │   │   └── app_typography.dart
│   │   └── utils/
│   │       ├── debouncer.dart
│   │       ├── formatters.dart
│   │       └── validators.dart
│   ├── shared/
│   │   ├── models/
│   │   │   ├── app_result.dart
│   │   │   ├── app_user.dart
│   │   │   ├── branch.dart
│   │   │   └── restaurant.dart
│   │   └── widgets/
│   │       ├── buttons/
│   │       ├── cards/
│   │       ├── feedback/
│   │       ├── images/
│   │       ├── inputs/
│   │       └── layout/
│   ├── features/
│   │   ├── splash/
│   │   ├── onboarding/
│   │   ├── auth/
│   │   ├── home/
│   │   ├── menu/
│   │   ├── bowl_builder/
│   │   ├── cart/
│   │   ├── checkout/
│   │   ├── orders/
│   │   ├── loyalty/
│   │   ├── campaigns/
│   │   ├── reservations/
│   │   ├── qr/
│   │   ├── profile/
│   │   ├── feedback/
│   │   ├── game/
│   │   └── admin/
│   └── l10n/
│       └── app_tr.arb
├── test/
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
```

## Feature İç Yapısı

Yeni veya genişleyen feature'larda hedef yapı:

```text
feature_name/
├── data/
│   ├── datasources/
│   ├── models/
│   ├── mappers/
│   └── repositories/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
└── presentation/
    ├── controllers/
    ├── screens/
    └── widgets/
```

## Önemli Notlar

- Bu ağaç proje hedefidir; bazı klasörler henüz boş veya oluşturulmamış olabilir.
- Gemini gerçek dosya sistemini görmeden bir dosyanın var olduğunu varsaymamalıdır.
- Görev promptunda yalnızca ilgili alt ağaç ayrıca verilmelidir.
- Mevcut bir dosyanın içeriği sağlanmamışsa Gemini o dosyayı yeniden yazmamalıdır.
- Yeni feature eklenirse bu belge güncellenmelidir.
