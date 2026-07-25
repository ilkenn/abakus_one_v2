class HomeMockData {
  const HomeMockData._();

  static const List<String> categories = [
    'Tümü',
    'Popüler Bowllar',
    'Diyet Menüleri',
    'İçecekler',
    'Tatlılar',
  ];

  static const List<Map<String, String>> popularProducts = [
    {
      'name': 'Abaküs Özel Bowl',
      'price': '180 TL',
      'desc': 'Somon, avokado, kinoa, taze yeşillikler',
    },
    {
      'name': 'Tavuklu Kinoa Bowl',
      'price': '150 TL',
      'desc': 'Izgara tavuk, kinoa, fırın sebzeler',
    },
    {
      'name': 'Fit Vegan Bowl',
      'price': '140 TL',
      'desc': 'Nohut, humus, falafel, mor lahana',
    },
  ];

  static const List<Map<String, String>> campaigns = [
    {
      'title': 'İlk Siparişe Özel!',
      'desc': 'Kendi bowlunu yarat, %20 indirim kazan.',
    },
    {
      'title': 'Sadakat Günleri',
      'desc': 'Bugün yapacağın bowl siparişine 2 kat boncuk!',
    },
  ];
}
