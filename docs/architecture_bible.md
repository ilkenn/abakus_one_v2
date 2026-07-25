# Abaküs — Architecture Bible

## 1. Proje Kimliği

- Müşterinin gördüğü uygulama adı: **Abaküs**
- Flutter proje klasörü: `abakus_one_v2`
- Dart package adı: `abakus_one_v2`
- Ana hedefler: Android ve iOS
- İkincil hedefler: Web; gerekirse yönetim ekranları
- Uygulama dili: Öncelikli Türkçe
- Kod dili: İngilizce
- Dosya adları: `snake_case`
- Sınıf adları: `PascalCase`
- Değişken ve fonksiyonlar: `camelCase`

> Kullanıcıya gösterilen marka adı ile teknik proje adı birbirinden bağımsızdır.
> Arayüzde `abakus_one_v2` yazısı kesinlikle gösterilmez.

---

## 2. Temel Mimari Yaklaşım

Proje **feature-first**, katmanlı ve modüler olarak geliştirilir.

Her özellik kendi sınırları içinde yaşar:

```text
feature/
├── data/
├── domain/
└── presentation/
```

Katmanların görevleri:

### `data`
- API, Firebase veya yerel veri kaynakları
- DTO ve data model sınıfları
- Repository implementasyonları
- Cache ve veri dönüştürme işlemleri

### `domain`
- Entity sınıfları
- Repository arayüzleri
- Use case sınıfları
- İş kuralları

### `presentation`
- Screens
- Feature'a özel widget'lar
- State/controller/provider sınıfları
- Kullanıcı etkileşimleri

Basit özelliklerde ihtiyaç olmayan katmanlar sırf klasör dolsun diye yapay kodla doldurulmaz. Ancak büyüme ihtimali olan özelliklerde bu sınırlar korunur.

---

## 3. Bağımlılık Kuralları

İzin verilen yön:

```text
presentation -> domain
data -> domain
core/shared -> bağımsız
```

Yasaklanan yönler:

```text
domain -> presentation
domain -> data
core -> feature
shared -> feature
feature A -> feature B presentation dosyaları
```

Bir feature başka bir feature'ın ekranını veya özel widget'ını doğrudan import etmez.

Ortak bir yapı gerekiyorsa:

- Genel teknik yapıysa `core/`
- Genel görsel veya model yapısıysa `shared/`
- İş akışı koordinasyonu gerekiyorsa router veya üst seviye orchestration katmanı

kullanılır.

---

## 4. Klasör Sorumlulukları

### `lib/bootstrap`
Uygulama başlatma akışı, environment ve servis initialization işlemleri.

### `lib/core`
Uygulamanın teknik omurgası:

- Config
- Router
- Theme
- Error handling
- Extensions
- Utilities

### `lib/shared`
Birden fazla feature tarafından kullanılan:

- Widget'lar
- Modeller
- Ortak UI parçaları
- Genel yardımcı yapılar

### `lib/features`
İş özellikleri ve ekran akışları.

### `lib/l10n`
Yerelleştirme dosyaları.

---

## 5. State Management

Nihai state management aracı seçilene kadar kod şu kurallara uyar:

- UI içinde iş mantığı tutulmaz.
- `setState` yalnızca küçük ve tamamen yerel UI durumlarında kullanılabilir.
- Ağ isteği, form süreci, kullanıcı oturumu, sepet veya sipariş gibi durumlar controller/provider katmanında tutulur.
- State sınıfları açık durumları temsil eder:
  - initial
  - loading
  - success/data
  - empty
  - error
- Widget içinde servis veya repository örneği oluşturulmaz.
- Global mutable değişken kullanılmaz.

State management kararı `decisions.md` içinde ADR olarak kesinleştirilmeden Gemini paket veya mimari uyduramaz.

---

## 6. Navigation ve Router

- Tüm route isimleri `app_routes.dart` içinde tutulur.
- Router kurulumu `app_router.dart` içinde yapılır.
- Route stringleri ekranlarda hard-code edilmez.
- Ekranlar doğrudan rastgele `MaterialPageRoute` üretmez.
- Parametreler tip güvenli biçimde taşınır.
- Authentication kontrolü router seviyesinde veya merkezi guard mekanizmasında yapılır.
- Bottom navigation yapısı gerekiyorsa `app_shell.dart` üzerinden yönetilir.
- Deep link ve notification navigation daha sonra aynı router üzerinden eklenebilir.

