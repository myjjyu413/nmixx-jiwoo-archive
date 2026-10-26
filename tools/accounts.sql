-- 쮸카이브 아이디(트위터 @아이디)·비밀번호 로그인 (board.sql, site.sql 다음에 통째로 붙여넣고 Run)
-- 누구나 가입하면 바로 편집자. 관리자는 맨 아래 줄로 지정해요.

create table if not exists public.site_users (
  id bigint generated always as identity primary key,
  handle text not null unique,
  pw_hash text not null,
  role text not null default 'editor' check (role in ('editor', 'admin')),
  q text check (char_length(q) between 1 and 100),
  a_hash text,
  created_at timestamptz not null default now()
);
-- 편집자 아이디는 @트위터아이디, 관리자 아이디는 @ 없이도 돼요. 관리자는 비밀번호 찾기 질문이 없어도 돼요.
alter table public.site_users drop constraint if exists site_users_handle_check;
alter table public.site_users add constraint site_users_handle_check check (handle ~ '^@[a-z0-9_]{1,15}$' or handle ~ '^[a-z0-9_]{2,20}$');
alter table public.site_users alter column q drop not null;
alter table public.site_users alter column a_hash drop not null;
alter table public.site_users enable row level security;
revoke all on public.site_users from anon, authenticated;

create table if not exists public.site_sessions (
  token_hash text primary key,
  user_id bigint not null references public.site_users(id) on delete cascade,
  expires_at timestamptz not null
);
alter table public.site_sessions enable row level security;
revoke all on public.site_sessions from anon, authenticated;

create table if not exists public.site_fails (
  handle text not null,
  at timestamptz not null default now()
);
alter table public.site_fails enable row level security;
revoke all on public.site_fails from anon, authenticated;

-- 로그인 토큰 → 역할
create or replace function public.tok_role(p text) returns text
language sql stable security definer set search_path = public, extensions as $$
  select u.role from public.site_sessions s join public.site_users u on u.id = s.user_id
  where p like 'tok_%' and s.token_hash = encode(digest(p, 'sha256'), 'hex') and s.expires_at > now();
$$;
revoke execute on function public.tok_role(text) from public, anon, authenticated;

