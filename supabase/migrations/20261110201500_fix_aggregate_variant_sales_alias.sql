do $$
declare v_oid oid; v_definition text; v_bad text := 'from jsonb_to_recordset(p_items) as x(product_id uuid,cantidad numeric)'; v_good text := 'from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad numeric)';
begin
 select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='registrar_venta_en_deposito'
 and pg_get_function_identity_arguments(p.oid) like '%p_lista_precio_id uuid';
 if v_oid is null then raise exception 'No se encontró la función de venta'; end if;
 v_definition:=pg_get_functiondef(v_oid);
 if position(v_bad in v_definition)>0 then
  v_definition:=replace(v_definition,v_bad,v_good);
  execute v_definition;
 end if;
end $$;