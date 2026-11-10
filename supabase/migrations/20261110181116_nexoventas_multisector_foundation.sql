-- NexoVentas multisector foundation. Additive migration: preserves legacy sales, purchases and stock.
create unique index if not exists clientes_comercio_id_uidx on public.clientes(comercio_id,id);

create table if not exists public.rubros (
 id uuid primary key default gen_random_uuid(),
 parent_id uuid references public.rubros(id) on delete restrict,
 slug text not null unique, nombre text not null, descripcion text,
 activo boolean not null default true, orden integer not null default 0,
 created_at timestamptz not null default now()
);
insert into public.rubros(slug,nombre,orden) values
('construccion','Construcción y corralones',10),('electricidad','Electricidad e iluminación',20),
('ferreteria','Ferretería y herramientas',30),('sanitarios','Sanitarios y plomería',40),
('pintureria','Pinturería',50),('hogar','Hogar y muebles',60),('automotor','Automotor y repuestos',70),
('indumentaria','Indumentaria y calzado',80),('alimentos','Alimentos y bebidas',90),
('tecnologia','Tecnología y electrónica',100),('salud-belleza','Salud y belleza',110),
('agro','Agro y jardinería',120),('oficina','Librería y oficina',130),
('servicios-profesionales','Servicios profesionales',140),('servicios-tecnicos','Servicios técnicos y mantenimiento',150),
('gastronomia','Gastronomía',160),('otros','Otros rubros',999)
on conflict(slug) do update set nombre=excluded.nombre,orden=excluded.orden;

create table if not exists public.unidades_medida (
 id uuid primary key default gen_random_uuid(), codigo text not null unique, nombre text not null,
 simbolo text not null, tipo text not null default 'unidad'
 check(tipo in ('unidad','longitud','superficie','volumen','peso','paquete','otro')),
 permite_decimales boolean not null default false, activo boolean not null default true, orden integer not null default 0
);
insert into public.unidades_medida(codigo,nombre,simbolo,tipo,permite_decimales,orden) values
('un','Unidad','un','unidad',false,10),('m','Metro','m','longitud',true,20),('cm','Centímetro','cm','longitud',true,30),
('m2','Metro cuadrado','m²','superficie',true,40),('m3','Metro cúbico','m³','volumen',true,50),
('kg','Kilogramo','kg','peso',true,60),('g','Gramo','g','peso',true,70),('tn','Tonelada','tn','peso',true,80),
('l','Litro','l','volumen',true,90),('ml','Mililitro','ml','volumen',true,100),('caja','Caja','caja','paquete',false,110),
('bolsa','Bolsa','bolsa','paquete',false,120),('rollo','Rollo','rollo','paquete',false,130),
('pallet','Pallet','pallet','paquete',false,140),('par','Par','par','paquete',false,150),
('hora','Hora','h','otro',true,160),('servicio','Servicio','serv.','otro',false,170)
on conflict(codigo) do update set nombre=excluded.nombre,simbolo=excluded.simbolo,tipo=excluded.tipo;

create table if not exists public.comercio_rubros (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 rubro_id uuid not null references public.rubros(id) on delete restrict, es_principal boolean not null default false,
 created_at timestamptz not null default now(), unique(comercio_id,rubro_id)
);
create unique index if not exists comercio_un_rubro_principal_idx on public.comercio_rubros(comercio_id) where es_principal;

create table if not exists public.sucursales (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 nombre text not null, codigo text, direccion text, localidad text, provincia text, codigo_postal text,
 telefono text, email text, es_principal boolean not null default false, activa boolean not null default true,
 created_at timestamptz not null default now(), unique(comercio_id,id), unique(comercio_id,codigo)
);
create unique index if not exists sucursal_principal_por_comercio_idx on public.sucursales(comercio_id) where es_principal;

create table if not exists public.depositos (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 sucursal_id uuid not null, nombre text not null, codigo text,
 tipo text not null default 'general' check(tipo in ('general','venta','reserva','transito','devoluciones')),
 es_principal boolean not null default false, activo boolean not null default true, created_at timestamptz not null default now(),
 unique(comercio_id,id), unique(comercio_id,sucursal_id,codigo),
 foreign key(comercio_id,sucursal_id) references public.sucursales(comercio_id,id) on delete restrict
);
create unique index if not exists deposito_principal_por_sucursal_idx on public.depositos(comercio_id,sucursal_id) where es_principal;

create table if not exists public.categorias_comercio (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 rubro_id uuid references public.rubros(id) on delete restrict, parent_id uuid references public.categorias_comercio(id) on delete restrict,
 nombre text not null, descripcion text, activa boolean not null default true, created_at timestamptz not null default now(),
 unique(comercio_id,id), unique(comercio_id,nombre)
);

