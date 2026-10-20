// The legacy entry point forwards the original JWT to the Node authorization
// boundary. It never constructs a service-role client or executes old writers.
export function createBusinessProxy(options: {
    target?: string;
    allowedOrigins: string[];
    fetchImpl?: typeof fetch;
    timeoutMs?: number;
}) {
    let target: URL | null = null;
    try {
        const value = new URL(options.target ?? '');
        const path = value.pathname.replace(/\/$/, '');
        if (value.protocol === 'https:' && !value.username && !value.password && !value.search && !value.hash && path.endsWith('/api') && !value.hostname.endsWith('.supabase.co')) {
            value.pathname = path + '/business-api';
            target = value;
        }
    }
    catch { /* Missing/invalid deployment configuration fails closed. */ }
    return async (request: Request) => {
        const origin = request.headers.get('origin');
        const headers = new Headers({ 'content-type': 'application/json', 'cache-control': 'no-store', 'vary': 'Origin', 'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info, x-request-id', 'access-control-allow-methods': 'POST, OPTIONS', 'access-control-expose-headers': 'x-request-id, retry-after' });
        const reply = (status: number, code: string, message: string) => new Response(JSON.stringify({ ok: false, error: { code, message } }), { status, headers });
        if (origin && !options.allowedOrigins.includes(origin))
            return reply(403, 'origin_denied', 'Origen no autorizado.');
        if (origin)
            headers.set('access-control-allow-origin', origin);
        if (request.method === 'OPTIONS')
            return new Response(null, { status: 204, headers });
        if (request.method !== 'POST')
            return reply(405, 'method_not_allowed', 'Método no permitido.');
        if (!target)
            return reply(503, 'legacy_proxy_unconfigured', 'El acceso requiere configurar el backend actualizado.');
        const authorization = request.headers.get('authorization') ?? '';
        if (!/^Bearer [^\s]+$/i.test(authorization))
            return reply(401, 'unauthorized', 'Sesión requerida.');
        const declared = Number(request.headers.get('content-length') ?? 0);
        if (Number.isFinite(declared) && declared > 524288)
            return reply(413, 'payload_too_large', 'El cuerpo excede el tamaño permitido.');
        const signal = AbortSignal.any([request.signal, AbortSignal.timeout(options.timeoutMs ?? 65000)]);
        const reader = request.body?.getReader();
        const abort = () => { void reader?.cancel().catch(() => { }); };
        signal.addEventListener('abort', abort, { once: true });
        try {
            const chunks: Uint8Array[] = [];
            let length = 0;
            if (reader)
                while (true) {
                    const result = await reader.read();
                    if (signal.aborted)
                        throw Error('aborted');
                    if (result.done)
                        break;
                    length += result.value.byteLength;
                    if (length > 524288) {
                        await reader.cancel();
                        return reply(413, 'payload_too_large', 'El cuerpo excede el tamaño permitido.');
                    }
                    chunks.push(result.value);
                }
            if (signal.aborted)
                throw Error('aborted');
            const body = new Uint8Array(length);
            let offset = 0;
            for (const chunk of chunks) {
                body.set(chunk, offset);
                offset += chunk.byteLength;
            }
            const upstreamHeaders = new Headers({ 'content-type': 'application/json', authorization });
            if (origin)
                upstreamHeaders.set('origin', origin);
            const requestId = request.headers.get('x-request-id');
            if (requestId && /^[A-Za-z0-9_.:-]{1,120}$/.test(requestId))
                upstreamHeaders.set('x-request-id', requestId);
            const upstream = await (options.fetchImpl ?? fetch)(target, { method: 'POST', headers: upstreamHeaders, body, signal, redirect: 'error' });
            for (const name of ['x-request-id', 'retry-after']) {
                const value = upstream.headers.get(name);
                if (value)
                    headers.set(name, value);
            }
            // Only the backend's public JSON contract is exposed; redirects are rejected.
            if (!upstream.headers.get('content-type')?.includes('application/json')) {
                void upstream.body?.cancel();
                return reply(503, 'backend_unavailable', 'No se pudo confirmar la operación.');
            }
            return new Response(upstream.body, { status: upstream.status, headers });
        }
        catch {
            return signal.aborted ? reply(504, 'request_timeout', 'No se pudo confirmar a tiempo. Reintenta con la misma clave.') : reply(503, 'backend_unavailable', 'No se pudo confirmar la operación. Reintenta con la misma clave.');
        }
        finally {
            signal.removeEventListener('abort', abort);
            reader?.releaseLock();
        }
    };
}
