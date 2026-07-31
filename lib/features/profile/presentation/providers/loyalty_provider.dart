import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/loyalty_campaign_model.dart';
import '../../domain/models/loyalty_history_model.dart';
import '../../domain/models/loyalty_level.dart';
import '../../domain/models/loyalty_reward_model.dart';
import '../../domain/models/loyalty_task_model.dart';

class LoyaltyState {
  final int currentBalance;
  final List<LoyaltyHistoryModel> history;
  final List<LoyaltyRewardModel> rewards;
  final List<LoyaltyTaskModel> tasks;
  final List<LoyaltyCampaignModel> campaigns;

  /// Whether today's "Şans Çarkını Çevir" spin is still available — resets
  /// to `true` externally once a day in a real backend; nothing in this
  /// client re-arms it on its own (no clock/day-boundary logic exists yet).
  final bool dailySpinAvailable;

  /// The points won on the most recent spin, or `null` before the first
  /// spin this session.
  final int? lastSpinReward;

  const LoyaltyState({
    required this.currentBalance,
    required this.history,
    this.rewards = const [],
    this.tasks = const [],
    this.campaigns = const [],
    this.dailySpinAvailable = true,
    this.lastSpinReward,
  });

  /// The tier [currentBalance] currently falls into — see [LoyaltyLevelInfo].
  LoyaltyLevel get level => LoyaltyLevelInfo.forBalance(currentBalance);

  /// The next tier up, or `null` if already at the top tier.
  LoyaltyLevel? get nextLevel => LoyaltyLevelInfo.next(level);

  /// How many more Boncuk are needed to reach [nextLevel]. `0` if already at
  /// the top tier.
  int get pointsToNextLevel {
    final next = nextLevel;
    if (next == null) return 0;
    return (LoyaltyLevelInfo.thresholdFor(next) - currentBalance).clamp(
      0,
      LoyaltyLevelInfo.thresholdFor(next),
    );
  }

  LoyaltyState copyWith({
    int? currentBalance,
    List<LoyaltyHistoryModel>? history,
    List<LoyaltyRewardModel>? rewards,
    List<LoyaltyTaskModel>? tasks,
    List<LoyaltyCampaignModel>? campaigns,
    bool? dailySpinAvailable,
    int? lastSpinReward,
  }) {
    return LoyaltyState(
      currentBalance: currentBalance ?? this.currentBalance,
      history: history ?? this.history,
      rewards: rewards ?? this.rewards,
      tasks: tasks ?? this.tasks,
      campaigns: campaigns ?? this.campaigns,
      dailySpinAvailable: dailySpinAvailable ?? this.dailySpinAvailable,
      lastSpinReward: lastSpinReward ?? this.lastSpinReward,
    );
  }
}

/// The fixed set of point values the "Şans Çarkını Çevir" wheel can land
/// on — a temporary, isolated placeholder (see `LoyaltyNotifier.spinWheel`
/// doc) until real wheel-odds configuration exists.
const List<int> kSpinWheelSegments = [5, 10, 5, 15, 20, 5, 10, 50];

