import assert from 'node:assert/strict';
import {test,mock} from 'node:test';
import {ConcurrencyGate} from '../src/lib/concurrency-gate';

test('dependency pressure remains bounded, admits queued requests fairly and never double-releases a slot',async()=>{
  const gate=new ConcurrencyGate(2,2),signal=new AbortController().signal;
  const a=await gate.acquire(signal),b=await gate.acquire(signal),order:string[]=[];
  const c=gate.acquire(signal).then(release=>{order.push('c');return release;});
  const d=gate.acquire(signal).then(release=>{order.push('d');return release;});
  await assert.rejects(gate.acquire(signal),/queue is full/);
  assert.equal(gate.snapshot().active,2);assert.equal(gate.snapshot().pending,2);
  b();const releaseC=await c;assert.deepEqual(order,['c']);
  b();assert.equal(gate.snapshot().pending,1);
  a();const releaseD=await d;assert.deepEqual(order,['c','d']);
  releaseC();releaseD();assert.equal(gate.snapshot().active,0);
  assert.equal(gate.snapshot().rejected,1);assert.equal(gate.snapshot().waited,2);
});

test('aborted queued work is removed and cannot consume a later slot or block healthy requests',async()=>{
  const gate=new ConcurrencyGate(1,2),signal=new AbortController().signal,abort=new AbortController();
  const first=await gate.acquire(signal);
  const cancelled=gate.acquire(abort.signal);
  const healthy=gate.acquire(signal);
  const rejected=assert.rejects(cancelled,{name:'AbortError'});abort.abort();await rejected;
  assert.equal(gate.snapshot().pending,1);
  first();const release=await healthy;release();
  assert.equal(gate.snapshot().active,0);assert.equal(gate.snapshot().pending,0);
  assert.equal(gate.snapshot().cancelled,1);
  await assert.rejects(gate.acquire(abort.signal),{name:'AbortError'});
});

test('transport failure and deadline expiry release pressure without starting abandoned dependency requests',async()=>{
  const gate=new ConcurrencyGate(1,1),signal=new AbortController().signal;
  const release=await gate.acquire(signal),abort=new AbortController();
  const queued=gate.acquire(abort.signal);
  const rejected=assert.rejects(queued,{name:'TimeoutError'});
  abort.abort(new DOMException('Deadline expired','TimeoutError'));await rejected;
  release();
  await assert.rejects((async()=>{const done=await gate.acquire(signal);try{throw Error('transport');}finally{done();}})(),/transport/);
  assert.equal(gate.snapshot().active,0);assert.equal(gate.snapshot().pending,0);
});

test('Supabase transport shares admission across Auth and REST, preserves responses and skips cancelled queued fetches',async()=>{
  process.env.NODE_ENV='test';process.env.SUPABASE_URL='https://fixture.supabase.co';process.env.SUPABASE_ANON_KEY='fixture';
  const {dependencyFetch}=require('../src/lib/dependency-fetch') as typeof import('../src/lib/dependency-fetch');
  const {dependencyAdmission,databaseAdmission}=require('../src/lib/dependency-admission') as typeof import('../src/lib/dependency-admission');
  const limit=dependencyAdmission.snapshot().limit;
  const started:string[]=[],replies:{finish:(response:Response)=>void;response:Response;url:string}[]=[];
  const fetchMock=mock.method(globalThis,'fetch',(input:Parameters<typeof fetch>[0])=>{
    started.push(String(input));
    return new Promise<Response>(finish=>replies.push({finish,response:new Response('{"ok":true}'),url:String(input)}));
  });
  try {
    const work=Array.from({length:limit+1},(_,i)=>dependencyFetch(`https://fixture.supabase.co/${i%2?'auth/v1/user':'rest/v1/rows'}?i=${i}`));
    const abort=new AbortController();
    const cancelled=dependencyFetch('https://fixture.supabase.co/rest/v1/cancelled',{signal:abort.signal});
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(started.length,limit);
    const rejection=assert.rejects(cancelled,{name:'AbortError'});abort.abort();await rejection;
    for(let i=0;i<limit+1;i++) {
      replies[i]!.finish(replies[i]!.response);
      await new Promise(resolve=>setImmediate(resolve));
    }
    const results=await Promise.all(work);
    assert.equal(started.length,limit+1);assert.ok(started.every(url=>!url.includes('cancelled')));
    results.forEach((response,i)=>assert.equal(response,replies.find(reply=>reply.url.endsWith('?i='+i))!.response));
    assert.equal(dependencyAdmission.snapshot().active,0);assert.equal(dependencyAdmission.snapshot().pending,0);
    assert.equal(databaseAdmission.snapshot().active,0);assert.equal(databaseAdmission.snapshot().pending,0);
  } finally {fetchMock.mock.restore();}
});