-- 관리자 확인: 관리자 비밀번호 또는 관리자 계정의 로그인 토큰
create or replace function public.board_is_admin(p_pw text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(coalesce(p_pw, '') <> '' and (
    coalesce(public.tok_role(p_pw), '') = 'admin'
    or (p_pw not like 'tok_%' and exists (select 1 from public.board_admin a where a.pw_hash = crypt(p_pw, a.pw_hash)))
  ), false);
$$;
revoke execute on function public.board_is_admin(text) from public, anon, authenticated;

-- 역할 확인: 토큰이면 계정 역할, 아니면 예전 비밀번호
create or replace function public.site_role(p_pw text) returns text
language plpgsql stable security definer set search_path = public, extensions as $$
declare r text;
begin
  if coalesce(p_pw, '') = '' then return null; end if;
  if p_pw like 'tok_%' then return public.tok_role(p_pw); end if;
  if public.board_is_admin(p_pw) then return 'admin'; end if;
  if exists (select 1 from public.site_editor e where e.pw_hash = crypt(p_pw, e.pw_hash)) then return 'editor'; end if;
  return null;
end $$;

create or replace function public.acct_new_token(p_uid bigint) returns text
language plpgsql volatile security definer set search_path = public, extensions as $$
declare t text := 'tok_' || encode(gen_random_bytes(24), 'hex');
begin
  delete from public.site_sessions s where s.expires_at < now();
  insert into public.site_sessions (token_hash, user_id, expires_at) values (encode(digest(t, 'sha256'), 'hex'), p_uid, now() + interval '12 hours');
  return t;
end $$;
revoke execute on function public.acct_new_token(bigint) from public, anon, authenticated;

create or replace function public.acct_norm(p text) returns text
language sql immutable as $$ select lower(trim(coalesce(p, ''))) $$;

-- 가입 (바로 로그인). 관리자 비밀번호(board_admin)를 함께 넣으면 관리자 아이디로 만들어져요.
drop function if exists public.acct_signup(text, text, text, text);
create or replace function public.acct_signup(p_handle text, p_pw text, p_q text, p_a text, p_admin text default null) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare h text := public.acct_norm(p_handle); uid bigint; r text := 'editor';
begin
  if coalesce(p_admin, '') <> '' then
    if p_admin like 'tok_%' or public.board_is_admin(p_admin) is not true then raise exception 'WRONG_ADMIN'; end if;
    r := 'admin';
  end if;
  if r = 'admin' then
    if h !~ '^@[a-z0-9_]{1,15}$' and h !~ '^[a-z0-9_]{2,20}$' then raise exception 'BAD_ADMIN_ID'; end if;
  else
    if h !~ '^@[a-z0-9_]{1,15}$' then raise exception 'BAD_HANDLE'; end if;
    if char_length(trim(coalesce(p_q, ''))) = 0 or char_length(trim(coalesce(p_a, ''))) = 0 then raise exception 'NO_Q'; end if;
  end if;
  if char_length(coalesce(p_pw, '')) < 6 then raise exception 'SHORT_PW'; end if;
  if (select count(*) from public.site_users u where u.created_at > now() - interval '1 hour') >= 30 then raise exception 'TOO_MANY'; end if;
  if exists (select 1 from public.site_users u where u.handle = h) then raise exception 'TAKEN'; end if;
  insert into public.site_users (handle, pw_hash, role, q, a_hash)
  values (h, crypt(p_pw, gen_salt('bf')), r, nullif(trim(coalesce(p_q, '')), ''),
          case when trim(coalesce(p_a, '')) = '' then null else crypt(public.acct_norm(p_a), gen_salt('bf')) end)
  returning id into uid;
  return jsonb_build_object('token', public.acct_new_token(uid), 'handle', h, 'role', r);
end $$;

-- 이미 만든 아이디를 관리자로: 로그인한 상태에서 관리자 비밀번호(board_admin)를 넣으면
create or replace function public.acct_promote(p_token text, p_admin text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare uid bigint; h text;
begin
  select s.user_id into uid from public.site_sessions s where s.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') and s.expires_at > now();
  if uid is null then raise exception 'NO_AUTH'; end if;
  if coalesce(p_admin, '') = '' or p_admin like 'tok_%' or public.board_is_admin(p_admin) is not true then raise exception 'WRONG_ADMIN'; end if;
  update public.site_users u set role = 'admin' where u.id = uid returning u.handle into h;
  return jsonb_build_object('token', p_token, 'handle', h, 'role', 'admin');
end $$;

-- 로그인 (틀리면 오류 대신 error 를 돌려줘요: 실패 횟수 기록이 지워지지 않게)
create or replace function public.acct_login(p_handle text, p_pw text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare h text := public.acct_norm(p_handle); u public.site_users;
begin
  if (select count(*) from public.site_fails f where f.handle = h and f.at > now() - interval '10 minutes') >= 8 then raise exception 'LOCKED'; end if;
  select * into u from public.site_users x where x.handle = h;
  if u.id is null and h !~ '^@' then select * into u from public.site_users x where x.handle = '@' || h; end if;
  if u.id is null or u.pw_hash <> crypt(coalesce(p_pw, ''), u.pw_hash) then
    insert into public.site_fails (handle) values (h);
    return jsonb_build_object('error', 'WRONG_LOGIN');
  end if;
  return jsonb_build_object('token', public.acct_new_token(u.id), 'handle', u.handle, 'role', u.role);
end $$;

-- 로그인 정보 확인 / 로그아웃
create or replace function public.acct_me(p_token text) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('handle', u.handle, 'role', u.role)
  from public.site_sessions s join public.site_users u on u.id = s.user_id
  where s.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') and s.expires_at > now();
$$;
create or replace function public.acct_logout(p_token text) returns boolean
language sql volatile security definer set search_path = public, extensions as $$
  delete from public.site_sessions s where s.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') returning true;
$$;

-- 아이디 찾기: 그 아이디로 가입돼 있는지 / 비밀번호 찾기용 질문
create or replace function public.acct_question(p_handle text) returns text
language sql stable security definer set search_path = public as $$
  select u.q from public.site_users u where u.handle = public.acct_norm(p_handle);
$$;

-- 비밀번호 찾기: 확인 질문의 답이 맞으면 새 비밀번호로 바꾸고 로그인
create or replace function public.acct_reset(p_handle text, p_a text, p_newpw text) returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare h text := public.acct_norm(p_handle); u public.site_users;
begin
  if char_length(coalesce(p_newpw, '')) < 6 then raise exception 'SHORT_PW'; end if;
  if (select count(*) from public.site_fails f where f.handle = h and f.at > now() - interval '10 minutes') >= 8 then raise exception 'LOCKED'; end if;
  select * into u from public.site_users x where x.handle = h;
  if u.id is null or u.a_hash is null or u.a_hash <> crypt(public.acct_norm(p_a), u.a_hash) then
    insert into public.site_fails (handle) values (h);
    return jsonb_build_object('error', 'WRONG_ANSWER');
  end if;
  update public.site_users x set pw_hash = crypt(p_newpw, gen_salt('bf')) where x.id = u.id;
  delete from public.site_sessions s where s.user_id = u.id;
  return jsonb_build_object('token', public.acct_new_token(u.id), 'handle', u.handle, 'role', u.role);
end $$;

grant execute on function public.acct_signup(text, text, text, text, text) to anon, authenticated;
grant execute on function public.acct_promote(text, text) to anon, authenticated;
grant execute on function public.acct_login(text, text) to anon, authenticated;
grant execute on function public.acct_me(text) to anon, authenticated;
grant execute on function public.acct_logout(text) to anon, authenticated;
grant execute on function public.acct_question(text) to anon, authenticated;
grant execute on function public.acct_reset(text, text, text) to anon, authenticated;
grant execute on function public.site_role(text) to anon, authenticated;

notify pgrst, 'reload schema';

-- ▼ 관리자 되기: 사이트에서 아이디를 만들 때 '관리자 비밀번호' 칸에 board.sql 때 정한 관리자 비밀번호를 넣으면 돼요.
--   (이미 만든 아이디라면 로그인한 뒤 화면 위쪽 '관리자 되기'에 넣거나, 아래 줄을 고쳐서 Run)
-- update public.site_users set role = 'admin' where handle = lower('@본인트위터아이디');
