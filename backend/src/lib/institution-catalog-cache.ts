import { randomUUID } from "node:crypto";

type ScaleCatalog = { scale: Record<string, unknown> | null; status: string };
type AttendanceStatuses = Array<Record<string, unknown>>;
type Options = {
  url?: string;
  token?: string;
  namespace?: string;
  fetch?: typeof fetch;
  now?: () => number;
  timeoutMs?: number;
};

/** Allowlisted reference catalogs only. Never cache grants, grades,
 * identities, chat or request contexts here. Authentication still runs on hits.
 * Versioned keys prevent a pre-mutation loader repopulating the current key.
 */
export class InstitutionCatalogCache {
  private readonly pending = new Map<string, Promise<unknown>>();
  private readonly statusRequests = new Map<string, Promise<AttendanceStatuses>>();
  private readonly statusLocal = new Map<string, { value: AttendanceStatuses; until: number }>();
  private unavailableUntil = 0;
  readonly metrics = { hits: 0, misses: 0, joins: 0, failures: 0, localHits: 0 };
  constructor(private readonly options: Options = {}) {}

  private get enabled() { return Boolean(this.options.url && this.options.token); }
  private get now() { return (this.options.now ?? Date.now)(); }
  snapshot() {
    return { enabled: this.enabled, circuitOpen: this.now < this.unavailableUntil,
      localEntries: this.statusLocal.size, ...this.metrics };
  }
  private key(institutionId: number, catalog = "scale") {
    if (!Number.isSafeInteger(institutionId) || institutionId <= 0) {
      throw new Error("Invalid catalog institution scope");
    }
    return `${this.options.namespace ?? "nivra"}:${catalog}:v1:${institutionId}`;
  }
  private failed() {
    this.metrics.failures++;
    this.unavailableUntil = this.now + 30_000;
  }
  private async command(args: Array<string | number>): Promise<unknown> {
    const response = await (this.options.fetch ?? fetch)(this.options.url!, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.options.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(this.options.timeoutMs ?? 2000),
    });
    if (!response.ok) throw new Error("Catalog cache unavailable");
    const body = await response.json() as { result?: unknown; error?: unknown };
    if (body.error) throw new Error("Catalog cache command failed");
    return body.result;
  }

  async read(institutionId: number, load: () => Promise<ScaleCatalog>): Promise<ScaleCatalog> {
    const base = this.key(institutionId);
    return this.readEntry(base, 30, load, (value: unknown): value is ScaleCatalog => {
      if (!value || typeof value !== "object") return false;
      const item = value as ScaleCatalog;
      return (item.status === "configured" && !!item.scale && typeof item.scale === "object" && !Array.isArray(item.scale)) ||
        (item.status === "not_configured" && item.scale === null);
    }, true);
  }

  /** Static public reference data, never the students or their actual marks.
   * 10s bounded L1 reduces free-tier Redis commands; Redis TTL is 60s.
   * There is no app mutation for this catalog; external SQL changes expire.
   */
  async readAttendanceStatuses(institutionId: number, load: () => Promise<AttendanceStatuses>): Promise<AttendanceStatuses> {
    const key = this.key(institutionId, "attendance-statuses");
    if (!this.enabled) return load();
    const local = this.statusLocal.get(key);
    if (local && local.until > this.now) {
      this.metrics.localHits++;
      return structuredClone(local.value);
    }
    const existing = this.statusRequests.get(key);
    if (existing) { this.metrics.joins++; return structuredClone(await existing); }
    const pending = (async () => {
      const value = await this.readEntry(key, 60, load, isAttendanceStatuses, false);
      // Bounded map even when a process serves many institutions.
      this.statusLocal.delete(key);
      if (this.statusLocal.size >= 128) this.statusLocal.delete(this.statusLocal.keys().next().value!);
      this.statusLocal.set(key, { value: structuredClone(value), until: this.now + 10_000 });
      return value;
    })();
    this.statusRequests.set(key, pending);
    try { return structuredClone(await pending); }
    finally { if (this.statusRequests.get(key) === pending) this.statusRequests.delete(key); }
  }

  private async readEntry<T>(base: string, ttl: number, load: () => Promise<T>,
    valid: (value: unknown) => value is T, revisioned: boolean): Promise<T> {
    if (!this.enabled || this.now < this.unavailableUntil) return load();
    let key: string;
    try {
      const version = revisioned ? await this.command(["GET", `${base}:revision`]) : null;
      key = revisioned ? `${base}:${typeof version === "string" ? version : "0"}` : base;
      const raw = await this.command(["GET", key]);
      if (typeof raw === "string") {
        const value: unknown = JSON.parse(raw);
        if (valid(value)) {
          this.metrics.hits++;
          return value;
        }
      }
    } catch {
      this.failed();
      return load();
    }
    const existing = this.pending.get(key);
    if (existing) { this.metrics.joins++; return existing as Promise<T>; }
    this.metrics.misses++;
    const pending = (async () => {
      const result = await load();
      try {
        await this.command(["SET", key, JSON.stringify(result), "EX", ttl]);
      } catch { this.failed(); }
      return result;
    })();
    this.pending.set(key, pending);
    try { return await pending; }
    finally { if (this.pending.get(key) === pending) this.pending.delete(key); }
  }

  async invalidate(institutionId: number) {
    const base = this.key(institutionId);
    if (!this.enabled) return;
    try {
      // Revision outlives every old value, then expires to bound storage.
      await this.command(["SET", `${base}:revision`, randomUUID(), "EX", 300]);
      this.unavailableUntil = 0;
    } catch { this.failed(); }
  }
}

function isAttendanceStatuses(value: unknown): value is AttendanceStatuses {
  return Array.isArray(value) && value.every(row => row && typeof row === "object" &&
    Number.isSafeInteger(row.id) && row.id > 0 && typeof row.name === "string" &&
    typeof row.code === "string" && typeof row.counts_as_absent === "boolean");
}
