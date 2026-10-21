-- RRS TEXCONPRO database: one table of records, private per user, plus a private photo store.
create table if not exists public.records (
  owner      uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  coll       text        not null,
  id         text        not null,
  data       jsonb       not null,
  updated_at timestamptz not null default now(),
  primary key (owner, coll, id)
);
comment on table public.records is 'RRS TEXCONPRO app records (mills, visits, bills, etc.), one row per record, private to its owner';

alter table public.records enable row level security;
alter table public.records replica identity full;

create policy "records: owner can read"   on public.records for select to authenticated using (owner = (select auth.uid()));
create policy "records: owner can add"    on public.records for insert to authenticated with check (owner = (select auth.uid()));
create policy "records: owner can change" on public.records for update to authenticated using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "records: owner can delete" on public.records for delete to authenticated using (owner = (select auth.uid()));

-- live sync between phone and computer
alter publication supabase_realtime add table public.records;

-- private photo storage: each user can only touch files in the folder named with their own id
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "photos: owner can read"   on storage.objects for select to authenticated using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "photos: owner can add"    on storage.objects for insert to authenticated with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "photos: owner can change" on storage.objects for update to authenticated using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "photos: owner can delete" on storage.objects for delete to authenticated using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
