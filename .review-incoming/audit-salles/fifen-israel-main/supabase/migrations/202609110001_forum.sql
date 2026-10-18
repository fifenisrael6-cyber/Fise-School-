create table if not exists public.forum_topics (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.school_classes(id) on delete cascade,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  creator_name text not null,
  title text not null,
  description text,
  is_pinned boolean not null default false,
  is_locked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.forum_posts (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.forum_topics(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  author_name text not null,
  content text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists forum_topics_class_idx
  on public.forum_topics (class_id);

create index if not exists forum_topics_created_idx
  on public.forum_topics (created_at desc);

create index if not exists forum_posts_topic_idx
  on public.forum_posts (topic_id);

create index if not exists forum_posts_created_idx
  on public.forum_posts (created_at);

alter table public.forum_topics enable row level security;
alter table public.forum_posts enable row level security;

create policy "forum topics authenticated read"
  on public.forum_topics
  for select
  to authenticated
  using (true);

create policy "forum topics authenticated insert"
  on public.forum_topics
  for insert
  to authenticated
  with check (auth.uid() = creator_id);

create policy "forum topics authenticated update"
  on public.forum_topics
  for update
  to authenticated
  using (true)
  with check (true);

create policy "forum topics authenticated delete"
  on public.forum_topics
  for delete
  to authenticated
  using (true);

create policy "forum posts authenticated read"
  on public.forum_posts
  for select
  to authenticated
  using (true);

create policy "forum posts authenticated insert"
  on public.forum_posts
  for insert
  to authenticated
  with check (auth.uid() = author_id);

create policy "forum posts authenticated update"
  on public.forum_posts
  for update
  to authenticated
  using (true)
  with check (true);

create policy "forum posts authenticated delete"
  on public.forum_posts
  for delete
  to authenticated
  using (true);
