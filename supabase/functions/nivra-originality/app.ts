import { createHandler } from './handler.ts';
import { runProbe } from './probe.ts';
import { runStep, type QueuePort } from './step.ts';

export function createWorkerHandler(config: { secret?: string; enabled?: boolean }, port: QueuePort) {
  return createHandler(config.secret, async request => {
    if (!config.enabled) return await runProbe(new URL(request.url).searchParams.get('probe') ?? 'txt');
    const result = await runStep(port);
    console.log(JSON.stringify({ event: 'originality_edge_step', ...result }));
    return result;
  });
}
