
-- NexoVentas: auditable warehouse transfers and inventory adjustments.
create table if not exists public.inventario_transferencias (
 id uuid primary key default gen_random_uuid(),
 comercio_id uuid not null references public.comercios(id) on delete cascade,
 deposito_origen_id uuid not null,
 deposito_destino_id uuid not null,
 estado text not null default 'completada' check (estado='completada'),
 motivo text not null,
 usuario_id uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 constraint inventario_transferencias_distintos_depositos check (deposito_origen_id<>deposito_destino_id),
 constraint inventario_transferencias_origen_fk foreign key(comercio_id,deposito_origen_id) references public.depositos(comercio_id,id) on delete restrict,
 constraint inventario_transferencias_destino_fk foreign key(comercio_id,deposito_destino_id) references public.depositos(comercio_id,id) on delete restrict,
 unique(comercio_id,id)
);
create table if not exists public.inventario_transferencia_detalles (
 id uuid primary key default gen_random_uuid(),
 comercio_id uuid not null,
 transferencia_id uuid not null,
 producto_id uuid not null,
 variante_id uuid,
 cantidad numeric(14,3) not null check(cantidad>0),
 created_at timestamptz not null default now(),
 constraint inv_transfer_det_transfer_fk foreign key(comercio_id,transferencia_id) references public.inventario_transferencias(comercio_id,id) on delete cascade,
 constraint inv_transfer_det_product_fk foreign key(comercio_id,producto_id) references public.productos(comercio_id,id) on delete restrict,
 constraint inv_transfer_det_variant_fk foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict
);
create index if not exists inventario_transferencias_comercio_fecha_idx on public.inventario_transferencias(comercio_id,created_at desc);
create index if not exists inventario_transferencias_origen_idx on public.inventario_transferencias(comercio_id,deposito_origen_id);
create index if not exists inventario_transferencias_destino_idx on public.inventario_transferencias(comercio_id,deposito_destino_id);
create index if not exists inventario_transferencia_detalles_transferencia_idx on public.inventario_transferencia_detalles(comercio_id,transferencia_id);
alter table public.inventario_transferencias enable row level security;
alter table public.inventario_transferencia_detalles enable row level security;
drop policy if exists inventario_transferencias_tenant_all on public.inventario_transferencias;
create policy inventario_transferencias_tenant_all on public.inventario_transferencias for all to authenticated
 using (comercio_id=(select private.current_user_commerce_id()))
 with check (comercio_id=(select private.current_user_commerce_id()));
drop policy if exists inventario_transferencia_detalles_tenant_all on public.inventario_transferencia_detalles;
create policy inventario_transferencia_detalles_tenant_all on public.inventario_transferencia_detalles for all to authenticated
 using (comercio_id=(select private.current_user_commerce_id()))
 with check (comercio_id=(select private.current_user_commerce_id()));
grant select,insert,update,delete on public.inventario_transferencias,public.inventario_transferencia_detalles to authenticated;

create or replace function public.registrar_transferencia_inventario(
 p_deposito_origen_id uuid,p_deposito_destino_id uuid,p_motivo text,p_items jsonb
) returns uuid language plpgsql security invoker set search_path=''
as $function$
declare
 v_user uuid:=auth.uid(); v_comercio uuid; v_transferencia uuid;
 v_item record; v_producto public.productos%rowtype; v_variante public.producto_variantes%rowtype;
 v_saldo public.inventario_saldos%rowtype; v_origen public.inventario_saldos%rowtype; v_destino public.inventario_saldos%rowtype;
 v_origen_sucursal uuid; v_destino_sucursal uuid;
