import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { zipSync, strToU8 } from 'npm:fflate@0.8.3';
import { createHandler } from '../handler.ts';
import { createWorkerHandler } from '../app.ts';
import { runStep, limits, algorithmVersion, downloadBounded, type QueuePort, type Checkpoint, type Candidate } from '../step.ts';
import { prepareText, sha256 } from '../generated/domain.ts';
import { readPdfPage } from '../pdf.ts';
const { pdf } = createRequire(import.meta.url)('../../../../backend/test/fixtures/originality-pdf.cjs');
const body = Array.from({ length: 80 }, (_, i) => 'word' + i).join(' ');
const secret = 'test-only-secret-'.repeat(4);

function twoPagePdf() {
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [4 0 R 6 0 R] /Count 2 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  for (let i=0;i<2;i++) {
    const stream='BT /F1 9 Tf 12 TL 20 700 Td '+(body.match(/(?:\S+\s*){1,8}/gu) ?? []).map(line=>'('+line+') Tj T*').join(' ')+' ET';
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5+2*i} 0 R >>`,
      `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
  }
  let source='%PDF-1.4\n';const offsets=[0];
  objects.forEach((obj,i)=>{offsets.push(source.length);source+=`${i+1} 0 obj\n${obj}\nendobj\n`;});
  const xref=source.length;
  source+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n${offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')}trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return new TextEncoder().encode(source);
}

function fixture(bytes?: Uint8Array, mime = 'text/plain', count = 0) {
  let checkpoint: Checkpoint | null = null, finished = false; let error: string | undefined;
  let content = bytes;
  const yielded: Checkpoint[] = [], committed: Record<string, unknown>[] = [];
  const doc = { id: 1, institution_id: 1, assignment_id: 1, submission_id: 1, file_id: bytes ? 1 : null, source_notes: body };
  const academic = prepareText(body);
  const port: QueuePort = {
    async rpc<T>(name: string, args: Record<string, unknown> = {}) {
      let data: unknown = null;
      if (name === 'originality_edge_claim') data = finished ? null : { id: 1, document_id: 1, lock_token: 'fixture', checkpoint: structuredClone(checkpoint) };
      if (name === 'originality_edge_live') data = true;
      if (name === 'originality_edge_yield') { checkpoint = structuredClone(args.p_state) as Checkpoint; yielded.push(structuredClone(checkpoint)); data = true; }
      if (name === 'originality_edge_finish') { committed.push(args); finished = true; data = true; }
      if (name === 'originality_fail') { error = String(args.p_code); finished = true; }
      if (name === 'originality_candidates') {
        const after = Number(args.p_after);
        data = after < count + 1 && count > 0 ? [{ ...doc, id: after < 2 ? 2 : after + 1, submission_id: 2, binary_hash: null, academic } satisfies Candidate] : [];
      }
      return data as T;
    },
    document: async () => doc, shared: async () => [],
    file: async () => ({ storage_path: '1/synthetic/file', mime_type: mime, size_bytes: content?.length ?? 0 }),
    sourceUrl: async () => 'https://fixture.invalid/signed',
  };
  const fetcher: typeof fetch = (_url, init) => {
    assert.equal((init as { redirect?: string } | undefined)?.redirect, 'error');
    return Promise.resolve(new Response(content ? new Uint8Array(content).buffer : undefined));
  };
  return { port, fetcher, yielded, committed, get error() { return error; }, setBytes(value: Uint8Array) { content = value; } };
}
async function drain(f: ReturnType<typeof fixture>) {
  const statuses = [];
  for (let i = 0; i < 60; i++) {
    const result = await runStep(f.port, f.fetcher); statuses.push(result.status);
    if (result.status === 'completed' || result.status === 'failed') break;
  }
  assert.equal(statuses.at(-1), 'completed'); return statuses;
}

Deno.test('handler rejects anonymous, invalid secret, wrong method and arbitrary work selection', async () => {
  let calls = 0; const handler = createHandler(secret, () => { calls++; return Promise.resolve({ status: 'idle' }); });
  const request = (value?: string, body?: string, method = 'POST') => new Request('https://fixture.invalid', {
    method, headers: value ? { 'x-originality-secret': value } : {}, ...(body ? { body } : {}),
  });
  assert.equal((await handler(request())).status,401);
  assert.equal((await handler(request('wrong'))).status,401);
  assert.equal((await handler(request(secret, undefined, 'GET'))).status,405);
  assert.equal((await handler(request(secret, '{"documentId":1}'))).status,400);
  assert.equal((await handler(request(secret, 'x'.repeat(129)))).status,400);
  assert.equal(calls,0);
  const accepted = await handler(request(secret,'{}'));
  assert.equal(accepted.status,200); assert.equal(accepted.headers.get('cache-control'),'no-store'); assert.equal(calls,1);
  assert.equal((await createHandler(undefined, () => Promise.resolve({}))(request(secret))).status,503);
  const unavailable = await createHandler(secret, () => { throw Error('private database detail'); })(request(secret));
  assert.equal(unavailable.status,503); assert.ok(!(await unavailable.text()).includes('private'));
});

