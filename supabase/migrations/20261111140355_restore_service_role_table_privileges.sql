-- Restore server-side access required by Supabase Edge Functions.
-- service_role remains server-only and bypasses RLS by design.
grant usage on schema public to service_role;
grant all privileges on all tables in schema public to service_role;
grant usage, select, update on all sequences in schema public to service_role;
alter default privileges in schema public grant all privileges on tables to service_role;
alter default privileges in schema public grant usage, select, update on sequences to service_role;
