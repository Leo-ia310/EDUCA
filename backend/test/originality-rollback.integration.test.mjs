import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {database} from './helpers/database.mjs';
test('0058 rollback leaves academic source tables and original files intact',{timeout:120000},async()=>{
 const db=await database();
 try{
  await db.admin.query(await readFile(new URL('../../supabase/rollback/0058_nivra_originality.sql',import.meta.url),'utf8'));
  for(const name of ['submissions','files','grades','assignments'])assert.equal((await db.admin.query('select to_regclass($1)::text name',[name])).rows[0].name,name);
  assert.equal((await db.admin.query("select to_regclass('originality_documents') name")).rows[0].name,null);
  assert.equal((await db.admin.query("select count(*) n from pg_trigger where tgname like 'originality_%'")).rows[0].n,'0');
 }finally{await db.close();}
});
