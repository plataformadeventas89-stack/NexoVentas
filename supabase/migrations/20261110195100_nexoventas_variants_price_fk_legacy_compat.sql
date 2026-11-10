-- Keep existing RPC signatures working while routing to the variant-aware implementations.
alter table public.pedido_detalles drop constraint if exists pedido_detalles_comercio_variante_fk;
alter table public.pedido_detalles add constraint pedido_detalles_comercio_variante_fk foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict;
alter table public.presupuesto_detalles drop constraint if exists presupuesto_detalles_comercio_variante_fk;
alter table public.presupuesto_detalles add constraint presupuesto_detalles_comercio_variante_fk foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict;
alter table public.compra_detalles drop constraint if exists compra_detalles_comercio_variante_fk;
alter table public.compra_detalles add constraint compra_detalles_comercio_variante_fk foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict;
alter table public.pedidos drop constraint if exists pedidos_comercio_lista_precio_fk;
alter table public.pedidos add constraint pedidos_comercio_lista_precio_fk foreign key(comercio_id,lista_precio_id) references public.listas_precios(comercio_id,id) on delete restrict;
alter table public.presupuestos drop constraint if exists presupuestos_comercio_lista_precio_fk;
alter table public.presupuestos add constraint presupuestos_comercio_lista_precio_fk foreign key(comercio_id,lista_precio_id) references public.listas_precios(comercio_id,id) on delete restrict;
create unique index if not exists lista_precios_items_unique_tier_idx on public.lista_precios_items(comercio_id,lista_precio_id,producto_id,(coalesce(variante_id,'00000000-0000-0000-0000-000000000000'::uuid)),cantidad_minima);
CREATE OR REPLACE FUNCTION public.registrar_presupuesto(p_cliente_id uuid, p_items jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select public.registrar_presupuesto(p_cliente_id,p_items,null::uuid);
$function$


CREATE OR REPLACE FUNCTION public.registrar_venta_en_deposito(p_cliente_id uuid, p_deposito_id uuid, p_items jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select public.registrar_venta_en_deposito(p_cliente_id,p_deposito_id,p_items,null::uuid);
$function$

revoke all on function public.registrar_venta_en_deposito(uuid,uuid,jsonb) from public,anon;
grant execute on function public.registrar_venta_en_deposito(uuid,uuid,jsonb) to authenticated;
revoke all on function public.registrar_presupuesto(uuid,jsonb) from public,anon;
grant execute on function public.registrar_presupuesto(uuid,jsonb) to authenticated;
