-- Advanced, date-aware and customer-specific pricing rules for NexoVentas.
alter table public.lista_precios_items add column if not exists cantidad_maxima numeric(14,3);
alter table public.lista_precios_items add column if not exists vigente_desde timestamptz;
alter table public.lista_precios_items add column if not exists vigente_hasta timestamptz;
alter table public.lista_precios_items add column if not exists prioridad integer not null default 0;
alter table public.lista_precios_items add column if not exists tipo_regla text not null default 'precio_fijo';
alter table public.lista_precios_items add column if not exists descuento_porcentaje numeric(5,2) not null default 0;
alter table public.clientes add column if not exists lista_precio_id uuid;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='clientes_comercio_lista_precio_fk') then
  alter table public.clientes add constraint clientes_comercio_lista_precio_fk foreign key(comercio_id,lista_precio_id) references public.listas_precios(comercio_id,id) on delete restrict;
 end if;
 if not exists(select 1 from pg_constraint where conname='lista_precios_items_quantity_range_ck') then
  alter table public.lista_precios_items add constraint lista_precios_items_quantity_range_ck check(cantidad_maxima is null or cantidad_maxima>=cantidad_minima);
 end if;
 if not exists(select 1 from pg_constraint where conname='lista_precios_items_date_range_ck') then
  alter table public.lista_precios_items add constraint lista_precios_items_date_range_ck check(vigente_hasta is null or vigente_desde is null or vigente_hasta>vigente_desde);
 end if;
 if not exists(select 1 from pg_constraint where conname='lista_precios_items_rule_type_ck') then
  alter table public.lista_precios_items add constraint lista_precios_items_rule_type_ck check(tipo_regla in ('precio_fijo','descuento_porcentaje'));
 end if;
 if not exists(select 1 from pg_constraint where conname='lista_precios_items_discount_ck') then
  alter table public.lista_precios_items add constraint lista_precios_items_discount_ck check(descuento_porcentaje>=0 and descuento_porcentaje<=100);
 end if;
end $$;
drop index if exists public.lista_precios_items_unique_tier_idx;
create unique index if not exists lista_precios_items_unique_rule_idx on public.lista_precios_items(comercio_id,lista_precio_id,producto_id,(coalesce(variante_id,'00000000-0000-0000-0000-000000000000'::uuid)),cantidad_minima,prioridad,(coalesce(vigente_desde,'-infinity'::timestamptz)),(coalesce(vigente_hasta,'infinity'::timestamptz)));
create index if not exists lista_precios_items_active_rules_idx on public.lista_precios_items(comercio_id,lista_precio_id,producto_id,prioridad desc,cantidad_minima desc);
create index if not exists clientes_comercio_lista_precio_idx on public.clientes(comercio_id,lista_precio_id);
create or replace function public.resolver_precio_lista(p_comercio_id uuid,p_lista_precio_id uuid,p_producto_id uuid,p_variante_id uuid,p_cantidad numeric,p_precio_base numeric)
returns table(precio numeric,regla_id uuid)
language sql security invoker set search_path=''
as $function$
 select coalesce(case when r.tipo_regla='descuento_porcentaje' then round(p_precio_base*(1-r.descuento_porcentaje/100),2) else r.precio end,p_precio_base),r.id
 from (select 1) seed
 left join lateral (
  select li.id,li.tipo_regla,li.descuento_porcentaje,li.precio
  from public.lista_precios_items li
  where li.comercio_id=p_comercio_id and li.lista_precio_id=p_lista_precio_id and li.producto_id=p_producto_id
   and (li.variante_id is not distinct from p_variante_id or (p_variante_id is not null and li.variante_id is null))
   and li.cantidad_minima<=p_cantidad and (li.cantidad_maxima is null or p_cantidad<=li.cantidad_maxima)
   and (li.vigente_desde is null or li.vigente_desde<=now()) and (li.vigente_hasta is null or li.vigente_hasta>=now())
  order by (li.variante_id is not null) desc,li.prioridad desc,li.cantidad_minima desc,li.vigente_desde desc nulls first,li.created_at desc
  limit 1
 ) r on true;