/// **Sprint 5E note (`docs/decisions.md` ADR-022)**: [build]'s initial state
/// below is hardcoded mock seed data (balance, dates, history) — there is
/// no backend for the Boncuk points program. It is deliberately confined to
/// this one notifier rather than scattered across widgets, so the mock
/// boundary is a single, clearly-isolated place: nothing outside this class
/// treats these values as authoritative, and every other Phase 5E screen
/// (e.g. the CRM Visit Passport) sources its data from real domain use
/// cases instead.
class LoyaltyNotifier extends Notifier<LoyaltyState> {
  @override
  LoyaltyState build() {
    return const LoyaltyState(
      currentBalance: 320,
      history: [
        LoyaltyHistoryModel(
          id: 'h_1',
          title: 'Protein Bowl Siparişi',
          date: '17.07.2026',
          points: 40,
          isEarned: true,
        ),
        LoyaltyHistoryModel(
          id: 'h_2',
          title: 'Detox Juice Siparişi',
          date: '12.07.2026',
          points: 15,
          isEarned: true,
        ),
        LoyaltyHistoryModel(
          id: 'h_3',
          title: 'Ücretsiz İçecek Ödülü',
          date: '01.07.2026',
          points: 100,
          isEarned: false,
        ),
      ],
      rewards: [
        LoyaltyRewardModel(
          id: 'reward_drink',
          title: 'İçecek Ödülü',
          description: 'Dilediğin soğuk içecek',
          cost: 50,
        ),
        LoyaltyRewardModel(
          id: 'reward_soup',
          title: 'Çorba Ödülü',
          description: 'Günün çorbası bizden',
          cost: 100,
        ),
        LoyaltyRewardModel(
          id: 'reward_dessert',
          title: 'Tatlı Ödülü',
          description: 'Tatlı toplardan 3 adet',
          cost: 150,
        ),
        LoyaltyRewardModel(
          id: 'reward_bowl',
          title: 'Bowl Ödülü',
          description: 'Seçili bowl çeşitlerinde geçerli',
          cost: 250,
        ),
      ],
      tasks: [
        LoyaltyTaskModel(
          id: 'task_order_bowl',
          title: '1 Bowl Sipariş Ver',
          rewardPoints: 20,
          progressCurrent: 0,
          progressTarget: 1,
        ),
        LoyaltyTaskModel(
          id: 'task_qr_order',
          title: 'QR ile Sipariş Ver',
          rewardPoints: 15,
          progressCurrent: 0,
          progressTarget: 1,
        ),
        LoyaltyTaskModel(
          id: 'task_invite_friend',
          title: 'Arkadaşını Davet Et',
          rewardPoints: 50,
          progressCurrent: 0,
          progressTarget: 1,
        ),
        LoyaltyTaskModel(
          id: 'task_two_bowls_today',
          title: 'Bugün 2 Bowl Sipariş Ver',
          rewardPoints: 40,
          progressCurrent: 1,
          progressTarget: 2,
        ),
      ],
      campaigns: [
        LoyaltyCampaignModel(
          id: 'campaign_protein_week',
          title: 'Protein Haftası 💪',
          description: 'Tüm proteinli bowllarda +40 Boncuk!',
          actionLabel: 'Detaylar',
        ),
        LoyaltyCampaignModel(
          id: 'campaign_wheel_day',
          title: 'Çark Günü 🎡',
          description: 'Bugün çarkı çeviren herkes en az +10 Boncuk kazanır!',
          actionLabel: 'Çevir & Kazan',
        ),
        LoyaltyCampaignModel(
          id: 'campaign_bowl_challenge',
          title: 'Bowl Challenge 🏆',
          description: '5 farklı bowl dene, +300 Boncuk kazan!',
          actionLabel: 'Detaylar',
        ),
      ],
    );
  }

  void redeemReward(String rewardTitle, int cost) {
    if (state.currentBalance >= cost) {
      final newHistoryItem = LoyaltyHistoryModel(
        id: 'h_${DateTime.now().millisecondsSinceEpoch}',
        title: '$rewardTitle Kullanımı',
        date: '17.07.2026',
        points: cost,
        isEarned: false,
      );

      state = state.copyWith(
        currentBalance: state.currentBalance - cost,
        history: [newHistoryItem, ...state.history],
      );
    }
  }

  /// Spins the "Şans Çarkını Çevir" wheel once, if today's spin hasn't been
  /// used yet — picks a random value from [kSpinWheelSegments] (a
  /// temporary, isolated placeholder value set; not real prize-odds
  /// configuration), credits it to the balance, records it in history, and
  /// consumes the daily spin. No-ops if [LoyaltyState.dailySpinAvailable] is
  /// already `false`. Returns the points won, or `null` if the spin was
  /// blocked.
  int? spinWheel() {
    if (!state.dailySpinAvailable) return null;

    final reward = kSpinWheelSegments[Random().nextInt(
      kSpinWheelSegments.length,
    )];

    final newHistoryItem = LoyaltyHistoryModel(
      id: 'h_spin_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Şans Çarkı Ödülü',
      date: '17.07.2026',
      points: reward,
      isEarned: true,
    );

    state = state.copyWith(
      currentBalance: state.currentBalance + reward,
      history: [newHistoryItem, ...state.history],
      dailySpinAvailable: false,
      lastSpinReward: reward,
    );
    return reward;
  }
}

final loyaltyProvider = NotifierProvider<LoyaltyNotifier, LoyaltyState>(() {
  return LoyaltyNotifier();
});
