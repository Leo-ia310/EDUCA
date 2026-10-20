import type { Server } from "node:http";
import { beginDrain, abortRequests } from "./request-lifetime";
export async function gracefulShutdown(server: Server, stops: Array<() => Promise<void>>, timeoutMs: number): Promise<boolean> {
    beginDrain();
    const closed = new Promise<void>((resolve, reject) => { server.close(error => error ? reject(error) : resolve()); server.closeIdleConnections(); });
    let timer: NodeJS.Timeout | undefined;
    const deadline = new Promise<false>(resolve => { timer = setTimeout(() => { abortRequests(); server.closeAllConnections(); resolve(false); }, timeoutMs); });
    const drain = Promise.allSettled([closed, ...stops.map(stop => Promise.resolve().then(stop))]).then(results => results.every(result => result.status === 'fulfilled'));
    try {
        return await Promise.race([drain, deadline]);
    }
    finally {
        clearTimeout(timer);
    }
}
