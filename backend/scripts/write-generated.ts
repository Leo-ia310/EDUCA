import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";

/** Preserve unchanged artifacts and never truncate a file while a reader maps it. */
export function writeGenerated(path: string, content: string) {
  if (existsSync(path) && readFileSync(path, "utf8") === content) return;
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
  try {
    writeFileSync(temporary, content, "utf8");
    for (let attempt = 0; ; attempt++) {
      try { renameSync(temporary, path); break; }
      catch (error) {
        const code = (error as NodeJS.ErrnoException).code;
        if (attempt >= 9 || !["EPERM", "EBUSY", "EACCES", "UNKNOWN"].includes(code ?? "")) throw error;
        // Build scripts only: short bounded retries for transient Windows locks.
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25 * (attempt + 1));
      }
    }
  } finally {
    if (existsSync(temporary)) rmSync(temporary);
  }
}
