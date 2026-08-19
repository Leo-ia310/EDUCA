import { createApp } from "./app";
import { env } from "./lib/env";

const app = createApp();

app.listen(env.port, () => {
  console.log(`Educa360 backend listening on http://localhost:${env.port}`);
});
