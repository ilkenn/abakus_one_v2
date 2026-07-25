import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/campaign_model.dart';

class CampaignsNotifier extends Notifier<List<CampaignModel>> {
  @override
  List<CampaignModel> build() {
    return const [
      CampaignModel(
        id: 'camp_1',
        title: 'Tüm Kaselerde %10 İndirim!',
        description:
            'Hafta içine özel tüm lezzetli bowl kaselerinde geçerli indirim fırsatı.',
        endDate: '31.12.2026',
        campaignType: CampaignType.percentage,
        couponCode: 'ABAKUS10',
        minimumOrderAmount: 0.0,
        discountValue: 10.0,
        isActive: true,
        isClaimed: false,
      ),
      CampaignModel(
        id: 'camp_2',
        title: 'İlk Siparişe 100 TL Hediye',
        description:
            'Abaküs Bowl ailesine katılan herkesin ilk lezzet deneyimine bizden destek.',
        endDate: '30.11.2026',
        campaignType: CampaignType.amount,
        couponCode: 'ILKSIPARIS',
        minimumOrderAmount: 250.0,
        discountValue: 100.0,
        isActive: true,
        isClaimed: false,
      ),
      CampaignModel(
        id: 'camp_3',
        title: 'Bedava Teslimat Ayrıcalığı',
        description:
            'Belirli tutarın üzerindeki tüm siparişlerinizde kurye ücretini sıfırlıyoruz.',
        endDate: '15.10.2026',
        campaignType: CampaignType.freeDelivery,
        couponCode: 'UCRETSIZ',
        minimumOrderAmount: 200.0,
        discountValue: 29.0,
        isActive: true,
        isClaimed: false,
      ),
      CampaignModel(
        id: 'camp_4',
        title: 'Geçmiş Yaz Sonu Festivali',
        description:
            'Yaz aylarına veda ederken sepetini dolduranlara özel kaçırılmayacak fırsat.',
        endDate: '01.06.2026',
        campaignType: CampaignType.percentage,
        couponCode: 'YAZBITTI',
        minimumOrderAmount: 150.0,
        discountValue: 15.0,
        isActive: false,
        isClaimed: false,
      ),
    ];
  }

  void claimCoupon(String id) {
    state = [
      for (final camp in state)
        if (camp.id == id) camp.copyWith(isClaimed: true) else camp,
    ];
  }
}

final campaignsProvider =
    NotifierProvider<CampaignsNotifier, List<CampaignModel>>(() {
  return CampaignsNotifier();
});
