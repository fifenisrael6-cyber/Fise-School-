-- Technical variants must not be treated as common subjects for Literary/Scientific teachers.
update public.subjects
set teaching_stream='technical'
where is_active and code in ('en_tech_english','fr_tech_francais','en_tech_citizenship','fr_tech_ecm','en_tech_pe','fr_tech_eps','en_tech_entrepreneurship');

update public.curricula cu
set teaching_stream=s.teaching_stream
from public.subjects s
where s.id=cu.subject_id and cu.teaching_stream is distinct from s.teaching_stream;

notify pgrst,'reload schema';