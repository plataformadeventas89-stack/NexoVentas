# Auditoría de sincronización Supabase ↔ GitHub

Fecha de revisión: 2026-11-11

## Estado observado

- Proyecto Supabase: `ryrnsaytoygkayynvkio`
- Rama inspeccionada: `main`
- Migraciones registradas en Supabase: **42**
- Archivos SQL presentes en `supabase/migrations`: **19**
- Versiones de migración sin archivo con la misma versión en GitHub: **34**
- Objetos observados en el esquema `public`: 38 tablas, 0 vistas, 26 funciones, 15 triggers, 69 políticas RLS y 169 índices.

La diferencia de 34 se calcula comparando el prefijo de versión de cada archivo SQL con `supabase_migrations.schema_migrations.version`. Algunas migraciones podrían tener un archivo equivalente con otro prefijo temporal; deben compararse por contenido y dependencias antes de considerarlas reconciliadas.

## Versiones registradas en Supabase sin archivo de igual versión

| Versión | Nombre registrado |
|---|---|
| `20261110154854` | `sales_quotes_stock_workflows` |
| `20261110155145` | `secure_sales_quote_rpc_and_indexes` |
| `20261110155204` | `secure_signup_and_inventory_constraints` |
| `20261110155225` | `optimize_signup_rls_claim_lookup` |
| `20261110155245` | `harden_transaction_input_validation` |
| `20261110172406` | `grant_authenticated_table_access_for_app` |
| `20261110172421` | `fix_commerce_rls_policy_recursion` |
| `20261110173750` | `nexoventas_v2_finance_suppliers_purchases` |
| `20261110173926` | `nexoventas_v2_foreign_key_indexes` |
| `20261110182709` | `inventory_transfers_adjustments` |
| `20261110190727` | `nexoventas_variants_price_lists_transactions` |
| `20261110190809` | `nexoventas_variants_price_fk_and_legacy_rpc_compat` |
| `20261110190901` | `nexoventas_price_list_fk_indexes` |
| `20261110190953` | `nexoventas_price_list_currency_guard` |
| `20261110191734` | `nexoventas_validate_aggregate_variant_sales` |
| `20261110191752` | `fix_aggregate_variant_sales_alias` |
| `20261110191805` | `fix_aggregate_variant_sales_record` |
| `20261110191817` | `fix_aggregate_variant_sales_product_field` |
| `20261110191909` | `nexoventas_advanced_price_rules` |
| `20261110192034` | `allow_multiple_advanced_price_rules` |
| `20261110201550` | `admin_vendedor_role_permissions` |
| `20261110201558` | `admin_write_policies_for_commerce_setup` |
| `20261110201613` | `seller_read_own_inventory_transfers` |
| `20261110202014` | `harden_seller_pricing_and_audit_log` |
| `20261110202955` | `tighten_seller_customer_and_inventory_reads` |
| `20261110210256` | `product_gallery_storage` |
| `20261110222637` | `add_public_store_profile` |
| `20261110224913` | `create_public_store_orders` |
| `20261110225121` | `harden_public_store_order_validation` |
| `20261110225129` | `validate_public_order_items_safely` |
| `20261110230126` | `create_shipping_configuration` |
| `20261110233741` | `prepare_secure_marketplace_checkout` |
| `20261110235814` | `seller_transfer_payment_settings` |
| `20261111215032` | `clientes_admin_delete_policy` |
| `20261111215118` | `validate_shipping_tracking_https_urls` |

## Criterio de recuperación

1. Recuperar SQL original desde commits históricos cuando esté disponible.
2. Comparar archivos con versiones distintas por contenido, no solo por nombre.
3. Para migraciones sin fuente histórica, reconstruirlas desde el catálogo actual de PostgreSQL y documentar dependencias y límites.
4. Generar un baseline reproducible que incluya tablas, tipos, secuencias, constraints, índices, funciones, triggers, políticas RLS, grants, extensiones y objetos dependientes.
5. Validar la reconstrucción en una base aislada antes de modificar el registro de migraciones.

## Protección de producción

**No se modificó el esquema ni el historial de migraciones de producción durante esta auditoría.** No se reinició la base, no se alteraron datos y no se insertaron versiones artificiales en el historial.

## Limitación técnica pendiente

La conexión disponible permite consultar SQL y el historial de migraciones, pero no ofrece un `pg_dump`/Supabase CLI ni una base de validación aislada ya provisionada. Por eso, este informe no afirma que el repositorio ya pueda reconstruir íntegramente la base. Hace falta obtener un volcado completo del esquema o habilitar un entorno aislado de validación para completar y probar el baseline.
