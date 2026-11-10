-- NexoVentas: permisos de administrador y vendedor.
-- Los helpers consultan el perfil del usuario autenticado y no confían en metadata editable del JWT.

create or replace function private.current_user_role()
returns text language sql stable security definer set search_path = ''
as $$
  select u.rol from public.usuarios u where u.id = (select auth.uid()) limit 1;
$$;

create or replace function private.is_commerce_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((select u.rol = 'admin' from public.usuarios u where u.id = (select auth.uid()) limit 1), false);
$$;

grant usage on schema private to authenticated;
grant execute on function private.current_user_role() to authenticated;
grant execute on function private.is_commerce_admin() to authenticated;

-- Las políticas antiguas tenant-wide ALL se reemplazan por SELECT para vendedores y escrituras admin.
do $$
declare t text;
begin
  foreach t in array array[
    'productos','stock','clientes','pedidos','pedido_detalles','presupuestos','presupuesto_detalles',
    'proveedores','compras','compra_detalles','caja_movimientos','comercio_rubros','sucursales','depositos',
    'categorias_comercio','producto_variantes','listas_precios','lista_precios_items','inventario_saldos',
    'inventario_movimientos','servicios','servicio_turnos','servicio_solicitudes',
    'inventario_transferencias','inventario_transferencia_detalles','usuarios','comercios'
  ] loop
    if to_regclass('public.'||t) is not null then
      execute format('alter table public.%I enable row level security',t);
      execute format('drop policy if exists %I on public.%I','Acceso a productos del comercio',t);
      execute format('drop policy if exists %I on public.%I','Acceso a clientes del comercio',t);
      execute format('drop policy if exists %I on public.%I','Acceso a stock del comercio',t);
      execute format('drop policy if exists %I on public.%I','Acceso a pedidos del comercio',t);
      execute format('drop policy if exists %I on public.%I','Acceso a detalles de ventas del comercio',t);
      execute format('drop policy if exists %I on public.%I','Acceso a presupuestos del comercio',t);
      execute format('drop policy if exists %I on public.%I','Acceso a detalles de presupuestos del comercio',t);
      execute format('drop policy if exists %I on public.%I','Comercio gestiona proveedores',t);
      execute format('drop policy if exists %I on public.%I','Comercio gestiona compras',t);
      execute format('drop policy if exists %I on public.%I','Comercio gestiona detalle compras',t);
      execute format('drop policy if exists %I on public.%I','Comercio gestiona caja',t);
      execute format('drop policy if exists %I on public.%I','comercio_rubros_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','sucursales_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','depositos_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','categorias_comercio_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','producto_variantes_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','listas_precios_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','lista_precios_items_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','inventario_saldos_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','inventario_movimientos_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','servicios_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','servicio_turnos_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','servicio_solicitudes_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','inventario_transferencias_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','inventario_transferencia_detalles_tenant_all',t);
      execute format('drop policy if exists %I on public.%I','Usuarios ven su perfil',t);
      execute format('drop policy if exists %I on public.%I','Usuario crea su perfil',t);
      execute format('drop policy if exists %I on public.%I','Usuarios ven su comercio',t);
    end if;
  end loop;
end $$;

create policy clientes_tenant_all on public.clientes for all to authenticated
using (comercio_id = (select private.current_user_commerce_id()))
with check (comercio_id = (select private.current_user_commerce_id()));

create policy productos_tenant_select on public.productos for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy productos_admin_insert on public.productos for insert to authenticated
with check (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));
create policy productos_admin_update on public.productos for update to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()))
with check (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));
create policy productos_admin_delete on public.productos for delete to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));

create policy stock_tenant_select on public.stock for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy stock_admin_insert on public.stock for insert to authenticated
with check (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));
create policy stock_admin_update on public.stock for update to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()))
with check (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));
create policy stock_admin_delete on public.stock for delete to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));

create policy pedidos_tenant_read on public.pedidos for select to authenticated
using (comercio_id = (select private.current_user_commerce_id())
  and ((select private.is_commerce_admin()) or vendedor_id = (select auth.uid())));
create policy pedido_detalles_read on public.pedido_detalles for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and exists (
  select 1 from public.pedidos p where p.id = pedido_id
  and ((select private.is_commerce_admin()) or p.vendedor_id = (select auth.uid()))
));
create policy presupuestos_tenant_read on public.presupuestos for select to authenticated
using (comercio_id = (select private.current_user_commerce_id())
  and ((select private.is_commerce_admin()) or vendedor_id = (select auth.uid())));
create policy presupuesto_detalles_read on public.presupuesto_detalles for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and exists (
  select 1 from public.presupuestos p where p.id = presupuesto_id
  and ((select private.is_commerce_admin()) or p.vendedor_id = (select auth.uid()))
));

