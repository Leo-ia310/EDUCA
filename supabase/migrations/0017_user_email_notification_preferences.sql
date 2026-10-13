-- Preferencia por usuario para envios de correo transaccional.
alter table users
  add column if not exists email_notifications_enabled boolean not null default true;
