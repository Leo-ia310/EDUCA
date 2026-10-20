import { detached, requestRuntime } from "./request-lifetime";
export class Readiness {
    private cached?: {
        healthy: boolean;
        until: number;
    };
    private inFlight?: Promise<boolean>;
    constructor(private readonly probe: () => Promise<boolean>, private readonly now: () => number = Date.now) { }
    async check() {
        if (requestRuntime().draining)
            return false;
        if (this.cached && this.cached.until > this.now())
            return this.cached.healthy;
        if (this.inFlight)
            return await this.inFlight && !requestRuntime().draining;
        const pending = detached(async () => {
            let healthy = false;
            try {
                healthy = await this.probe();
            }
            catch { /* no private dependency errors in health responses */ }
            this.cached = { healthy, until: this.now() + 2000 };
            return healthy;
        });
        this.inFlight = pending;
        try {
            return await pending && !requestRuntime().draining;
        }
        finally {
            if (this.inFlight === pending)
                this.inFlight = undefined;
        }
    }
}
