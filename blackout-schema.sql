-- =====================================================================
--  RESISTÊNCIA BLACKOUT — banco do Terminal
--  Cole isto inteiro no SQL Editor do Supabase e clique em RUN.
--  Pode rodar de novo sem medo: tudo é "if not exists" / "or replace".
-- =====================================================================

-- ---------- TABELAS ----------

create table if not exists players (
  id          uuid primary key references auth.users on delete cascade,
  username    text unique not null,
  name        text not null,
  age         text    default '',
  photo       text    default '',
  bio         text    default '',
  activity    text    default '',
  status      text    default 'Trabalhando',
  wanted      int     default 0,
  num         text    default '',
  hue         int     default 0,
  access      int     default 1,
  role        text    default '',
  doses       int     default 0,
  skills      jsonb   default '[]'::jsonb,
  claims      jsonb   default '[]'::jsonb,
  main_skill  text    default '',          -- habilidade principal, escrita pelo jogador
  element     text    default '',          -- habilidade elemental, escolhida na criação
  trof        jsonb   default '[]'::jsonb,
  intro       boolean default false,
  active      boolean default true,
  is_master   boolean default false,
  created_at  timestamptz default now()
);

create table if not exists items (
  id         text primary key,
  owner      uuid references players(id) on delete set null,  -- null = cofre do Mestre
  origin     text default 'mestre',
  by_name    text default '',
  name       text not null,
  kind       text default 'item',
  cat        text default 'documento',
  icon       text default 'doc',
  stage      int  default 1,
  rumor      text default '',
  partial    text default '',
  full_text  text default '',
  img        text,
  doc        jsonb,
  locks      jsonb default '[]'::jsonb,
  ts         bigint default (extract(epoch from now())*1000)::bigint
);
create index if not exists items_owner_idx on items(owner);

create table if not exists letters (
  id        text primary key,
  to_player uuid references players(id) on delete cascade,
  dir       text default 'out',          -- out = do Mestre, in = do jogador
  from_name text default '',
  title     text default '',
  body      text default '',
  img       text,
  att       jsonb,
  read      boolean default false,
  ts        bigint default (extract(epoch from now())*1000)::bigint
);
create index if not exists letters_to_idx on letters(to_player);

create table if not exists notes (
  id    text primary key,
  owner uuid references players(id) on delete cascade,
  title text default '',
  body  text default '',
  img   text,
  ts    bigint default (extract(epoch from now())*1000)::bigint
);
create index if not exists notes_owner_idx on notes(owner);

create table if not exists app_state (
  k text primary key,
  v jsonb not null default '{}'::jsonb
);

create table if not exists logs (
  id  bigserial primary key,
  txt text not null,
  ts  bigint default (extract(epoch from now())*1000)::bigint
);

create table if not exists mural_items (id text primary key, v jsonb not null);
create table if not exists mural_links (id text primary key, v jsonb not null);

-- ---------- QUEM É O MESTRE ----------

create or replace function is_master()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select p.is_master from players p where p.id = auth.uid()), false);
$$;

-- ---------- HABILIDADES (bancos criados antes desta versão) ----------
alter table players add column if not exists main_skill text default '';
alter table players add column if not exists element    text default '';

-- A habilidade elemental é definitiva: o jogador não troca, só o Mestre.
-- A principal ele reescreve quando quiser (o Mestre é avisado no registro).
create or replace function lock_power()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if is_master() then
    return new;
  end if;
  if coalesce(old.element,'') <> '' then
    new.element := old.element;
  end if;
  return new;
end;
$$;

drop trigger if exists players_lock_power on players;
create trigger players_lock_power
  before update on players
  for each row execute function lock_power();

-- ---------- TRAVAS (RLS) ----------

alter table players     enable row level security;
alter table items       enable row level security;
alter table letters     enable row level security;
alter table notes       enable row level security;
alter table app_state   enable row level security;
alter table logs        enable row level security;
alter table mural_items enable row level security;
alter table mural_links enable row level security;

