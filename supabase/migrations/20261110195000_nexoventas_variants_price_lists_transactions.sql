-- NexoVentas: variant-aware sales, purchases, quotes and price lists.
alter table public.pedido_detalles add column if not exists variante_id uuid;
alter table public.pedido_detalles add column if not exists lista_precio_item_id uuid;
alter table public.pedidos add column if not exists lista_precio_id uuid;
alter table public.presupuesto_detalles add column if not exists variante_id uuid;
alter table public.presupuesto_detalles add column if not exists lista_precio_item_id uuid;
alter table public.presupuestos add column if not exists lista_precio_id uuid;
alter table public.compra_detalles add column if not exists variante_id uuid;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='pedido_detalles_comercio_variante_fk') then
  alter table public.pedido_detalles add constraint pedido_detalles_comercio_variante_fk foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict;
 end if;
 if not exists(select 1 from pg_constraint where conname='presupuesto_detalles_comercio_variante_fk') then
  alter table public.presupuesto_detalles add constraint presupuesto_detalles_comercio_variante_fk foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict;
 end if;
 if not exists(select 1 from pg_constraint where conname='compra_detalles_comercio_variante_fk') then
  alter table public.compra_detalles add constraint compra_detalles_comercio_variante_fk foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict;
 end if;
 if not exists(select 1 from pg_constraint where conname='pedidos_comercio_lista_precio_fk') then
  alter table public.pedidos add constraint pedidos_comercio_lista_precio_fk foreign key(comercio_id,lista_precio_id) references public.listas_precios(comercio_id,id) on delete restrict;
 end if;
 if not exists(select 1 from pg_constraint where conname='presupuestos_comercio_lista_precio_fk') then
  alter table public.presupuestos add constraint presupuestos_comercio_lista_precio_fk foreign key(comercio_id,lista_precio_id) references public.listas_precios(comercio_id,id) on delete restrict;
 end if;
