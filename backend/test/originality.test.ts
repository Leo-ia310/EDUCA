import assert from 'node:assert/strict';
import { test } from 'node:test';
import { zipSync, strToU8 } from 'fflate';
import { prepareText, compareTexts, mergeIntervals, sha256 } from '../src/modules/assignments/originality/domain';
import { extract, type ExtractionInput } from '../src/modules/assignments/originality/extract';
import { parseOriginalityQuery, parseOriginalityRetry } from '../src/modules/assignments/originality/originality.schemas';
import { parseSubmissionFiles } from '../src/modules/assignments/submission.schemas';
const body = Array.from({ length: 80 }, (_, i) => `palabra${i}`).join(' ');
const defaults: ExtractionInput = { maxBytes: 5 * 1024 * 1024, maxPages: 50, maxWords: 20000, minWords: 40, ngram: 5 };
test('Unicode, whitespace, case, hashes and offsets are deterministic; filenames never enter the algorithm', () => {
  assert.equal(prepareText('ＡBC\n DEF').textHash, prepareText('abc def').textHash);
  assert.equal(sha256(Buffer.from(body)), sha256(Buffer.from(body)));
  assert.notEqual(sha256('a'), sha256('b'));
  const text = prepareText('😀 Nombre: x\n' + body);
  const token = text.tokens.find(t => t.word === 'palabra0')!;
  assert.equal(Array.from(text.text).slice(token.start, token.end).join(''), 'palabra0');
});
test('explicit metadata, shared lines, quotes and bibliography are auditable; body remains', () => {
  const text = prepareText('Nombre: Ana\nEscribe un ensayo sobre la energía\n' + body + '\n> una cita\nBibliografía\nfuente externa', ['Escribe un ensayo sobre la energía']);
  assert.equal(text.tokens.length, 80);
  assert.ok(text.excluded.some(e => e.rule === 'shared_instruction_line'));
  assert.equal(compareTexts(text, prepareText(body)).aCoverage, 100);
  const words=body.split(' ');
  const withQuote=prepareText(words.slice(0,40).join(' ')+'\n> excluded quote\n'+words.slice(40).join(' '));
  const match=compareTexts(withQuote,prepareText(body));
  assert.equal(match.aCoverage,100);assert.equal(match.aIntervals.length,2);
  assert.ok(match.aIntervals.every(([l,r])=>!Array.from(withQuote.text).slice(l,r).join('').includes('excluded')));
});
test('coverage fuses overlaps, is directional and ignores trivial grams', () => {
  assert.deepEqual(mergeIntervals([[0, 5], [3, 10], [12, 14]]), [[0, 10], [12, 14]]);
  const a = prepareText(body), b = prepareText(body + ' ' + Array.from({ length: 80 }, (_, i) => `otro${i}`).join(' '));
  const result = compareTexts(a, b);
  assert.equal(result.aCoverage, 100); assert.equal(result.bCoverage, 50);
  assert.equal(compareTexts(prepareText('de la de la de la de la de la'), prepareText('de la de la de la de la')).aCoverage, 0);
  assert.equal(compareTexts(prepareText(''), prepareText('')).aCoverage, 0);
});
test('extraction states: editor, TXT, DOCX, short/empty, MIME spoof and zip limits', async () => {
  assert.equal((await extract({ ...defaults, notes: body })).state, 'completed');
  assert.equal((await extract({ ...defaults, notes: '' })).state, 'insufficient_text');
  assert.equal((await extract({ ...defaults, bytes: Buffer.from(body), mime: 'text/plain' })).state, 'completed');
  const docx = zipSync({ '[Content_Types].xml': strToU8('<Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'), 'word/document.xml': strToU8(`<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>${body}</w:t></w:r></w:p></w:body></w:document>`) });
  const parsed = await extract({ ...defaults, bytes: docx, mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' });
  assert.equal(parsed.textHash, prepareText(body).textHash);
  await assert.rejects(extract({ ...defaults, bytes: docx, mime: 'text/plain' }), /mime_mismatch/);
  await assert.rejects(extract({ ...defaults, bytes: Buffer.from([0, 1]), mime: 'text/plain' }), /mime_mismatch/);
  assert.equal((await extract({ ...defaults, bytes: Buffer.from('image'), mime: 'image/png' })).state, 'unsupported_format');
  const bomb = zipSync({ 'word/document.xml': new Uint8Array(2 * 1024 * 1024 + 1) });
  await assert.rejects(extract({ ...defaults, bytes: bomb, mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }), /resource_limit/);
  await assert.rejects(extract({ ...defaults, notes: body, maxWords: 10 }), /resource_limit/);
});
test('request schemas reject coercion, unbounded keys, invalid flags and retry payloads', () => {
  assert.deepEqual(parseOriginalityQuery('5', { evidence: 'true' }), { submissionId: 5, evidence: true });
  assert.throws(() => parseOriginalityQuery('0', {}));
  assert.throws(() => parseOriginalityQuery('1', { evidence: 'yes' }));
  assert.throws(() => parseOriginalityQuery('1', { institutionId: 2 }));
  assert.throws(() => parseOriginalityRetry('1', { source: 2 }));
  assert.equal(parseSubmissionFiles(undefined),null);
  assert.deepEqual(parseSubmissionFiles([]),[]);
  assert.throws(()=>parseSubmissionFiles({id:1}));
  assert.throws(()=>parseSubmissionFiles([{id:'invalid'}]));
});

const { pdf } = require('./fixtures/originality-pdf.cjs') as { pdf: (text: string) => Buffer };
test('selectable PDF extracts text, an empty/scanned-equivalent page is insufficient', async () => {
  assert.equal((await extract({ ...defaults, bytes: pdf(body), mime: 'application/pdf' })).state, 'completed');
  assert.equal((await extract({ ...defaults, bytes: pdf(''), mime: 'application/pdf' })).state, 'insufficient_text');
  await assert.rejects(extract({ ...defaults, bytes: pdf(body), mime: 'text/plain' }), /mime_mismatch/);
});
