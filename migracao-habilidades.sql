-- ---------- HABILIDADES (bancos criados antes desta versão) ----------
alter table players add column if not exists main_skill text default '';
alter table players add column if not exists element    text default '';

-- Habilidade escolhida é definitiva: o jogador não troca, só o Mestre.
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
  if coalesce(old.main_skill,'') <> '' then
    new.main_skill := old.main_skill;
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
