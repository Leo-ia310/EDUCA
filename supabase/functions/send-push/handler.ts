export function createPushQueueHandler(options: {
    secret?: string;
    enqueue: (id: string, signal: AbortSignal) => Promise<{
        status: string;
    }>;
}) {
    return async (request: Request) => {
        const requestId = crypto.randomUUID();
        const reply = (status: number, data: unknown) => new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-request-id': requestId } });
        if (request.method !== 'POST')
            return reply(405, { ok: false, error: { code: 'method_not_allowed' } });
        if (!options.secret)
            return reply(401, { ok: false, error: { code: 'unauthorized' } });
        const encoder = new TextEncoder();
        const hashes = await Promise.all([`Bearer ${options.secret}`, request.headers.get('authorization') ?? ''].map(value => crypto.subtle.digest('SHA-256', encoder.encode(value))));
        const a = new Uint8Array(hashes[0]), b = new Uint8Array(hashes[1]);
        let difference = 0;
        for (let i = 0; i < a.length; i++)
            difference |= a[i] ^ b[i];
        if (difference !== 0)
            return reply(401, { ok: false, error: { code: 'unauthorized' } });
        let body: any;
        try {
            body = await request.json();
        }
        catch {
            return reply(400, { ok: false, error: { code: 'invalid_json' } });
        }
        const value = body?.notificationId, id = String(value ?? '');
        if (typeof value !== 'number' && typeof value !== 'string' || typeof value === 'number' && !Number.isSafeInteger(value) || !/^[1-9][0-9]{0,18}$/.test(id) || BigInt(id) > 9223372036854775807n)
            return reply(400, { ok: false, error: { code: 'validation_error' } });
        try {
            const data = await options.enqueue(id, AbortSignal.any([request.signal, AbortSignal.timeout(10000)]));
            if (!['pending', 'sent', 'skipped', 'failed'].includes(data.status))
                throw Error('unexpected_status');
            return reply(data.status === 'pending' ? 202 : 200, { ok: true, data });
        }
        catch {
            return reply(503, { ok: false, error: { code: 'push_queue_unavailable', requestId } });
        }
    };
}