Deno.test('default validation mode only runs fixed probes and never touches the production queue or files', async () => {
  const forbidden=()=>{throw Error('production dependency was touched');};
  const port: QueuePort={rpc:forbidden,document:forbidden,file:forbidden,shared:forbidden,sourceUrl:forbidden};
  const handler=createWorkerHandler({secret},port);
  for(const format of ['txt','docx','pdf','prepare','compare']) {
    const response=await handler(new Request('https://fixture.invalid?probe='+format,{method:'POST',headers:{'x-originality-secret':secret},body:'{}'}));
    assert.equal(response.status,200);const result=await response.json();
    assert.equal(result.status,'validated');assert.equal(result.mode,'validate');assert.equal(result.words,format==='pdf'?80:20000);
  }
});

Deno.test('TXT and DOCX survive persisted phase transitions and produce the same shared algorithm output', async () => {
  const docx = zipSync({
    '[Content_Types].xml': strToU8('<Types><Override ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'),
    'word/document.xml': strToU8('<w:document><w:body><w:p><w:r><w:t>' + body + '</w:t></w:r></w:p></w:body></w:document>'),
  });
  for (const [bytes,mime] of [[new TextEncoder().encode(body),'text/plain'],[docx,'application/vnd.openxmlformats-officedocument.wordprocessingml.document']] as const) {
    const f = fixture(bytes,mime); await drain(f);
    const result = f.committed[0].p_result as { state: string; academic: { normalized: string }; binaryHash: string; algorithmVersion: string };
    assert.equal(result.state,'completed'); assert.equal(result.academic.normalized,prepareText(body).normalized);
    assert.equal(result.binaryHash,sha256(bytes)); assert.equal(result.algorithmVersion,algorithmVersion);
    assert.deepEqual(f.yielded.map(c => c.stage),['prepare','compare','finish']);
  }
});

Deno.test('PDF uses the serverless parser, produces selectable text and rejects page overflow', async () => {
  const bytes = pdf(body); const f = fixture(bytes,'application/pdf'); await drain(f);
  const result = f.committed[0].p_result as { state: string; academic: { tokens: unknown[] } };
  assert.equal(result.state,'completed'); assert.equal(result.academic.tokens.length,80);
  await assert.rejects(() => readPdfPage(bytes,1,0),/resource_limit/);
  const empty = fixture(pdf(''),'application/pdf'); await drain(empty);
  assert.equal((empty.committed[0].p_result as {state:string}).state,'insufficient_text');
});

Deno.test('candidate pagination resumes across invocations and never commits an incomplete maximum', async () => {
  const f = fixture(undefined,'text/plain',7); await drain(f);
  assert.ok(f.yielded.filter(c => c.stage === 'compare').length >= 3);
  assert.equal(f.committed.length,1);
  const pairs = f.committed[0].p_pairs as {aCoverage:number;otherId:number}[];
  assert.equal(pairs.length,7); assert.ok(pairs.every(p => p.aCoverage === 100));
  assert.equal(new Set(pairs.map(p => p.otherId)).size,7);
});

Deno.test('multi-page PDF yields after each page and detects a changed object before combining text', async () => {
  const f=fixture(twoPagePdf(),'application/pdf');
  await runStep(f.port,f.fetcher); assert.equal(f.yielded[0].stage,'pdf'); assert.equal(f.yielded[0].pdfPage,2);
  assert.equal(f.committed.length,0); await drain(f);
  assert.equal((f.committed[0].p_result as {academic:{tokens:unknown[]}}).academic.tokens.length,160);
  const changed=fixture(twoPagePdf(),'application/pdf');await runStep(changed.port,changed.fetcher);
  changed.setBytes(pdf(body));
  assert.equal((await runStep(changed.port,changed.fetcher)).status,'failed');
  assert.equal(changed.error,'invalid_document'); assert.equal(changed.committed.length,0);
});

Deno.test('input limits apply to declared and streamed sizes; bytes are not fetched with redirects enabled', async () => {
  await assert.rejects(() => downloadBounded('https://fixture.invalid',10, () => Promise.resolve(new Response(new Uint8Array(11), { headers: {'Content-Length':'11'} }))),/resource_limit/);
  await assert.rejects(() => downloadBounded('https://fixture.invalid',10, () => Promise.resolve(new Response(new Uint8Array(11)))),/resource_limit/);
  const f = fixture(new Uint8Array(limits.maxBytes + 1));
  const result = await runStep(f.port,f.fetcher); assert.equal(result.status,'failed'); assert.equal(f.error,'resource_limit'); assert.equal(f.committed.length,0);
});

Deno.test('MIME spoofing and untrusted checkpoints cannot publish analysis', async () => {
  const f = fixture(pdf(body),'text/plain');
  assert.equal((await runStep(f.port,f.fetcher)).status,'failed'); assert.equal(f.error,'mime_mismatch'); assert.equal(f.committed.length,0);
});
