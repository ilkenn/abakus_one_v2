param(
    [string]$ProjectRoot = "."
)

$ErrorActionPreference = "Stop"

function New-SafeDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "[DIR ] $Path" -ForegroundColor Cyan
    }
}

function New-SafeFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Content = ""
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { New-SafeDirectory -Path $parent }
    if (-not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
        Write-Host "[FILE] $Path" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] $Path zaten mevcut" -ForegroundColor DarkGray
    }
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
Write-Host ""
Write-Host "Abakus One V2 proje yapisi kuruluyor..." -ForegroundColor Yellow
Write-Host "Hedef: $root" -ForegroundColor Yellow
Write-Host ""

$directories = @(
    "assets/images/branding",
    "assets/images/onboarding",
    "assets/images/home",
    "assets/images/menu",
    "assets/images/products",
    "assets/images/campaigns",
    "assets/images/loyalty",
    "assets/images/profile",
    "assets/images/placeholders",
    "assets/icons",
    "assets/animations",
    "assets/fonts",
    "lib/bootstrap",
    "lib/core/config",
    "lib/core/router",
    "lib/core/theme",
    "lib/core/services/auth",
    "lib/core/services/database",
    "lib/core/services/storage",
    "lib/core/services/notifications",
    "lib/core/services/analytics",
    "lib/core/services/location",
    "lib/core/errors",
    "lib/core/extensions",
    "lib/core/utils",
    "lib/shared/widgets/buttons",
    "lib/shared/widgets/cards",
    "lib/shared/widgets/inputs",
    "lib/shared/widgets/feedback",
    "lib/shared/widgets/images",
    "lib/shared/widgets/layout",
    "lib/shared/models",
    "lib/features/splash/data",
    "lib/features/splash/domain",
    "lib/features/splash/presentation/screens",
    "lib/features/splash/presentation/controllers",
    "lib/features/splash/presentation/widgets",
    "lib/features/onboarding/data",
    "lib/features/onboarding/domain",
    "lib/features/onboarding/presentation/screens",
    "lib/features/onboarding/presentation/controllers",
    "lib/features/onboarding/presentation/widgets",
    "lib/features/auth/data/datasources",
    "lib/features/auth/data/models",
    "lib/features/auth/data/repositories",
    "lib/features/auth/domain/entities",
    "lib/features/auth/domain/repositories",
    "lib/features/auth/domain/usecases",
    "lib/features/auth/presentation/screens",
    "lib/features/auth/presentation/controllers",
    "lib/features/auth/presentation/widgets",
    "lib/features/home/data",
    "lib/features/home/domain",
    "lib/features/home/presentation/screens",
    "lib/features/home/presentation/controllers",
    "lib/features/home/presentation/widgets",
    "lib/features/menu/data/datasources",
    "lib/features/menu/data/models",
    "lib/features/menu/data/repositories",
    "lib/features/menu/domain/entities",
    "lib/features/menu/domain/repositories",
    "lib/features/menu/domain/usecases",
    "lib/features/menu/presentation/screens",
    "lib/features/menu/presentation/controllers",
    "lib/features/menu/presentation/widgets",
    "lib/features/bowl_builder/data",
    "lib/features/bowl_builder/domain",
    "lib/features/bowl_builder/presentation/screens",
    "lib/features/bowl_builder/presentation/controllers",
    "lib/features/bowl_builder/presentation/widgets",
    "lib/features/cart/data",
    "lib/features/cart/domain",
    "lib/features/cart/presentation/screens",
    "lib/features/cart/presentation/controllers",
    "lib/features/cart/presentation/widgets",
    "lib/features/checkout/data",
    "lib/features/checkout/domain",
    "lib/features/checkout/presentation/screens",
    "lib/features/checkout/presentation/controllers",
    "lib/features/checkout/presentation/widgets",
    "lib/features/orders/data",
    "lib/features/orders/domain",
    "lib/features/orders/presentation/screens",
    "lib/features/orders/presentation/controllers",
    "lib/features/orders/presentation/widgets",
    "lib/features/loyalty/data",
    "lib/features/loyalty/domain",
    "lib/features/loyalty/presentation/screens",
    "lib/features/loyalty/presentation/controllers",
    "lib/features/loyalty/presentation/widgets",
    "lib/features/campaigns/data",
    "lib/features/campaigns/domain",
    "lib/features/campaigns/presentation/screens",
    "lib/features/campaigns/presentation/controllers",
    "lib/features/campaigns/presentation/widgets",
    "lib/features/reservations/data",
    "lib/features/reservations/domain",
    "lib/features/reservations/presentation/screens",
    "lib/features/reservations/presentation/controllers",
    "lib/features/reservations/presentation/widgets",
    "lib/features/qr/data",
    "lib/features/qr/domain",
    "lib/features/qr/presentation/screens",
    "lib/features/qr/presentation/controllers",
    "lib/features/qr/presentation/widgets",
    "lib/features/profile/data",
    "lib/features/profile/domain",
    "lib/features/profile/presentation/screens",
    "lib/features/profile/presentation/controllers",
    "lib/features/profile/presentation/widgets",
    "lib/features/feedback/data",
    "lib/features/feedback/domain",
    "lib/features/feedback/presentation/screens",
    "lib/features/feedback/presentation/controllers",
    "lib/features/feedback/presentation/widgets",
    "lib/features/game/data",
    "lib/features/game/domain",
    "lib/features/game/presentation/screens",
    "lib/features/game/presentation/controllers",
    "lib/features/game/presentation/widgets",
    "lib/features/admin/data/datasources",
    "lib/features/admin/data/models",
    "lib/features/admin/data/repositories",
    "lib/features/admin/domain/entities",
    "lib/features/admin/domain/repositories",
    "lib/features/admin/domain/usecases",
    "lib/features/admin/presentation/screens",
    "lib/features/admin/presentation/controllers",
    "lib/features/admin/presentation/widgets",
    "lib/l10n",
    "test/core",
    "test/shared",
    "test/features",
    "integration_test"
)

