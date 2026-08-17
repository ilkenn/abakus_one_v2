/**
 * Server-side display/snapshot metadata for the 7 LOCKED delivery payment
 * methods — Paket Servis P.3. Ported verbatim (not fabricated) from
 * `lib/features/payment/domain/models/payment_method_seed_data.dart`'s
 * real, committed seed entries — the exact 7 ids
 * `deliveryPaymentPolicy.ts`'s `DELIVERY_ENABLED_PAYMENT_METHOD_IDS`
 * already authorizes. Hardcoded rather than loaded from a live Firestore
 * `paymentMethods` catalog because no such collection exists anywhere in
 * this codebase yet (confirmed) — inventing one would be new,
 * unrequested scope; these 7 methods' *display* metadata is not
 * authorization-relevant (only the id-membership check in
 * `deliveryPaymentPolicy.ts` is), so mirroring the real static seed data
 * here is safe and matches this codebase's established
 * "kept in sync by hand, Dart is the source of truth" duplication
 * pattern used everywhere else (`takeawayPricing.ts`, fraud types, etc).
 */

export type PaymentMethodReportingCategory =
  | "cash"
  | "card"
  | "mealCard"
  | "bankTransfer"
  | "giftVoucher"
  | "unknown";

export type PaymentProviderId =
  | "iyzico"
  | "stripe"
  | "adyen"
  | "odeal"
  | "pluxee"
  | "multinet"
  | "setcard"
  | "edenred"
  | "metropolCard";

export interface DeliveryPaymentMethodMetadata {
  id: string;
  displayName: string;
  iconAssetPath: string;
  brandColorValue: number;
  reportingCategory: PaymentMethodReportingCategory;
  providerId: PaymentProviderId | null;
  supportsSplitPaymentAtCapture: boolean;
  supportsRefundAtCapture: boolean;
  requiresReferenceNumberAtCapture: boolean;
  requiresApprovalAtCapture: boolean;
}

export const DELIVERY_PAYMENT_METHOD_CATALOG: Readonly<
  Record<string, DeliveryPaymentMethodMetadata>
> = {
  cash: {
    id: "cash",
    displayName: "Nakit",
    iconAssetPath: "assets/images/payment/cash.png",
    brandColorValue: 0xff2e7d32,
    reportingCategory: "cash",
    providerId: null,
    supportsSplitPaymentAtCapture: true,
    supportsRefundAtCapture: true,
    requiresReferenceNumberAtCapture: false,
    requiresApprovalAtCapture: false,
  },
  credit_card: {
    id: "credit_card",
    displayName: "Kredi/Banka Kartı",
    iconAssetPath: "assets/images/payment/credit_card.png",
    brandColorValue: 0xff1565c0,
    reportingCategory: "card",
    providerId: null,
    supportsSplitPaymentAtCapture: true,
    supportsRefundAtCapture: true,
    requiresReferenceNumberAtCapture: false,
    requiresApprovalAtCapture: false,
  },
  pluxee: {
    id: "pluxee",
    displayName: "Pluxee",
    iconAssetPath: "assets/images/payment/pluxee.png",
    brandColorValue: 0xffee2a7b,
    reportingCategory: "mealCard",
    providerId: "pluxee",
    supportsSplitPaymentAtCapture: true,
    supportsRefundAtCapture: true,
    requiresReferenceNumberAtCapture: false,
    requiresApprovalAtCapture: false,
  },
  multinet: {
    id: "multinet",
    displayName: "Multinet",
    iconAssetPath: "assets/images/payment/multinet.png",
    brandColorValue: 0xfff37021,
    reportingCategory: "mealCard",
    providerId: "multinet",
    supportsSplitPaymentAtCapture: true,
    supportsRefundAtCapture: true,
    requiresReferenceNumberAtCapture: false,
    requiresApprovalAtCapture: false,
  },
  setcard: {
    id: "setcard",
    displayName: "Setcard",
    iconAssetPath: "assets/images/payment/setcard.png",
    brandColorValue: 0xff6a1b9a,
    reportingCategory: "mealCard",
    providerId: "setcard",
    supportsSplitPaymentAtCapture: true,
    supportsRefundAtCapture: true,
    requiresReferenceNumberAtCapture: false,
    requiresApprovalAtCapture: false,
  },
  edenred: {
    id: "edenred",
    displayName: "Edenred",
    iconAssetPath: "assets/images/payment/edenred.png",
    brandColorValue: 0xffe30613,
    reportingCategory: "mealCard",
    providerId: "edenred",
    supportsSplitPaymentAtCapture: true,
    supportsRefundAtCapture: true,
    requiresReferenceNumberAtCapture: false,
    requiresApprovalAtCapture: false,
  },
  metropol_card: {
    id: "metropol_card",
    displayName: "MetropolCard",
    iconAssetPath: "assets/images/payment/metropol_card.png",
    brandColorValue: 0xff00838f,
    reportingCategory: "mealCard",
    providerId: "metropolCard",
    supportsSplitPaymentAtCapture: true,
    supportsRefundAtCapture: true,
    requiresReferenceNumberAtCapture: false,
    requiresApprovalAtCapture: false,
  },
};
