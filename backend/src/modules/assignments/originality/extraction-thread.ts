import { parentPort, workerData } from 'node:worker_threads';
import { getHeapStatistics } from 'node:v8';
import { extract, type ExtractionInput } from './extract';

export const safeError = (error: unknown) => error instanceof Error && ['resource_limit','mime_mismatch','invalid_document','extraction_timeout'].includes(error.message) ? error.message : 'analysis_unavailable';
if (parentPort) {
  extract(workerData as ExtractionInput).then(result => parentPort!.postMessage({ result: { ...result, runtime: { heapSizeLimitBytes: getHeapStatistics().heap_size_limit } } }))
    .catch(error => parentPort!.postMessage({ error: safeError(error) }));
}
