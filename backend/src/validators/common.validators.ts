import { HttpError } from "../lib/errors";

export function requiredString(value: unknown, label: string, max = 250) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, `${label} es obligatorio.`, "validation_error");
  }
  const cleaned = value.trim();
  if (cleaned.length > max) {
    throw new HttpError(
      400,
      `${label} no puede superar ${max} caracteres.`,
      "validation_error",
    );
  }
  return cleaned;
}

export function optionalString(value: unknown, max = 2000) {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw new HttpError(400, "Texto inválido.", "validation_error");
  }
  const cleaned = value.trim();
  if (cleaned.length > max) {
    throw new HttpError(
      400,
      `El texto no puede superar ${max} caracteres.`,
      "validation_error",
    );
  }
  return cleaned.length === 0 ? null : cleaned;
}

export function requiredId(value: unknown, label: string) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new HttpError(400, `${label} inválido.`, "validation_error");
  }
  return parsed;
}

export function optionalId(value: unknown) {
  if (value == null || value === "") return null;
  return requiredId(value, "ID");
}

export function requiredNumber(value: unknown, label: string) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new HttpError(400, `${label} inválido.`, "validation_error");
  }
  return parsed;
}

export function requiredDate(value: unknown, label: string) {
  if (typeof value !== "string" && typeof value !== "number") {
    throw new HttpError(400, `${label} inválida.`, "validation_error");
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new HttpError(400, `${label} inválida.`, "validation_error");
  }
  return date;
}

export function dateOnly(date: Date) {
  return date.toISOString().slice(0, 10);
}

export function asList(value: unknown) {
  return Array.isArray(value) ? value : [];
}

export function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}