---

## 7. Tasarım Sistemi

UI içinde doğrudan aşağıdaki değerler kullanılmaz:

- Rastgele `Color(...)`
- Rastgele font boyutları
- Rastgele padding/margin değerleri
- Rastgele border radius
- Tekrarlanan shadow tanımları

Bunun yerine:

```text
AppColors
AppTypography
AppSpacing
AppRadius
AppShadows
AppTheme
```

kullanılır.

İstisna yalnızca tasarım sistemine yeni token eklenmesi gerektiğinde mümkündür.

---

## 8. Widget Kuralları

- Bir screen mümkün olduğunca orchestration görevi görür.
- Tekrar kullanılabilir parçalar ayrı widget yapılır.
- Feature'a özel widget ilgili feature altında kalır.
- En az iki farklı feature'da kullanılacak yapı `shared/widgets` altına taşınır.
- Çok küçük ve yalnızca bir yerde kullanılan widget gereksiz yere ayrı dosyaya çıkarılmaz.
- Build metodu okunabilir kalmalıdır.
- Büyük widget ağaçları anlamlı parçalara bölünmelidir.
- Widget constructor'larında mümkün olduğunca `const` kullanılır.
- Kullanıcıya görünen metinler gelecekte localization sistemine taşınabilecek şekilde merkezi tutulur.

---

## 9. Naming Kuralları

Örnekler:

```text
home_screen.dart         -> HomeScreen
product_card.dart        -> ProductCard
cart_controller.dart     -> CartController
order_repository.dart    -> OrderRepository
order_repository_impl.dart -> OrderRepositoryImpl
get_active_order.dart    -> GetActiveOrder
```

Kaçınılacak isimler:

```text
helper.dart
utils2.dart
new_screen.dart
temp.dart
test_widget.dart
common.dart
manager.dart
```

Dosya adı, dosyanın gerçek sorumluluğunu anlatmalıdır.

---

## 10. Model ve Veri Kuralları

- Domain entity ile API DTO aynı şey olmak zorunda değildir.
- JSON parse işlemleri UI katmanında yapılmaz.
- Null değerler rastgele `!` ile zorlanmaz.
- Para değerleri `double` ile kontrolsüz biçimde işlenmez; uygun model veya integer minor unit yaklaşımı değerlendirilir.
- Tarihler ISO 8601 veya merkezi formatter ile yönetilir.
- Enum yerine serbest string kullanımı mümkün olduğunca azaltılır.
- Model dönüşümleri açık mapper fonksiyonlarıyla yapılır.

---

## 11. Hata Yönetimi

- Teknik exception kullanıcıya doğrudan gösterilmez.
- Data katmanındaki hatalar merkezi failure yapısına dönüştürülür.
- Kullanıcı mesajları anlaşılır ve Türkçe olmalıdır.
- Her veri ekranı loading, empty ve error durumlarını ele almalıdır.
- Hata mesajları yalnızca `print` ile bırakılmaz.
- Geliştirme logları üretim davranışından ayrılır.
- Retry mümkünse kullanıcıya sunulur.

---

## 12. Form ve Validation

- Validation fonksiyonları merkezi veya feature'a özel validator katmanında tutulur.
- Telefon, OTP, e-posta ve zorunlu alan kontrolleri tutarlı olmalıdır.
- Form gönderilirken çift tıklama engellenir.
- Loading sırasında ilgili buton devre dışı kalır.
- Hata mesajı alanla ilişkili ve anlaşılır olmalıdır.
- Controller'lar yaşam döngüsünde doğru şekilde dispose edilir.

---

## 13. Asset Kuralları

Asset yolları `asset_paths.dart` üzerinden yönetilir.

Örnek:

```dart
abstract final class AssetPaths {
  static const logo = 'assets/images/branding/logo.png';
}
```

Yasak:

```dart
Image.asset('assets/images/branding/logo.png')
```

Aynı yolun ekranlarda tekrar tekrar yazılması.

Asset klasörleri:

```text
assets/images/branding
assets/images/onboarding
assets/images/home
assets/images/menu
assets/images/products
assets/images/campaigns
assets/images/loyalty
assets/images/profile
assets/images/placeholders
assets/icons
assets/animations
assets/fonts
```

---

## 14. Responsive Tasarım

