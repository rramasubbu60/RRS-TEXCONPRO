-- RRS TEXCONPRO: only listed emails may use the app; everyone listed shares the same records.
-- Safe to run more than once.

-- 1. The list of people allowed in
create table if not exists public.app_users (
  email    text primary key check (email = lower(email)),
  role     text not null default 'user' check (role in ('admin','user')),
  added_at timestamptz not null default now()
);
comment on table public.app_users is 'Emails allowed to use RRS TEXCONPRO and their role (admin manages this list)';
alter table public.app_users enable row level security;

insert into public.app_users (email, role) values
  ('abbishek.rrs@gmail.com', 'admin'),
  ('rramasubbu60@gmail.com', 'user')
on conflict (email) do update set role = excluded.role;

-- 2. Helper checks used by the privacy rules
create or replace function public.my_role() returns text
language sql stable security definer set search_path = '' as $$
  select role from public.app_users where email = lower(coalesce(auth.jwt() ->> 'email', ''));
$$;
create or replace function public.is_allowed() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_users where email = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_users where role = 'admin' and email = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
-- finds a photo saved before sharing was switched on (stored under the uploader's own folder)
create or replace function public.photo_path(pid text) returns text
language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o
  where public.is_allowed() and o.bucket_id = 'photos' and o.name like '%/' || pid || '.jpg'
  order by o.created_at desc limit 1;
$$;
revoke all on function public.my_role(), public.is_allowed(), public.is_admin(), public.photo_path(text) from public, anon;
grant execute on function public.my_role(), public.is_allowed(), public.is_admin(), public.photo_path(text) to authenticated;

drop policy if exists "app_users: allowed people can see the list" on public.app_users;
drop policy if exists "app_users: admin can add"    on public.app_users;
drop policy if exists "app_users: admin can change" on public.app_users;
drop policy if exists "app_users: admin can remove" on public.app_users;
create policy "app_users: allowed people can see the list" on public.app_users for select to authenticated using ((select public.is_allowed()));
create policy "app_users: admin can add"    on public.app_users for insert to authenticated with check ((select public.is_admin()));
create policy "app_users: admin can change" on public.app_users for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "app_users: admin can remove" on public.app_users for delete to authenticated using ((select public.is_admin()) and email <> lower(coalesce(auth.jwt() ->> 'email', '')));

-- 3. Records become shared between the allowed people
alter table public.records add column if not exists updated_by text;
alter table public.records alter column owner drop not null;
alter table public.records drop constraint if exists records_owner_fkey;
alter table public.records add constraint records_owner_fkey foreign key (owner) references auth.users(id) on delete set null;
-- if the same record was ever saved twice by different people, keep the newest copy
delete from public.records a using public.records b
  where a.coll = b.coll and a.id = b.id and (a.updated_at < b.updated_at or (a.updated_at = b.updated_at and a.ctid < b.ctid));
alter table public.records drop constraint if exists records_pkey;
alter table public.records add primary key (coll, id);

drop policy if exists "records: owner can read"   on public.records;
drop policy if exists "records: owner can add"    on public.records;
drop policy if exists "records: owner can change" on public.records;
drop policy if exists "records: owner can delete" on public.records;
drop policy if exists "records: allowed people can read"   on public.records;
drop policy if exists "records: allowed people can add"    on public.records;
drop policy if exists "records: allowed people can change" on public.records;
drop policy if exists "records: allowed people can delete" on public.records;
create policy "records: allowed people can read"   on public.records for select to authenticated using ((select public.is_allowed()));
create policy "records: allowed people can add"    on public.records for insert to authenticated with check ((select public.is_allowed()));
create policy "records: allowed people can change" on public.records for update to authenticated using ((select public.is_allowed())) with check ((select public.is_allowed()));
create policy "records: allowed people can delete" on public.records for delete to authenticated using ((select public.is_allowed()));

-- 4. Photos: shared between the allowed people
drop policy if exists "photos: owner can read"   on storage.objects;
drop policy if exists "photos: owner can add"    on storage.objects;
drop policy if exists "photos: owner can change" on storage.objects;
drop policy if exists "photos: owner can delete" on storage.objects;
drop policy if exists "photos: allowed people can read"   on storage.objects;
drop policy if exists "photos: allowed people can add"    on storage.objects;
drop policy if exists "photos: allowed people can change" on storage.objects;
drop policy if exists "photos: allowed people can delete" on storage.objects;
create policy "photos: allowed people can read"   on storage.objects for select to authenticated using (bucket_id = 'photos' and (select public.is_allowed()));
create policy "photos: allowed people can add"    on storage.objects for insert to authenticated with check (bucket_id = 'photos' and (select public.is_allowed()));
create policy "photos: allowed people can change" on storage.objects for update to authenticated using (bucket_id = 'photos' and (select public.is_allowed()));
create policy "photos: allowed people can delete" on storage.objects for delete to authenticated using (bucket_id = 'photos' and (select public.is_allowed()));

-- 5. Nobody outside the list can even create an account
create or replace function public.only_listed_emails() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.app_users where email = lower(new.email)) then
    raise exception 'This email is not allowed to use RRS TEXCONPRO';
  end if;
  return new;
end $$;
drop trigger if exists only_listed_emails on auth.users;
create trigger only_listed_emails before insert on auth.users for each row execute function public.only_listed_emails();
