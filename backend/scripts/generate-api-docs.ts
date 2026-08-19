import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { apiManifest } from "../src/lib/api-manifest";

const docsPath = join(process.cwd(), "..", "docs", "APIS_PENDIENTES_POR_CONECTAR.md");

const pending = apiManifest.filter((entry) => entry.frontendStatus === "pending");
const byModule = new Map<string, typeof pending>();

for (const entry of pending) {
  const rows = byModule.get(entry.module) ?? [];
  rows.push(entry);
  byModule.set(entry.module, rows);
}

const lines = [
  "# APIs Pendientes Por Conectar",
  "",
  "> Archivo generado automaticamente. No editar a mano.",
  "> Fuente: `backend/src/lib/api-manifest.ts`.",
  "> Para actualizar: `cd backend && npm run docs:apis`.",
  "",
  "Estas APIs ya estan preparadas en el backend, pero todavia no tienen interfaz Flutter conectada.",
  "",
  "## Regla Para Futuras Modificaciones",
  "",
  "Cuando se agregue, quite o cambie una API, actualiza `backend/src/lib/api-manifest.ts` y ejecuta `npm run docs:apis`. El comando `npm run build` tambien regenera este archivo antes de compilar.",
  "",
  "## Resumen",
  "",
  `- Total pendiente de conectar: ${pending.length}`,
  `- Modulos con trabajo pendiente: ${byModule.size}`,
  "",
];

for (const [module, entries] of [...byModule.entries()].sort(([a], [b]) => a.localeCompare(b))) {
  lines.push(`## ${title(module)}`, "");
  lines.push("| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const entry of entries) {
    lines.push([
      `\`${entry.method}\``,
      `\`${entry.path}\``,
      escapeCell(entry.summary),
      escapeCell(entry.auth),
      escapeCell(entry.request),
      escapeCell(entry.response),
      `\`${entry.source}\``,
      escapeCell(entry.notes ?? ""),
    ].join(" | ").replace(/^/, "| ").replace(/$/, " |"));
  }
  lines.push("");
}

while (lines.length > 0 && lines[lines.length - 1] === "") {
  lines.pop();
}

writeFileSync(docsPath, `${lines.join("\n")}\n`, "utf8");
console.log(`API docs generated: ${docsPath}`);

function title(value: string) {
  return value
    .split(/[_-]/g)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function escapeCell(value: string) {
  return value.replace(/\|/g, "\\|").replace(/\n/g, " ");
}
