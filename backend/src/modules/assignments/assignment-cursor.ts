import { HttpError } from "../../lib/errors";
import { asRecord, optionalString, requiredDate } from "../../validators/common.validators";
export type AssignmentCursor = {
    id: string;
    dueAt: string | null;
};
export function encodeAssignmentCursor(cursor: AssignmentCursor | null) {
    return cursor == null ? null : Buffer.from(JSON.stringify(cursor)).toString("base64url");
}
export function decodeAssignmentCursor(value: unknown): AssignmentCursor | null {
    const text = optionalString(value, 512);
    if (!text)
        return null;
    try {
        if (!/^[\w-]+$/.test(text))
            throw new Error("cursor");
        const parsed = asRecord(JSON.parse(Buffer.from(text, "base64url").toString("utf8")));
        if (typeof parsed.id !== "string" || !/^[1-9]\d{0,18}$/.test(parsed.id) || BigInt(parsed.id) > 9223372036854775807n)
            throw new Error("id");
        if (parsed.dueAt == null)
            return { id: parsed.id, dueAt: null };
        if (typeof parsed.dueAt !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(parsed.dueAt))
            throw new Error("date");
        requiredDate(parsed.dueAt, "Cursor");
        // PostgreSQL stores microseconds and bigint IDs. Keep their exact strings;
        // JS Date.toISOString()/Number would lose precision and repeat pages.
        return { id: parsed.id, dueAt: parsed.dueAt };
    }
    catch {
        throw new HttpError(400, "Cursor de tareas inválido.", "validation_error");
    }
}
