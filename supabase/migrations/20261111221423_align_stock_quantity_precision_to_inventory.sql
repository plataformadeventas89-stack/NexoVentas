alter table public.stock
  alter column cantidad type numeric(14,3)
  using cantidad::numeric(14,3);
