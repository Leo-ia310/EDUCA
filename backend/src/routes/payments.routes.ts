import { Router } from "express";

import {
  cancelCharge,
  registerPayment,
} from "../controllers/payments.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";
import { requireAdmin, requireRoles } from "../middleware/permissions.middleware";

export const paymentsRoutes = Router();

paymentsRoutes.use(authMiddleware);
paymentsRoutes.post("/register", requireRoles(["parent"]), asyncHandler(registerPayment));
paymentsRoutes.post("/cancel-charge", requireAdmin, asyncHandler(cancelCharge));
paymentsRoutes.patch("/charges/:chargeId/cancel", requireAdmin, asyncHandler(cancelCharge));
