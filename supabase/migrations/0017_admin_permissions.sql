-- Permisos por persona para perfiles administrativos (admin, coordinator,
-- director). NULL = sin restricciones (comportamiento histórico del rol);
-- un arreglo = lista exacta de permisos concedidos (puede estar vacío).
-- Códigos con formato "<modulo>.<accion>", ver backend/src/lib/admin-permissions.ts.
alter table users add column if not exists admin_permissions text[];

comment on column users.admin_permissions is
  'Permisos administrativos concedidos a este usuario. NULL = todos los del rol.';
