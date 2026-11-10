-- Prevent sellers from selecting an alternate price list at transaction time.
create or replace function public.registrar_venta_en_deposito(
  p_cliente_id uuid, p_deposito_id uuid, p_items jsonb, p_lista_precio_id uuid, p_sucursal_id uuid
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_comercio uuid; v_sucursal uuid; v_lista uuid;
begin
  select u.comercio_id into v_comercio from public.usuarios u where u.id=auth.uid();
  if v_comercio is null then raise exception 'Debes iniciar sesión con un usuario del comercio'; end if;
  select d.sucursal_id into v_sucursal from public.depositos d where d.id=p_deposito_id and d.comercio_id=v_comercio and d.activo;
  if v_sucursal is null then raise exception 'Seleccioná un depósito activo de tu comercio'; end if;
  if p_sucursal_id is not null and p_sucursal_id<>v_sucursal then raise exception 'La sucursal no coincide con el depósito seleccionado'; end if;
  if private.current_user_role()='vendedor' then
    v_lista:=public.resolver_lista_precio(v_comercio,v_sucursal,p_cliente_id,null::uuid);
  else
    v_lista:=public.resolver_lista_precio(v_comercio,v_sucursal,p_cliente_id,p_lista_precio_id);
  end if;
  return public.registrar_venta_en_deposito(p_cliente_id,p_deposito_id,p_items,v_lista);
end $$;

create or replace function public.registrar_presupuesto(
  p_cliente_id uuid, p_items jsonb, p_lista_precio_id uuid, p_sucursal_id uuid
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_comercio uuid; v_lista uuid; v_presupuesto uuid;
begin
  select u.comercio_id into v_comercio from public.usuarios u where u.id=auth.uid();
  if v_comercio is null then raise exception 'Debes iniciar sesión con un usuario del comercio'; end if;
  if private.current_user_role()='vendedor' then
    v_lista:=public.resolver_lista_precio(v_comercio,p_sucursal_id,p_cliente_id,null::uuid);
  else
    v_lista:=public.resolver_lista_precio(v_comercio,p_sucursal_id,p_cliente_id,p_lista_precio_id);
  end if;
  v_presupuesto:=public.registrar_presupuesto(p_cliente_id,p_items,v_lista);
  update public.presupuestos set sucursal_id=p_sucursal_id where id=v_presupuesto and comercio_id=v_comercio;
  return v_presupuesto;
end $$;

create table if not exists public.auditoria_cambios (
  id uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  actor_id uuid, tabla text not null, registro_id uuid,
  operacion text not null check (operacion in ('INSERT','UPDATE','DELETE')),
  antes jsonb, despues jsonb, created_at timestamptz not null default now()
);
create index if not exists auditoria_cambios_comercio_fecha_idx on public.auditoria_cambios(comercio_id,created_at desc);
alter table public.auditoria_cambios enable row level security;
drop policy if exists auditoria_cambios_admin_read on public.auditoria_cambios;
create policy auditoria_cambios_admin_read on public.auditoria_cambios for select to authenticated
using (comercio_id=(select private.current_user_commerce_id()) and (select private.is_commerce_admin()));
revoke all on public.auditoria_cambios from anon,authenticated;
grant select on public.auditoria_cambios to authenticated;

create or replace function private.log_commerce_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_before jsonb; v_after jsonb; v_comercio uuid; v_id uuid;
begin
  if tg_op='INSERT' then v_after:=to_jsonb(new); v_comercio:=(v_after->>'comercio_id')::uuid; v_id:=(v_after->>'id')::uuid;
  elsif tg_op='UPDATE' then v_before:=to_jsonb(old); v_after:=to_jsonb(new); v_comercio:=coalesce((v_after->>'comercio_id')::uuid,(v_before->>'comercio_id')::uuid); v_id:=(v_after->>'id')::uuid;
  else v_before:=to_jsonb(old); v_comercio:=(v_before->>'comercio_id')::uuid; v_id:=(v_before->>'id')::uuid;
  end if;
  if v_comercio is not null then
    insert into public.auditoria_cambios(comercio_id,actor_id,tabla,registro_id,operacion,antes,despues)
    values(v_comercio,auth.uid(),tg_table_name,v_id,tg_op,v_before,v_after);
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['productos','listas_precios','lista_precios_items','stock','inventario_saldos',
    'inventario_movimientos','compras','caja_movimientos','usuarios','pedidos','presupuestos','clientes'] loop
    execute format('drop trigger if exists audit_%I on public.%I',t,t);
    execute format('create trigger audit_%I after insert or update or delete on public.%I for each row execute function private.log_commerce_change()',t,t);
  end loop;
end $$;