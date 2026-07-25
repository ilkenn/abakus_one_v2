import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnboardingPageNotifier extends Notifier<int> {
  @override
  int build() {
    return 0;
  }

  void setPage(int index) {
    state = index;
  }
}

final onboardingPageProvider = NotifierProvider<OnboardingPageNotifier, int>(
  () {
    return OnboardingPageNotifier();
  },
);

class OnboardingCompleteNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void completeOnboarding() {
    state = true;
  }
}

final onboardingCompleteProvider =
    NotifierProvider<OnboardingCompleteNotifier, bool>(() {
  return OnboardingCompleteNotifier();
});
