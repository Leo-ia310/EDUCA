import { createApp } from "./app";
import { env } from "./lib/env";
import { startAnnouncementDeliveryWorker } from "./modules/events/announcement-delivery.worker";

const app = createApp();

app.listen(env.port, () => {
  startAnnouncementDeliveryWorker();
  console.log(JSON.stringify({
    level: "info",
    service: "educa360-backend",
    event: "server_started",
    port: env.port,
  }));
});
