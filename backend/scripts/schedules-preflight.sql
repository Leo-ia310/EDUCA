-- Read-only. Run before 0038 against a restored copy and then the target DB.
-- Both result sets must be empty. Correct source data through an audited
-- administrative operation; do not automatically delete conflicting slots.
with source as (
  select s.*,c.institution_id class_institution,c.group_id class_group,c.academic_year_id class_year,
    coalesce(case when s.kind='class' then c.group_id else s.group_id end,null) effective_group,
    case when s.kind='class' then c.academic_year_id else g.academic_year_id end linked_year,
    g.institution_id group_institution,g.academic_year_id group_year,
    room.institution_id room_institution,room.name room_name,
    (select count(*) from academic_years y where y.institution_id=s.institution_id and y.is_current and y.active) current_years
  from schedules s left join classes c on c.id=s.class_id
    left join groups g on g.id=case when s.kind='class' then c.group_id else s.group_id end
    left join classrooms room on room.id=s.classroom_id
)
select id,'Datos incompletos o referencias incompatibles; corregir antes de migrar' problem from source
where institution_id is null or weekday_id is null or weekday_id not between 1 and 7
  or start_time is null or end_time is null or start_time>=end_time
  or extract(second from start_time)<>0 or extract(second from end_time)<>0
  or kind='class' and (class_institution is distinct from institution_id or class_group is null
    or class_year is null or class_year is distinct from group_year)
  or effective_group is not null and (group_institution is distinct from institution_id or group_year is null)
  or kind='break' and effective_group is null and current_years<>1
  or kind='class' and classroom_id is not null and (room_institution is distinct from institution_id or nullif(trim(room_name),'') is null);

with normalized as (
  select s.id,s.institution_id,s.weekday_id,s.start_time,s.end_time,
    coalesce(case when s.kind='class' then c.academic_year_id else g.academic_year_id end,
      (select min(y.id) from academic_years y where y.institution_id=s.institution_id and y.is_current and y.active)) year_id,
    case when s.kind='class' then c.group_id else s.group_id end group_id,
    case when s.kind='class' then c.teacher_id end teacher_id,
    case when s.kind='class' then lower(trim(room.name)) end room_key
  from schedules s left join classes c on c.id=s.class_id left join groups g on g.id=s.group_id
    left join classrooms room on room.id=s.classroom_id
)
select a.id first_id,b.id second_id,'Cruce de grupo, maestro o aula' problem
from normalized a join normalized b on a.id<b.id and a.institution_id=b.institution_id and a.year_id=b.year_id
  and a.weekday_id=b.weekday_id and a.start_time<b.end_time and a.end_time>b.start_time
where a.group_id is null or b.group_id is null or a.group_id=b.group_id
  or a.teacher_id=b.teacher_id or a.room_key=b.room_key;
