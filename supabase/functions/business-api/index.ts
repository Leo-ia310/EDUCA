import {createBusinessProxy} from "./proxy.ts";
Deno.serve(createBusinessProxy({
 target:Deno.env.get("BACKEND_API_BASE_URL"),
 allowedOrigins:(Deno.env.get("CORS_ORIGIN")??"").split(",").map(value=>value.trim()).filter(Boolean),
}));
