/// Customer Registration CR.1 — collected once during "Profilini
/// Tamamla". Mirrors `functions/src/completeCustomerProfile.ts`'s own
/// `GENDERS` string set exactly (`.name` is the wire value in both
/// directions).
///
/// [preferNotToSay] is a fully first-class, equally valid choice — never
/// treated as "incomplete" or a fallback default (locked product
/// requirement). Personalization data only — never an authorization
/// input.
enum CustomerGender { female, male, preferNotToSay }

/// Turkish, customer-facing label — "Kadın" / "Erkek" / "Belirtmek istemiyorum".
String customerGenderLabel(CustomerGender gender) {
  switch (gender) {
    case CustomerGender.female:
      return 'Kadın';
    case CustomerGender.male:
      return 'Erkek';
    case CustomerGender.preferNotToSay:
      return 'Belirtmek istemiyorum';
  }
}
