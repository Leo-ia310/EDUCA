import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { apiManifest } from "../src/lib/api-manifest";

const paths: Record<string, Record<string, unknown>> = {};

for (const entry of apiManifest) {
  if (entry.path.startsWith("action:")) continue;
  const path = entry.path.replace(/\*/g, "{wildcard}").replace(/:id/g, "{id}");
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
    requestBody: ["POST", "PUT", "PATCH"].includes(entry.method)
      ? {
        required: false,
        content: {
          "application/json": {
            schema: { type: "object", additionalProperties: true },
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
            schema: { type: "object", additionalProperties: true },
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
