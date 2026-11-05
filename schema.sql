-- =====================================================================
-- Laguna College ICT Services Portal - MS Teams Support Portal
-- Run this whole file once in the Supabase SQL Editor.
-- It is safe to re-run.
-- =====================================================================

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Atomic ticket numbers: LC-YYYY-00001
--    One counter row per year. The INSERT ... ON CONFLICT DO UPDATE takes a
--    row lock, so simultaneous submissions can never receive the same number.
-- ---------------------------------------------------------------------
create table if not exists public.ticket_counters (
  year       int primary key,
  last_value int not null default 0
);
alter table public.ticket_counters enable row level security;
revoke all on public.ticket_counters from anon, authenticated;

create or replace function public.generate_ticket_id()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  y int := extract(year from (now() at time zone 'Asia/Manila'))::int;
  n int;
begin
  insert into public.ticket_counters as c (year, last_value)
  values (y, 1)
  on conflict (year) do update set last_value = c.last_value + 1
  returning c.last_value into n;

  return 'LC-' || y::text || '-' || lpad(n::text, 5, '0');
end;
$$;

revoke execute on function public.generate_ticket_id() from public, anon, authenticated;
grant  execute on function public.generate_ticket_id() to service_role;

-- ---------------------------------------------------------------------
-- 2. ICT staff allow-list (who may use the admin area)
-- ---------------------------------------------------------------------
create table if not exists public.ict_staff (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null,
  email      text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.ict_staff enable row level security;

create or replace function public.is_ict_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ict_staff s
    where s.user_id = auth.uid() and s.active
  );
$$;

