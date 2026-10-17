import express from "express";
import { familyRoutes } from "./modules/family/family.routes";
import { portalAccessRoutes } from "./modules/portal-access/portal-access.routes";

import { env } from "./lib/env";
import { adminRoutes } from "./modules/admin/admin.routes";
import { assignmentsRoutes } from "./modules/assignments/assignments.routes";
import { attendanceRoutes } from "./modules/attendance/attendance.routes";
import { authRoutes } from "./modules/auth/auth.routes";
import { businessApiRoutes } from "./modules/business-api/business-api.routes";
import { chatsRoutes } from "./modules/chats/chats.routes";
import { collaborationRoutes } from "./modules/collaborations/collaborations.routes";
import { developerRoutes } from "./modules/developer/developer.routes";
import { eventsRoutes } from "./modules/events/events.routes";
import { filesRoutes } from "./modules/files/files.routes";
import { gradesRoutes } from "./modules/grades/grades.routes";
import { notificationsRoutes } from "./modules/notifications/notifications.routes";
import { paymentsRoutes } from "./modules/payments/payments.routes";
import { schedulesRoutes } from "./modules/schedules/schedules.routes";
import { reportsRoutes } from "./modules/reports/reports.routes";
import { syncRoutes } from "./modules/sync/sync.routes";
import {
  errorHandler,
  notFoundHandler,
} from "./middleware/error.middleware";
import { requestIdMiddleware } from "./middleware/request-id.middleware";
import {
  authenticatedRateLimit,
  corsMiddleware,
  generalRateLimit,
  noStore,
  securityHeaders,
} from "./middleware/security.middleware";

export function createApp() {
  const app = express();

  app.set("trust proxy", env.trustProxy ? 1 : false);
  app.disable("x-powered-by");

  app.use(requestIdMiddleware);
  app.use(securityHeaders);
  app.use(corsMiddleware);
  app.use(noStore);
  app.use(generalRateLimit);
  app.use(express.json({ limit: env.jsonLimit }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true, service: "educa360-backend" });
  });

  app.use("/api/auth", authenticatedRateLimit, authRoutes);
  app.use("/api/portal-access", authenticatedRateLimit, portalAccessRoutes);
  app.use("/api/admin", authenticatedRateLimit, adminRoutes);
  app.use("/api/business-api", authenticatedRateLimit, businessApiRoutes);
  app.use("/functions/v1/business-api", authenticatedRateLimit, businessApiRoutes);
  app.use("/api/assignments", authenticatedRateLimit, assignmentsRoutes);
  app.use("/api/attendance", authenticatedRateLimit, attendanceRoutes);
  app.use("/api/chats", authenticatedRateLimit, chatsRoutes);
  app.use("/api/collaborations", authenticatedRateLimit, collaborationRoutes);
  app.use("/api/developer", authenticatedRateLimit, developerRoutes);
  app.use("/api/family", authenticatedRateLimit, familyRoutes);
  app.use("/api/events", authenticatedRateLimit, eventsRoutes);
  app.use("/api/files", authenticatedRateLimit, filesRoutes);
  app.use("/api/grades", authenticatedRateLimit, gradesRoutes);
  app.use("/api/notifications", authenticatedRateLimit, notificationsRoutes);
  app.use("/api/payments", authenticatedRateLimit, paymentsRoutes);
  app.use("/api/reports", authenticatedRateLimit, reportsRoutes);
  app.use("/api/schedules", authenticatedRateLimit, schedulesRoutes);
  app.use("/api/sync", authenticatedRateLimit, syncRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
