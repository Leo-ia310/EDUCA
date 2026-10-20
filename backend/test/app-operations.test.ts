import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test, mock } from 'node:test';
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
process.env.INTERNAL_API_SECRET = 'fixture-metrics-secret';
const { createApp } = require('../src/app') as typeof import('../src/app');
const { supabasePublic } = require('../src/lib/supabase') as typeof import('../src/lib/supabase');
test('real app separates liveness, cached readiness and authenticated metrics without using a remote dependency', async () => {
    let probes = 0;
    const rpc = mock.method(supabasePublic, 'rpc', ((name: string) => { assert.equal(name, 'backend_readiness_v1'); probes++; return Promise.resolve({ data: { schemaVersion: 53 }, error: null }); }) as any);
    const server = createApp().listen(0, '127.0.0.1');
    await once(server, 'listening');
    const url = `http://127.0.0.1:${(server.address() as {
        port: number;
    }).port}`;
    try {
        assert.equal((await fetch(url + '/health')).status, 200);
        assert.equal(probes, 0);
        const ready = await fetch(url + '/ready');
        assert.equal(ready.status, 200);
        assert.equal((await ready.json() as any).schemaVersion, 53);
        assert.equal((await fetch(url + '/ready')).status, 200);
        assert.equal(probes, 1);
        assert.equal((await fetch(url + '/internal/metrics')).status, 403);
        const metrics = await fetch(url + '/internal/metrics', { headers: { authorization: 'Bearer fixture-metrics-secret' } });
        assert.equal(metrics.status, 200);
        assert.equal((await metrics.json() as any).data.scope, 'process');
    }
    finally {
        rpc.mock.restore();
        server.closeAllConnections();
        await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }
});
