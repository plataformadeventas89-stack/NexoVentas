alter table public.presupuestos
  add column if not exists sucursal_id uuid;
alter table public.presupuestos
  drop constraint if exists presupuestos_sucursal_comercio_fk;
alter table public.presupuestos
  add constraint presupuestos_sucursal_comercio_fk
  foreign key (sucursal_id, comercio_id)
  references public.sucursales(id, comercio_id)
  on delete restrict;
create index if not exists listas_precios_sucursal_comercio_fk_idx
  on public.listas_precios(sucursal_id, comercio_id);
create index if not exists presupuestos_sucursal_comercio_fk_idx
  on public.presupuestos(sucursal_id, comercio_id);
create index if not exists presupuestos_comercio_sucursal_idx
  on public.presupuestos(comercio_id, sucursal_id);

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
  ) then raise exception 'La sucursal seleccionada no pertenece a tu comercio o está inactiva'; end if;

  if p_lista_precio_id is not null then
    select l.id into v_lista from public.listas_precios l
    where l.id = p_lista_precio_id and l.comercio_id = p_comercio_id
      and l.activa and l.moneda = 'ARS'
      and (l.sucursal_id is null or l.sucursal_id = p_sucursal_id)
      and (l.segmento_cliente is null or l.segmento_cliente = v_segmento);
    if v_lista is null then raise exception 'La lista elegida no corresponde a la sucursal o al segmento del cliente'; end if;
    return v_lista;
  end if;

  if v_asignada is not null then
    select l.id into v_lista from public.listas_precios l
    where l.id = v_asignada and l.comercio_id = p_comercio_id
      and l.activa and l.moneda = 'ARS'
      and (l.sucursal_id is null or l.sucursal_id = p_sucursal_id)
      and (l.segmento_cliente is null or l.segmento_cliente = v_segmento);
    if v_lista is not null then return v_lista; end if;
  end if;

  select l.id into v_lista from public.listas_precios l
  where l.comercio_id = p_comercio_id and l.activa and l.moneda = 'ARS'
    and (l.sucursal_id is null or l.sucursal_id = p_sucursal_id)
    and (l.segmento_cliente is null or l.segmento_cliente = v_segmento)
  order by (l.sucursal_id is not null) desc,
           (l.segmento_cliente is not null) desc,
           l.es_predeterminada desc, l.created_at desc
  limit 1;

  if v_lista is null then
    select l.id into v_lista from public.listas_precios l
    where l.comercio_id = p_comercio_id and l.activa and l.moneda = 'ARS'
      and l.es_predeterminada and l.sucursal_id is null
      and l.segmento_cliente is null
    order by l.created_at desc limit 1;
  end if;

  if v_lista is null and v_asignada is not null then
    raise exception 'La lista asignada al cliente no es válida para esta sucursal o segmento; asigná una lista compatible';
  end if;
  return v_lista;
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
  v_presupuesto uuid;
begin
  select u.comercio_id into v_comercio from public.usuarios u where u.id = auth.uid();
  if v_comercio is null then raise exception 'Debes iniciar sesión'; end if;
  v_lista := public.resolver_lista_precio(v_comercio, p_sucursal_id, p_cliente_id, p_lista_precio_id);
  v_presupuesto := public.registrar_presupuesto(p_cliente_id, p_items, v_lista);
  update public.presupuestos
  set sucursal_id = p_sucursal_id
  where id = v_presupuesto and comercio_id = v_comercio;
  return v_presupuesto;
end;
$$;

revoke all on function public.resolver_lista_precio(uuid,uuid,uuid,uuid) from public, anon;
grant execute on function public.resolver_lista_precio(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) from public, anon;
grant execute on function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) to authenticated;