- Tasarım yalnızca tek telefon ölçüsüne göre yazılmaz.
- Safe area dikkate alınır.
- Klavye açıldığında overflow oluşmamalıdır.
- Küçük ekranlarda metin ve butonlar taşmamalıdır.
- Tablet ve web için gerektiğinde maksimum içerik genişliği kullanılır.
- Sabit yükseklikler zorunlu olmadıkça tercih edilmez.
- `Expanded`, `Flexible`, `LayoutBuilder` ve scroll yapıları doğru bağlamda kullanılır.
- Erişilebilir dokunma alanları korunur.

---

## 15. Performans

- Gereksiz rebuild azaltılır.
- Mümkün olan widget'lar `const` yapılır.
- Büyük listelerde `ListView.builder` veya uygun lazy yapı kullanılır.
- Ağ görsellerinde placeholder ve error durumu bulunur.
- Aynı veriye gereksiz tekrar istek atılmaz.
- Ağır hesaplama build metodu içinde yapılmaz.
- Controller, animation ve stream kaynakları dispose edilir.
- Gereksiz paket eklenmez.

---

## 16. Güvenlik ve Gizlilik

- API key ve secret değerleri kaynak koda yazılmaz.
- Kullanıcı tokenları güvenli saklama yaklaşımıyla yönetilir.
- Loglarda token, telefon veya kişisel veri basılmaz.
- Admin ekranları yalnızca UI gizleyerek korunmaz; yetki kontrolü backend tarafında da yapılır.
- QR ve kampanya doğrulamaları yalnızca istemciye güvenmez.
- Kullanıcı girdisi doğrulanır.
- Firebase veya API güvenlik kuralları ayrıca tanımlanır.

---

## 17. Test Stratejisi

Minimum beklentiler:

- Kritik iş kuralları için unit test
- Tekrar kullanılan widget'lar için widget test
- Login, sepet ve sipariş gibi ana akışlar için integration test
- Hata, loading ve empty state testleri
- Router davranışı testleri

Bir özellik tamamlandı sayılmadan önce en az:

```text
flutter analyze
flutter test
```

başarılı olmalıdır.

---

## 18. Kod Kalitesi

Kod üretiminden sonra:

```powershell
dart format lib test integration_test
flutter analyze
flutter test
```

çalıştırılır.

Kurallar:

- Analyzer hatası bırakılmaz.
- Kullanılmayan import bırakılmaz.
- TODO yalnızca açıkça onaylanmış gelecek iş için yazılır.
- Placeholder kod tamamlanmış gibi sunulmaz.
- Deprecated API kullanılmaz.
- Paket sürümleri `pubspec.yaml` görülmeden uydurulmaz.
- Mevcut dosya içeriği görülmeden dosya yeniden yazılmaz.

---

## 19. Gemini İçin Değişmez Kurallar

Gemini:

1. Görmediği mevcut dosyanın içeriğini tahmin etmez.
2. İzin verilmemiş dosyayı değiştirmez.
3. Önce oluşturacağı ve değiştireceği dosyaları listeler.
4. Her kod bloğunun üstünde tam dosya yolunu yazar.
5. Var olan mimariyi değiştirmek için açık izin ister.
6. Paket eklemeden önce nedenini açıklar.
7. Hard-coded tasarım değeri eklemez.
8. TODO, sahte servis veya eksik metot bırakmaz.
9. Kodun derlenebilir olması için gerekli tüm importları verir.
10. Sonunda çalıştırılacak kontrol komutlarını yazar.
11. Mevcut dosyanın içeriği verilmediyse replacement üretmez.
12. Belirsizlikte varsayım yapmak yerine açık bir `ASSUMPTION` bölümü yazar.
13. Ürettiği değişiklikleri kısa bir değişiklik özetiyle kapatır.

---

## 20. Definition of Done

Bir görev yalnızca şu koşullarda tamamlanır:

- İstenen davranış uygulanmış
- Mimariye uyulmuş
- Tüm ekran durumları ele alınmış
- UI tasarım sistemini kullanıyor
- Responsive davranış düşünülmüş
- Analyzer hatası yok
- Testler güncellenmiş veya neden gerekmediği açıklanmış
- Feature status güncellenmiş
- Karar değiştiyse decisions.md güncellenmiş
- Gemini değiştirdiği tüm dosyaları açıkça listelemiş
