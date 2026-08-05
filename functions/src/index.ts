import { initializeApp } from "firebase-admin/app";

initializeApp();

export { onOrderCreated } from "./onOrderCreated";
export { onOrderCompleted } from "./onOrderCompleted";
export { processAccountDeletion } from "./processAccountDeletion";
