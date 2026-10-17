import { randomUUID } from "node:crypto";
import { extname } from "node:path";

import { env } from "../../lib/env";
import { HttpError } from "../../lib/errors";
import { mapAttachment } from "../../lib/files";
import { paginationFromQuery } from "../../lib/pagination";
import {
  filesRepository,
  FilesRepository,
} from "./files.repository";
import type {
  PrepareUploadInput,
  RegisterFileMetadataInput,
} from "./files.schemas";
import type { AppContext } from "../../types/app-context";
import { requiredId } from "../../validators/common.validators";
import { permissionsService } from "../../services/permissions.service";

export class FilesService {
  constructor(
    private readonly repository: FilesRepository = filesRepository,
  ) {}

  async list(ctx: AppContext, query: Record<string, unknown> = {}) {
    const page = await this.repository.listFiles(
      ctx.institutionId,
      paginationFromQuery(query),
    );
    return {
      ...page,
      items: page.items.map((row) => mapAttachment(row as Record<string, unknown>)),
    };
  }

  /**
   * URL firmada y temporal para descargar un archivo (el almacenamiento es privado). Se concede a
   * administración, a quien lo subió, al maestro que ve la tarea o la entrega a la que está adjunto,
   * y al alumno o padre solo si es de una tarea publicada de su salón o de una entrega de su hijo.
   */
  async downloadUrl(ctx: AppContext, idRaw: unknown) {
    const id = requiredId(idRaw, "Archivo");
    const file = await this.repository.findFile(ctx.institutionId, id);
    if (!file) throw new HttpError(404, "Archivo no encontrado.", "not_found");

    let allowed = permissionsService.isAdmin(ctx) || Number(file.uploaded_by) === ctx.userId;
    if (!allowed && ctx.roles.has("teacher")) {
      const [a, s] = await Promise.all([this.repository.assignmentsOfFile(id), this.repository.submissionsOfFile(id)]);
      allowed = a.length > 0 || s.length > 0;
    }
    if (!allowed && (ctx.roles.has("student") || ctx.roles.has("parent"))) {
      let studentIds: number[] = [];
      if (ctx.roles.has("parent")) {
        const parentId = await permissionsService.currentParentId(ctx);
        studentIds = parentId == null ? [] : await this.repository.childIdsOfParent(parentId);
      } else {
        const own = await permissionsService.currentStudentId(ctx);
        studentIds = own == null ? [] : [own];
      }
      const groups = new Set(await this.repository.groupIdsOfStudents(ctx.institutionId, studentIds));
      const [a, s] = await Promise.all([this.repository.assignmentsOfFile(id), this.repository.submissionsOfFile(id)]);
      allowed =
        a.some((r) => r.assignments?.published === true && r.assignments?.deleted_at == null && groups.has(Number(r.assignments?.classes?.group_id))) ||
        s.some((r) => studentIds.includes(Number(r.submissions?.student_id)));
    }
    if (!allowed) throw new HttpError(403, "No tienes acceso a este archivo.", "forbidden");

    const name = String(file.original_name ?? "archivo");
    const url = await this.repository.createSignedDownloadUrl(String(file.storage_path), 120, name);
    return { url, name, mimeType: file.mime_type ?? null, expiresInSeconds: 120 };
  }

  async prepareUpload(ctx: AppContext, payload: PrepareUploadInput) {
    const { originalName, mimeType, sizeBytes } = payload;
    this.validateFile(mimeType, sizeBytes);
    const folder = this.cleanSegment(payload.folder ?? "general");
    const extension = this.cleanExtension(extname(originalName));
    const storagePath = `${ctx.institutionId}/${folder}/${randomUUID()}${extension}`;
    const signedUpload = await this.repository.createSignedUploadUrl(storagePath);
    return {
      bucket: "files",
      storagePath,
      signedUpload,
      maxBytes: env.fileUploadMaxBytes,
      allowedMimeTypes: this.allowedMimeTypes(),
    };
  }

  async registerMetadata(ctx: AppContext, payload: RegisterFileMetadataInput) {
    const { originalName, storagePath, mimeType, sizeBytes } = payload;
    this.validateFile(mimeType, sizeBytes);
    if (!storagePath.startsWith(`${ctx.institutionId}/`)) {
      throw new HttpError(
        403,
        "La ruta del archivo no pertenece a tu institución.",
        "forbidden",
      );
    }
    const row = await this.repository.insertFileMetadata({
      institution_id: ctx.institutionId,
      original_name: originalName,
      storage_path: storagePath,
      url: payload.url,
      size_bytes: Math.trunc(sizeBytes),
      mime_type: mimeType,
      uploaded_by: ctx.userId,
    });
    return { file: mapAttachment(row) };
  }

  private validateFile(mimeType: string, sizeBytes: number) {
    if (!Number.isFinite(sizeBytes) || sizeBytes <= 0) {
      throw new HttpError(400, "Tamaño de archivo inválido.", "validation_error");
    }
    if (sizeBytes > env.fileUploadMaxBytes) {
      throw new HttpError(
        400,
        `El archivo supera el límite de ${env.fileUploadMaxBytes} bytes.`,
        "validation_error",
      );
    }
    if (!this.allowedMimeTypes().includes(mimeType)) {
      throw new HttpError(400, "Tipo de archivo no permitido.", "validation_error");
    }
  }

  private allowedMimeTypes() {
    return env.fileAllowedMimeTypes
      .split(",")
      .map((type) => type.trim().toLowerCase())
      .filter(Boolean);
  }

  private cleanSegment(value: string) {
    return value.toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "") || "general";
  }

  private cleanExtension(value: string) {
    return value.toLowerCase().replace(/[^a-z0-9.]/g, "").slice(0, 12);
  }
}

export const filesService = new FilesService();