-- players: todo mundo logado vê a lista de operadores (nome, foto, situação).
-- Cada um só edita a própria ficha; o Mestre edita qualquer uma.
drop policy if exists p_sel on players;
create policy p_sel on players for select to authenticated using (true);
drop policy if exists p_ins on players;
create policy p_ins on players for insert to authenticated with check (id = auth.uid());
drop policy if exists p_upd on players;
create policy p_upd on players for update to authenticated
  using (id = auth.uid() or is_master()) with check (id = auth.uid() or is_master());
drop policy if exists p_del on players;
create policy p_del on players for delete to authenticated using (is_master());

-- items: o jogador só enxerga o que é dele. O cofre (owner null) é só do Mestre.
drop policy if exists i_sel on items;
create policy i_sel on items for select to authenticated
  using (owner = auth.uid() or is_master());
drop policy if exists i_ins on items;
create policy i_ins on items for insert to authenticated
  with check (is_master() or (owner = auth.uid() and origin = 'jogador'));
drop policy if exists i_upd on items;
create policy i_upd on items for update to authenticated
  using (is_master() or (owner = auth.uid() and origin = 'jogador'))
  with check (is_master() or (owner = auth.uid() and origin = 'jogador'));
drop policy if exists i_del on items;
create policy i_del on items for delete to authenticated
  using (is_master() or (owner = auth.uid() and origin = 'jogador'));

-- letters: a conversa é de duas pessoas só.
drop policy if exists l_sel on letters;
create policy l_sel on letters for select to authenticated
  using (to_player = auth.uid() or is_master());
drop policy if exists l_ins on letters;
create policy l_ins on letters for insert to authenticated
  with check (is_master() or to_player = auth.uid());
drop policy if exists l_upd on letters;
create policy l_upd on letters for update to authenticated
  using (to_player = auth.uid() or is_master())
  with check (to_player = auth.uid() or is_master());
drop policy if exists l_del on letters;
create policy l_del on letters for delete to authenticated using (is_master());

-- notes: o diário é do jogador (o Mestre lê, como no protótipo).
drop policy if exists n_sel on notes;
create policy n_sel on notes for select to authenticated
  using (owner = auth.uid() or is_master());
drop policy if exists n_all on notes;
create policy n_all on notes for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

-- app_state: data da campanha, sessão e lista de troféus. Todos leem, só o Mestre muda.
drop policy if exists s_sel on app_state;
create policy s_sel on app_state for select to authenticated using (true);
drop policy if exists s_wr on app_state;
create policy s_wr on app_state for all to authenticated
  using (is_master()) with check (is_master());

-- logs: só o Mestre lê; qualquer um logado escreve.
drop policy if exists g_sel on logs;
create policy g_sel on logs for select to authenticated using (is_master());
drop policy if exists g_ins on logs;
create policy g_ins on logs for insert to authenticated with check (true);
drop policy if exists g_del on logs;
create policy g_del on logs for delete to authenticated using (is_master());

-- mural: quadro coletivo, todo mundo mexe.
drop policy if exists m_i on mural_items;
create policy m_i on mural_items for all to authenticated using (true) with check (true);
drop policy if exists m_l on mural_links;
create policy m_l on mural_links for all to authenticated using (true) with check (true);

-- ---------- TEMPO REAL ----------
do $$
begin
  begin execute 'alter publication supabase_realtime add table players';     exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table items';       exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table letters';     exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table notes';       exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table app_state';   exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table mural_items'; exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table mural_links'; exception when others then null; end;
end $$;

-- ---------- VALORES INICIAIS ----------
insert into app_state (k, v) values
  ('meta', '{"date":"JUL 2005","ses":1,"tot":24}'::jsonb)
on conflict (k) do nothing;

insert into app_state (k, v) values ('trof', '[]'::jsonb)
on conflict (k) do nothing;

-- =====================================================================
--  PRONTO. Depois de criar a SUA ficha no sistema, rode esta linha
--  trocando pelo seu usuário, para virar Mestre:
--
--     update players set is_master = true where username = 'daniel';
-- =====================================================================
