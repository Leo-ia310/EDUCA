import { Worker } from 'node:worker_threads';
import { join } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { requireSupabaseServiceRole } from '../../../lib/supabase';
import { OriginalityRepository, type Job } from './originality.repository';
import { compareTexts } from './domain';
import { safeError } from './extraction-thread';
import type { ExtractionInput, ExtractionResult } from './extract';
import { originalityConfig } from './config';

export async function isolatedExtraction(input: ExtractionInput, timeoutMs: number): Promise<ExtractionResult> {
  return new Promise((resolve, reject) => {
    const worker = new Worker(join(__dirname, 'extraction-thread.js'), { workerData: input,
      env: { NODE_ENV: 'production' }, execArgv: [],
      // The parent CLI's --max-old-space-size overrides a smaller isolate limit.
      // Match the documented 160 MiB old-space budget and report the real V8 limit.
      resourceLimits: { maxOldGenerationSizeMb: 160, maxYoungGenerationSizeMb: 16, stackSizeMb: 4 } });
    const timer = setTimeout(() => { void worker.terminate(); reject(new Error('extraction_timeout')); }, timeoutMs);
    worker.once('message', (message: { result?: ExtractionResult; error?: string }) => {
      clearTimeout(timer); void worker.terminate();
      if (message.result) resolve(message.result); else reject(new Error(message.error ?? 'analysis_unavailable'));
    });
    worker.once('error', error => { clearTimeout(timer); reject(error); });
    worker.once('exit', code => { clearTimeout(timer); if (code !== 0) reject(new Error('analysis_unavailable')); });
  });
}

async function download(url: string, maxBytes: number): Promise<Uint8Array> {
  const response = await fetch(url, { signal: AbortSignal.timeout(15000), redirect: 'error' });
  if (!response.ok || !response.body) throw new Error('analysis_unavailable');
  if (Number(response.headers.get('content-length')) > maxBytes) { await response.body.cancel(); throw new Error('resource_limit'); }
  const chunks: Uint8Array[] = []; let size = 0;
  const reader = response.body.getReader();
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length; if (size > maxBytes) throw new Error('resource_limit'); chunks.push(value);
    }
  } finally { await reader.cancel(); }
  return Buffer.concat(chunks, size);
}

