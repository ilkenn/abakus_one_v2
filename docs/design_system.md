# Abaküs — Design System Specification

> Bu belge başlangıç sözleşmesidir. Kesin renk kodları, font ailesi ve ölçüler UI tasarımları incelendikten sonra doldurulacaktır.

## 1. Marka

- Görünen marka adı: **Abaküs**
- Teknik proje adı arayüzde kullanılmaz.
- Marka dili: sıcak, modern, güvenilir, iştah açıcı ve sade
- Tasarım yaklaşımı: güçlü hiyerarşi, temiz alan kullanımı, anlaşılır aksiyonlar

## 2. Token Dosyaları

```text
lib/core/theme/
├── app_colors.dart
├── app_typography.dart
├── app_spacing.dart
├── app_radius.dart
├── app_shadows.dart
└── app_theme.dart
```

## 3. Renk Rolleri

Kesin değerler tasarımdan çıkarılacaktır.

Gerekli roller:

```text
primary
primaryDark
primaryLight
secondary
accent
background
surface
surfaceVariant
textPrimary
textSecondary
textDisabled
border
divider
success
warning
error
info
overlay
scrim
```

Renkler kullanım rolüne göre adlandırılır. `red500`, `green2` gibi anlamsız isimler kullanılmaz.

## 4. Typography Rolleri

```text
displayLarge
displayMedium
headlineLarge
headlineMedium
titleLarge
titleMedium
bodyLarge
bodyMedium
bodySmall
labelLarge
labelMedium
caption
priceLarge
priceMedium
```

Kurallar:

- Font boyutu ekran içinde hard-code edilmez.
- Font ağırlıkları merkezi tanımlanır.
- Metin ölçeklendirmesi erişilebilirliği bozacak şekilde kapatılmaz.
- Fiyat, başlık ve CTA metinleri tutarlı rollere bağlıdır.

## 5. Spacing Sistemi

Başlangıç ölçeği:

```text
xs   = 4
sm   = 8
md   = 12
lg   = 16
xl   = 24
xxl  = 32
xxxl = 48
```

Kesin ölçek tasarımlar incelendikten sonra güncellenebilir.

## 6. Radius Sistemi

```text
small
medium
large
extraLarge
pill
circle
```

Kart, input ve butonlarda ortak token kullanılır.

## 7. Shadow Sistemi

```text
subtle
card
floating
modal
```

Gölgeler minimal ve tutarlı olmalıdır. Ekran içinde yeni `BoxShadow` listeleri oluşturulmaz.

## 8. Butonlar

### Primary
- Ana aksiyon
- Yüksek vurgu
- Loading ve disabled durumu zorunlu

### Secondary
- İkincil aksiyon
- Outline veya düşük vurgu

### Text
- Düşük vurgu
- Navigasyon veya yardımcı aksiyon

### Icon Action
- Tooltip veya erişilebilir semantic label
- Minimum dokunma alanı korunur

Her buton için:

- default
- pressed
- focused
- disabled
- loading

durumları tanımlanır.

## 9. Input Alanları

Gerekli türler:

- Genel text field
- Telefon alanı
- OTP alanı
- Arama alanı
- Açıklama/not alanı
- Select/dropdown alanı

Durumlar:

- normal
- focused
- filled
- disabled
- error
- success gerekirse

## 10. Kartlar

- AppCard
- ProductCard
- CampaignCard
- RewardCard
- LoyaltySummaryCard
- GlassCard yalnızca tasarım gerektiriyorsa

Kartlarda radius, padding, shadow ve border merkezi tokenlarla belirlenir.

## 11. Ekran Durumları

Her veri ekranı için:

- loading
- content
- empty
- error
- refreshing gerekirse

tasarlanır.

## 12. Görsel Kullanımı

- Ağ görsellerinde placeholder ve hata görünümü zorunlu
- Ürün görselleri tutarlı aspect ratio kullanır
- Logo oranı bozulmaz
- Asset yolu `AssetPaths` üzerinden çağrılır
- Düşük çözünürlüklü görsel büyütülmez

## 13. Responsive Kuralları

- Telefon öncelikli
- İçerik maksimum genişliği tablet/web için sınırlanabilir
- Grid kolon sayısı genişliğe göre değişir
- Bottom sheet ve dialog küçük ekranlarda taşmaz
- Klavye görünümünde form erişilebilir kalır

## 14. Erişilebilirlik

- Kontrast kontrol edilir
- Icon-only butonlarda semantic label kullanılır
- Metin büyütme senaryoları düşünülür
- Dokunma alanları yeterli büyüklükte tutulur
- Hata yalnızca renkle anlatılmaz
