create table public.api_write_receipts(
 institution_id bigint not null references public.institutions(id) on delete cascade,
 user_id bigint not null references public.users(id) on delete cascade,
 idempotency_key uuid not null, operation text not null, request_hash bytea not null,
 response jsonb, created_at timestamptz not null default clock_timestamp(),
 primary key(institution_id,user_id,idempotency_key)
);
alter table public.api_write_receipts enable row level security;
revoke all on public.api_write_receipts from public,anon,authenticated;
create function public.write_receipt_begin(p_inst bigint,p_actor bigint,p_key uuid,p_operation text,p_request jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare receipt public.api_write_receipts%rowtype; fingerprint bytea:=sha256(convert_to(p_request::text,'UTF8'));
begin
 if p_key is null then raise exception 'Clave requerida.' using errcode='22023'; end if;
 insert into public.api_write_receipts(institution_id,user_id,idempotency_key,operation,request_hash)
 values(p_inst,p_actor,p_key,p_operation,fingerprint) on conflict do nothing;
 select * into receipt from public.api_write_receipts where institution_id=p_inst and user_id=p_actor and idempotency_key=p_key for update;
 if receipt.operation<>p_operation or receipt.request_hash<>fingerprint then raise exception 'La clave ya tiene otro contenido.' using errcode='23505'; end if;
 return receipt.response;
end $$;
create function public.write_receipt_finish(p_inst bigint,p_actor bigint,p_key uuid,p_response jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
 update public.api_write_receipts set response=p_response where institution_id=p_inst and user_id=p_actor and idempotency_key=p_key;
 return p_response;
end $$;
revoke all on function public.write_receipt_begin(bigint,bigint,uuid,text,jsonb),public.write_receipt_finish(bigint,bigint,uuid,jsonb) from public,anon,authenticated;

create function public.grading_scale_write(p_id bigint,p_header jsonb,p_ranges jsonb,p_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); header public.grading_scales%rowtype;
 result jsonb; row_range public.grading_scale_ranges%rowtype; value jsonb;
begin
 if not public.administrative_permission(inst,'settings.edit') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
 if jsonb_typeof(p_header) is distinct from 'object' or jsonb_typeof(p_ranges) is distinct from 'array' or jsonb_array_length(p_ranges)>100 then raise exception 'Escala inválida.' using errcode='22023'; end if;
 header:=jsonb_populate_record(null::public.grading_scales,p_header);
 if nullif(trim(header.name),'') is null or header.scale_type not in('numeric','qualitative','letters') or header.scale_type is null
  or header.min_value is null or header.max_value is null or header.pass_value is null or header.decimals is null
  or header.min_value::text in('NaN','Infinity','-Infinity') or header.max_value::text in('NaN','Infinity','-Infinity') or header.pass_value::text in('NaN','Infinity','-Infinity')
  or header.min_value>=header.max_value or header.pass_value<header.min_value or header.pass_value>header.max_value or header.decimals not between 0 and 4 then raise exception 'Escala inválida.' using errcode='22023'; end if;
 for value in select * from jsonb_array_elements(p_ranges) loop
  row_range:=jsonb_populate_record(null::public.grading_scale_ranges,value);
  if nullif(trim(row_range.label),'') is null or row_range.range_min is null or row_range.range_max is null
   or row_range.range_min::text in('NaN','Infinity','-Infinity') or row_range.range_max::text in('NaN','Infinity','-Infinity')
   or row_range.range_min>row_range.range_max or row_range.range_min<header.min_value or row_range.range_max>header.max_value
   or row_range.color is not null and row_range.color!~'^#[0-9A-Fa-f]{6}$' then raise exception 'Rango de escala inválido.' using errcode='22023'; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_ranges) with ordinality x(value,n)
  join jsonb_array_elements(p_ranges) with ordinality y(value,n) on y.n>x.n
  where numrange((x.value->>'range_min')::numeric,(x.value->>'range_max')::numeric,'[]') && numrange((y.value->>'range_min')::numeric,(y.value->>'range_max')::numeric,'[]')) then
  raise exception 'Los rangos no pueden superponerse.' using errcode='22023'; end if;
 result:=public.write_receipt_begin(inst,actor,p_key,'grading_scale_write',jsonb_build_object('id',p_id,'header',p_header,'ranges',p_ranges));
 if result is not null then return result; end if;
 if p_id is null then
  insert into public.grading_scales(institution_id,name,scale_type,min_value,max_value,pass_value,decimals,active)
   values(inst,header.name,header.scale_type,header.min_value,header.max_value,header.pass_value,header.decimals,true) returning * into header;
 else
  update public.grading_scales set name=header.name,scale_type=header.scale_type,min_value=header.min_value,max_value=header.max_value,pass_value=header.pass_value,decimals=header.decimals,active=true
   where id=p_id and institution_id=inst returning * into header;
  if not found then raise exception 'Escala no encontrada.' using errcode='P0002'; end if;
 end if;
 delete from public.grading_scale_ranges where scale_id=header.id;
 insert into public.grading_scale_ranges(scale_id,label,range_min,range_max,description,passed,color)
  select header.id,r.label,r.range_min,r.range_max,r.description,coalesce(r.passed,true),r.color from jsonb_populate_recordset(null::public.grading_scale_ranges,p_ranges) r;
 result:=to_jsonb(header)||jsonb_build_object('grading_scale_ranges',coalesce((select jsonb_agg(to_jsonb(r.*) order by r.range_min,r.id) from public.grading_scale_ranges r where r.scale_id=header.id),'[]'::jsonb));
 return public.write_receipt_finish(inst,actor,p_key,result);
