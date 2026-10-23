import { compareTexts, sha256, type AcademicText } from './generated/domain.ts';
import { readDocument, prepareExtraction, type ExtractionResult } from './generated/extract-core.ts';

export const limits = { maxBytes: 5242880, maxPages: 50, maxWords: 20000, minWords: 40, ngram: 5 };
export const algorithmVersion = 'nivra-1-n5-m40';
type Pair = ReturnType<typeof compareTexts> & { otherId: number; binaryIdentical: boolean };
type Result = ExtractionResult & { algorithmVersion: string; durationMs: number };
export type Checkpoint = {
  stage: 'extract' | 'pdf' | 'prepare' | 'compare' | 'finish'; version: string;
  text?: string; pdfPage?: number; binaryHash?: string | null;
  result?: Result; after?: number; pairs?: Pair[]; spentMs?: number;
};
export type Job = { id: number; document_id: number; lock_token: string; checkpoint: Checkpoint | null };
type Document = { id: number; institution_id: number; assignment_id: number; submission_id: number; file_id: number | null; source_notes: string | null };
export type Candidate = Document & { binary_hash: string | null; academic: AcademicText | null };
export interface QueuePort {
  rpc<T>(name: string, args?: Record<string, unknown>): Promise<T>;
  document(id: number): Promise<Document>;
  shared(institution: number, assignment: number): Promise<string[]>;
  file(institution: number, id: number): Promise<{ storage_path: string; mime_type: string; size_bytes: number }>;
  sourceUrl(path: string): Promise<string>;
}
export async function downloadBounded(url: string, maxBytes: number, fetcher: typeof fetch = fetch) {
  const response = await fetcher(url, { signal: AbortSignal.timeout(15000), redirect: 'error' });
  if (!response.ok || !response.body) throw Error('analysis_unavailable');
  if (Number(response.headers.get('content-length')) > maxBytes) { await response.body.cancel(); throw Error('resource_limit'); }
  const reader = response.body.getReader(); const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const part = await reader.read(); if (part.done) break;
      size += part.value.length; if (size > maxBytes) throw Error('resource_limit'); chunks.push(part.value);
    }
  } finally { await reader.cancel(); }
  const bytes = new Uint8Array(size); let at = 0;
  for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.length; }
  return bytes;
}
export const safeError = (error: unknown) => error instanceof Error &&
  ['resource_limit','mime_mismatch','invalid_document','extraction_timeout'].includes(error.message) ? error.message : 'analysis_unavailable';

