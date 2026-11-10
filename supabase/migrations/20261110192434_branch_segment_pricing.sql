alter table public.clientes
  add column if not exists segmento text not null default 'minorista';
alter table public.clientes
  drop constraint if exists clientes_segmento_check;
alter table public.clientes
  add constraint clientes_segmento_check
  check (segmento in ('minorista','mayorista','distribuidor','especial'));

alter table public.listas_precios
  add column if not exists sucursal_id uuid,
  add column if not exists segmento_cliente text;
alter table public.listas_precios
  drop constraint if exists listas_precios_segmento_cliente_check;
alter table public.listas_precios
  add constraint listas_precios_segmento_cliente_check
  check (segmento_cliente is null or segmento_cliente in ('minorista','mayorista','distribuidor','especial'));
alter table public.listas_precios
  drop constraint if exists listas_precios_sucursal_comercio_fk;
alter table public.listas_precios
  add constraint listas_precios_sucursal_comercio_fk
  foreign key (sucursal_id, comercio_id)
  references public.sucursales(id, comercio_id)
  on delete restrict;

create index if not exists listas_precios_scope_idx
  on public.listas_precios(comercio_id, sucursal_id, segmento_cliente, activa, moneda);
create index if not exists clientes_segmento_idx
  on public.clientes(comercio_id, segmento);

create or replace function public.resolver_lista_precio(
  p_comercio_id uuid,
  p_sucursal_id uuid,
  p_cliente_id uuid,
  p_lista_precio_id uuid default null
) returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_segmento text := 'minorista';
  v_asignada uuid;
  v_lista uuid;
begin
  if p_cliente_id is not null then
    select c.segmento, c.lista_precio_id into v_segmento, v_asignada
    from public.clientes c
    where c.id = p_cliente_id and c.comercio_id = p_comercio_id;
    if not found then raise exception 'El cliente no pertenece a tu comercio'; end if;
  end if;

  if p_sucursal_id is not null and not exists (
    select 1 from public.sucursales s
    where s.id = p_sucursal_id and s.comercio_id = p_comercio_id and s.activa
  ) then
    raise exception 'La sucursal seleccionada no pertenece a tu comercio o está inactiva';
  end if;

  if p_lista_precio_id is not null then
    select l.id into v_lista
    from public.listas_precios l
    where l.id = p_lista_precio_id
      and l.comercio_id = p_comercio_id
      and l.activa and l.moneda = 'ARS'
      and (l.sucursal_id is null or l.sucursal_id = p_sucursal_id)
      and (l.segmento_cliente is null or l.segmento_cliente = v_segmento);
    if v_lista is null then
      raise exception 'La lista elegida no corresponde a la sucursal o al segmento del cliente';
    end if;
    return v_lista;
  end if;

  if v_asignada is not null then
    select l.id into v_lista
    from public.listas_precios l
    where l.id = v_asignada and l.comercio_id = p_comercio_id
      and l.activa and l.moneda = 'ARS'
      and (l.sucursal_id is null or l.sucursal_id = p_sucursal_id)
      and (l.segmento_cliente is null or l.segmento_cliente = v_segmento);
    if v_lista is not null then return v_lista; end if;
  end if;

  select l.id into v_lista
  from public.listas_precios l
  where l.comercio_id = p_comercio_id and l.activa and l.moneda = 'ARS'
    and (l.sucursal_id is null or l.sucursal_id = p_sucursal_id)
    and (l.segmento_cliente is null or l.segmento_cliente = v_segmento)
  order by
    (l.sucursal_id is not null) desc,
    (l.segmento_cliente is not null) desc,
    l.es_predeterminada desc,
    l.created_at desc
  limit 1;

  if v_lista is null then
    select l.id into v_lista
    from public.listas_precios l
    where l.comercio_id = p_comercio_id and l.activa and l.moneda = 'ARS'
      and l.es_predeterminada and l.sucursal_id is null
      and l.segmento_cliente is null
    order by l.created_at desc limit 1;
  end if;
  return v_lista;
end;
$$;

create or replace function public.registrar_venta_en_deposito(
  p_cliente_id uuid,
  p_deposito_id uuid,
  p_items jsonb,
  p_lista_precio_id uuid,
  p_sucursal_id uuid
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_comercio uuid;
  v_sucursal uuid;
  v_lista uuid;
begin
  select u.comercio_id into v_comercio
  from public.usuarios u where u.id = auth.uid();
  if v_comercio is null then raise exception 'Debes iniciar sesión'; end if;

  select d.sucursal_id into v_sucursal
  from public.depositos d
  where d.id = p_deposito_id and d.comercio_id = v_comercio and d.activo;
  if v_sucursal is null then raise exception 'Seleccioná un depósito activo de tu comercio'; end if;
  if p_sucursal_id is not null and p_sucursal_id <> v_sucursal then
    raise exception 'La sucursal no coincide con el depósito seleccionado';
  end if;

  v_lista := public.resolver_lista_precio(v_comercio, v_sucursal, p_cliente_id, p_lista_precio_id);
  return public.registrar_venta_en_deposito(p_cliente_id, p_deposito_id, p_items, v_lista);
end;
$$;

create or replace function public.registrar_presupuesto(
  p_cliente_id uuid,
  p_items jsonb,
  p_lista_precio_id uuid,
  p_sucursal_id uuid
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_comercio uuid;
  v_lista uuid;
begin
  select u.comercio_id into v_comercio
  from public.usuarios u where u.id = auth.uid();
  if v_comercio is null then raise exception 'Debes iniciar sesión'; end if;

  v_lista := public.resolver_lista_precio(v_comercio, p_sucursal_id, p_cliente_id, p_lista_precio_id);
  return public.registrar_presupuesto(p_cliente_id, p_items, v_lista);
end;
$$;

revoke all on function public.resolver_lista_precio(uuid,uuid,uuid,uuid) from public, anon;
grant execute on function public.resolver_lista_precio(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid,uuid) from public, anon;
grant execute on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid,uuid) to authenticated;
revoke all on function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) from public, anon;
grant execute on function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) to authenticated;
