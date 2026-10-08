import { randomUUID } from "node:crypto";
import type { NextFunction, Response } from "express";

import type { AppRequest } from "../types/app-context";

export function requestIdMiddleware(
  req: AppRequest,
  res: Response,
  next: NextFunction,
) {
  const incoming = req.header("x-request-id")?.trim();
  const requestId = incoming && incoming.length <= 120 ? incoming : randomUUID();
  req.requestId = requestId;
  res.setHeader("x-request-id", requestId);
  next();
}
