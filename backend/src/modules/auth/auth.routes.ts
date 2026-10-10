import { Router } from "express";

import { login, logout, recoverPassword, refresh } from "./auth.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";

export const authRoutes = Router();

authRoutes.post("/login", asyncHandler(login));
authRoutes.post("/refresh", asyncHandler(refresh));
authRoutes.post("/recover-password", asyncHandler(recoverPassword));
authRoutes.post("/logout", authMiddleware, asyncHandler(logout));