alter table public.productos
 add column if not exists sku text, add column if not exists codigo_barras text, add column if not exists marca text,
 add column if not exists unidad_medida_id uuid references public.unidades_medida(id),
 add column if not exists categoria_comercio_id uuid, add column if not exists atributos jsonb not null default '{}'::jsonb,
 add column if not exists imagen_url text, add column if not exists publicado_online boolean not null default false,
 add column if not exists peso_kg numeric(12,3), add column if not exists largo_cm numeric(12,2),
 add column if not exists ancho_cm numeric(12,2), add column if not exists alto_cm numeric(12,2),
 add column if not exists stock_minimo numeric(14,3) not null default 0,
 add column if not exists permite_venta_fraccionada boolean not null default false;
create unique index if not exists productos_comercio_sku_uidx on public.productos(comercio_id,sku) where sku is not null and sku<>'';
create unique index if not exists productos_comercio_barcode_uidx on public.productos(comercio_id,codigo_barras) where codigo_barras is not null and codigo_barras<>'';
create unique index if not exists productos_comercio_id_uidx on public.productos(comercio_id,id);
alter table public.productos drop constraint if exists productos_categoria_comercio_fk;
alter table public.productos add constraint productos_categoria_comercio_fk
 foreign key(comercio_id,categoria_comercio_id) references public.categorias_comercio(comercio_id,id) on delete restrict;

create table if not exists public.producto_variantes (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 producto_id uuid not null, sku text, codigo_barras text, nombre text not null, atributos jsonb not null default '{}'::jsonb,
 precio_adicional numeric(14,2) not null default 0, costo_adicional numeric(14,2) not null default 0,
 activa boolean not null default true, created_at timestamptz not null default now(), unique(comercio_id,id),
 foreign key(comercio_id,producto_id) references public.productos(comercio_id,id) on delete cascade
);
create unique index if not exists variantes_comercio_sku_uidx on public.producto_variantes(comercio_id,sku) where sku is not null and sku<>'';
create unique index if not exists variantes_comercio_barcode_uidx on public.producto_variantes(comercio_id,codigo_barras) where codigo_barras is not null and codigo_barras<>'';

create table if not exists public.listas_precios (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 nombre text not null, descripcion text, tipo text not null default 'personalizada'
 check(tipo in ('minorista','mayorista','distribuidor','especial','personalizada')),
 moneda text not null default 'ARS', es_predeterminada boolean not null default false,
 activa boolean not null default true, created_at timestamptz not null default now(),
 unique(comercio_id,id), unique(comercio_id,nombre)
);
create unique index if not exists lista_precios_predeterminada_idx on public.listas_precios(comercio_id) where es_predeterminada;

create table if not exists public.lista_precios_items (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 lista_precio_id uuid not null, producto_id uuid not null, variante_id uuid,
 cantidad_minima numeric(14,3) not null default 1 check(cantidad_minima>0), precio numeric(14,2) not null check(precio>=0),
 created_at timestamptz not null default now(),
 foreign key(comercio_id,lista_precio_id) references public.listas_precios(comercio_id,id) on delete cascade,
 foreign key(comercio_id,producto_id) references public.productos(comercio_id,id) on delete cascade,
 foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete cascade
);
create unique index if not exists lista_precio_item_producto_idx on public.lista_precios_items(lista_precio_id,producto_id,cantidad_minima) where variante_id is null;
create unique index if not exists lista_precio_item_variante_idx on public.lista_precios_items(lista_precio_id,variante_id,cantidad_minima) where variante_id is not null;

create table if not exists public.inventario_saldos (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 deposito_id uuid not null, producto_id uuid not null, variante_id uuid,
 cantidad numeric(14,3) not null default 0, cantidad_reservada numeric(14,3) not null default 0,
 updated_at timestamptz not null default now(),
 unique nulls not distinct(comercio_id,deposito_id,producto_id,variante_id),
 foreign key(comercio_id,deposito_id) references public.depositos(comercio_id,id) on delete restrict,
 foreign key(comercio_id,producto_id) references public.productos(comercio_id,id) on delete restrict,
 foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict,
 check(cantidad_reservada>=0 and cantidad_reservada<=cantidad)
);
create table if not exists public.inventario_movimientos (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 tipo text not null check(tipo in ('apertura','entrada','salida','transferencia_entrada','transferencia_salida','ajuste')),
 deposito_origen_id uuid, deposito_destino_id uuid, producto_id uuid not null, variante_id uuid,
 cantidad numeric(14,3) not null check(cantidad>0), referencia_tipo text, referencia_id uuid, motivo text,
 usuario_id uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(),
 foreign key(comercio_id,deposito_origen_id) references public.depositos(comercio_id,id) on delete restrict,
 foreign key(comercio_id,deposito_destino_id) references public.depositos(comercio_id,id) on delete restrict,
 foreign key(comercio_id,producto_id) references public.productos(comercio_id,id) on delete restrict,
 foreign key(comercio_id,variante_id) references public.producto_variantes(comercio_id,id) on delete restrict,
 check(deposito_origen_id is not null or deposito_destino_id is not null)
);
create index if not exists inventario_saldos_producto_idx on public.inventario_saldos(comercio_id,producto_id);
create index if not exists inventario_movimientos_comercio_fecha_idx on public.inventario_movimientos(comercio_id,created_at desc);
create index if not exists inventario_movimientos_producto_idx on public.inventario_movimientos(comercio_id,producto_id,created_at desc);

