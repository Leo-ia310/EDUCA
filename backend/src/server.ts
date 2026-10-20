import {createApp} from "./app";
import {env} from "./lib/env";
import {gracefulShutdown} from "./lib/graceful-shutdown";
import {startAnnouncementDeliveryWorker,stopAnnouncementDeliveryWorker} from "./modules/events/announcement-delivery.worker";
import {startPushDeliveryWorker,stopPushDeliveryWorker} from "./modules/notifications/push-delivery.worker";
const server=createApp().listen(env.port,()=>{
 startAnnouncementDeliveryWorker();startPushDeliveryWorker();
 console.log(JSON.stringify({level:"info",service:"educa360-backend",event:"server_started",port:env.port}));
});
server.requestTimeout=env.requestTimeoutMs;
server.headersTimeout=Math.min(env.requestTimeoutMs,15000);
server.keepAliveTimeout=5000;
let stopping=false;
async function stop(signal:string){
 if(stopping)return;stopping=true;
 console.log(JSON.stringify({level:"info",event:"server_draining",signal}));
 const clean=await gracefulShutdown(server,[stopAnnouncementDeliveryWorker,stopPushDeliveryWorker],env.shutdownTimeoutMs);
 console.log(JSON.stringify({level:clean?"info":"error",event:clean?"server_stopped":"server_drain_incomplete"}));
 process.exit(clean?0:1);
}
process.once("SIGTERM",()=>{void stop("SIGTERM");});process.once("SIGINT",()=>{void stop("SIGINT");});
server.once("error",error=>{console.error({event:"server_failed",code:(error as NodeJS.ErrnoException).code});process.exitCode=1;});
