import { Router } from "express";

import { enqueue, listQueue, markFailed, pullChanges, retry } from "../controllers/sync.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";

export const syncRoutes = Router();

syncRoutes.use(authMiddleware);

syncRoutes.get("/queue", asyncHandler(listQueue));
syncRoutes.post("/queue", asyncHandler(enqueue));
syncRoutes.post("/queue/:id/retry", asyncHandler(retry));
syncRoutes.post("/queue/:id/failed", asyncHandler(markFailed));
syncRoutes.get("/changes", asyncHandler(pullChanges));
