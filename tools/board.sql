-- 쮸카이브 게시판 (Supabase SQL Editor에 통째로 붙여넣고 Run)
-- 방문자는 아래 함수로만 글을 읽고/쓰고/고치고/지울 수 있어요. 표에 직접 접근은 막혀 있어요.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.board_posts (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 20),
  body text not null check (char_length(body) between 1 and 1000),
  secret boolean not null default false,
  pw_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table public.board_posts enable row level security;
revoke all on public.board_posts from anon, authenticated;

create table if not exists public.board_admin (
  id int primary key default 1 check (id = 1),
  pw_hash text not null
);
alter table public.board_admin enable row level security;
revoke all on public.board_admin from anon, authenticated;

-- 관리자 비밀번호가 맞는지
create or replace function public.board_is_admin(p_pw text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(p_pw, '') <> ''
     and exists (select 1 from public.board_admin a where a.pw_hash = crypt(p_pw, a.pw_hash));
$$;

-- 글 비밀번호(또는 관리자 비밀번호)가 맞는지
create or replace function public.board_check(p_id bigint, p_pw text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.board_posts p where p.id = p_id and p.pw_hash = crypt(coalesce(p_pw, ''), p.pw_hash))
      or public.board_is_admin(p_pw);
$$;

revoke execute on function public.board_is_admin(text) from public, anon, authenticated;
revoke execute on function public.board_check(bigint, text) from public, anon, authenticated;

-- 목록: 비밀글 내용은 관리자 비밀번호를 줬을 때만
create or replace function public.board_list(p_admin text default null, p_before bigint default null, p_limit int default 60)
returns table (id bigint, name text, body text, secret boolean, created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
declare adm boolean := public.board_is_admin(p_admin);
begin
  return query
    select p.id, p.name, case when p.secret and not adm then null else p.body end, p.secret, p.created_at, p.updated_at
    from public.board_posts p
    where p_before is null or p.id < p_before
    order by p.id desc
    limit least(greatest(coalesce(p_limit, 60), 1), 100);
end $$;

-- 글쓰기
create or replace function public.board_add(p_name text, p_body text, p_secret boolean, p_pw text) returns bigint
language plpgsql volatile security definer set search_path = public, extensions as $$
declare new_id bigint;
begin
  if char_length(coalesce(p_pw, '')) < 4 then raise exception 'SHORT_PW'; end if;
  if char_length(trim(coalesce(p_name, ''))) = 0 or char_length(trim(coalesce(p_body, ''))) = 0 then raise exception 'EMPTY'; end if;
  if (select count(*) from public.board_posts p where p.created_at > now() - interval '1 minute') >= 10 then raise exception 'TOO_MANY'; end if;
  insert into public.board_posts (name, body, secret, pw_hash)
  values (trim(p_name), trim(p_body), coalesce(p_secret, false), crypt(p_pw, gen_salt('bf')))
  returning board_posts.id into new_id;
  return new_id;
end $$;

-- 수정 전에 원래 내용 가져오기 (비밀글도 비밀번호가 맞으면)
create or replace function public.board_get(p_id bigint, p_pw text) returns table (body text, secret boolean)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.board_check(p_id, p_pw) then raise exception 'WRONG_PW'; end if;
  return query select p.body, p.secret from public.board_posts p where p.id = p_id;
end $$;

create or replace function public.board_edit(p_id bigint, p_pw text, p_body text, p_secret boolean) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if not public.board_check(p_id, p_pw) then raise exception 'WRONG_PW'; end if;
  if char_length(trim(coalesce(p_body, ''))) = 0 then raise exception 'EMPTY'; end if;
  update public.board_posts p set body = trim(p_body), secret = coalesce(p_secret, false), updated_at = now() where p.id = p_id;
  return true;
end $$;

create or replace function public.board_delete(p_id bigint, p_pw text) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if not public.board_check(p_id, p_pw) then raise exception 'WRONG_PW'; end if;
  delete from public.board_posts p where p.id = p_id;
  return true;
end $$;

grant execute on function public.board_list(text, bigint, int) to anon, authenticated;
grant execute on function public.board_add(text, text, boolean, text) to anon, authenticated;
grant execute on function public.board_get(bigint, text) to anon, authenticated;
grant execute on function public.board_edit(bigint, text, text, boolean) to anon, authenticated;
grant execute on function public.board_delete(bigint, text) to anon, authenticated;

-- ▼ 마지막으로, 아래 줄의 '여기에관리자비밀번호' 를 원하는 비밀번호로 바꿔서 한 번 더 Run 하세요.
-- insert into public.board_admin (id, pw_hash) values (1, extensions.crypt('여기에관리자비밀번호', extensions.gen_salt('bf')))
--   on conflict (id) do update set pw_hash = excluded.pw_hash;
