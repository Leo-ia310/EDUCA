import assert from 'node:assert/strict';
import { createWorkerHandler } from '../app.ts';
import type { QueuePort } from '../step.ts';

Deno.test('real loopback HTTP endpoint refuses anonymous work and accepts only its scheduled idle tick', async () => {
  const calls: string[] = [];
  const port: QueuePort = {
    rpc<T>(name: string) { calls.push(name); return Promise.resolve(null as T); },
    document: () => { throw Error('unexpected document'); },
    file: () => { throw Error('unexpected file'); },
    shared: () => { throw Error('unexpected assignment'); },
    sourceUrl: () => { throw Error('unexpected URL'); },
  };
  const secret='local-http-fixture-secret-'.repeat(3);
  const controller=new AbortController();
  const server=Deno.serve({hostname:'127.0.0.1',port:0,signal:controller.signal,onListen() {}},
    createWorkerHandler({secret,enabled:true},port));
  const address=`http://127.0.0.1:${server.addr.port}/functions/v1/nivra-originality`;
  try {
    const anonymous=await fetch(address,{method:'POST',body:'{}'});
    assert.equal(anonymous.status,401);await anonymous.text();assert.equal(calls.length,0);
    const valid=await fetch(address,{method:'POST',body:'{}',headers:{'x-originality-secret':secret}});
    assert.equal(valid.status,200);assert.deepEqual(await valid.json(),{status:'idle'});
    assert.deepEqual(calls,['originality_edge_reconcile','originality_edge_claim']);
    const invalid=await fetch(address,{method:'POST',body:'{"documentId":3}',headers:{'x-originality-secret':secret}});
    assert.equal(invalid.status,400);await invalid.text();assert.equal(calls.length,2);
  } finally { controller.abort();await server.finished; }
});
