import { createApp } from "./app";
import { env } from "./lib/env";

const app = createApp();

app.listen(env.port, () => {
  console.log(JSON.stringify({
    level: "info",
    service: "educa360-backend",
    event: "server_started",
    port: env.port,
  }));
});
