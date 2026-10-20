import { HttpError } from "../lib/errors";
export function requiredString(value: unknown, label: string, max = 250) {
    if (typeof value !== "string" || value.trim().length === 0) {
        throw new HttpError(400, `${label} es obligatorio.`, "validation_error");
    }
    const cleaned = value.trim();
    if (cleaned.length > max) {
        throw new HttpError(400, `${label} no puede superar ${max} caracteres.`, "validation_error");
    }
    return cleaned;
}
export function optionalString(value: unknown, max = 2000) {
    if (value == null)
        return null;
    if (typeof value !== "string") {
        throw new HttpError(400, "Texto inválido.", "validation_error");
    }
    const cleaned = value.trim();
    if (cleaned.length > max) {
        throw new HttpError(400, `El texto no puede superar ${max} caracteres.`, "validation_error");
    }
    return cleaned.length === 0 ? null : cleaned;
}
export function requiredId(value: unknown, label: string) {
    const validType = typeof value === "number" || typeof value === "string" && /^[1-9][0-9]*$/.test(value);
    const parsed = validType ? Number(value) : NaN;
    if (!Number.isSafeInteger(parsed) || parsed <= 0) {
        throw new HttpError(400, `${label} inválido.`, "validation_error");
    }
    return parsed;
}
export function optionalId(value: unknown) {
    if (value == null || value === "")
        return null;
    return requiredId(value, "ID");
}
export function requiredNumber(value: unknown, label: string) {
    const validType = typeof value === "number" || typeof value === "string" && /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$/.test(value);
    const parsed = validType ? Number(value) : NaN;
    if (!Number.isFinite(parsed)) {
        throw new HttpError(400, `${label} inválido.`, "validation_error");
    }
    return parsed;
}
export function requiredDate(value: unknown, label: string) {
    if (typeof value !== "string" && typeof value !== "number") {
        throw new HttpError(400, `${label} inválida.`, "validation_error");
    }
    if (typeof value === "number" && !Number.isSafeInteger(value))
        throw new HttpError(400, `${label} inválida.`, "validation_error");
    if (typeof value === "string") {
        const civil = /^(\d{4})-(\d{2})-(\d{2})(?:$|T)/.exec(value);
        if (!civil)
            throw new HttpError(400, `${label} inválida.`, "validation_error");
        const day = new Date(Date.UTC(Number(civil[1]), Number(civil[2]) - 1, Number(civil[3])));
        if (day.getUTCFullYear() !== Number(civil[1]) || day.getUTCMonth() + 1 !== Number(civil[2]) || day.getUTCDate() !== Number(civil[3]))
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
export function optionalBoolean(value: unknown, fallback?: boolean) {
    if (value == null || value === '')
        return fallback;
    if (value === true || value === 'true')
        return true;
    if (value === false || value === 'false')
        return false;
    throw new HttpError(400, 'Booleano inválido.', 'validation_error');
}
