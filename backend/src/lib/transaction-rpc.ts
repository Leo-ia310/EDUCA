import { databaseError } from "./database-error";
import { HttpError } from "./errors";
export async function transactionRpc<T = any>(client: any, name: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await client.rpc(name, args);
    if (error)
        throw databaseError(error);
    if (data == null)
        throw new HttpError(503, "No se pudo confirmar la operación. Reintenta con la misma clave.", "transaction_error", 2);
    return data as T;
}
