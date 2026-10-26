-- 쮸카이브 관리자 잠금 + 사이트에서 바로 영상 추가/수정 (board.sql 다음에 통째로 붙여넣고 Run)
-- 관리자 비밀번호 = 게시판 관리자 비밀번호(board_admin)와 같아요.
-- 편집자 비밀번호는 맨 아래 줄에서 정해요.

create table if not exists public.site_editor (
  id int primary key default 1 check (id = 1),
  pw_hash text not null
);
alter table public.site_editor enable row level security;
revoke all on public.site_editor from anon, authenticated;

-- 사이트에서 추가한 영상
create table if not exists public.vid_add (
  id bigint generated always as identity primary key,
  url text not null unique check (char_length(url) between 10 and 300),
  title text not null check (char_length(title) between 1 and 300),
  date text check (date ~ '^\d{4}-\d{2}-\d{2}$'),
  category text not null check (char_length(category) between 1 and 40),
  sub text check (sub is null or char_length(sub) <= 40),
  created_at timestamptz not null default now()
);
alter table public.vid_add enable row level security;
revoke all on public.vid_add from anon, authenticated;

-- 영상 수정(카테고리 이동, 세부 카테고리, 삭제)
create table if not exists public.vid_edit (
  url text primary key,
  category text,
  sub text,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.vid_edit enable row level security;
revoke all on public.vid_edit from anon, authenticated;

-- 비밀번호로 역할 확인: 'admin' / 'editor' / null
create or replace function public.site_role(p_pw text) returns text
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if coalesce(p_pw, '') = '' then return null; end if;
  if public.board_is_admin(p_pw) then return 'admin'; end if;
  if exists (select 1 from public.site_editor e where e.pw_hash = crypt(p_pw, e.pw_hash)) then return 'editor'; end if;
  return null;
end $$;

-- 누구나: 추가된 영상과 수정 내용 읽기
create or replace function public.vid_list() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'adds', coalesce((select jsonb_agg(jsonb_build_object('url', a.url, 'title', a.title, 'date', a.date, 'category', a.category, 'sub', a.sub) order by a.id) from public.vid_add a), '[]'::jsonb),
    'edits', coalesce((select jsonb_agg(jsonb_build_object('url', e.url, 'category', e.category, 'sub', e.sub, 'deleted', e.deleted)) from public.vid_edit e), '[]'::jsonb)
  );
$$;

-- 편집자·관리자: 영상 추가
create or replace function public.vid_add_one(p_pw text, p_url text, p_title text, p_date text, p_category text, p_sub text default null) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
declare r text := public.site_role(p_pw);
begin
  if r is null then raise exception 'NO_AUTH'; end if;
  if r <> 'admin' and exists (select 1 from public.vid_edit e where e.url = p_url and e.deleted) then raise exception 'DELETED'; end if;
  if (select count(*) from public.vid_add a where a.created_at > now() - interval '1 minute') >= 300 then raise exception 'TOO_MANY'; end if;
  insert into public.vid_add (url, title, date, category, sub)
  values (trim(p_url), trim(p_title), nullif(p_date, ''), p_category, nullif(p_sub, ''))
  on conflict (url) do nothing;
  if r = 'admin' then update public.vid_edit e set deleted = false, updated_at = now() where e.url = p_url and e.deleted; end if;
  return true;
end $$;

-- 편집자·관리자: 세부 카테고리 바꾸기
create or replace function public.vid_set_sub(p_pw text, p_url text, p_sub text) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if public.site_role(p_pw) is null then raise exception 'NO_AUTH'; end if;
  insert into public.vid_edit (url, sub) values (p_url, nullif(p_sub, ''))
  on conflict (url) do update set sub = excluded.sub, updated_at = now();
  return true;
end $$;

-- 편집자·관리자: 카테고리 이동
create or replace function public.vid_move(p_pw text, p_url text, p_category text, p_sub text default null) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if public.site_role(p_pw) is null then raise exception 'NO_AUTH'; end if;
  insert into public.vid_edit (url, category, sub) values (p_url, p_category, nullif(p_sub, ''))
  on conflict (url) do update set category = excluded.category, sub = excluded.sub, updated_at = now();
  return true;
end $$;

-- 관리자만: 영상 삭제
create or replace function public.vid_delete(p_pw text, p_url text) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if public.site_role(p_pw) is distinct from 'admin' then raise exception 'ADMIN_ONLY'; end if;
  insert into public.vid_edit (url, deleted) values (p_url, true)
  on conflict (url) do update set deleted = true, updated_at = now();
  return true;
end $$;

-- 게시판 글 삭제는 관리자만
create or replace function public.board_delete(p_id bigint, p_pw text) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if not public.board_is_admin(p_pw) then raise exception 'ADMIN_ONLY'; end if;
  delete from public.board_posts p where p.id = p_id;
  return true;
end $$;

grant execute on function public.site_role(text) to anon, authenticated;
grant execute on function public.vid_list() to anon, authenticated;
grant execute on function public.vid_add_one(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.vid_set_sub(text, text, text) to anon, authenticated;
grant execute on function public.vid_move(text, text, text, text) to anon, authenticated;
grant execute on function public.vid_delete(text, text) to anon, authenticated;
grant execute on function public.board_delete(bigint, text) to anon, authenticated;

notify pgrst, 'reload schema';

-- ▼ 마지막으로, 아래 두 줄의 앞 '--' 를 지우고 '여기에편집자비밀번호' 를 바꿔서 그 두 줄만 한 번 더 Run 하세요.
-- insert into public.site_editor (id, pw_hash) values (1, extensions.crypt('여기에편집자비밀번호', extensions.gen_salt('bf')))
--   on conflict (id) do update set pw_hash = excluded.pw_hash;