// One bounded phase per invocation. No self-invocation or permanent polling loop.
export async function runStep(port: QueuePort, fetcher: typeof fetch = fetch) {
  const started = performance.now();
  await port.rpc('originality_edge_reconcile');
  const job = await port.rpc<Job | null>('originality_edge_claim');
  if (!job) return { status: 'idle' };
  try {
    const doc = await port.document(job.document_id);
    let checkpoint: Checkpoint = job.checkpoint ?? { stage: 'extract', version: algorithmVersion };
    if (checkpoint.version !== algorithmVersion) throw Error('invalid_document');
    const previousStage = checkpoint.stage;
    if (!await port.rpc<boolean>('originality_edge_live', { p_document: doc.id })) throw Error('invalid_document');
    if (checkpoint.stage === 'extract' || checkpoint.stage === 'pdf') {
      if (doc.file_id) {
        const file = await port.file(doc.institution_id, doc.file_id);
        if (!file.storage_path.startsWith(`${doc.institution_id}/`) || file.size_bytes > limits.maxBytes) throw Error('resource_limit');
        const bytes = await downloadBounded(await port.sourceUrl(file.storage_path), limits.maxBytes, fetcher);
        const hash = sha256(bytes);
        if (checkpoint.binaryHash && checkpoint.binaryHash !== hash) throw Error('invalid_document');
        const isPdf = new TextDecoder().decode(bytes.subarray(0,5)) === '%PDF-';
        if (isPdf) {
          const { readPdfPage } = await import('./pdf.ts');
          if (file.mime_type !== 'application/pdf') throw Error('mime_mismatch');
          const page = checkpoint.pdfPage ?? 1;
          const result = await readPdfPage(bytes, page, limits.maxPages);
          const text = (checkpoint.text ?? '') + (page > 1 ? '\n' : '') + result.text;
          if (text.length > 500000) throw Error('resource_limit');
          checkpoint = { ...checkpoint, stage: page < result.totalPages ? 'pdf' : 'prepare', text, pdfPage: page + 1, binaryHash: hash };
        } else {
          if (checkpoint.stage === 'pdf') throw Error('invalid_document');
          const raw = await readDocument({ ...limits, bytes, mime: file.mime_type }, () => { throw Error('invalid_document'); });
          checkpoint = raw.unsupported
            ? { version: algorithmVersion, stage: 'compare', after: 0, pairs: [], result: { state: 'unsupported_format', binaryHash: raw.binaryHash, textHash: null, academic: null, fingerprints: [], algorithmVersion, durationMs: 0 } }
            : { ...checkpoint, stage: 'prepare', text: raw.text, binaryHash: raw.binaryHash };
        }
      } else checkpoint = { ...checkpoint, stage: 'prepare', text: doc.source_notes ?? '', binaryHash: null };
    } else if (checkpoint.stage === 'prepare') {
      const shared = await port.shared(doc.institution_id, doc.assignment_id);
      const result = prepareExtraction(checkpoint.text ?? '', checkpoint.binaryHash ?? null, { ...limits, shared });
      checkpoint = { version: algorithmVersion, stage: 'compare', after: 0, pairs: [], spentMs: checkpoint.spentMs,
        result: { ...result, academic: result.academic ? { ...result.academic, fingerprints: [] } : null, algorithmVersion, durationMs: 0 } };
    } else if (checkpoint.stage === 'compare') {
      const result = checkpoint.result; if (!result) throw Error('invalid_document');
      const pairs = checkpoint.pairs ?? [];
      // Hard page cap plus a soft elapsed-time budget. Exhaustion always yields;
      // it never publishes a maximum before all candidates have been traversed.
      for (let i = 0; i < 3; i++) {
        if (i > 0 && performance.now() - started > 350) break;
        if (!result.academic && !result.binaryHash) { checkpoint.stage = 'finish'; break; }
        const candidates = await port.rpc<Candidate[]>('originality_candidates', {
          p_document: doc.id, p_binary: result.binaryHash, p_text: result.textHash,
          p_fingerprints: result.fingerprints, p_after: checkpoint.after ?? 0, p_version: algorithmVersion,
        });
        if (!candidates.length) { checkpoint.stage = 'finish'; break; }
        const candidate = candidates[0];
        const comparison = result.academic && candidate.academic ? compareTexts(result.academic, candidate.academic, limits.ngram)
          : { aCoverage: 0, bCoverage: 0, aIntervals: [], bIntervals: [], textIdentical: false };
        const binaryIdentical = !!result.binaryHash && result.binaryHash === candidate.binary_hash;
        if (comparison.aCoverage > 0 || comparison.bCoverage > 0 || binaryIdentical) pairs.push({ otherId: candidate.id, ...comparison, binaryIdentical });
        checkpoint.after = candidate.id;
        if (JSON.stringify(pairs).length > 2 * 1024 * 1024) throw Error('resource_limit');
      }
      checkpoint.pairs = pairs;
    } else if (checkpoint.stage === 'finish') {
      if (!checkpoint.result) throw Error('invalid_document');
      checkpoint.result.durationMs = Math.ceil((checkpoint.spentMs ?? 0) + performance.now() - started);
      const committed = await port.rpc<boolean>('originality_edge_finish', { p_job: job.id, p_lock: job.lock_token,
        p_result: checkpoint.result, p_pairs: checkpoint.pairs ?? [] });
      return { status: committed ? 'completed' : 'discarded', stage: previousStage };
    } else throw Error('invalid_document');
    checkpoint.spentMs = Math.ceil((checkpoint.spentMs ?? 0) + performance.now() - started);
    const live = await port.rpc<boolean>('originality_edge_yield', { p_job: job.id, p_lock: job.lock_token, p_state: checkpoint });
    return { status: live ? 'yielded' : 'discarded', stage: previousStage, nextStage: checkpoint.stage };
  } catch (error) {
    const code = safeError(error);
    await port.rpc('originality_fail', { p_job: job.id, p_lock: job.lock_token, p_code: code })
      .catch(() => console.error(JSON.stringify({ event: 'originality_edge_lease_recovery_pending' })));
    return { status: 'failed', code };
  }
}
