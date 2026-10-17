import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { apiManifest } from "../src/lib/api-manifest";
import { requestSchemas, responseSchemas } from "../src/lib/api-schemas";

const paths: Record<string, Record<string, unknown>> = {};

// Cada esquema tipado debe corresponder a una entrada del manifiesto (evita que se desincronicen).
const known = new Set(apiManifest.map((e) => `${e.method} ${e.path}`));
for (const key of [...Object.keys(responseSchemas), ...Object.keys(requestSchemas)]) {
  if (!known.has(key)) throw new Error(`api-schemas.ts: «${key}» no existe en api-manifest.ts`);
}

for (const entry of apiManifest) {
  if (entry.path.startsWith("action:")) continue;
  const path = entry.path.replace(/\*/g, "{wildcard}").replace(/:([A-Za-z]+)/g, "{$1}");
  const pathParams = [...path.matchAll(/\{([A-Za-z]+)\}/g)].map((m) => m[1]);
  const typed = responseSchemas[`${entry.method} ${entry.path}`];
  const typedRequest = requestSchemas[`${entry.method} ${entry.path}`];
  const method = entry.method.toLowerCase();
  paths[path] ??= {};
  paths[path][method] = {
    tags: [entry.module],
    summary: entry.summary,
    description: [
      `Auth: ${entry.auth}.`,
      entry.notes ? `Notas: ${entry.notes}` : "",
      `Fuente: ${entry.source}.`,
    ].filter(Boolean).join("\n\n"),
    security: entry.auth === "publico" ? [] : [{ bearerAuth: [] }],
    parameters: pathParams.length
      ? pathParams.map((name) => ({ name, in: "path", required: true, schema: { type: "string" } }))
      : undefined,
    requestBody: ["POST", "PUT", "PATCH"].includes(entry.method)
      ? {
        required: typedRequest ? true : false,
        content: {
          "application/json": {
            schema: typedRequest ?? { type: "object", additionalProperties: true },
            examples: {
              manifest: { value: entry.request },
            },
          },
        },
      }
      : undefined,
    responses: {
      "200": {
        description: entry.response,
        content: {
          "application/json": {
            schema: typed
              ? { type: "object", required: ["ok", "data"], properties: { ok: { type: "boolean", const: true }, data: typed } }
              : { type: "object", additionalProperties: true },
          },
        },
      },
      "400": { description: "Error de validación o negocio." },
      "401": { description: "Sesión requerida o inválida." },
      "403": { description: "Permisos insuficientes." },
    },
  };
}

const document = {
  openapi: "3.1.0",
  info: {
    title: "Nivra Backend API",
    version: "0.1.0",
    description:
      "Contrato inicial generado desde backend/src/lib/api-manifest.ts. Los schemas son deliberadamente amplios hasta centralizar DTOs formales.",
  },
  servers: [{ url: "http://localhost:3000" }],
  components: {
    securitySchemes: {
      bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT" },
    },
  },
  paths,
};

const docsPath = join(process.cwd(), "..", "docs", "openapi.json");
writeFileSync(docsPath, `${JSON.stringify(document, null, 2)}\n`, "utf8");
console.log(`OpenAPI generated: ${docsPath}`);
