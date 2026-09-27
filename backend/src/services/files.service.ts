import { randomUUID } from "node:crypto";
import { extname } from "node:path";

import { env } from "../lib/env";
import { HttpError } from "../lib/errors";
import { mapAttachment } from "../lib/files";
import type { AppContext } from "../types/app-context";
import {
  optionalString,
  requiredNumber,
  requiredString,
} from "../validators/common.validators";
import {
  filesRepository,
  FilesRepository,
} from "../repositories/files.repository";

export class FilesService {
  constructor(
    private readonly repository: FilesRepository = filesRepository,
  ) {}

  async list(ctx: AppContext) {
    const rows = await this.repository.listFiles(ctx.institutionId);
    return rows.map((row: Record<string, unknown>) => mapAttachment(row));
  }

  async prepareUpload(ctx: AppContext, payload: Record<string, unknown>) {
    const originalName = requiredString(payload.originalName ?? payload.original_name, "Nombre", 255);
    const mimeType = requiredString(payload.mimeType ?? payload.mime_type, "MIME", 100).toLowerCase();
    const sizeBytes = requiredNumber(payload.sizeBytes ?? payload.size_bytes, "Tamaño");
    this.validateFile(mimeType, sizeBytes);
    const folder = this.cleanSegment(optionalString(payload.folder, 80) ?? "general");
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

  async registerMetadata(ctx: AppContext, payload: Record<string, unknown>) {
    const originalName = requiredString(payload.originalName ?? payload.original_name, "Nombre", 255);
    const storagePath = requiredString(payload.storagePath ?? payload.storage_path, "Ruta", 500);
    const mimeType = requiredString(payload.mimeType ?? payload.mime_type, "MIME", 100).toLowerCase();
    const sizeBytes = requiredNumber(payload.sizeBytes ?? payload.size_bytes, "Tamaño");
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
      url: optionalString(payload.url, 2000),
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
