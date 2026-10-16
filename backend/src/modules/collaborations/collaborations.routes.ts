import { Router } from "express";
import { authMiddleware, requireAppContext } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import { requireRoles } from "../../middleware/permissions.middleware";
import { collaborationService } from "./collaborations.service";
import { asRecord } from "../../validators/common.validators";

export const collaborationRoutes = Router();
collaborationRoutes.use(authMiddleware, requireRoles(["teacher"]));
collaborationRoutes.get("/", asyncHandler(async (req, res) => {
  res.json({ ok: true, data: await collaborationService.workspace(requireAppContext(req)) });
}));
collaborationRoutes.post("/", asyncHandler(async (req, res) => {
  res.json({ ok: true, data: await collaborationService.manage(requireAppContext(req), asRecord(req.body)) });
}));
