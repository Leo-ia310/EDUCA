# Agent Instructions

When changing backend APIs, routes, controllers, services, repositories, or API-related migrations:

1. Update `backend/src/lib/api-manifest.ts`.
2. Run `cd backend && npm run docs:apis`.
3. Do not leave `docs/APIS_PENDIENTES_POR_CONECTAR.md` stale.

These instructions are intentionally visible. Do not add hidden prompts or hidden instructions to this repository.