$files = @(
    "lib/main.dart",
    "lib/app.dart",
    "lib/bootstrap/app_bootstrap.dart",
    "lib/bootstrap/app_environment.dart",
    "lib/core/config/app_constants.dart",
    "lib/core/config/app_environment_config.dart",
    "lib/core/config/asset_paths.dart",
    "lib/core/router/app_router.dart",
    "lib/core/router/app_routes.dart",
    "lib/core/router/app_shell.dart",
    "lib/core/theme/app_theme.dart",
    "lib/core/theme/app_colors.dart",
    "lib/core/theme/app_typography.dart",
    "lib/core/theme/app_spacing.dart",
    "lib/core/theme/app_radius.dart",
    "lib/core/theme/app_shadows.dart",
    "lib/core/errors/app_exception.dart",
    "lib/core/errors/failure.dart",
    "lib/core/errors/error_mapper.dart",
    "lib/core/extensions/context_extensions.dart",
    "lib/core/extensions/date_extensions.dart",
    "lib/core/extensions/string_extensions.dart",
    "lib/core/utils/validators.dart",
    "lib/core/utils/formatters.dart",
    "lib/core/utils/debouncer.dart",
    "lib/shared/widgets/buttons/primary_button.dart",
    "lib/shared/widgets/buttons/secondary_button.dart",
    "lib/shared/widgets/buttons/icon_action_button.dart",
    "lib/shared/widgets/cards/app_card.dart",
    "lib/shared/widgets/cards/glass_card.dart",
    "lib/shared/widgets/inputs/app_text_field.dart",
    "lib/shared/widgets/inputs/phone_text_field.dart",
    "lib/shared/widgets/inputs/otp_input.dart",
    "lib/shared/widgets/feedback/loading_view.dart",
    "lib/shared/widgets/feedback/empty_view.dart",
    "lib/shared/widgets/feedback/error_view.dart",
    "lib/shared/widgets/images/network_image_view.dart",
    "lib/shared/widgets/images/app_avatar.dart",
    "lib/shared/widgets/layout/app_scaffold.dart",
    "lib/shared/widgets/layout/app_section_header.dart",
    "lib/shared/widgets/layout/responsive_container.dart",
    "lib/shared/models/app_user.dart",
    "lib/shared/models/branch.dart",
    "lib/shared/models/app_result.dart",
    "lib/features/splash/presentation/screens/splash_screen.dart",
    "lib/features/auth/presentation/screens/login_screen.dart",
    "lib/features/auth/presentation/screens/otp_screen.dart",
    "lib/features/home/presentation/screens/home_screen.dart",
    "lib/features/home/presentation/widgets/home_header.dart",
    "lib/features/home/presentation/widgets/loyalty_summary_card.dart",
    "lib/features/home/presentation/widgets/campaign_carousel.dart",
    "lib/features/home/presentation/widgets/quick_actions.dart",
    "lib/features/home/presentation/widgets/featured_products.dart",
    "lib/features/menu/presentation/screens/menu_screen.dart",
    "lib/features/menu/presentation/screens/product_detail_screen.dart",
    "lib/features/menu/presentation/widgets/category_selector.dart",
    "lib/features/menu/presentation/widgets/product_card.dart",
    "lib/features/menu/presentation/widgets/product_grid.dart",
    "lib/features/menu/presentation/widgets/modifier_selector.dart",
    "lib/features/bowl_builder/presentation/screens/bowl_builder_screen.dart",
    "lib/features/bowl_builder/presentation/widgets/builder_step_header.dart",
    "lib/features/bowl_builder/presentation/widgets/ingredient_card.dart",
    "lib/features/bowl_builder/presentation/widgets/builder_summary.dart",
    "lib/features/bowl_builder/presentation/widgets/builder_progress.dart",
    "lib/features/cart/presentation/screens/cart_screen.dart",
    "lib/features/cart/presentation/widgets/cart_item_tile.dart",
    "lib/features/cart/presentation/widgets/cart_summary.dart",
    "lib/features/cart/presentation/widgets/checkout_button.dart",
    "lib/features/orders/presentation/screens/active_order_screen.dart",
    "lib/features/orders/presentation/screens/order_detail_screen.dart",
    "lib/features/orders/presentation/screens/order_history_screen.dart",
    "lib/features/loyalty/presentation/screens/loyalty_screen.dart",
    "lib/features/loyalty/presentation/screens/beads_history_screen.dart",
    "lib/features/loyalty/presentation/widgets/abacus_card.dart",
    "lib/features/loyalty/presentation/widgets/reward_card.dart",
    "lib/features/loyalty/presentation/widgets/loyalty_progress.dart",
    "lib/features/campaigns/presentation/screens/campaigns_screen.dart",
    "lib/features/campaigns/presentation/screens/campaign_detail_screen.dart",
    "lib/features/reservations/presentation/screens/reservation_screen.dart",
    "lib/features/qr/presentation/screens/qr_scanner_screen.dart",
    "lib/features/qr/presentation/screens/personal_qr_screen.dart",
    "lib/features/profile/presentation/screens/profile_screen.dart",
    "lib/features/profile/presentation/screens/edit_profile_screen.dart",
    "lib/features/profile/presentation/screens/settings_screen.dart",
    "lib/features/game/presentation/screens/fortune_wheel_screen.dart",
    "lib/features/admin/presentation/screens/admin_dashboard_screen.dart",
    "lib/features/admin/presentation/screens/product_management_screen.dart",
    "lib/features/admin/presentation/screens/campaign_management_screen.dart",
    "lib/features/admin/presentation/screens/loyalty_management_screen.dart",
    "lib/features/admin/presentation/screens/table_requests_screen.dart",
    "lib/l10n/app_tr.arb"
)

foreach ($directory in $directories) {
    New-SafeDirectory -Path (Join-Path $root $directory)
}

foreach ($file in $files) {
    New-SafeFile -Path (Join-Path $root $file)
}

$gitKeepDirectories = @(
    "assets/images/branding",
    "assets/images/onboarding",
    "assets/images/home",
    "assets/images/menu",
    "assets/images/products",
    "assets/images/campaigns",
    "assets/images/loyalty",
    "assets/images/profile",
    "assets/images/placeholders",
    "assets/icons",
    "assets/animations",
    "assets/fonts"
)

foreach ($directory in $gitKeepDirectories) {
    New-SafeFile -Path (Join-Path $root "$directory/.gitkeep")
}

Write-Host ""
Write-Host "Kurulum tamamlandi." -ForegroundColor Green
Write-Host "Mevcut dosyalarin uzerine yazilmadi." -ForegroundColor Green
Write-Host ""
Write-Host "Sonraki komutlar:" -ForegroundColor Yellow
Write-Host "  flutter pub get"
Write-Host "  dart format lib"
Write-Host "  flutter analyze"
