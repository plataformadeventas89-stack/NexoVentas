-- Prevent combined variant lines from overselling the product-level stock total.
do $$
declare
  v_oid oid;
  v_definition text;
  v_marker text := ' for v_group in
  select x.producto_id,x.variante_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,variante_id uuid,cantidad numeric)
  group by x.producto_id,x.variante_id order by x.producto_id,x.variante_id nulls first
 loop';
  v_insert text := ' for v_group in
  select x.producto_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(product_id uuid,cantidad numeric)
  group by x.producto_id order by x.producto_id
 loop
  if v_group.product_id is null or v_group.cantidad is null or v_group.cantidad<=0 then
   raise exception ''Hay productos o cantidades inválidas'';
  end if;
  select * into v_stock from public.stock s where s.comercio_id=v_comercio and s.producto_id=v_group.product_id for update;
  if not found then raise exception ''No existe el stock general del producto''; end if;
  if v_stock.cantidad<v_group.cantidad then
   raise exception ''La cantidad total solicitada supera el stock general del producto'';
  end if;
 end loop;

 for v_group in
  select x.producto_id,x.variante_id,sum(x.cantidad)::numeric(14,3) cantidad
  from jsonb_to_recordset(p_items) as x(producto_id uuid,variante_id uuid,cantidad numeric)
  group by x.producto_id,x.variante_id order by x.producto_id,x.variante_id nulls first
 loop';
begin
 select p.oid into v_oid
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='registrar_venta_en_deposito'
   and pg_get_function_identity_arguments(p.oid) like '%p_lista_precio_id uuid';
 if v_oid is null then raise exception 'No se encontró la función de venta con lista de precios'; end if;
 v_definition:=pg_get_functiondef(v_oid);
 if position(v_insert in v_definition)=0 then
  if position(v_marker in v_definition)=0 then raise exception 'No se encontró el bloque de validación de stock esperado'; end if;
  v_definition:=replace(v_definition,v_marker,v_insert);
  execute v_definition;
 end if;
end $$;