end $$;
revoke all on function public.grading_scale_write(bigint,jsonb,jsonb,uuid) from public,anon;
grant execute on function public.grading_scale_write(bigint,jsonb,jsonb,uuid) to authenticated;

create function public.report_card_generate(p_student bigint,p_period bigint,p_notes text,p_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); year_id bigint; enrollment bigint;
 wide boolean; grade_rows jsonb; average numeric; card public.report_cards%rowtype; result jsonb;
begin
 select academic_year_id into year_id from public.academic_periods where id=p_period and institution_id=inst;
 if year_id is null or length(coalesce(p_notes,''))>2000 then raise exception 'Periodo o notas inválidos.' using errcode='22023'; end if;
 select id into enrollment from public.enrollments where student_id=p_student and institution_id=inst and academic_year_id=year_id order by id desc limit 1;
 if not exists(select 1 from public.students where id=p_student and institution_id=inst) then raise exception 'Estudiante fuera de la institución.' using errcode='42501'; end if;
 if enrollment is null then raise exception 'El estudiante no tiene matrícula en ese año.' using errcode='22023'; end if;
 wide:=public.administrative_permission(inst,'reports.generate') and public.administrative_permission(inst,'reports.view');
 if not wide and not exists(select 1 from public.enrollments e join public.classes c on c.group_id=e.group_id and c.academic_year_id=e.academic_year_id and c.institution_id=e.institution_id
   where e.id=enrollment and public.teacher_class_permission(c.id,'students.view')) then raise exception 'No puedes generar ese boletín.' using errcode='42501'; end if;
 if not public.portal_can('reports.view') or not public.portal_can_view_grades(p_student,p_period) then raise exception 'Boletín restringido.' using errcode='42501'; end if;
 result:=public.write_receipt_begin(inst,actor,p_key,'report_card_generate',jsonb_build_object('student',p_student,'period',p_period,'notes',p_notes));
 if result is not null then return result; end if;
 -- Snapshot the authorized grade rows once: header and lines cannot disagree
 -- if another teacher saves grades while this transaction is running.
 select coalesce(jsonb_agg(jsonb_build_object('subject_id',coalesce(g.subject_id,c.subject_id),'final_score',g.final_score,
  'qualitative_label',g.qualitative_label,'passed',g.passed,'notes',g.notes,'teacher_id',c.teacher_id) order by g.subject_id,g.id),'[]'::jsonb)
 into grade_rows from public.period_grades g left join public.classes c on c.id=g.class_id and c.institution_id=inst
 where g.institution_id=inst and g.student_id=p_student and g.academic_period_id=p_period and (wide or public.teacher_class_permission(g.class_id,'class.view'));
 select round(avg((value->>'final_score')::numeric),2) into average from jsonb_array_elements(grade_rows);
 insert into public.report_cards(institution_id,student_id,enrollment_id,academic_year_id,academic_period_id,overall_average,general_notes,status,generated_at)
  values(inst,p_student,enrollment,year_id,p_period,average,p_notes,'generated',clock_timestamp()) returning * into card;
 insert into public.report_card_lines(report_card_id,subject_id,final_score,qualitative_label,passed,notes,teacher_id)
  select card.id,r.subject_id,r.final_score,r.qualitative_label,r.passed,r.notes,r.teacher_id from jsonb_populate_recordset(null::public.report_card_lines,grade_rows) r;
 result:=to_jsonb(card)||jsonb_build_object('lines',coalesce((select jsonb_agg(to_jsonb(l.*) order by l.id) from public.report_card_lines l where l.report_card_id=card.id),'[]'::jsonb));
 return public.write_receipt_finish(inst,actor,p_key,result);
