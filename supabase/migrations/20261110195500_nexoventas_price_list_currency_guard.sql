-- Apply price lists only when denominated in ARS until multi-currency support is implemented.
do $$
declare r record; d text;
begin
 for r in
  select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and ((p.proname='registrar_venta_en_deposito' and pg_get_function_identity_arguments(p.oid) like '%p_lista_precio_id uuid') or (p.proname='registrar_presupuesto' and pg_get_function_identity_arguments(p.oid) like '%p_lista_precio_id uuid'))
 loop
  d:=pg_get_functiondef(r.oid);
  d:=replace(d,'and l.comercio_id=v_comercio and l.activa) then raise exception','and l.comercio_id=v_comercio and l.activa and l.moneda=''ARS'') then raise exception');
  d:=replace(d,'and l.activa and l.es_predeterminada order by','and l.activa and l.moneda=''ARS'' and l.es_predeterminada order by');
  execute d;
 end loop;
end $$;