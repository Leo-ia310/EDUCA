export function createHandler(secret: string | undefined, step: (request: Request) => Promise<unknown>) {
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
  return async (request: Request) => {
    if (request.method !== 'POST') return new Response('{}', { status: 405, headers: { ...headers, Allow: 'POST' } });
    if (!secret || secret.length < 32) return new Response('{}', { status: 503, headers });
    const supplied = request.headers.get('x-originality-secret') ?? '';
    if (supplied.length > 512) return new Response('{}', { status: 401, headers });
    const digest = (value: string) => crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
    const [a,b] = await Promise.all([digest(secret),digest(supplied)]);
    const aa = new Uint8Array(a), bb = new Uint8Array(b);
    let different = 0; for (let i = 0; i < aa.length; i++) different |= aa[i] ^ bb[i];
    if (different) return new Response('{}', { status: 401, headers });
    // Scheduled requests carry only {}; callers cannot select documents, URLs or tenants.
    if (Number(request.headers.get('content-length')) > 128) return new Response('{}', { status: 400, headers });
    if (request.body) {
      const reader = request.body.getReader(); let body = ''; let length = 0;
      try {
        const decoder = new TextDecoder();
        while (true) { const part = await reader.read(); if (part.done) break;
          length += part.value.length; if (length > 128) return new Response('{}', { status: 400, headers });
          body += decoder.decode(part.value, { stream: true });
        }
        body += decoder.decode();
        if (body.trim() && body.trim() !== '{}') return new Response('{}', { status: 400, headers });
      } finally { await reader.cancel(); }
    }
    try { return Response.json(await step(request), { headers }); }
    catch { return new Response('{"status":"unavailable"}', { status: 503, headers }); }
  };
}
