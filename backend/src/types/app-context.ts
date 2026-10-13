import type { Request } from "express";

export type AppContext = {
  authUserId: string;
  userId: number;
  institutionId: number;
  personId: number | null;
  fullName: string;
  roles: Set<string>;
  /** Permisos admin del usuario; null = sin restricciones (histórico). */
  adminPermissions: string[] | null;
  teacherId?: number | null;
  studentId?: number | null;
  parentId?: number | null;
};

export interface AppRequest extends Request {
  appContext?: AppContext;
  requestId?: string;
}
