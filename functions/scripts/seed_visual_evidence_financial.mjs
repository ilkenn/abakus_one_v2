/**
 * One-off, NOT committed-for-production seed to populate real financial
 * data under org-1/branch-ap3vis (the seed_local_admin.js tenant) for
 * AP-4 Wave F visual-evidence capture — real callables only, no direct
 * Firestore writes for anything that has a real write path. Safe to
 * rerun; not part of the build (tsconfig only includes src/**\/*.ts).
 */
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

const PROJECT_ID = 'abakus-one-dev';
const FUNCTIONS_HOST = 'http://127.0.0.1:5001';
const AUTH_HOST = 'http://127.0.0.1:9099';
const fn = (name) => `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/${name}`;

async function callCallable(name, data, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const res = await fetch(fn(name), { method: 'POST', headers, body: JSON.stringify({ data }) });
  const body = await res.json();
  if (res.status !== 200) {
    throw new Error(`${name} failed (${res.status}): ${JSON.stringify(body)}`);
  }
  return body.result;
}

async function signIn(email, password) {
  const res = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await res.json();
  if (!body.idToken) throw new Error(`sign-in failed for ${email}: ${JSON.stringify(body)}`);
  return body.idToken;
}

async function main() {
  const organizationId = 'org-1';
  const branchId = 'branch-ap3vis';
  const managerToken = await signIn('yonetici@abakus.test', 'GorselKabul2026!');
  const cashierToken = await signIn('kasiyer@abakus.test', 'GorselKabul2026!');

  console.log('Requesting device registration (cashier)...');
  const { generateKeyPairSync, sign: cryptoSign } = await import('node:crypto');
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const publicKeyPem = publicKey.export({ type: 'spki', format: 'pem' }).toString();
  const sign = (nonce) => cryptoSign(null, Buffer.from(nonce, 'utf8'), privateKey).toString('base64');

  const reg = await callCallable('requestDeviceRegistration', {
    organizationId, branchId, platform: 'android', publicKeyPem, signatureAlgorithm: 'ed25519', capabilities: ['POS'],
  }, cashierToken);
  const deviceId = reg.deviceId;
  if (reg.approvalRequestId) {
    await callCallable('respondToApprovalRequest', { requestId: reg.approvalRequestId, decision: 'approved' }, managerToken);
  }
  const challenge = await callCallable('requestDeviceChallenge', { organizationId, branchId, deviceId, purpose: 'issue' }, cashierToken);
  const session = await callCallable('issueDeviceSession', {
    organizationId, branchId, deviceId, challengeId: challenge.challengeId, signature: sign(challenge.nonce),
  }, cashierToken);
  const deviceSessionId = session.sessionId;
  const ctx = { organizationId, branchId, deviceId, deviceSessionId };
  console.log('Device session issued:', deviceId);

  // Real cash drawer/session for the Kasa Oturumları tab.
  console.log('Opening cash drawer/session...');
  const drawer = await callCallable('createCashDrawer', { ...ctx, name: 'Görsel Kanıt Kasası' }, managerToken);
  const cashSession = await callCallable('requestCashSessionOpen', {
    ...ctx, drawerId: drawer.drawerId, openingFloatAmountMinorUnits: 50000, currencyCode: 'TRY', reason: 'Görsel kanıt için açılış.',
  }, managerToken);
  console.log('Cash session:', cashSession.sessionId, cashSession.status);

  // The available table (table-ap3vis-1) has no active session by design —
  // open one via the real customer-QR entry point (same callable the real
  // QR flow uses; any authenticated caller may open it, matching Flow #1's
  // own established pattern) before entering a staff order.
  console.log('Opening a table guest session for table-ap3vis-1...');
  const openSession = await callCallable('openTableGuestSession', { token: 'qrtoken-ap3vis-available' }, cashierToken);
  const tableSessionId = openSession.tableSessionId;

  console.log('Submitting staff order...');
  const submit = await callCallable('submitDineInOrder', {
    mode: 'staffEntry', submissionKey: `visual-evidence-${Date.now()}`, ...ctx, tableId: 'table-ap3vis-1',
    items: [{ kind: 'product', productId: 'product-ap3vis-bowl', quantity: 1 }],
    subAccountSelection: { mode: 'staffGeneral' },
  }, cashierToken);
  const orderId = submit.orderId;
  const subAccountId = submit.subAccountId;

  const openCheck = await callCallable('openCheck', { ...ctx, tableSessionId }, cashierToken);
  const checkId = openCheck.checkId;
  await callCallable('splitCheckByProduct', { ...ctx, checkId, subAccountId, sourceOrderId: orderId, sourceLineIndex: 0 }, cashierToken);
  await callCallable('finalizeCheckReadyForPayment', { ...ctx, checkId }, cashierToken);
  const intent = await callCallable('createPaymentIntent', { ...ctx, checkId }, cashierToken);
  const attempt = await callCallable('recordPaymentAttempt', {
    ...ctx, checkId, sessionId: intent.sessionId, tenderType: 'cash', idempotencyKey: `visual-evidence-pay-${Date.now()}`, cashSessionId: cashSession.sessionId,
    allocations: [{ subAccountId, amountMinorUnits: intent.payableAmountMinorUnits }],
  }, cashierToken);
  console.log('Payment attempt:', attempt.attemptId, attempt.status);

  // Real partial refund for the İadeler tab.
  console.log('Requesting partial refund...');
  const refund = await callCallable('requestPaymentRefund', {
    ...ctx, checkId, refundType: 'partial', amountMinorUnits: 1000, reasonCode: 'guestComplaint', reasonMessage: 'Görsel kanıt için kısmi iade.',
  }, cashierToken);
  console.log('Refund requested:', refund.refundId, '- leaving pendingApproval so the İadeler tab shows a real awaiting-approval row.');

  // Real fiscal journal entry in a genuine timedOut/unresolved state (the
  // test-only deterministic adapter's own FORCE_TIMEOUT marker — never
  // reachable outside FUNCTIONS_EMULATOR) for the Fiskal Günlük tab.
  console.log('Recording a FORCE_TIMEOUT fiscal operation...');
  const fiscalOp = await callCallable('recordFiscalOperation', {
    ...ctx, operationType: 'sale', amountMinorUnits: intent.payableAmountMinorUnits, currencyCode: 'TRY',
    idempotencyKey: `visual-evidence-FORCE_TIMEOUT-${Date.now()}`, checkId, paymentAttemptId: attempt.attemptId,
  }, managerToken);
  console.log('Fiscal operation:', fiscalOp.entryId, fiscalOp.status);

  // Real offline lease for the Offline Yetkiler tab.
  console.log('Issuing an offline lease...');
  const lease = await callCallable('issueOfflineLease', { ...ctx }, cashierToken);
  console.log('Offline lease issued:', lease.leaseId);

  console.log('DONE. Real financial data seeded under org-1/branch-ap3vis.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
