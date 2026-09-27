import { Router } from "express";

import { listFiles, prepareUpload, registerMetadata } from "../controllers/files.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";

export const filesRoutes = Router();

filesRoutes.use(authMiddleware);

filesRoutes.get("/", asyncHandler(listFiles));
filesRoutes.post("/prepare-upload", asyncHandler(prepareUpload));
filesRoutes.post("/metadata", asyncHandler(registerMetadata));