end $$;
revoke all on function public.report_card_generate(bigint,bigint,text,uuid) from public,anon;
grant execute on function public.report_card_generate(bigint,bigint,text,uuid) to authenticated;
-- Official persisted documents must be generated from database grades.
revoke insert,update,delete on public.report_cards,public.report_card_lines from anon,authenticated;

create function public.charges_create_batch(p_rows jsonb,p_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); result jsonb;
begin
 if not public.administrative_permission(inst,'payments.create') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>10000 then raise exception 'Lote de cargos inválido.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.charges,p_rows) r where r.institution_id is distinct from inst
  or r.amount is null or r.amount<0 or r.amount::text in('NaN','Infinity','-Infinity') or r.discount is null or r.discount<0 or r.discount>r.amount
  or coalesce(r.late_fee,0)<>0 or r.due_at is null or not isfinite(r.due_at)
  or not exists(select 1 from public.students s where s.id=r.student_id and s.institution_id=inst and s.active)
  or not exists(select 1 from public.payment_concepts c where c.id=r.concept_id and c.institution_id=inst and c.active)
  or r.academic_year_id is not null and not exists(select 1 from public.academic_years y where y.id=r.academic_year_id and y.institution_id=inst)) then raise exception 'Cargo inválido o fuera de la institución.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.charges,p_rows) r group by r.student_id,r.concept_id,r.due_at having count(*)>1) then raise exception 'El lote contiene cargos duplicados.' using errcode='22023'; end if;
 result:=public.write_receipt_begin(inst,actor,p_key,'charges_create_batch',p_rows);
 if result is not null then return result; end if;
 with inserted as(insert into public.charges(institution_id,student_id,concept_id,academic_year_id,description,amount,discount,late_fee,total_amount,due_at,status)
  select inst,r.student_id,r.concept_id,r.academic_year_id,r.description,r.amount,r.discount,0,r.amount-r.discount,r.due_at,'pending'
   from jsonb_populate_recordset(null::public.charges,p_rows) r returning id)
 select coalesce(jsonb_agg(id::text order by id),'[]'::jsonb) into result from inserted;
 return public.write_receipt_finish(inst,actor,p_key,result);
end $$;
revoke all on function public.charges_create_batch(jsonb,uuid) from public,anon;
grant execute on function public.charges_create_batch(jsonb,uuid) to authenticated;
notify pgrst,'reload schema';
