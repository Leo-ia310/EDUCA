import { readFileSync } from 'node:fs';
import pg from 'pg';
import { loadEnv, pgConfig } from './env.mjs';

// Explicit operator command. Default is a local-only plan, not a database write.
const args=process.argv.slice(2),at=args.indexOf('--secrets-file');
if(at<0||!args[at+1])throw Error('Required: --secrets-file <absolute local secrets file>; optional --apply');
const settings=Object.fromEntries(readFileSync(args[at+1],'utf8').split(/\r?\n/).filter(line=>line.includes('=')&&!line.trim().startsWith('#'))
  .map(line=>{const at=line.indexOf('=');return [line.slice(0,at).trim(),line.slice(at+1).trim()];}));
const secret=settings.ORIGINALITY_CRON_SECRET;
if(!secret||secret.length<32||secret.length>512)throw Error('Invalid ORIGINALITY_CRON_SECRET length');
const env=loadEnv(),base=new URL(env.SUPABASE_URL);
if(base.protocol!=='https:'||base.hostname!==env.SUPABASE_PROJECT_REF+'.supabase.co')throw Error('Supabase project reference mismatch');
const names=['nivra_originality_url','nivra_originality_cron_secret'];
if(!args.includes('--apply')) {
  console.log(JSON.stringify({mode:'plan',projectRef:env.SUPABASE_PROJECT_REF,vaultNames:names,activatesCron:false}));
} else {
  const client=new pg.Client({...pgConfig(env),connectionTimeoutMillis:15000,application_name:'nivra_edge_vault_setup'});
  try {
    await client.connect();await client.query('begin');await client.query("set local lock_timeout='5s'; set local statement_timeout='15s'");
    const cron=(await client.query("select to_regclass('cron.job') is not null present")).rows[0].present;
    if(cron&&(await client.query("select 1 from cron.job where jobname='nivra-originality' and active limit 1")).rowCount)throw Error('Stop the active Nivra schedule before rotating its secret');
    const values=[base.origin+'/functions/v1/nivra-originality',secret];
    for(let i=0;i<names.length;i++) {
      const found=await client.query('select id from vault.secrets where name=$1',[names[i]]);
      if(found.rowCount>1)throw Error('Duplicate Nivra Vault configuration');
      if(found.rowCount)await client.query('select vault.update_secret($1::uuid,$2::text)',[found.rows[0].id,values[i]]);
      else await client.query('select vault.create_secret($1::text,$2::text)',[values[i],names[i]]);
    }
    await client.query('commit');console.log(JSON.stringify({mode:'applied',vaultNames:names,activatesCron:false}));
  } catch(error) {
    await client.query('rollback').catch(()=>{});
    console.error(JSON.stringify({error:'Vault provisioning failed; no secret values logged',code:error.code??null}));process.exitCode=1;
  } finally { await client.end(); }
}