end $$;
create index if not exists pedido_detalles_variante_idx on public.pedido_detalles(comercio_id,variante_id);
create index if not exists presupuesto_detalles_variante_idx on public.presupuesto_detalles(comercio_id,variante_id);
create index if not exists compra_detalles_variante_idx on public.compra_detalles(comercio_id,variante_id);
create index if not exists lista_precios_items_lookup_idx on public.lista_precios_items(comercio_id,lista_precio_id,producto_id,variante_id,cantidad_minima desc);
create unique index if not exists lista_precios_items_unique_tier_idx on public.lista_precios_items(comercio_id,lista_precio_id,producto_id,(coalesce(variante_id,'00000000-0000-0000-0000-000000000000'::uuid)),cantidad_minima);
CREATE OR REPLACE FUNCTION public.registrar_compra_en_deposito(p_proveedor_id uuid, p_deposito_id uuid, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_comercio uuid; v_sucursal uuid; v_compra uuid; v_item jsonb;
 v_producto public.productos%rowtype; v_variante public.producto_variantes%rowtype; v_stock public.stock%rowtype;
 v_qty numeric(14,3); v_cost numeric(14,2); v_total numeric(14,2):=0; v_group record;
begin
 if v_user is null then raise exception 'Debes iniciar sesión'; end if;
 select u.comercio_id into v_comercio from public.usuarios u where u.id=v_user;
 if v_comercio is null then raise exception 'El usuario no tiene un comercio asociado'; end if;
 select d.sucursal_id into v_sucursal from public.depositos d where d.id=p_deposito_id and d.comercio_id=v_comercio and d.activo for update;
 if v_sucursal is null then raise exception 'Seleccioná un depósito activo de tu comercio'; end if;
 if p_proveedor_id is not null and not exists(select 1 from public.proveedores p where p.id=p_proveedor_id and p.comercio_id=v_comercio) then raise exception 'El proveedor no pertenece a tu comercio'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Agregá al menos un producto a la compra'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=nullif(v_item->>'cantidad','')::numeric; v_cost:=nullif(v_item->>'costo_unitario','')::numeric;
  if v_qty is null or v_qty<=0 or v_cost is null or v_cost<0 then raise exception 'La cantidad y el costo deben ser válidos'; end if;
  select * into v_producto from public.productos p where p.id=(v_item->>'producto_id')::uuid and p.comercio_id=v_comercio and p.activo for update;
  if not found then raise exception 'Hay un producto inválido o inactivo'; end if;
  if nullif(v_item->>'variante_id','') is not null then
   select * into v_variante from public.producto_variantes pv where pv.id=(v_item->>'variante_id')::uuid and pv.comercio_id=v_comercio and pv.producto_id=v_producto.id and pv.activa for update;
   if not found then raise exception 'La variante no pertenece al producto o está inactiva'; end if;
  end if;
  if not exists(select 1 from public.stock s where s.comercio_id=v_comercio and s.producto_id=v_producto.id) then raise exception 'No existe el stock general para %',v_producto.nombre; end if;
  v_total:=v_total+round(v_qty*v_cost,2);
 end loop;
 insert into public.compras(comercio_id,proveedor_id,total,estado,sucursal_id,deposito_id) values(v_comercio,p_proveedor_id,v_total,'recibida',v_sucursal,p_deposito_id) returning id into v_compra;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=nullif(v_item->>'cantidad','')::numeric; v_cost:=nullif(v_item->>'costo_unitario','')::numeric;
  select * into v_producto from public.productos p where p.id=(v_item->>'producto_id')::uuid and p.comercio_id=v_comercio;
  v_variante:=null;
  if nullif(v_item->>'variante_id','') is not null then select * into v_variante from public.producto_variantes pv where pv.id=(v_item->>'variante_id')::uuid and pv.comercio_id=v_comercio; end if;
  insert into public.compra_detalles(comercio_id,compra_id,producto_id,producto_nombre,cantidad,costo_unitario,subtotal,variante_id)
  values(v_comercio,v_compra,v_producto.id,v_producto.nombre||case when v_variante.id is not null then ' · '||v_variante.nombre else '' end,v_qty,v_cost,round(v_qty*v_cost,2),v_variante.id);
 end loop;
 for v_group in
  select x.producto_id,sum(x.cantidad)::numeric(14,3) cantidad,sum(x.cantidad*x.costo_unitario)::numeric(14,2) costo_total
  from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad numeric,costo_unitario numeric)
  group by x.producto_id order by x.producto_id
 loop
  select * into v_producto from public.productos p where p.id=v_group.producto_id and p.comercio_id=v_comercio for update;
  select * into v_stock from public.stock s where s.comercio_id=v_comercio and s.producto_id=v_group.producto_id for update;
  update public.stock set cantidad=cantidad+v_group.cantidad,updated_at=now() where comercio_id=v_comercio and producto_id=v_group.producto_id;
  update public.productos set costo_unitario=case when v_stock.cantidad+v_group.cantidad>0 then round(((v_stock.cantidad*v_producto.costo_unitario)+v_group.costo_total)/(v_stock.cantidad+v_group.cantidad),2) else v_producto.costo_unitario end
   where comercio_id=v_comercio and id=v_group.producto_id;
 end loop;
 for v_group in
  select x.producto_id,x.variante_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,variante_id uuid,cantidad numeric)
  group by x.producto_id,x.variante_id order by x.producto_id,x.variante_id nulls first
 loop
  insert into public.inventario_saldos(comercio_id,deposito_id,producto_id,variante_id,cantidad)
   values(v_comercio,p_deposito_id,v_group.producto_id,v_group.variante_id,0)
   on conflict(comercio_id,deposito_id,producto_id,variante_id) do nothing;
  update public.inventario_saldos set cantidad=cantidad+v_group.cantidad,updated_at=now()
   where comercio_id=v_comercio and deposito_id=p_deposito_id and producto_id=v_group.producto_id and variante_id is not distinct from v_group.variante_id;
  insert into public.inventario_movimientos(comercio_id,tipo,deposito_destino_id,producto_id,variante_id,cantidad,referencia_tipo,referencia_id,motivo,usuario_id)
  values(v_comercio,'entrada',p_deposito_id,v_group.producto_id,v_group.variante_id,v_group.cantidad,'compra',v_compra,'Compra recibida',v_user);
 end loop;
 return v_compra;
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
  if not exists(select 1 from public.listas_precios l where l.id=p_lista_precio_id and l.comercio_id=v_comercio and l.activa) then raise exception 'La lista de precios no pertenece a tu comercio o está inactiva'; end if;
  v_lista:=p_lista_precio_id;
 else select l.id into v_lista from public.listas_precios l where l.comercio_id=v_comercio and l.activa and l.es_predeterminada order by l.created_at desc limit 1;
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
  if v_lista is not null then
   select li.id,li.precio into v_list_item,v_price from public.lista_precios_items li where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id and li.variante_id is not distinct from v_variante.id and li.cantidad_minima<=v_qty order by li.cantidad_minima desc limit 1;
   if v_list_item is null and v_variante.id is not null then select li.id,li.precio into v_list_item,v_price from public.lista_precios_items li where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id and li.variante_id is null and li.cantidad_minima<=v_qty order by li.cantidad_minima desc limit 1; end if;
   if v_list_item is null then v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0); end if;
  end if;
  v_subtotal:=round(v_price*v_qty,2);v_total:=v_total+v_subtotal;
 end loop;
 insert into public.presupuestos(comercio_id,cliente_id,vendedor_id,total,estado,lista_precio_id) values(v_comercio,p_cliente_id,v_user,v_total,'borrador',v_lista) returning id into v_presupuesto;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_qty:=nullif(v_item->>'cantidad','')::numeric;
  select * into v_producto from public.productos p where p.id=(v_item->>'producto_id')::uuid and p.comercio_id=v_comercio;
  v_variante:=null;if nullif(v_item->>'variante_id','') is not null then select * into v_variante from public.producto_variantes pv where pv.id=(v_item->>'variante_id')::uuid and pv.comercio_id=v_comercio; end if;
  v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0);v_list_item:=null;
  if v_lista is not null then
   select li.id,li.precio into v_list_item,v_price from public.lista_precios_items li where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id and li.variante_id is not distinct from v_variante.id and li.cantidad_minima<=v_qty order by li.cantidad_minima desc limit 1;
   if v_list_item is null and v_variante.id is not null then select li.id,li.precio into v_list_item,v_price from public.lista_precios_items li where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id and li.variante_id is null and li.cantidad_minima<=v_qty order by li.cantidad_minima desc limit 1; end if;
   if v_list_item is null then v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0); end if;
  end if;
  v_subtotal:=round(v_price*v_qty,2);
  insert into public.presupuesto_detalles(comercio_id,presupuesto_id,producto_id,producto_nombre,cantidad,precio_unitario,subtotal,variante_id,lista_precio_item_id)
  values(v_comercio,v_presupuesto,v_producto.id,v_producto.nombre||case when v_variante.id is not null then ' · '||v_variante.nombre else '' end,v_qty,v_price,v_subtotal,v_variante.id,v_list_item);
 end loop;
 return v_presupuesto;
