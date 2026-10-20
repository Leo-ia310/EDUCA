import { HttpError } from "./errors";
export function assertAuthAvailable(error: {
    status?: number;
    name?: string;
} | null | undefined) {
    if (!error)
        return;
    if (error.status === 429)
        throw new HttpError(429, "El servicio de autenticación está ocupado. Espera antes de reintentar.", "authentication_rate_limited", 10);
    if (![400, 401, 403, 422].includes(error.status ?? 0) || error.name === "AuthRetryableFetchError") {
        throw new HttpError(503, "El servicio de autenticación no está disponible. Intenta nuevamente.", "authentication_unavailable", 2);
    }
}
