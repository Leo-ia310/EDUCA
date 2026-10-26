// Sin argumentos valida y revierte. --apply confirma una carga ya autorizada.
import {readFileSync} from 'node:fs';
import pg from 'pg';
import {loadEnv,pgConfig} from './env.mjs';
const apply=process.argv.includes('--apply');
const client=new pg.Client({...pgConfig(loadEnv()),connectionTimeoutMillis:15000});
const tables=['grading_scales','grading_scale_ranges','assignments','evaluations','submissions','grades','period_grades','class_sessions','attendances','calendar_events'];
async function counts() {
  const result={};
  for(const table of tables) {
    const where=table==='grading_scale_ranges'
      ? "scale_id in(select s.id from grading_scales s join institutions i on i.id=s.institution_id where i.code='BIGSCHOOL')"
      : "institution_id=(select id from institutions where code='BIGSCHOOL')";
    result[table]=Number((await client.query(`select count(*) n from ${table} where ${where}`)).rows[0].n);
  }
  return result;
}
try {
  await client.connect();
  await client.query('begin');
  await client.query("set local statement_timeout='90s'");
  const before=await counts();
  await client.query(readFileSync(new URL('../../supabase/demo/bigschool-presentation.sql',import.meta.url),'utf8'));
  const after=await counts();
  const added=Object.fromEntries(tables.map(t=>[t,after[t]-before[t]]));
  // Cada alumno matriculado debe tener notas publicadas en los tres trimestres.
  const missing=await client.query(`select r.student_id,c.id class_id,p.id period_id
    from bs_roster r join bs_classes c on c.group_id=r.group_id
    join academic_periods p on p.academic_year_id=c.academic_year_id
    where not exists(select 1 from evaluations e join grades g on g.evaluation_id=e.id
      where e.class_id=c.id and e.academic_period_id=p.id and e.published and g.student_id=r.student_id)`);
  if(missing.rowCount) throw Error('Hay materias o trimestres sin notas: se revierte toda la carga.');
  if(apply && Object.values(added).some(n=>n>0)) {
    await client.query(`insert into audit_log(institution_id,table_name,record_id,action,data_after)
      select institution_id,'bigschool_presentation','v1','DEMO_SEED',$1::jsonb from bs_context`,[JSON.stringify({added,synthetic:true})]);
  }
  await client.query(apply?'commit':'rollback');
  console.log(JSON.stringify({mode:apply?'applied':'validated-and-rolled-back',before,added,after,missingGradeScopes:missing.rowCount},null,2));
} catch(e) {
  await client.query('rollback').catch(()=>{});
  console.error('Carga revertida:',e.code??'',e.message||'Conexión no disponible');
  process.exitCode=1;
} finally {await client.end();}
