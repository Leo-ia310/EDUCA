import type { Response } from "express";

import { adminService } from "./admin.service";
import { requireAppContext } from "../../middleware/auth.middleware";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";

export async function listInstitutions(req: AppRequest, res: Response) {
  const data = await adminService.listInstitutions(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function createInstitution(req: AppRequest, res: Response) {
  const data = await adminService.createInstitution(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function updateInstitution(req: AppRequest, res: Response) {
  const data = await adminService.updateInstitution(requireAppContext(req), req.params.id, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function archiveInstitution(req: AppRequest, res: Response) {
  const data = await adminService.archiveInstitution(requireAppContext(req), req.params.id);
  return res.json({ ok: true, data });
}

export async function listUsers(req: AppRequest, res: Response) {
  const data = await adminService.listUsers(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function directory(req: AppRequest, res: Response) {
  const data = await adminService.directory(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function createUser(req: AppRequest, res: Response) {
  const data = await adminService.createUser(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function updateUser(req: AppRequest, res: Response) {
  const data = await adminService.updateUser(requireAppContext(req), req.params.id, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function archiveUser(req: AppRequest, res: Response) {
  const data = await adminService.archiveUser(requireAppContext(req), req.params.id, asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function listRoles(req: AppRequest, res: Response) {
  const data = await adminService.listRoles(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function createRole(req: AppRequest, res: Response) {
  const data = await adminService.createRole(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function updateRole(req: AppRequest, res: Response) {
  const data = await adminService.updateRole(requireAppContext(req), req.params.id, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function archiveRole(req: AppRequest, res: Response) {
  const data = await adminService.archiveRole(requireAppContext(req), req.params.id, asRecord(req.query));
  return res.json({ ok: true, data });
}

export function listPeople(resource: "students" | "teachers" | "parents") {
  return async (req: AppRequest, res: Response) => {
    const data = await adminService.listPeople(requireAppContext(req), resource, asRecord(req.query));
    return res.json({ ok: true, data });
  };
}

export function createPeople(resource: "students" | "teachers" | "parents") {
  return async (req: AppRequest, res: Response) => {
    const data = await adminService.createPeople(requireAppContext(req), resource, asRecord(req.body));
    return res.status(201).json({ ok: true, data });
  };
}

export function updatePeople(resource: "students" | "teachers" | "parents") {
  return async (req: AppRequest, res: Response) => {
    const data = await adminService.updatePeople(requireAppContext(req), resource, req.params.id, asRecord(req.body));
    return res.json({ ok: true, data });
  };
}

export function archivePeople(resource: "students" | "teachers" | "parents") {
  return async (req: AppRequest, res: Response) => {
    const data = await adminService.archivePeople(requireAppContext(req), resource, req.params.id, asRecord(req.query));
    return res.json({ ok: true, data });
  };
}

export async function createGroup(req: AppRequest, res: Response) {
  const data = await adminService.createGroup(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function updateGroup(req: AppRequest, res: Response) {
  const data = await adminService.updateGroup(requireAppContext(req), req.params.id, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function archiveGroup(req: AppRequest, res: Response) {
  const data = await adminService.archiveGroup(requireAppContext(req), req.params.id, asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function createClass(req: AppRequest, res: Response) {
  const data = await adminService.createClass(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function updateClass(req: AppRequest, res: Response) {
  const data = await adminService.updateClass(requireAppContext(req), req.params.id, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function archiveClass(req: AppRequest, res: Response) {
  const data = await adminService.archiveClass(requireAppContext(req), req.params.id, asRecord(req.query));
  return res.json({ ok: true, data });
}


export async function listPermissionCatalog(req: AppRequest, res: Response) {
  const data = await adminService.listPermissionCatalog(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function listProfiles(req: AppRequest, res: Response) {
  const data = await adminService.listProfiles(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function createProfile(req: AppRequest, res: Response) {
  const data = await adminService.createProfile(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function updateProfile(req: AppRequest, res: Response) {
  const data = await adminService.updateProfile(requireAppContext(req), req.params.id, asRecord(req.body));
  return res.json({ ok: true, data });
}