test('database backlog leaves shared capacity for Auth and releases both admissions on cancellation',async()=>{
  const {dependencyFetch}=require('../src/lib/dependency-fetch') as typeof import('../src/lib/dependency-fetch');
  const {dependencyAdmission,databaseAdmission}=require('../src/lib/dependency-admission') as typeof import('../src/lib/dependency-admission');
  const started:string[]=[],finish:((r:Response)=>void)[]=[];
  const fetchMock=mock.method(globalThis,'fetch',(input:Parameters<typeof fetch>[0])=>{
    started.push(String(input));return new Promise<Response>(resolve=>finish.push(resolve));
  });
  try {
    const count=databaseAdmission.snapshot().limit;
    const work=Array.from({length:count},()=>dependencyFetch('https://fixture.supabase.co/rest/v1/rows'));
    await new Promise(resolve=>setImmediate(resolve));
    const abort=new AbortController(),queued=dependencyFetch('https://fixture.supabase.co/rest/v1/queued',{signal:abort.signal});
    const auth=dependencyFetch('https://fixture.supabase.co/auth/v1/user');
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(started.filter(url=>url.includes('/rest/')).length,count);
    assert.ok(started.some(url=>url.includes('/auth/')));
    const rejection=assert.rejects(queued,{name:'AbortError'});abort.abort();await rejection;
    finish.forEach(resolve=>resolve(new Response('{}')));await Promise.all([...work,auth]);
    assert.equal(dependencyAdmission.snapshot().active,0);assert.equal(databaseAdmission.snapshot().active,0);
  } finally {fetchMock.mock.restore();}
});

test('a SQL request cancelled while waiting for shared capacity releases its database reservation',async()=>{
  const {dependencyFetch}=require('../src/lib/dependency-fetch') as typeof import('../src/lib/dependency-fetch');
  const {dependencyAdmission,databaseAdmission}=require('../src/lib/dependency-admission') as typeof import('../src/lib/dependency-admission');
  const finish:((r:Response)=>void)[]=[];
  const fetchMock=mock.method(globalThis,'fetch',()=>new Promise<Response>(resolve=>finish.push(resolve)));
  try {
    const auth=Array.from({length:dependencyAdmission.snapshot().limit},()=>dependencyFetch('https://fixture.supabase.co/auth/v1/user'));
    await new Promise(resolve=>setImmediate(resolve));
    const abort=new AbortController(),sql=dependencyFetch('https://fixture.supabase.co/rest/v1/rows',{signal:abort.signal});
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(databaseAdmission.snapshot().active,1);assert.equal(dependencyAdmission.snapshot().pending,1);
    const rejection=assert.rejects(sql,{name:'AbortError'});abort.abort();await rejection;
    assert.equal(databaseAdmission.snapshot().active,0);assert.equal(dependencyAdmission.snapshot().pending,0);
    finish.forEach(resolve=>resolve(new Response('{}')));await Promise.all(auth);
    assert.equal(dependencyAdmission.snapshot().active,0);
  } finally {fetchMock.mock.restore();}
});
