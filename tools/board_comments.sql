-- 쮸카이브 게시판 댓글 추가 (board.sql 을 먼저 실행한 뒤, 이 파일을 통째로 붙여넣고 Run)

create table if not exists public.board_comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.board_posts(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 20),
  body text not null check (char_length(body) between 1 and 300),
  pw_hash text not null,
  created_at timestamptz not null default now()
);
create index if not exists board_comments_post_idx on public.board_comments(post_id);
alter table public.board_comments enable row level security;
revoke all on public.board_comments from anon, authenticated;

-- 글 하나의 댓글 목록(json)
create or replace function public.board_comments_of(p_post bigint) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'body', c.body, 'created_at', c.created_at) order by c.id), '[]'::jsonb)
  from public.board_comments c where c.post_id = p_post;
$$;
revoke execute on function public.board_comments_of(bigint) from public, anon, authenticated;

-- 목록/가져오기에 댓글을 함께 (돌려주는 모양이 바뀌어서 지우고 다시 만들어요)
drop function if exists public.board_list(text, bigint, int);
create function public.board_list(p_admin text default null, p_before bigint default null, p_limit int default 60)
returns table (id bigint, name text, body text, secret boolean, created_at timestamptz, updated_at timestamptz, comments jsonb)
language plpgsql stable security definer set search_path = public, extensions as $$
declare adm boolean := public.board_is_admin(p_admin);
begin
  return query
    select p.id, p.name,
           case when p.secret and not adm then null else p.body end,
           p.secret, p.created_at, p.updated_at,
           case when p.secret and not adm then null else public.board_comments_of(p.id) end
    from public.board_posts p
    where p_before is null or p.id < p_before
    order by p.id desc
    limit least(greatest(coalesce(p_limit, 60), 1), 100);
end $$;

drop function if exists public.board_get(bigint, text);
create function public.board_get(p_id bigint, p_pw text) returns table (body text, secret boolean, comments jsonb)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.board_check(p_id, p_pw) then raise exception 'WRONG_PW'; end if;
  return query select p.body, p.secret, public.board_comments_of(p.id) from public.board_posts p where p.id = p_id;
end $$;

-- 댓글 쓰기
create or replace function public.board_comment_add(p_post bigint, p_name text, p_body text, p_pw text) returns bigint
language plpgsql volatile security definer set search_path = public, extensions as $$
declare new_id bigint;
begin
  if char_length(coalesce(p_pw, '')) < 4 then raise exception 'SHORT_PW'; end if;
  if char_length(trim(coalesce(p_name, ''))) = 0 or char_length(trim(coalesce(p_body, ''))) = 0 then raise exception 'EMPTY'; end if;
  if not exists (select 1 from public.board_posts p where p.id = p_post) then raise exception 'NO_POST'; end if;
  if (select count(*) from public.board_comments c where c.created_at > now() - interval '1 minute') >= 20 then raise exception 'TOO_MANY'; end if;
  insert into public.board_comments (post_id, name, body, pw_hash)
  values (p_post, trim(p_name), trim(p_body), crypt(p_pw, gen_salt('bf')))
  returning board_comments.id into new_id;
  return new_id;
end $$;

-- 댓글 지우기 (댓글 비밀번호 또는 관리자 비밀번호)
create or replace function public.board_comment_delete(p_id bigint, p_pw text) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if not (exists (select 1 from public.board_comments c where c.id = p_id and c.pw_hash = crypt(coalesce(p_pw, ''), c.pw_hash))
          or public.board_is_admin(p_pw)) then
    raise exception 'WRONG_PW';
  end if;
  delete from public.board_comments c where c.id = p_id;
  return true;
end $$;

grant execute on function public.board_list(text, bigint, int) to anon, authenticated;
grant execute on function public.board_get(bigint, text) to anon, authenticated;
grant execute on function public.board_comment_add(bigint, text, text, text) to anon, authenticated;
grant execute on function public.board_comment_delete(bigint, text) to anon, authenticated;

-- PostgREST가 바뀐 함수를 바로 알아보도록
notify pgrst, 'reload schema';
