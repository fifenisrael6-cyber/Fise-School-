-- Joining a teacher group must immediately create the server-side membership used
-- by evaluation, assignment, QCM and private-file authorization.
-- The expected class is checked before joining; raising an exception rolls back
-- any changes made by the nested join_teacher_access_code call.
CREATE OR REPLACE FUNCTION public.join_teacher_access_code_for_class(
  p_code text,
  p_expected_class_id uuid
)
RETURNS TABLE(teacher_id uuid, class_id uuid, access_code_id text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_code text := upper(trim(coalesce(p_code, '')));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_expected_class_id IS NULL THEN
    RAISE EXCEPTION 'A classroom is required';
  END IF;

  IF v_code LIKE 'FISE-%' THEN
    v_code := substring(v_code from 6);
  ELSIF v_code LIKE 'FISE%' THEN
    v_code := regexp_replace(v_code, '^FISE-?', '');
  ELSIF v_code LIKE 'GRP-%' THEN
    v_code := substring(v_code from 5);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.teacher_access_codes tac
    WHERE upper(trim(tac.code)) = v_code
      AND tac.class_id = p_expected_class_id::text
      AND tac.is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid code for this classroom';
  END IF;

  -- This RPC creates/updates class_students and teacher_access_memberships.
  -- Because this is one transaction, failure rolls the entire join back.
  RETURN QUERY
  SELECT joined.teacher_id, joined.class_id, joined.access_code_id
  FROM public.join_teacher_access_code(p_code) AS joined
  WHERE joined.class_id = p_expected_class_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unable to activate teacher group access';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.join_teacher_access_code_for_class(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_teacher_access_code_for_class(text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_teacher_access_code_for_class(text, uuid) TO authenticated;
