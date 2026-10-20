import {randomUUID} from 'node:crypto';
const keys=new WeakMap();
function keyed(payload,key='requestId'){
 if(payload[key])return payload;
 let value=keys.get(payload);if(!value){value=randomUUID();keys.set(payload,value);}
 return {...payload,[key]:value};
}
// Test tools keep one UUID for a reused payload. No production requests are
// issued here; callers explicitly own fixture creation, execution and cleanup.
export function withRequestKey(method,path,body){
 if(method!=='POST'||!body||typeof body!=='object')return body;
 if(/\/admin\/(students|teachers|parents|profiles)$/.test(path)||/\/chats\/messages$/.test(path))return keyed(body);
 if(body.action==='chat.sendMessage'&&body.payload&&typeof body.payload==='object')return {...body,payload:keyed(body.payload)};
 return body;
}