export class OriginalityWorker {
  private busy = false;
  constructor(private readonly repository: Pick<OriginalityRepository,'rpc'|'document'|'shared'|'file'|'sourceUrl'|'candidates'> & { readonly databaseRequests?: number }, private readonly config = originalityConfig(),
    private readonly extraction = isolatedExtraction) {}
  async runOnce() {
    if (this.busy) return;
    this.busy = true;
    let job: Job | null = null;
    const started = performance.now(), cpu = process.cpuUsage();
    const initialDatabaseRequests = this.repository.databaseRequests ?? 0;
    try {
      job = await this.repository.rpc<Job | null>('originality_claim'); if (!job) return;
      const doc = await this.repository.document(job.document_id);
      const shared = await this.repository.shared(doc.institution_id, doc.assignment_id);
      const input: ExtractionInput = { ...this.config, shared, notes: doc.source_notes ?? '' };
      if (doc.file_id) {
        if (!await this.repository.rpc<boolean>('originality_source_allowed', { p_submission: doc.submission_id, p_file: doc.file_id })) throw new Error('invalid_document');
        const file = await this.repository.file(doc.institution_id, doc.file_id);
        if (!file.storage_path?.startsWith(`${doc.institution_id}/`)) throw new Error('invalid_document');
        if (file.size_bytes > this.config.maxBytes) throw new Error('resource_limit');
        input.mime = file.mime_type;
        input.bytes = await download(await this.repository.sourceUrl(file.storage_path), this.config.maxBytes);
      }
      const result = await this.extraction(input, this.config.timeoutMs);
      const pairs: Record<string, unknown>[] = [];
      let after = 0, queries = 0, lastHeartbeat = performance.now(), pairBytes = 0;
      if (result.state === 'completed' || result.binaryHash) {
        while (true) {
          if (performance.now() - started > 90000 || queries > 2000) throw new Error('resource_limit');
          if (performance.now() - lastHeartbeat > 15000) { await this.repository.rpc('originality_heartbeat', { p_job: job.id, p_lock: job.lock_token }); lastHeartbeat = performance.now(); }
          const candidates = await this.repository.candidates({ ...doc, algorithm_version: this.config.algorithmVersion }, result.binaryHash, result.textHash, result.fingerprints, after); queries++;
          if (!candidates.length) break;
          const candidate = candidates[0]; after = candidate.id;
          const binaryIdentical = result.binaryHash != null && result.binaryHash === candidate.binary_hash;
          const comparison = result.academic && candidate.academic ? compareTexts(result.academic, candidate.academic, this.config.ngram)
            : { aCoverage: 0, bCoverage: 0, aIntervals: [], bIntervals: [], textIdentical: false };
          if (comparison.aCoverage > 0 || comparison.bCoverage > 0 || binaryIdentical) {
            const pair = { otherId: candidate.id, ...comparison, binaryIdentical };
            pairBytes += JSON.stringify(pair).length;
            if (pairBytes > 2 * 1024 * 1024) throw new Error('resource_limit');
            pairs.push(pair);
          }
        }
      }
      const durationMs = Math.ceil(performance.now() - started);
      await this.repository.rpc('originality_finish', { p_job: job.id, p_lock: job.lock_token,
        p_result: { ...result, academic: result.academic ? { ...result.academic, fingerprints: [] } : null,
          algorithmVersion: this.config.algorithmVersion, durationMs }, p_pairs: pairs });
      console.log(JSON.stringify({ event: 'originality_processed', format: input.mime ?? 'editor', state: result.state, attempts: job.attempts,
        jobId: job.id, documentId: job.document_id, algorithmVersion: this.config.algorithmVersion,
        queueWaitMs: Math.max(0, Date.now() - Date.parse(job.enqueued_at) - durationMs), durationMs, candidateQueries: queries,
        databaseRequests: (this.repository.databaseRequests ?? 0) - initialDatabaseRequests,
        deduplicatedPairs: pairs.filter(p => p.binaryIdentical || p.textIdentical).length,
        rssBytes: process.memoryUsage().rss, maxRssKb: process.resourceUsage().maxRSS, extractionHeapLimitBytes: result.runtime?.heapSizeLimitBytes, cpuMicros: process.cpuUsage(cpu) }));
    } catch (error) {
      if (job) await this.repository.rpc('originality_fail', { p_job: job.id, p_lock: job.lock_token, p_code: safeError(error) })
        .catch(() => console.error(JSON.stringify({ event: 'originality_lease_recovery_pending' })));
      console.error(JSON.stringify({ event: 'originality_failed', jobId: job?.id, code: safeError(error) }));
    } finally { this.busy = false; }
  }
}

if (require.main === module) {
  const repository = new OriginalityRepository(requireSupabaseServiceRole());
  const config = originalityConfig(), worker = new OriginalityWorker(repository, config);
  let stopped = false, after = 0, nextReconcile = 0, nextMetrics = 0;
  process.once('SIGTERM', () => { stopped = true; }); process.once('SIGINT', () => { stopped = true; });
  void (async () => {
    while (!stopped) {
      try {
        if (Date.now() >= nextMetrics) {
          console.log(JSON.stringify({ event: 'originality_queue_metrics', ...await repository.rpc<Record<string, number>>('originality_metrics') }));
          nextMetrics = Date.now() + 60000;
        }
        if (Date.now() >= nextReconcile) {
          after = await repository.rpc<number>('originality_reconcile', { p_after: after });
          nextReconcile = Date.now() + (after === 0 ? 60000 : 1000);
        }
        await worker.runOnce();
      } catch { console.error(JSON.stringify({ event: 'originality_queue_unavailable' })); }
      await pause(config.pollMs);
    }
  })().catch(() => { process.exitCode = 1; });
}
