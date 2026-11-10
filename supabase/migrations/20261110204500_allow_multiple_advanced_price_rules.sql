-- Allow multiple non-overlapping / prioritized price rules for the same product tier.
drop index if exists public.lista_precio_item_producto_idx;
drop index if exists public.lista_precio_item_variante_idx;