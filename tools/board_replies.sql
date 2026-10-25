-- 쮸카이브 게시판 대댓글 (board.sql, board_comments.sql 다음에 통째로 붙여넣고 Run)

alter table public.board_comments add column if not exists parent_id bigint references public.board_comments(id) on delete cascade;

create or replace function public.board_comments_of(p_post bigint) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'parent_id', c.parent_id, 'name', c.name, 'body', c.body, 'created_at', c.created_at) order by c.id), '[]'::jsonb)
  from public.board_comments c where c.post_id = p_post;
$$;

drop function if exists public.board_comment_add(bigint, text, text, text);
create or replace function public.board_comment_add(p_post bigint, p_name text, p_body text, p_pw text, p_parent bigint default null) returns bigint
language plpgsql volatile security definer set search_path = public, extensions as $$
declare new_id bigint; par bigint := p_parent;
begin
  if char_length(coalesce(p_pw, '')) < 4 then raise exception 'SHORT_PW'; end if;
  if char_length(trim(coalesce(p_name, ''))) = 0 or char_length(trim(coalesce(p_body, ''))) = 0 then raise exception 'EMPTY'; end if;
  if not exists (select 1 from public.board_posts p where p.id = p_post) then raise exception 'NO_POST'; end if;
  if par is not null then
    -- 같은 글의 댓글에만, 그리고 한 단계까지만 (대댓글에 단 답글은 원래 댓글 아래로)
    select coalesce(c.parent_id, c.id) into par from public.board_comments c where c.id = par and c.post_id = p_post;
    if par is null then raise exception 'NO_PARENT'; end if;
  end if;
  if (select count(*) from public.board_comments c where c.created_at > now() - interval '1 minute') >= 20 then raise exception 'TOO_MANY'; end if;
  insert into public.board_comments (post_id, parent_id, name, body, pw_hash)
  values (p_post, par, trim(p_name), trim(p_body), crypt(p_pw, gen_salt('bf')))
  returning board_comments.id into new_id;
  return new_id;
end $$;

grant execute on function public.board_comment_add(bigint, text, text, text, bigint) to anon, authenticated;

notify pgrst, 'reload schema';
