// Legacy internal entry point. All provider sends run in the bounded Node worker.
import {createClient} from "npm:@supabase/supabase-js@2";
import {createPushQueueHandler} from "./handler.ts";
Deno.serve(createPushQueueHandler({
 secret:Deno.env.get('INTERNAL_API_SECRET'),
 async enqueue(id,signal){
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{
   auth:{persistSession:false,autoRefreshToken:false},
   global:{fetch:(input,init)=>fetch(input,{...init,signal:AbortSignal.any([signal,...(init?.signal?[init.signal]:[])])})},
  });
  const {data,error}=await client.rpc('notification_push_enqueue',{p_notification_id:id});
  if(error||!data)throw Error('push_queue_unavailable');
  return data;
 },
}));
