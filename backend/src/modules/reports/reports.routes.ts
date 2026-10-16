import { Router } from "express";

import { generateReportCard, getReportCard, listReportCards, previewReportCard } from "./reports.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";

export const reportsRoutes = Router();

reportsRoutes.use(authMiddleware);

reportsRoutes.get("/report-cards", asyncHandler(listReportCards));
reportsRoutes.get("/report-cards/preview", asyncHandler(previewReportCard));
reportsRoutes.post("/report-cards", asyncHandler(generateReportCard));
reportsRoutes.get("/report-cards/:id", asyncHandler(getReportCard));
