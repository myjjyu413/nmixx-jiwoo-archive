-- 카테고리 이동을 편집자도 할 수 있게 (site.sql 을 이미 Run 했다면 이것만 Run)
create or replace function public.vid_move(p_pw text, p_url text, p_category text, p_sub text default null) returns boolean
language plpgsql volatile security definer set search_path = public, extensions as $$
begin
  if public.site_role(p_pw) is null then raise exception 'NO_AUTH'; end if;
  insert into public.vid_edit (url, category, sub) values (p_url, p_category, nullif(p_sub, ''))
  on conflict (url) do update set category = excluded.category, sub = excluded.sub, updated_at = now();
  return true;
end $$;
notify pgrst, 'reload schema';