begin
 if v_user is null then raise exception 'Debes iniciar sesión'; end if;
 select u.comercio_id into v_comercio from public.usuarios u where u.id=v_user;
 if v_comercio is null then raise exception 'El usuario no tiene un comercio asociado'; end if;
 if p_deposito_origen_id is null or p_deposito_destino_id is null or p_deposito_origen_id=p_deposito_destino_id then raise exception 'Seleccioná dos depósitos diferentes'; end if;
 select d.sucursal_id into v_origen_sucursal from public.depositos d where d.id=p_deposito_origen_id and d.comercio_id=v_comercio and d.activo for update;
 if v_origen_sucursal is null then raise exception 'El depósito de origen no es válido o está inactivo'; end if;
 select d.sucursal_id into v_destino_sucursal from public.depositos d where d.id=p_deposito_destino_id and d.comercio_id=v_comercio and d.activo for update;
 if v_destino_sucursal is null then raise exception 'El depósito de destino no es válido o está inactivo'; end if;
 if coalesce(length(trim(p_motivo)),0)<3 then raise exception 'Indicá un motivo para la transferencia'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Agregá al menos un producto a transferir'; end if;
 for v_item in
  select x.producto_id,x.variante_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,variante_id uuid,cantidad numeric)
  group by x.producto_id,x.variante_id order by x.producto_id,x.variante_id nulls first
 loop
  if v_item.producto_id is null or v_item.cantidad is null or v_item.cantidad<=0 then raise exception 'Producto o cantidad inválida'; end if;
  select * into v_producto from public.productos p where p.id=v_item.producto_id and p.comercio_id=v_comercio and p.activo for update;
  if not found then raise exception 'Hay un producto inválido o inactivo'; end if;
  if v_item.variante_id is not null then
   select * into v_variante from public.producto_variantes pv where pv.id=v_item.variante_id and pv.comercio_id=v_comercio and pv.producto_id=v_item.producto_id and pv.activa;
   if not found then raise exception 'La variante no pertenece al producto o está inactiva'; end if;
  end if;
  insert into public.inventario_saldos(comercio_id,deposito_id,producto_id,variante_id,cantidad)
   values(v_comercio,p_deposito_origen_id,v_item.producto_id,v_item.variante_id,0),(v_comercio,p_deposito_destino_id,v_item.producto_id,v_item.variante_id,0)
   on conflict (comercio_id,deposito_id,producto_id,variante_id) do nothing;
  v_origen:=null; v_destino:=null;
  for v_saldo in
   select i.* from public.inventario_saldos i where i.comercio_id=v_comercio and i.producto_id=v_item.producto_id
    and i.variante_id is not distinct from v_item.variante_id and i.deposito_id in (p_deposito_origen_id,p_deposito_destino_id)
   order by i.deposito_id for update
  loop
   if v_saldo.deposito_id=p_deposito_origen_id then v_origen:=v_saldo; else v_destino:=v_saldo; end if;
  end loop;
  if v_origen.cantidad-v_origen.cantidad_reservada<v_item.cantidad then
   raise exception 'Stock insuficiente en origen para % (disponible: %)',v_producto.nombre,v_origen.cantidad-v_origen.cantidad_reservada;
  end if;
 end loop;
 insert into public.inventario_transferencias(comercio_id,deposito_origen_id,deposito_destino_id,motivo,usuario_id)
 values(v_comercio,p_deposito_origen_id,p_deposito_destino_id,trim(p_motivo),v_user) returning id into v_transferencia;
 for v_item in
  select x.producto_id,x.variante_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,variante_id uuid,cantidad numeric)
  group by x.producto_id,x.variante_id order by x.producto_id,x.variante_id nulls first
 loop
  update public.inventario_saldos set cantidad=cantidad-v_item.cantidad,updated_at=now()
   where comercio_id=v_comercio and deposito_id=p_deposito_origen_id and producto_id=v_item.producto_id and variante_id is not distinct from v_item.variante_id;
  update public.inventario_saldos set cantidad=cantidad+v_item.cantidad,updated_at=now()
   where comercio_id=v_comercio and deposito_id=p_deposito_destino_id and producto_id=v_item.producto_id and variante_id is not distinct from v_item.variante_id;
  insert into public.inventario_transferencia_detalles(comercio_id,transferencia_id,producto_id,variante_id,cantidad)
   values(v_comercio,v_transferencia,v_item.producto_id,v_item.variante_id,v_item.cantidad);
  insert into public.inventario_movimientos(comercio_id,tipo,deposito_origen_id,producto_id,variante_id,cantidad,referencia_tipo,referencia_id,motivo,usuario_id)
   values(v_comercio,'transferencia_salida',p_deposito_origen_id,v_item.producto_id,v_item.variante_id,v_item.cantidad,'transferencia',v_transferencia,trim(p_motivo),v_user);
  insert into public.inventario_movimientos(comercio_id,tipo,deposito_destino_id,producto_id,variante_id,cantidad,referencia_tipo,referencia_id,motivo,usuario_id)
   values(v_comercio,'transferencia_entrada',p_deposito_destino_id,v_item.producto_id,v_item.variante_id,v_item.cantidad,'transferencia',v_transferencia,trim(p_motivo),v_user);
 end loop;
 return v_transferencia;
end;
$function$;

