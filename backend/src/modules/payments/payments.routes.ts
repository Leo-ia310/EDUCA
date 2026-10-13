import { Router } from "express";

import {
  cancelCharge,
  registerPayment,
} from "./payments.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import { requireAdmin, requireAdminPermission, requireRoles } from "../../middleware/permissions.middleware";

export const paymentsRoutes = Router();

paymentsRoutes.use(authMiddleware);
paymentsRoutes.post("/register", requireRoles(["parent"]), asyncHandler(registerPayment));
paymentsRoutes.post("/cancel-charge", requireAdmin, requireAdminPermission("payments.cancel"), asyncHandler(cancelCharge));
paymentsRoutes.patch("/charges/:chargeId/cancel", requireAdmin, requireAdminPermission("payments.cancel"), asyncHandler(cancelCharge));

