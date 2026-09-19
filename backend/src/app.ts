import express from "express";

import { env } from "./lib/env";
import { assignmentsRoutes } from "./routes/assignments.routes";
import { attendanceRoutes } from "./routes/attendance.routes";
import { businessApiRoutes } from "./routes/business-api.routes";
import { chatsRoutes } from "./routes/chats.routes";
import { developerRoutes } from "./routes/developer.routes";
import { eventsRoutes } from "./routes/events.routes";
import { gradesRoutes } from "./routes/grades.routes";
import { notificationsRoutes } from "./routes/notifications.routes";
import { paymentsRoutes } from "./routes/payments.routes";
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

  app.use("/api/business-api", authenticatedRateLimit, businessApiRoutes);
  app.use("/functions/v1/business-api", authenticatedRateLimit, businessApiRoutes);
  app.use("/api/assignments", authenticatedRateLimit, assignmentsRoutes);
  app.use("/api/attendance", authenticatedRateLimit, attendanceRoutes);
  app.use("/api/chats", authenticatedRateLimit, chatsRoutes);
  app.use("/api/developer", authenticatedRateLimit, developerRoutes);
  app.use("/api/events", authenticatedRateLimit, eventsRoutes);
  app.use("/api/grades", authenticatedRateLimit, gradesRoutes);
  app.use("/api/notifications", authenticatedRateLimit, notificationsRoutes);
  app.use("/api/payments", authenticatedRateLimit, paymentsRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