create or replace function public.registrar_ajuste_inventario(
 p_deposito_id uuid,p_producto_id uuid,p_variante_id uuid,p_cantidad_objetivo numeric,p_motivo text
) returns uuid language plpgsql security invoker set search_path=''
as $function$
declare
 v_user uuid:=auth.uid(); v_comercio uuid; v_producto public.productos%rowtype; v_variante public.producto_variantes%rowtype;
 v_saldo public.inventario_saldos%rowtype; v_stock public.stock%rowtype; v_delta numeric(14,3); v_mov uuid;
begin
 if v_user is null then raise exception 'Debes iniciar sesión'; end if;
 select u.comercio_id into v_comercio from public.usuarios u where u.id=v_user;
 if v_comercio is null then raise exception 'El usuario no tiene un comercio asociado'; end if;
 if p_cantidad_objetivo is null or p_cantidad_objetivo<0 then raise exception 'La cantidad final debe ser cero o mayor'; end if;
 if coalesce(length(trim(p_motivo)),0)<3 then raise exception 'Indicá un motivo para el ajuste'; end if;
 if not exists(select 1 from public.depositos d where d.id=p_deposito_id and d.comercio_id=v_comercio and d.activo) then raise exception 'Seleccioná un depósito activo de tu comercio'; end if;
 select * into v_producto from public.productos p where p.id=p_producto_id and p.comercio_id=v_comercio and p.activo for update;
 if not found then raise exception 'El producto no existe o está inactivo'; end if;
 if p_variante_id is not null then
  select * into v_variante from public.producto_variantes pv where pv.id=p_variante_id and pv.comercio_id=v_comercio and pv.producto_id=p_producto_id and pv.activa;
  if not found then raise exception 'La variante no pertenece al producto o está inactiva'; end if;
 end if;
 insert into public.inventario_saldos(comercio_id,deposito_id,producto_id,variante_id,cantidad) values(v_comercio,p_deposito_id,p_producto_id,p_variante_id,0)
 on conflict(comercio_id,deposito_id,producto_id,variante_id) do nothing;
 select * into v_saldo from public.inventario_saldos i where i.comercio_id=v_comercio and i.deposito_id=p_deposito_id and i.producto_id=p_producto_id and i.variante_id is not distinct from p_variante_id for update;
 v_delta:=p_cantidad_objetivo-v_saldo.cantidad;
 if v_delta=0 then raise exception 'La cantidad ingresada coincide con el saldo actual'; end if;
 if v_delta<0 and p_cantidad_objetivo<v_saldo.cantidad_reservada then raise exception 'No podés dejar el saldo por debajo de las unidades reservadas (%)',v_saldo.cantidad_reservada; end if;
 select * into v_stock from public.stock s where s.comercio_id=v_comercio and s.producto_id=p_producto_id for update;
 if not found then raise exception 'No existe el stock total del producto'; end if;
 if v_stock.cantidad+v_delta<0 then raise exception 'El ajuste dejaría el stock total en negativo'; end if;
 update public.inventario_saldos set cantidad=p_cantidad_objetivo,updated_at=now() where id=v_saldo.id;
 update public.stock set cantidad=cantidad+v_delta,updated_at=now() where comercio_id=v_comercio and producto_id=p_producto_id;
 insert into public.inventario_movimientos(comercio_id,tipo,deposito_origen_id,deposito_destino_id,producto_id,variante_id,cantidad,referencia_tipo,motivo,usuario_id)
 values(v_comercio,'ajuste',case when v_delta<0 then p_deposito_id else null end,case when v_delta>0 then p_deposito_id else null end,p_producto_id,p_variante_id,abs(v_delta),'ajuste',trim(p_motivo),v_user)
 returning id into v_mov;
 return v_mov;
end;
$function$;
revoke all on function public.registrar_transferencia_inventario(uuid,uuid,text,jsonb) from public,anon;
revoke all on function public.registrar_ajuste_inventario(uuid,uuid,uuid,numeric,text) from public,anon;
grant execute on function public.registrar_transferencia_inventario(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.registrar_ajuste_inventario(uuid,uuid,uuid,numeric,text) to authenticated;

create index if not exists inventario_transferencia_detalles_producto_idx on public.inventario_transferencia_detalles(comercio_id,producto_id);
create index if not exists inventario_transferencia_detalles_variante_idx on public.inventario_transferencia_detalles(comercio_id,variante_id);
create index if not exists inventario_transferencias_usuario_idx on public.inventario_transferencias(usuario_id);
