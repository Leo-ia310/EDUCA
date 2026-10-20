import { HttpError } from "./errors";
export type DatabaseError = {
    code?: string;
    message?: string;
    details?: unknown;
    hint?: unknown;
    status?: number;
};
/** Public messages never expose relation names, SQL, connection strings or rows. */
export function databaseError(error: DatabaseError): HttpError {
    const code = String(error.code ?? "");
    if (code === "42501")
        return new HttpError(403, "No tienes permiso para realizar esta operación.", "forbidden");
    if (code === "P0002" || code === "PGRST116" && String(error.details ?? "").includes("0 rows"))
        return new HttpError(404, "Registro no encontrado.", "not_found");
    if (code === "23505" || code === "23P01" || code === "40001" || code === "40P01")
        return new HttpError(409, "La operación entra en conflicto con otra escritura. Reintenta con la misma clave.", "write_conflict");
    if (code.startsWith("22") || code.startsWith("23"))
        return new HttpError(400, "Los datos no cumplen las reglas de la operación.", "validation_error");
    // Missing migrations, malformed queries and dependency timeouts are operational
    // failures, not invalid user input. PGRST116 can also mean multiple rows.
    return new HttpError(503, "No se pudo confirmar la operación. Reintenta con la misma clave.", "database_unavailable", 2);
}
