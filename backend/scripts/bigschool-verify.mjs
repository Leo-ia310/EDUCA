// Verificación de lectura con las sesiones y RLS reales. Nunca imprime tokens.
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {loadEnv} from './env.mjs';
const env=loadEnv();
const base='https://nivra-backend-mcc4.onrender.com/api';
const accounts=[['Osmar','teacher','BIGSCHOOL_PASSWORD'],['Pablo','student','BIGSCHOOL_PASSWORD'],['Maikel','parent','BIGSCHOOL_PASSWORD'],['Ernesto','director','BIGSCHOOL_DIRECTOR_PASSWORD']];
async function json(url,options={}) {
  const response=await fetch(url,{...options,signal:AbortSignal.timeout(45000)});
  const body=await response.json();
  assert.equal(response.status,200,`HTTP ${response.status}: ${body.error?.code??body.code??'unexpected'}`);
  return body;
}
let failed=false;
for(const [name,role,passwordEnv] of accounts.filter(([name])=>!process.env.BIGSCHOOL_VERIFY_ACCOUNTS||process.env.BIGSCHOOL_VERIFY_ACCOUNTS.split(',').includes(name))) {
  let token;
  let stage='login';
  try {
    assert.ok(process.env[passwordEnv],`Falta ${passwordEnv}`);
    const login=await json(`${base}/auth/login`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username:`${name}@bigschool.edu`,password:process.env[passwordEnv],institutionCode:'BIGSCHOOL'})});
    token=login.data?.session?.accessToken;
    assert.ok(token,'Login sin sesión (posible 2FA pendiente).');
    assert.equal(login.data?.institution?.code,'BIGSCHOOL');
    const headers={Authorization:`Bearer ${token}`};
    const db=createClient(env.SUPABASE_URL,env.SUPABASE_ANON_KEY,{global:{headers},auth:{persistSession:false,autoRefreshToken:false}});
    stage='scale';
    const scale=await json(`${base}/grades/scales/default`,{headers});
    assert.ok(scale.data?.scale??scale.scale,'Escala no visible.');
    stage='periods';
    const periods=await json(`${base}/grades/periods`,{headers});
    assert.equal((periods.data?.periods??periods.periods).length,3);
    const summary={account:name,role,login:'ok',scale:'visible',periods:3};
    if(role==='student'||role==='parent') {
      const studentId=role==='student'?22:23;
      stage='grades';
      const {data:grades,error}=await db.from('grades').select('evaluation_id,score,evaluations!inner(published,academic_period_id)').eq('institution_id',2).eq('student_id',studentId);
      assert.ifError(error);
      assert.ok(grades.length>=48,'Notas insuficientes en la sesión familiar.');
      assert.equal(new Set(grades.filter(g=>g.evaluations.published).map(g=>g.evaluations.academic_period_id)).size,3);
      stage='report';
      const {data:report,error:reportError}=await db.rpc('student_report_context',{p_student_id:studentId,p_period_id:6});
      assert.ifError(reportError);
      assert.ok(report.attendancePct>0,'Asistencia no visible en el boletín.');
      stage='assignments';
      const {data:feed,error:feedError}=await db.rpc('assignment_feed',{p_student_id:studentId,p_limit:20});
      assert.ifError(feedError);
      assert.ok(feed.assignments.length>0,'Tareas no visibles.');
      Object.assign(summary,{visibleGrades:grades.length,attendancePct:report.attendancePct,visibleTasks:feed.assignments.length});
      if(role==='parent') {
        const {data:children,error:childrenError}=await db.from('parent_students').select('student_id').eq('parent_id',17);
        assert.ifError(childrenError); assert.equal(children.length,4);
        summary.children=children.length;
      }
    } else {
      stage='gradebook';
      const gradebook=await json(`${base}/grades/gradebook?classId=14&periodId=6`,{headers});
      const book=gradebook.data??gradebook;
      assert.ok(book.students.length>=5);assert.ok(book.evaluations.length>=4);
      Object.assign(summary,{gradebookStudents:book.students.length,gradebookEvaluations:book.evaluations.length});
      if(role==='teacher') {
        const {data:workspace,error}=await db.rpc('teacher_dashboard_classes');
        assert.ifError(error);assert.ok(workspace);
        summary.dashboard='visible';
      }
    }
    console.log(JSON.stringify(summary));
  } catch(e) {failed=true;console.error(JSON.stringify({account:name,status:'failed',stage,message:e.message}));}
  finally {
    if(token) {
      const admin=createClient(env.SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
      const {error}=await admin.auth.admin.signOut(token,'local');
      if(error) {failed=true;console.error(JSON.stringify({account:name,sessionClosed:false}));}
    }
  }
}
if(failed) process.exitCode=1;
