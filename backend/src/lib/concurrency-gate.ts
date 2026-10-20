type Waiter = { admit: () => void };

/** FIFO admission for a dependency. Pending work is bounded and abortable. */
export class ConcurrencyGate {
  private active = 0;
  private readonly pending = new Set<Waiter>();
  private rejected = 0;
  private cancelled = 0;
  private waited = 0;
  private totalWaitMs = 0;
  private maxWaitMs = 0;

  constructor(readonly limit: number, readonly queueLimit: number) {
    if (!Number.isSafeInteger(limit) || limit < 1 || !Number.isSafeInteger(queueLimit) || queueLimit < 0)
      throw new Error('Invalid dependency concurrency bounds');
  }

  async acquire(signal: AbortSignal): Promise<() => void> {
    signal.throwIfAborted();
    if (this.active < this.limit) {
      this.active++;
      return this.releaseOnce();
    }
    if (this.pending.size >= this.queueLimit) {
      this.rejected++;
      throw new Error('Dependency admission queue is full');
    }
    const start = performance.now();
    return new Promise((resolve, reject) => {
      const cancel = () => {
        if (!this.pending.delete(waiter)) return;
        signal.removeEventListener('abort', cancel);
        this.cancelled++;
        reject(signal.reason);
      };
      const waiter: Waiter = {admit: () => {
        signal.removeEventListener('abort', cancel);
        const ms = performance.now() - start;
        this.waited++;
        this.totalWaitMs += ms;
        this.maxWaitMs = Math.max(this.maxWaitMs, ms);
        resolve(this.releaseOnce());
      }};
      this.pending.add(waiter);
      signal.addEventListener('abort', cancel, {once: true});
    });
  }

  private releaseOnce() {
    let released = false;
    return () => {
      if (released) return;
      released = true;
      const next = this.pending.values().next().value;
      if (next) {
        this.pending.delete(next);
        next.admit();
      } else this.active--;
    };
  }

  snapshot() {
    return {active: this.active, pending: this.pending.size, limit: this.limit, queueLimit: this.queueLimit,
      rejected: this.rejected, cancelled: this.cancelled, waited: this.waited,
      totalWaitMs: this.totalWaitMs, maxWaitMs: this.maxWaitMs};
  }
}
