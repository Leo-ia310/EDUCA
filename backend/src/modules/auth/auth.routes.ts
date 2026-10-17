import { Router } from "express";

import {
  changePassword,
  sendTwoFactorEmailCode,
  resendTwoFactorLogin,
  disableTwoFactor,
  enableTwoFactor,
  login,
  logout,
  recoverPassword,
  resetPassword,
  refresh,
  setupTwoFactor,
  twoFactorStatus,
  verifyTwoFactorLogin,
} from "./auth.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";

export const authRoutes = Router();

authRoutes.post("/login", asyncHandler(login));
authRoutes.post("/2fa/resend-login", asyncHandler(resendTwoFactorLogin));
authRoutes.post("/2fa/verify-login", asyncHandler(verifyTwoFactorLogin));
authRoutes.post("/refresh", asyncHandler(refresh));
authRoutes.post("/recover-password", asyncHandler(recoverPassword));
authRoutes.post("/reset-password", asyncHandler(resetPassword));
authRoutes.get("/2fa/status", authMiddleware, asyncHandler(twoFactorStatus));
authRoutes.post("/2fa/setup", authMiddleware, asyncHandler(setupTwoFactor));
authRoutes.post("/2fa/enable", authMiddleware, asyncHandler(enableTwoFactor));
authRoutes.post("/2fa/email-code", authMiddleware, asyncHandler(sendTwoFactorEmailCode));
authRoutes.post("/2fa/disable", authMiddleware, asyncHandler(disableTwoFactor));
authRoutes.post("/change-password", authMiddleware, asyncHandler(changePassword));
authRoutes.post("/logout", authMiddleware, asyncHandler(logout));

