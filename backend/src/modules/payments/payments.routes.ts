import { Router } from "express";

import {
  cancelCharge,
  createCharges,
  getCharge,
  listCharges,
  listConcepts,
  paymentsSummary,
  registerPayment,
  registerPaymentAsAdmin,
} from "./payments.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import { requireAdmin, requireAdminPermission, requireRoles } from "../../middleware/permissions.middleware";

export const paymentsRoutes = Router();

paymentsRoutes.use(authMiddleware);
paymentsRoutes.post("/register", requireRoles(["parent"]), asyncHandler(registerPayment));
paymentsRoutes.post("/cancel-charge", requireAdmin, requireAdminPermission("payments.cancel"), asyncHandler(cancelCharge));
paymentsRoutes.patch("/charges/:chargeId/cancel", requireAdmin, requireAdminPermission("payments.cancel"), asyncHandler(cancelCharge));

// Administración (panel web): lectura, alta de cargos y pago en caja.
paymentsRoutes.get("/summary", requireAdmin, requireAdminPermission("payments.view"), asyncHandler(paymentsSummary));
paymentsRoutes.get("/concepts", requireAdmin, requireAdminPermission("payments.view"), asyncHandler(listConcepts));
paymentsRoutes.get("/charges", requireAdmin, requireAdminPermission("payments.view"), asyncHandler(listCharges));
paymentsRoutes.get("/charges/:chargeId", requireAdmin, requireAdminPermission("payments.view"), asyncHandler(getCharge));
paymentsRoutes.post("/charges", requireAdmin, requireAdminPermission("payments.create"), asyncHandler(createCharges));
paymentsRoutes.post("/charges/:chargeId/payments", requireAdmin, requireAdminPermission("payments.create"), asyncHandler(registerPaymentAsAdmin));