create policy sucursales_tenant_read on public.sucursales for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy depositos_tenant_read on public.depositos for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy categorias_tenant_read on public.categorias_comercio for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy variantes_tenant_read on public.producto_variantes for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy listas_tenant_read on public.listas_precios for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy lista_items_tenant_read on public.lista_precios_items for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy inventory_balances_tenant_read on public.inventario_saldos for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));
create policy inventory_moves_tenant_read on public.inventario_movimientos for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()));

create policy comercio_rubros_admin_all on public.comercio_rubros for all to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()))
with check (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));

do $$
declare t text;
begin
  foreach t in array array['proveedores','compras','compra_detalles','caja_movimientos',
    'inventario_transferencias','inventario_transferencia_detalles','servicios','servicio_turnos','servicio_solicitudes',
    'sucursales','depositos','categorias_comercio','producto_variantes','listas_precios','lista_precios_items',
    'inventario_saldos','inventario_movimientos'] loop
    execute format('create policy %I on public.%I for all to authenticated using (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin())) with check (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()))', t||'_admin_all');
  end loop;
end $$;

create policy inventario_transferencias_seller_read on public.inventario_transferencias for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and usuario_id = (select auth.uid()));
create policy inventario_transferencia_detalles_seller_read on public.inventario_transferencia_detalles for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and exists (
  select 1 from public.inventario_transferencias t where t.id = transferencia_id and t.usuario_id = (select auth.uid())
));

create policy comercios_tenant_read on public.comercios for select to authenticated
using (id = (select private.current_user_commerce_id()));
create policy comercios_admin_update on public.comercios for update to authenticated
using (id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()))
with check (id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));

create policy usuarios_self_read on public.usuarios for select to authenticated
using (id = (select auth.uid()));
create policy usuarios_admin_read on public.usuarios for select to authenticated
using (comercio_id = (select private.current_user_commerce_id()) and (select private.is_commerce_admin()));
create policy usuarios_register_admin on public.usuarios for insert to authenticated
with check (id = (select auth.uid()) and rol = 'admin'
  and comercio_id in (select c.id from public.comercios c where c.email = ((select auth.jwt())->>'email')));

create or replace function private.guard_client_commercial_fields()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_role text;
begin
  select u.rol into v_role from public.usuarios u where u.id = (select auth.uid());
  if v_role = 'vendedor' then
    if tg_op = 'INSERT' then
      if new.segmento is distinct from 'minorista' or new.lista_precio_id is not null then
        raise exception 'Solo un administrador puede asignar segmentos o listas de precios a clientes';
      end if;
    elsif new.segmento is distinct from old.segmento or new.lista_precio_id is distinct from old.lista_precio_id then
      raise exception 'Solo un administrador puede cambiar el segmento o la lista de precios del cliente';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_client_commercial_fields on public.clientes;
create trigger guard_client_commercial_fields before insert or update on public.clientes
for each row execute function private.guard_client_commercial_fields();

create or replace function public.admin_cambiar_rol_usuario(p_usuario_id uuid, p_rol text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_comercio uuid; v_target_role text; v_admin_count integer;
begin
  if auth.uid() is null or not private.is_commerce_admin() then
    raise exception 'Solo un administrador puede gestionar los roles';
  end if;
  if p_rol not in ('admin','vendedor') then raise exception 'Rol inválido'; end if;
  select comercio_id into v_comercio from public.usuarios where id = auth.uid();
  select rol into v_target_role from public.usuarios where id = p_usuario_id and comercio_id = v_comercio for update;
  if not found then raise exception 'El usuario no pertenece a este comercio'; end if;
  if p_rol = 'vendedor' and v_target_role = 'admin' then
    select count(*) into v_admin_count from public.usuarios where comercio_id = v_comercio and rol = 'admin';
    if v_admin_count <= 1 then raise exception 'El comercio debe conservar al menos un administrador'; end if;
  end if;
  update public.usuarios set rol = p_rol where id = p_usuario_id and comercio_id = v_comercio;
end $$;
revoke all on function public.admin_cambiar_rol_usuario(uuid,text) from public, anon;
grant execute on function public.admin_cambiar_rol_usuario(uuid,text) to authenticated;

alter function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid,uuid) security definer;
alter function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid,uuid) set search_path = '';
revoke all on function public.registrar_venta_en_deposito(uuid,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid) from public, anon, authenticated;
revoke all on function public.registrar_venta(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid,uuid) from public, anon;
grant execute on function public.registrar_venta_en_deposito(uuid,uuid,jsonb,uuid,uuid) to authenticated;

alter function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) security definer;
alter function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) set search_path = '';
revoke all on function public.registrar_presupuesto(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.registrar_presupuesto(uuid,jsonb,uuid) from public, anon, authenticated;
revoke all on function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) from public, anon;
grant execute on function public.registrar_presupuesto(uuid,jsonb,uuid,uuid) to authenticated;
