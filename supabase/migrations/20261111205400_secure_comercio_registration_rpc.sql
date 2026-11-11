create or replace function public.registrar_comercio(p_nombre text, p_nombre_usuario text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_usuario uuid := auth.uid();
  v_comercio uuid;
  v_email text;
begin
  if v_usuario is null then
    raise exception 'Debes iniciar sesión';
  end if;

  if nullif(trim(p_nombre), '') is null then
    raise exception 'El nombre del comercio es obligatorio';
  end if;

  if nullif(trim(p_nombre_usuario), '') is null then
    raise exception 'El nombre del usuario es obligatorio';
  end if;

  select u.email
    into v_email
    from auth.users as u
   where u.id = v_usuario;

  if v_email is null then
    raise exception 'No se pudo validar el correo de la cuenta';
  end if;

  if exists (
    select 1
      from public.usuarios as u
     where u.id = v_usuario
  ) then
    raise exception 'El usuario ya tiene un comercio registrado';
  end if;

  insert into public.comercios(nombre, email)
  values (trim(p_nombre), v_email)
  returning id into v_comercio;

  insert into public.usuarios(id, comercio_id, nombre, rol)
  values (v_usuario, v_comercio, trim(p_nombre_usuario), 'admin');

  return v_comercio;
end;
$function$;

revoke all on function public.registrar_comercio(text, text) from public, anon;
grant execute on function public.registrar_comercio(text, text) to authenticated;
