import { Router } from "express";

import { downloadUrl, listFiles, prepareUpload, registerMetadata } from "./files.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";

export const filesRoutes = Router();

filesRoutes.use(authMiddleware);

filesRoutes.get("/", asyncHandler(listFiles));
filesRoutes.get("/:id/download-url", asyncHandler(downloadUrl));
filesRoutes.post("/prepare-upload", asyncHandler(prepareUpload));
filesRoutes.post("/metadata", asyncHandler(registerMetadata));
