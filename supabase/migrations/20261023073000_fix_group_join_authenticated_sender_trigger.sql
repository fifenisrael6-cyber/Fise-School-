-- Fix student group joining: the membership trigger previously inserted a
-- synthetic chat message as the group owner. Message guards correctly require
-- auth.uid() = sender_id, so the INSERT raised "Authenticated sender required"
-- and rolled back the entire join transaction.
--
-- Keep the separate message_group_member_notification trigger: it notifies
-- existing group members through public.notifications without forging a chat
-- message or consuming a student's message quota.
drop trigger if exists message_group_membership_notifications
  on public.message_group_members;
