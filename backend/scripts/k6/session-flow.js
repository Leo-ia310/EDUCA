import http from 'k6/http';
import {check,sleep} from 'k6';
import exec from 'k6/execution';
import {Counter,Rate,Trend} from 'k6/metrics';
const base=(__ENV.BASE_URL||'http://127.0.0.1:3000').replace(/\/$/,'');
const accounts=JSON.parse(__ENV.ACCOUNTS_JSON||'[]');
const people=Number(__ENV.PEOPLE||Math.max(1,accounts.length));
if(!Number.isInteger(people)||people<1||people>1000)throw Error('PEOPLE must be an integer from 1 to 1000');
const businessRequests=new Counter('business_requests'),failed=new Rate('business_failed'),limited=new Rate('business_limited'),serverFailed=new Rate('business_server_failed'),duration=new Trend('business_duration',true);
export const options={
 setupTimeout:'15m',scenarios:{sessions:{executor:'ramping-vus',startVUs:0,gracefulRampDown:'30s',stages:[
  {duration:'30s',target:Math.max(1,Math.ceil(people/4))},{duration:'2m',target:Math.max(1,Math.ceil(people/4))},
  {duration:'30s',target:Math.max(1,Math.ceil(people/2))},{duration:'2m',target:Math.max(1,Math.ceil(people/2))},
  {duration:'30s',target:people},{duration:'3m',target:people},{duration:'30s',target:0},
 ]}},thresholds:{business_failed:['rate<0.01'],business_duration:['p(95)<2000'],
  business_server_failed:[{threshold:'rate<0.05',abortOnFail:true,delayAbortEval:'30s'}],
  business_limited:[{threshold:'rate<0.10',abortOnFail:true,delayAbortEval:'30s'}]},
 summaryTrendStats:['avg','med','p(95)','p(99)','max'],
};
const journeys={
 admin:['/api/admin/directory/counts','/api/admin/profiles?pageSize=20','/api/events/announcements?limit=20'],
 teacher:['/api/assignments/teacher?limit=20','/api/schedules/mine','/api/chats/conversations?limit=20'],
 student:['/api/assignments/student?limit=20','/api/payments/mine','/api/schedules/mine'],
 parent:['/api/family/children','/api/chats/conversations?limit=20','/api/events/announcements?limit=20'],
};
function json(response){try{return response.json();}catch{return null;}}
function get(path,session,phase){return http.get(base+path,{headers:{Authorization:`Bearer ${session.token}`},timeout:'70s',tags:{phase,name:path.split('?')[0],role:session.role}});}
export function setup(){
 if(!Array.isArray(accounts)||accounts.length<people)throw Error('Provide at least PEOPLE distinct test accounts through ACCOUNTS_JSON. Accounts are never multiplied.');
 const sessions=[],ids=new Set();
 for(const account of accounts.slice(0,people)){
  if(!journeys[account.role])throw Error('Every account needs role admin/teacher/student/parent');
  const response=http.post(base+'/api/auth/login',JSON.stringify({username:account.username,password:account.password,institutionCode:account.institutionCode||'EDU360'}),{headers:{'content-type':'application/json'},timeout:'70s',tags:{phase:'setup',name:'/api/auth/login'}});
  const data=json(response)?.data;
  if(response.status!==200||!data?.session?.accessToken||data.institution?.code!=='EDU360')throw Error('Login/EDU360 scope failed; no business load started.');
  if(ids.has(data.user.id))throw Error('Repeated identity; each virtual person must have a distinct account.');
  ids.add(data.user.id);const session={token:data.session.accessToken,role:account.role};
  for(const path of journeys[session.role]){const probe=get(path,session,'setup');if(probe.status!==200||json(probe)?.ok!==true)throw Error('Journey prerequisite failed: '+path+' HTTP '+probe.status);}
  sessions.push(session);
 }
 console.log(JSON.stringify({profile:'session-flow',distinctAccounts:sessions.length,peakVus:people,thinkSeconds:'3–7',writes:false}));
 return sessions;
}
export default function(sessions){
 const session=sessions[exec.vu.idInTest-1];if(!session)throw Error('A virtual user has no assigned identity.');
 for(const path of journeys[session.role]){
  const response=get(path,session,'business');const ok=response.status===200&&json(response)?.ok===true;
  const tags={endpoint:path.split('?')[0],role:session.role};
  businessRequests.add(1,tags);failed.add(!ok,tags);limited.add(response.status===429,tags);serverFailed.add(response.status===0||response.status>=500,tags);duration.add(response.timings.duration,tags);
  check(response,{'business response succeeds':()=>ok});sleep(3+Math.random()*4);
 }
}
export function handleSummary(data){
 delete data.setup_data;
 return {[__ENV.SUMMARY_PATH||'session-flow-summary.json']:JSON.stringify({profile:'session-flow',distinctAccounts:people,peakVus:people,metrics:data.metrics,state:data.state},null,2)};
}
