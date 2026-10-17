import { Router } from "express";
import type { Response } from "express";

import { authMiddleware, requireAppContext } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import { requireRoles } from "../../middleware/permissions.middleware";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";
import { familyService } from "./family.service";

export const familyRoutes = Router();

familyRoutes.use(authMiddleware);
familyRoutes.use(requireRoles(["parent", "student"]));

familyRoutes.get("/children", asyncHandler(async (req: AppRequest, res: Response) => {
  res.json({ ok: true, data: await familyService.children(requireAppContext(req)) });
}));
familyRoutes.get("/attendance", asyncHandler(async (req: AppRequest, res: Response) => {
  res.json({ ok: true, data: await familyService.attendance(requireAppContext(req), asRecord(req.query)) });
}));
familyRoutes.get("/assignments", asyncHandler(async (req: AppRequest, res: Response) => {
  res.json({ ok: true, data: await familyService.assignments(requireAppContext(req), asRecord(req.query)) });
}));
