enum AnalyticsEventType {
  appOpened('app_opened'),
  onboardingCompleted('onboarding_completed'),
  loginStarted('login_started'),
  loginCompleted('login_completed'),
  productViewed('product_viewed'),
  productAddedToCart('product_added_to_cart'),
  cartViewed('cart_viewed'),
  checkoutStarted('checkout_started'),
  orderCompleted('order_completed'),
  campaignViewed('campaign_viewed'),
  favoriteAdded('favorite_added'),
  customBowlStarted('custom_bowl_started'),
  customBowlCompleted('custom_bowl_completed');

  final String eventName;
  const AnalyticsEventType(this.eventName);
}
