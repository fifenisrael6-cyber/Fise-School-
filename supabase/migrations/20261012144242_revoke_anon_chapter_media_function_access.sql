-- Revoke anonymous access to the chapter media access-check functions.
-- Authenticated students/teachers retain the required execute grants.
revoke all on function public.student_can_access_chapter(uuid) from anon;
revoke all on function public.teacher_can_upload_chapter_media(uuid) from anon;
grant execute on function public.student_can_access_chapter(uuid) to authenticated;
grant execute on function public.teacher_can_upload_chapter_media(uuid) to authenticated;
