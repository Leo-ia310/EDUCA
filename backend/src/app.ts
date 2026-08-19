import cors from "cors";
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

export function createApp() {
  const app = express();

  app.use(cors({
    origin: env.corsOrigin === "*" ? "*" : env.corsOrigin.split(","),
    allowedHeaders: ["authorization", "x-client-info", "apikey", "content-type"],
    methods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
  }));
  app.use(express.json({ limit: "2mb" }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true, service: "educa360-backend" });
  });

  app.use("/api/business-api", businessApiRoutes);
  app.use("/functions/v1/business-api", businessApiRoutes);
  app.use("/api/assignments", assignmentsRoutes);
  app.use("/api/attendance", attendanceRoutes);
  app.use("/api/chats", chatsRoutes);
  app.use("/api/developer", developerRoutes);
  app.use("/api/events", eventsRoutes);
  app.use("/api/grades", gradesRoutes);
  app.use("/api/notifications", notificationsRoutes);
  app.use("/api/payments", paymentsRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
