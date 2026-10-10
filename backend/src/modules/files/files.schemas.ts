import { asRecord, optionalString, requiredNumber, requiredString } from "../../validators/common.validators";

export type ListFilesQuery = Record<string, unknown>;

export type PrepareUploadInput = {
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  folder: string | null;
};

export type RegisterFileMetadataInput = {
  originalName: string;
  storagePath: string;
  mimeType: string;
  sizeBytes: number;
  url: string | null;
};

export function parseListFilesQuery(value: unknown): ListFilesQuery {
  return asRecord(value);
}

export function parsePrepareUploadBody(value: unknown): PrepareUploadInput {
  const payload = asRecord(value);
  return {
    originalName: requiredString(
      payload.originalName ?? payload.original_name,
      "Nombre",
      255,
    ),
    mimeType: requiredString(
      payload.mimeType ?? payload.mime_type,
      "MIME",
      100,
    ).toLowerCase(),
    sizeBytes: requiredNumber(
      payload.sizeBytes ?? payload.size_bytes,
      "Tamaño",
    ),
    folder: optionalString(payload.folder, 80),
  };
}

export function parseRegisterFileMetadataBody(value: unknown): RegisterFileMetadataInput {
  const payload = asRecord(value);
  return {
    originalName: requiredString(
      payload.originalName ?? payload.original_name,
      "Nombre",
      255,
    ),
    storagePath: requiredString(
      payload.storagePath ?? payload.storage_path,
      "Ruta",
      500,
    ),
    mimeType: requiredString(
      payload.mimeType ?? payload.mime_type,
      "MIME",
      100,
    ).toLowerCase(),
    sizeBytes: requiredNumber(
      payload.sizeBytes ?? payload.size_bytes,
      "Tamaño",
    ),
    url: optionalString(payload.url, 2000),
  };
}