$function$;
revoke all on function public.resolver_precio_lista(uuid,uuid,uuid,uuid,numeric,numeric) from public,anon;
grant execute on function public.resolver_precio_lista(uuid,uuid,uuid,uuid,numeric,numeric) to authenticated;
CREATE OR REPLACE FUNCTION public.registrar_venta_en_deposito(p_cliente_id uuid, p_deposito_id uuid, p_items jsonb, p_lista_precio_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_comercio uuid; v_sucursal uuid; v_pedido uuid;
 v_item jsonb; v_producto public.productos%rowtype; v_variante public.producto_variantes%rowtype;
 v_stock public.stock%rowtype; v_saldo public.inventario_saldos%rowtype;
 v_qty numeric(14,3); v_total numeric(14,2):=0; v_subtotal numeric(14,2);
 v_group record; v_lista uuid; v_price numeric(14,2); v_list_item uuid;
begin
 if v_user is null then raise exception 'Debes iniciar sesión'; end if;
 select u.comercio_id into v_comercio from public.usuarios u where u.id=v_user;
 if v_comercio is null then raise exception 'El usuario no tiene un comercio asociado'; end if;
 select d.sucursal_id into v_sucursal from public.depositos d where d.id=p_deposito_id and d.comercio_id=v_comercio and d.activo for update;
 if v_sucursal is null then raise exception 'Seleccioná un depósito activo de tu comercio'; end if;
 if p_cliente_id is not null and not exists(select 1 from public.clientes c where c.id=p_cliente_id and c.comercio_id=v_comercio) then raise exception 'El cliente no pertenece a tu comercio'; end if;
 if p_lista_precio_id is not null then
  if not exists(select 1 from public.listas_precios l where l.id=p_lista_precio_id and l.comercio_id=v_comercio and l.activa and l.moneda='ARS') then raise exception 'La lista de precios no pertenece a tu comercio o está inactiva'; end if;
  v_lista:=p_lista_precio_id;
 else
  if p_cliente_id is not null then
   select c.lista_precio_id into v_lista from public.clientes c where c.id=p_cliente_id and c.comercio_id=v_comercio;
   if v_lista is not null and not exists(select 1 from public.listas_precios l where l.id=v_lista and l.comercio_id=v_comercio and l.activa and l.moneda='ARS') then
    raise exception 'La lista asignada al cliente no está activa o no está en ARS';
   end if;
  end if;
  if v_lista is null then
   select l.id into v_lista from public.listas_precios l where l.comercio_id=v_comercio and l.activa and l.moneda='ARS' and l.es_predeterminada order by l.created_at desc limit 1;
  end if;
 end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Agregá al menos un producto'; end if;

 for v_group in
  select x.producto_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad numeric)
  group by x.producto_id order by x.producto_id
 loop
  if v_group.producto_id is null or v_group.cantidad is null or v_group.cantidad<=0 then
   raise exception 'Hay productos o cantidades inválidas';
  end if;
  select * into v_stock from public.stock s where s.comercio_id=v_comercio and s.producto_id=v_group.producto_id for update;
  if not found then raise exception 'No existe el stock general del producto'; end if;
  if v_stock.cantidad<v_group.cantidad then
   raise exception 'La cantidad total solicitada supera el stock general del producto';
  end if;
 end loop;

 for v_group in
  select x.producto_id,x.variante_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,variante_id uuid,cantidad numeric)
  group by x.producto_id,x.variante_id order by x.producto_id,x.variante_id nulls first
 loop
  if v_group.producto_id is null or v_group.cantidad is null or v_group.cantidad<=0 then raise exception 'Hay productos o cantidades inválidas'; end if;
  select * into v_producto from public.productos p where p.id=v_group.producto_id and p.comercio_id=v_comercio and p.activo for update;
  if not found then raise exception 'Hay un producto inválido o inactivo'; end if;
  if v_group.variante_id is not null then
   select * into v_variante from public.producto_variantes pv where pv.id=v_group.variante_id and pv.comercio_id=v_comercio and pv.producto_id=v_group.producto_id and pv.activa for update;
   if not found then raise exception 'La variante no pertenece al producto o está inactiva'; end if;
  end if;
  select * into v_stock from public.stock s where s.comercio_id=v_comercio and s.producto_id=v_group.producto_id for update;
  if not found then raise exception 'No existe el stock general de %',v_producto.nombre; end if;
  insert into public.inventario_saldos(comercio_id,deposito_id,producto_id,variante_id,cantidad)
   values(v_comercio,p_deposito_id,v_group.producto_id,v_group.variante_id,0)
   on conflict(comercio_id,deposito_id,producto_id,variante_id) do nothing;
  select * into v_saldo from public.inventario_saldos i where i.comercio_id=v_comercio and i.deposito_id=p_deposito_id and i.producto_id=v_group.producto_id and i.variante_id is not distinct from v_group.variante_id for update;
  if v_saldo.cantidad-v_saldo.cantidad_reservada<v_group.cantidad then raise exception 'Stock insuficiente para % (disponible: %)',v_producto.nombre,v_saldo.cantidad-v_saldo.cantidad_reservada; end if;
  if v_stock.cantidad<v_group.cantidad then raise exception 'El stock total del comercio no coincide con el inventario por depósito para %',v_producto.nombre; end if;
 end loop;

 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=nullif(v_item->>'cantidad','')::numeric;
  select * into v_producto from public.productos p where p.id=(v_item->>'producto_id')::uuid and p.comercio_id=v_comercio and p.activo;
  v_variante:=null;
  if nullif(v_item->>'variante_id','') is not null then
   select * into v_variante from public.producto_variantes pv where pv.id=(v_item->>'variante_id')::uuid and pv.comercio_id=v_comercio and pv.producto_id=v_producto.id and pv.activa;
   if not found then raise exception 'Variante inválida'; end if;
  end if;
  v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0); v_list_item:=null;
  select rp.precio,rp.regla_id into v_price,v_list_item
  from public.resolver_precio_lista(v_comercio,v_lista,v_producto.id,v_variante.id,v_qty,v_producto.precio+coalesce(v_variante.precio_adicional,0)) rp;
  v_subtotal:=round(v_price*v_qty,2); v_total:=v_total+v_subtotal;
 end loop;

 insert into public.pedidos(comercio_id,cliente_id,vendedor_id,total,estado,sucursal_id,deposito_id,lista_precio_id)
 values(v_comercio,p_cliente_id,v_user,v_total,'completada',v_sucursal,p_deposito_id,v_lista) returning id into v_pedido;

 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=nullif(v_item->>'cantidad','')::numeric;
  select * into v_producto from public.productos p where p.id=(v_item->>'producto_id')::uuid and p.comercio_id=v_comercio;
  v_variante:=null;
  if nullif(v_item->>'variante_id','') is not null then select * into v_variante from public.producto_variantes pv where pv.id=(v_item->>'variante_id')::uuid and pv.comercio_id=v_comercio; end if;
  v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0); v_list_item:=null;
  select rp.precio,rp.regla_id into v_price,v_list_item
  from public.resolver_precio_lista(v_comercio,v_lista,v_producto.id,v_variante.id,v_qty,v_producto.precio+coalesce(v_variante.precio_adicional,0)) rp;
  v_subtotal:=round(v_price*v_qty,2);
  insert into public.pedido_detalles(comercio_id,pedido_id,producto_id,producto_nombre,cantidad,precio_unitario,costo_unitario,subtotal,variante_id,lista_precio_item_id)
  values(v_comercio,v_pedido,v_producto.id,v_producto.nombre||case when v_variante.id is not null then ' · '||v_variante.nombre else '' end,v_qty,v_price,v_producto.costo_unitario+coalesce(v_variante.costo_adicional,0),v_subtotal,v_variante.id,v_list_item);
 end loop;

 for v_group in
  select x.producto_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad numeric)
  group by x.producto_id order by x.producto_id
 loop
  if v_group.producto_id is null or v_group.cantidad is null or v_group.cantidad<=0 then
   raise exception 'Hay productos o cantidades inválidas';
  end if;
  select * into v_stock from public.stock s where s.comercio_id=v_comercio and s.producto_id=v_group.producto_id for update;
  if not found then raise exception 'No existe el stock general del producto'; end if;
  if v_stock.cantidad<v_group.cantidad then
   raise exception 'La cantidad total solicitada supera el stock general del producto';
  end if;
 end loop;

 for v_group in
  select x.producto_id,x.variante_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,variante_id uuid,cantidad numeric)
  group by x.producto_id,x.variante_id order by x.producto_id,x.variante_id nulls first
 loop
  update public.stock set cantidad=cantidad-v_group.cantidad,updated_at=now() where comercio_id=v_comercio and producto_id=v_group.producto_id;
  update public.inventario_saldos set cantidad=cantidad-v_group.cantidad,updated_at=now()
   where comercio_id=v_comercio and deposito_id=p_deposito_id and producto_id=v_group.producto_id and variante_id is not distinct from v_group.variante_id;
  insert into public.inventario_movimientos(comercio_id,tipo,deposito_origen_id,producto_id,variante_id,cantidad,referencia_tipo,referencia_id,motivo,usuario_id)
  values(v_comercio,'salida',p_deposito_id,v_group.producto_id,v_group.variante_id,v_group.cantidad,'venta',v_pedido,'Venta registrada',v_user);
 end loop;
 return v_pedido;
