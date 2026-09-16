-- Castelle Express CEO — estrutura para Supabase
-- Execute como migration no projeto correto.

create table if not exists public.services (
  id bigint generated always as identity primary key,
  name text not null unique,
  price numeric(10,2) not null default 0,
  duration_minutes integer not null default 60,
  active boolean not null default true
);

create table if not exists public.professionals (
  id bigint generated always as identity primary key,
  name text not null unique,
  active boolean not null default true
);

create table if not exists public.professional_hours (
  id bigint generated always as identity primary key,
  professional_id bigint not null references public.professionals(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 6),
  starts_at time not null,
  ends_at time not null,
  UNIQUE(professional_id, weekday)
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  service_id bigint not null references public.services(id),
  professional_id bigint not null references public.professionals(id),
  customer_name text not null,
  customer_phone text not null,
  appointment_date date not null,
  starts_at time not null,
  duration_minutes integer not null,
  status text not null default 'pending' check (status in ('pending','confirmed','cancelled')),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists appointments_schedule_idx
on public.appointments(professional_id, appointment_date, starts_at);

alter table public.services enable row level security;
alter table public.professionals enable row level security;
alter table public.professional_hours enable row level security;
alter table public.appointments enable row level security;

drop policy if exists "public read active services" on public.services;
create policy "public read active services" on public.services
for select to anon, authenticated using (active = true);

drop policy if exists "public read active professionals" on public.professionals;
create policy "public read active professionals" on public.professionals
for select to anon, authenticated using (active = true);

drop policy if exists "public read professional hours" on public.professional_hours;
create policy "public read professional hours" on public.professional_hours
for select to anon, authenticated using (true);

-- O cliente NÃO recebe acesso direto aos agendamentos.
-- A criação deve passar pela função abaixo, que valida disponibilidade.

create or replace function public.create_appointment(
  p_service_id bigint,
  p_professional_id bigint,
  p_customer_name text,
  p_customer_phone text,
  p_appointment_date date,
  p_starts_at time,
  p_notes text default null
)
returns public.appointments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service public.services;
  v_hour public.professional_hours;
  v_row public.appointments;
  v_end time;
begin
  select * into v_service
  from public.services
  where id = p_service_id and active = true;

  if v_service.id is null then
    raise exception 'Serviço indisponível';
  end if;

  select * into v_hour
  from public.professional_hours
  where professional_id = p_professional_id
    and weekday = extract(isodow from p_appointment_date)::smallint;

  if v_hour.id is null then
    raise exception 'Profissional não atende neste dia';
  end if;

  v_end := p_starts_at + make_interval(mins => v_service.duration_minutes);

  if p_starts_at < v_hour.starts_at or v_end > v_hour.ends_at then
    raise exception 'Horário fora da agenda do profissional';
  end if;

  if exists (
    select 1 from public.appointments a
    where a.professional_id = p_professional_id
      and a.appointment_date = p_appointment_date
      and a.status in ('pending','confirmed')
      and p_starts_at < a.starts_at + make_interval(mins => a.duration_minutes)
      and a.starts_at < v_end
  ) then
    raise exception 'Este horário já está ocupado';
  end if;

  insert into public.appointments
    (service_id, professional_id, customer_name, customer_phone,
     appointment_date, starts_at, duration_minutes, status, notes)
  values
    (p_service_id, p_professional_id, p_customer_name, p_customer_phone,
     p_appointment_date, p_starts_at, v_service.duration_minutes, 'pending', p_notes)
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.create_appointment(bigint,bigint,text,text,date,time,text) from public;
grant execute on function public.create_appointment(bigint,bigint,text,text,date,time,text) to anon, authenticated;

-- Dados iniciais
insert into public.services(name,price,duration_minutes) values
('Escova',45,60),('Corte feminino',80,60),('Hidratação',70,60),
('Manicure',35,45),('Pedicure',40,45),('Manicure + Pedicure',70,90),('Barbearia',35,45)
on conflict (name) do nothing;

insert into public.professionals(name) values
('Anita'),('Cira'),('Mara'),('Patrícia')
on conflict (name) do nothing;

-- Horários informados para a equipe. Segunda=1 ... Sábado=6.
-- Ajuste sábado individualmente no painel quando a operação real estiver definida.
insert into public.professional_hours(professional_id,weekday,starts_at,ends_at)
select p.id, d.weekday,
  case when p.name='Patrícia' and d.weekday=1 then '08:30'::time
       when p.name='Mara' and d.weekday between 1 and 5 then '10:00'::time
       else '09:00'::time end,
  case when p.name='Patrícia' and d.weekday=1 then '16:30'::time
       else '19:00'::time end
from public.professionals p
cross join generate_series(1,5) as d(weekday)
where not exists (
  select 1 from public.professional_hours h
  where h.professional_id=p.id and h.weekday=d.weekday
);

-- Folgas:
-- Anita: terça (2)
-- Mara: terça (2)
-- Cira: quarta (3)
-- Patrícia: segunda (1)
delete from public.professional_hours h
using public.professionals p
where h.professional_id=p.id
and ((p.name in ('Anita','Mara') and h.weekday=2)
  or (p.name='Cira' and h.weekday=3)
  or (p.name='Patrícia' and h.weekday=1));
