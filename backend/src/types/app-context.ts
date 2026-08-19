import type { Request } from "express";

export type AppContext = {
  authUserId: string;
  userId: number;
  institutionId: number;
  personId: number | null;
  fullName: string;
  roles: Set<string>;
  teacherId?: number | null;
  studentId?: number | null;
  parentId?: number | null;
};

export interface AppRequest extends Request {
  appContext?: AppContext;
}