end;
$function$


CREATE OR REPLACE FUNCTION public.registrar_presupuesto(p_cliente_id uuid, p_items jsonb, p_lista_precio_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_comercio uuid; v_presupuesto uuid; v_item jsonb;
 v_producto public.productos%rowtype; v_variante public.producto_variantes%rowtype;
 v_qty numeric(14,3); v_total numeric(14,2):=0; v_price numeric(14,2); v_subtotal numeric(14,2); v_lista uuid; v_list_item uuid;
begin
 if v_user is null then raise exception 'Debes iniciar sesión'; end if;
 select u.comercio_id into v_comercio from public.usuarios u where u.id=v_user;
 if v_comercio is null then raise exception 'El usuario no tiene un comercio asociado'; end if;
 if p_cliente_id is not null and not exists(select 1 from public.clientes c where c.id=p_cliente_id and c.comercio_id=v_comercio) then raise exception 'El cliente no pertenece a tu comercio'; end if;
 if p_lista_precio_id is not null then
  if not exists(select 1 from public.listas_precios l where l.id=p_lista_precio_id and l.comercio_id=v_comercio and l.activa and l.moneda='ARS') then raise exception 'La lista de precios no pertenece a tu comercio o está inactiva'; end if;
  v_lista:=p_lista_precio_id;
 else
  if p_cliente_id is not null then
   select c.lista_precio_id into v_lista from public.clientes c where c.id=p_cliente_id and c.comercio_id=v_comercio;
   if v_lista is not null and not exists(select 1 from public.listas_precios l where l.id=v_lista and l.comercio_id=v_comercio and l.activa and l.moneda='ARS') then
    raise exception 'La lista asignada al cliente no está activa o no está en ARS';
   end if;
  end if;
  if v_lista is null then
   select l.id into v_lista from public.listas_precios l where l.comercio_id=v_comercio and l.activa and l.moneda='ARS' and l.es_predeterminada order by l.created_at desc limit 1;
  end if;
 end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Agregá al menos un producto'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=nullif(v_item->>'cantidad','')::numeric;
  if v_qty is null or v_qty<=0 then raise exception 'La cantidad debe ser mayor a cero'; end if;
  select * into v_producto from public.productos p where p.id=(v_item->>'producto_id')::uuid and p.comercio_id=v_comercio and p.activo;
  if not found then raise exception 'Hay un producto inválido o inactivo'; end if;
  v_variante:=null;
  if nullif(v_item->>'variante_id','') is not null then select * into v_variante from public.producto_variantes pv where pv.id=(v_item->>'variante_id')::uuid and pv.comercio_id=v_comercio and pv.producto_id=v_producto.id and pv.activa; if not found then raise exception 'Variante inválida'; end if; end if;
  v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0);v_list_item:=null;
  select rp.precio,rp.regla_id into v_price,v_list_item
  from public.resolver_precio_lista(v_comercio,v_lista,v_producto.id,v_variante.id,v_qty,v_producto.precio+coalesce(v_variante.precio_adicional,0)) rp;
  v_subtotal:=round(v_price*v_qty,2);v_total:=v_total+v_subtotal;
 end loop;
 insert into public.presupuestos(comercio_id,cliente_id,vendedor_id,total,estado,lista_precio_id) values(v_comercio,p_cliente_id,v_user,v_total,'borrador',v_lista) returning id into v_presupuesto;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=nullif(v_item->>'cantidad','')::numeric;
  select * into v_producto from public.productos p where p.id=(v_item->>'producto_id')::uuid and p.comercio_id=v_comercio;
  v_variante:=null;if nullif(v_item->>'variante_id','') is not null then select * into v_variante from public.producto_variantes pv where pv.id=(v_item->>'variante_id')::uuid and pv.comercio_id=v_comercio; end if;
  v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0);v_list_item:=null;
  select rp.precio,rp.regla_id into v_price,v_list_item
  from public.resolver_precio_lista(v_comercio,v_lista,v_producto.id,v_variante.id,v_qty,v_producto.precio+coalesce(v_variante.precio_adicional,0)) rp;
  v_subtotal:=round(v_price*v_qty,2);
  insert into public.presupuesto_detalles(comercio_id,presupuesto_id,producto_id,producto_nombre,cantidad,precio_unitario,subtotal,variante_id,lista_precio_item_id)
  values(v_comercio,v_presupuesto,v_producto.id,v_producto.nombre||case when v_variante.id is not null then ' · '||v_variante.nombre else '' end,v_qty,v_price,v_subtotal,v_variante.id,v_list_item);
 end loop;
 return v_presupuesto;
end;
$function$

revoke all on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid) from public,anon;
grant execute on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid) to authenticated;
revoke all on function public.registrar_presupuesto(uuid,jsonb,uuid) from public,anon;
grant execute on function public.registrar_presupuesto(uuid,jsonb,uuid) to authenticated;