create table if not exists public.servicios (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 categoria_comercio_id uuid, nombre text not null, descripcion text,
 modalidad text not null default 'mixto' check(modalidad in ('presencial','domicilio','remoto','mixto')),
 precio_tipo text not null default 'presupuesto' check(precio_tipo in ('fijo','desde','rango','presupuesto')),
 precio numeric(14,2), precio_hasta numeric(14,2), duracion_minutos integer,
 permite_turnos boolean not null default true, permite_presupuesto boolean not null default true,
 zona_cobertura text, publicado_online boolean not null default false, activo boolean not null default true,
 created_at timestamptz not null default now(), unique(comercio_id,id),
 foreign key(comercio_id,categoria_comercio_id) references public.categorias_comercio(comercio_id,id) on delete restrict,
 check(precio is null or precio>=0), check(precio_hasta is null or precio_hasta>=0),
 check(duracion_minutos is null or duracion_minutos>0)
);
create table if not exists public.servicio_turnos (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 servicio_id uuid not null, cliente_id uuid, sucursal_id uuid, inicio timestamptz not null, fin timestamptz not null,
 estado text not null default 'solicitado' check(estado in ('solicitado','confirmado','realizado','cancelado','ausente')),
 notas text, created_at timestamptz not null default now(),
 foreign key(comercio_id,servicio_id) references public.servicios(comercio_id,id) on delete restrict,
 foreign key(comercio_id,cliente_id) references public.clientes(comercio_id,id) on delete restrict,
 foreign key(comercio_id,sucursal_id) references public.sucursales(comercio_id,id) on delete restrict,
 check(fin>inicio)
);
create table if not exists public.servicio_solicitudes (
 id uuid primary key default gen_random_uuid(), comercio_id uuid not null references public.comercios(id) on delete cascade,
 servicio_id uuid not null, cliente_id uuid, nombre_contacto text, telefono text, email text,
 descripcion_trabajo text, direccion_servicio text,
 estado text not null default 'recibida' check(estado in ('recibida','en_revision','presupuestada','aceptada','rechazada','finalizada')),
 presupuesto numeric(14,2), created_at timestamptz not null default now(),
 foreign key(comercio_id,servicio_id) references public.servicios(comercio_id,id) on delete restrict,
 foreign key(comercio_id,cliente_id) references public.clientes(comercio_id,id) on delete restrict
);

insert into public.sucursales(comercio_id,nombre,codigo,es_principal)
select c.id,'Casa central','CENTRAL',true from public.comercios c
where not exists(select 1 from public.sucursales s where s.comercio_id=c.id);
insert into public.depositos(comercio_id,sucursal_id,nombre,codigo,tipo,es_principal)
select s.comercio_id,s.id,'Depósito principal','PRINCIPAL','general',true from public.sucursales s
where s.es_principal and not exists(select 1 from public.depositos d where d.comercio_id=s.comercio_id and d.sucursal_id=s.id);
insert into public.inventario_saldos(comercio_id,deposito_id,producto_id,cantidad)
select st.comercio_id,d.id,st.producto_id,st.cantidad from public.stock st
join public.depositos d on d.comercio_id=st.comercio_id and d.es_principal on conflict do nothing;
insert into public.inventario_movimientos(comercio_id,tipo,deposito_destino_id,producto_id,cantidad,motivo)
select st.comercio_id,'apertura',d.id,st.producto_id,st.cantidad,'Migración inicial desde stock existente'
from public.stock st join public.depositos d on d.comercio_id=st.comercio_id and d.es_principal
where st.cantidad>0 and not exists(select 1 from public.inventario_movimientos m
 where m.comercio_id=st.comercio_id and m.producto_id=st.producto_id and m.deposito_destino_id=d.id and m.tipo='apertura');

do $$
declare t text;
begin
 foreach t in array array['comercio_rubros','sucursales','depositos','categorias_comercio','producto_variantes',
 'listas_precios','lista_precios_items','inventario_saldos','inventario_movimientos','servicios','servicio_turnos','servicio_solicitudes']
 loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I on public.%I',t||'_tenant_all',t);
  execute format('create policy %I on public.%I for all to authenticated using (comercio_id=(select private.current_user_commerce_id())) with check (comercio_id=(select private.current_user_commerce_id()))',t||'_tenant_all',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;
alter table public.rubros enable row level security;
drop policy if exists rubros_read_all on public.rubros;
create policy rubros_read_all on public.rubros for select to anon,authenticated using(activo=true);
grant select on public.rubros to anon,authenticated;
alter table public.unidades_medida enable row level security;
drop policy if exists unidades_read_all on public.unidades_medida;
create policy unidades_read_all on public.unidades_medida for select to anon,authenticated using(activo=true);
grant select on public.unidades_medida to anon,authenticated;
grant usage on schema public to anon,authenticated;
