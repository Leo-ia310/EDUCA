type Summary = {
    count: number;
    errors: number;
    totalMs: number;
    maxMs: number;
    latencyBuckets: number[];
};
const bounds = [100, 300, 1000, 3000, 10000, 30000, 60000];
const requests = new Map<string, Summary>(), dependencies = new Map<string, Summary>();
function record(map: Map<string, Summary>, key: string, ms: number, failed: boolean) {
    let current = map.get(key);
    if (!current) {
        current = { count: 0, errors: 0, totalMs: 0, maxMs: 0, latencyBuckets: Array(bounds.length + 1).fill(0) };
        map.set(key, current);
    }
    current.count++;
    current.errors += Number(failed);
    current.totalMs += ms;
    current.maxMs = Math.max(current.maxMs, ms);
    const bucket = bounds.findIndex(bound => ms <= bound);
    current.latencyBuckets[bucket < 0 ? bounds.length : bucket]++;
}
export const operationalMetrics = {
    request(method: string, route: string, status: number, ms: number) { record(requests, `${method} ${route} ${status}`, ms, status >= 500); },
    dependency(name: string, status: number, ms: number) { record(dependencies, `${name} ${status === 0 ? 'transport' : String(status)}`, ms, status === 0 || status >= 500); },
    snapshot(active: number, draining: boolean) { return { scope: "process", uptimeSeconds: Math.floor(process.uptime()), activeRequests: active, draining, latencyBucketUpperMs: [...bounds, null], requests: Object.fromEntries(requests), dependencies: Object.fromEntries(dependencies) }; }
};
