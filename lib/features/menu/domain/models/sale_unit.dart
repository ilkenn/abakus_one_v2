/// How a [MenuProduct] is sold — Adım 4 (2026-11-07), "Tartılı Ürünler İçin
/// Gramaj Giriş Desteği". `piece` (the default, every product defined
/// before this existed) is a whole countable item, exactly today's
/// behavior. `kilogram` marks a product priced per kilogram and sold by a
/// staff-entered or scale-read weight — see `WeightEntryDialog`'s own doc
/// comment for why entering a weight is, for now, deliberately NOT wired
/// into a real priced order line.
enum SaleUnit { piece, kilogram }