end;
$function$


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
  if not exists(select 1 from public.listas_precios l where l.id=p_lista_precio_id and l.comercio_id=v_comercio and l.activa) then raise exception 'La lista de precios no pertenece a tu comercio o está inactiva'; end if;
  v_lista:=p_lista_precio_id;
 else
  select l.id into v_lista from public.listas_precios l where l.comercio_id=v_comercio and l.activa and l.es_predeterminada order by l.created_at desc limit 1;
 end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Agregá al menos un producto'; end if;

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
  if v_lista is not null then
   select li.id,li.precio into v_list_item,v_price
   from public.lista_precios_items li
   where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id
    and li.variante_id is not distinct from v_variante.id and li.cantidad_minima<=v_qty
   order by li.cantidad_minima desc limit 1;
   if v_list_item is null and v_variante.id is not null then
    select li.id,li.precio into v_list_item,v_price
    from public.lista_precios_items li
    where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id
     and li.variante_id is null and li.cantidad_minima<=v_qty
    order by li.cantidad_minima desc limit 1;
   end if;
   if v_list_item is null then v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0); end if;
  end if;
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
  if v_lista is not null then
   select li.id,li.precio into v_list_item,v_price from public.lista_precios_items li
   where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id and li.variante_id is not distinct from v_variante.id and li.cantidad_minima<=v_qty order by li.cantidad_minima desc limit 1;
   if v_list_item is null and v_variante.id is not null then
    select li.id,li.precio into v_list_item,v_price from public.lista_precios_items li
    where li.comercio_id=v_comercio and li.lista_precio_id=v_lista and li.producto_id=v_producto.id and li.variante_id is null and li.cantidad_minima<=v_qty order by li.cantidad_minima desc limit 1;
   end if;
   if v_list_item is null then v_price:=v_producto.precio+coalesce(v_variante.precio_adicional,0); end if;
  end if;
  v_subtotal:=round(v_price*v_qty,2);
  insert into public.pedido_detalles(comercio_id,pedido_id,producto_id,producto_nombre,cantidad,precio_unitario,costo_unitario,subtotal,variante_id,lista_precio_item_id)
  values(v_comercio,v_pedido,v_producto.id,v_producto.nombre||case when v_variante.id is not null then ' · '||v_variante.nombre else '' end,v_qty,v_price,v_producto.costo_unitario+coalesce(v_variante.costo_adicional,0),v_subtotal,v_variante.id,v_list_item);
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

revoke all on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid) from public,anon;
grant execute on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid) to authenticated;
revoke all on function public.registrar_compra_en_deposito(uuid,uuid,jsonb) from public,anon;
grant execute on function public.registrar_compra_en_deposito(uuid,uuid,jsonb) to authenticated;
revoke all on function public.registrar_presupuesto(uuid,jsonb,uuid) from public,anon;
grant execute on function public.registrar_presupuesto(uuid,jsonb,uuid) to authenticated;
