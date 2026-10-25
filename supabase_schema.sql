-- Escala da Equipe v2 — Supabase (PostgreSQL) com RLS e perfis de acesso
-- Rode UMA vez no SQL Editor de um projeto novo.
-- (Se já rodou a versão anterior, apague antes: drop table public.schedule_entries, public.employees cascade;)

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'viewer' check (role in ('admin','editor','viewer'))
);
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  name text not null, role text default '',
  entry time, break_start time, break_end time, exit_time time,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index employees_name_uq on public.employees (lower(name));  -- sem duplicidade
create table public.schedule_entries (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  day date not null,
  type text not null check (type in ('work','F','D','V','I','A','T')),
  entry time, break_start time, break_end time, exit_time time,
  note text default '', updated_at timestamptz not null default now(),
  unique (employee_id, day)
);
create table public.app_settings (id int primary key check (id = 1), data jsonb not null default '{}');

-- Primeiro usuário cadastrado vira administrador; os demais entram como leitor.
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, email, role)
  values (new.id, new.email, case when exists (select 1 from public.profiles) then 'viewer' else 'admin' end);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
-- Se você já criou usuários antes de rodar este script:
insert into public.profiles(id, email, role)
select id, email, case when row_number() over (order by created_at) = 1 then 'admin' else 'viewer' end
from auth.users on conflict do nothing;

create function public.my_role() returns text language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

alter table public.profiles enable row level security;
alter table public.employees enable row level security;
alter table public.schedule_entries enable row level security;
alter table public.app_settings enable row level security;

create policy "perfil: próprio ou admin" on public.profiles for select to authenticated using (id = auth.uid() or my_role() = 'admin');
create policy "perfil: só admin altera" on public.profiles for update to authenticated using (my_role() = 'admin') with check (my_role() = 'admin');

do $$ declare t text; begin
  foreach t in array array['employees','schedule_entries','app_settings'] loop
    execute format('create policy "%1$s: leitura" on public.%1$s for select to authenticated using (my_role() is not null)', t);
    execute format('create policy "%1$s: escrita" on public.%1$s for all to authenticated using (my_role() in (''admin'',''editor'')) with check (my_role() in (''admin'',''editor''))', t);
  end loop;
end $$;

alter publication supabase_realtime add table public.employees, public.schedule_entries;