revoke execute on function public.is_ict_staff() from public, anon;
grant  execute on function public.is_ict_staff() to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 3. Tickets
-- ---------------------------------------------------------------------
create table if not exists public.tickets (
  id               uuid primary key default gen_random_uuid(),
  ticket_id        text not null default public.generate_ticket_id(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  full_name        text not null,
  user_type        text not null,
  student_id       text not null,            -- Student ID or Employee ID
  department       text,
  year_level       text,                     -- Year level or Grade level
  course           text,                     -- Course / Program (or strand)
  mobile_number    text not null,
  has_lc_account   boolean not null default false,
  lc_email         text,
  personal_email   text not null,

  category         text not null,
  concern          text not null,
  description      text not null,
  screenshot_path  text,

  status           text not null default 'Open',
  priority         text not null default 'Normal',
  assigned_to      text,
  resolution_notes text,
  resolved_at      timestamptz,

  constraint tickets_ticket_id_unique unique (ticket_id),
  constraint tickets_user_type_check  check (user_type in ('Student', 'Faculty', 'Administration')),
  constraint tickets_status_check     check (status in ('Open', 'In Progress', 'Resolved', 'Closed')),
  constraint tickets_priority_check   check (priority in ('Low', 'Normal', 'High', 'Urgent')),
  constraint tickets_department_check check (department is null or department in ('Basic Education', 'College', 'Graduate Studies')),
  constraint tickets_student_fields_check
    check (user_type = 'Student' or (department is null and year_level is null and course is null)),
  constraint tickets_lc_email_check   check (has_lc_account = false or lc_email is not null),
  constraint tickets_description_len  check (char_length(description) between 10 and 3000),
  constraint tickets_path_len         check (screenshot_path is null or char_length(screenshot_path) <= 300)
);

create index if not exists tickets_created_at_idx  on public.tickets (created_at desc);
create index if not exists tickets_student_id_idx  on public.tickets (student_id);
create index if not exists tickets_lc_email_idx    on public.tickets (lc_email);
create index if not exists tickets_category_idx    on public.tickets (category);
create index if not exists tickets_concern_idx     on public.tickets (concern);
create index if not exists tickets_status_idx      on public.tickets (status);
create index if not exists tickets_priority_idx    on public.tickets (priority);
create index if not exists tickets_full_name_idx   on public.tickets (full_name);
-- ticket_id is already indexed by its UNIQUE constraint.
-- Trigram indexes make the dashboard's "contains" search fast.
create index if not exists tickets_full_name_trgm  on public.tickets using gin (full_name  extensions.gin_trgm_ops);
create index if not exists tickets_student_id_trgm on public.tickets using gin (student_id extensions.gin_trgm_ops);
create index if not exists tickets_lc_email_trgm   on public.tickets using gin (lc_email   extensions.gin_trgm_ops);
create index if not exists tickets_ticket_id_trgm  on public.tickets using gin (ticket_id  extensions.gin_trgm_ops);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists tickets_set_updated_at on public.tickets;
create trigger tickets_set_updated_at
  before update on public.tickets
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- 4. Row Level Security
--    - Nobody can read or write tickets from the browser except ICT staff.
--    - Public submissions go through /api/submit, which uses the
--      server-only service-role key (it bypasses RLS).
--    - Staff can only UPDATE the workflow columns, never requester data.
-- ---------------------------------------------------------------------
alter table public.tickets enable row level security;

revoke all on public.tickets from anon, authenticated;
grant select on public.tickets to authenticated;
grant update (status, priority, assigned_to, resolution_notes, resolved_at)
  on public.tickets to authenticated;
grant all on public.tickets to service_role;

drop policy if exists "ICT staff can read tickets" on public.tickets;
create policy "ICT staff can read tickets"
  on public.tickets for select to authenticated
  using (public.is_ict_staff());

drop policy if exists "ICT staff can update tickets" on public.tickets;
create policy "ICT staff can update tickets"
  on public.tickets for update to authenticated
  using (public.is_ict_staff())
  with check (public.is_ict_staff());

revoke all on public.ict_staff from anon, authenticated;
grant select on public.ict_staff to authenticated;

drop policy if exists "Staff can read the staff list" on public.ict_staff;
create policy "Staff can read the staff list"
  on public.ict_staff for select to authenticated
  using (user_id = auth.uid() or public.is_ict_staff());

-- ---------------------------------------------------------------------
-- 5. Dashboard statistics (runs as the caller, so RLS applies)
-- ---------------------------------------------------------------------
create or replace function public.ticket_stats()
returns json
language sql
stable
security invoker
set search_path = public
as $$
  select json_build_object(
    'total',          count(*),
    'open',           count(*) filter (where status = 'Open'),
    'in_progress',    count(*) filter (where status = 'In Progress'),
    'resolved',       count(*) filter (where status = 'Resolved'),
    'high_priority',  count(*) filter (where priority in ('High', 'Urgent') and status in ('Open', 'In Progress')),
    'password_reset', count(*) filter (where concern = 'Password Reset'),
    'new_account',    count(*) filter (where concern = 'New MS Teams Account'),
    'cannot_login',   count(*) filter (where concern = 'Cannot Login to MS Teams')
  )
  from public.tickets;
$$;

revoke execute on function public.ticket_stats() from public, anon;
grant  execute on function public.ticket_stats() to authenticated;

-- ---------------------------------------------------------------------
-- 6. Private storage bucket for screenshots
--    Uploads happen through short-lived signed upload URLs created by the
--    server. Only active ICT staff can read objects (via signed URLs).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ms-teams-screenshots',
  'ms-teams-screenshots',
  false,
  5242880,
  array['image/png', 'image/jpeg', 'application/pdf']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "ICT staff can read screenshots" on storage.objects;
create policy "ICT staff can read screenshots"
  on storage.objects for select to authenticated
  using (bucket_id = 'ms-teams-screenshots' and public.is_ict_staff());

-- ---------------------------------------------------------------------
-- 7. Add your first ICT staff member (after creating the user under
--    Authentication -> Users in the Supabase dashboard):
--
-- insert into public.ict_staff (user_id, full_name, email)
-- select id, 'Your Name', email from auth.users where email = 'ict.admin@example.com';
-- ---------------------------------------------------------------------
