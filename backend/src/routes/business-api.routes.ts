import { Router } from "express";

import { dispatchAction } from "../controllers/business-api.controller";
import { asyncHandler } from "../middleware/error.middleware";
import { authMiddleware } from "../middleware/auth.middleware";

export const businessApiRoutes = Router();

businessApiRoutes.post("/", authMiddleware, asyncHandler(dispatchAction));
