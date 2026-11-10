# Pendiente para Maikel: redesplegar la función Edge de Nivra Originality

Hola Maikel. Al hacer `git pull` falta un paso que solo se puede hacer con acceso a Supabase: **redesplegar la función Edge `nivra-originality`**.

## Qué cambió

En el commit `4ccfe5d` se agregó la plantilla de exclusión por actividad. El cambio de código está en `supabase/functions/nivra-originality/index.ts`: ahora `shared()` también lee la tabla privada `originality_templates` (migración 0065) y pasa esa plantilla al motor como texto a excluir.

## Estado actual

- La migración `0065_originality_summary_template.sql` **ya está aplicada** en la base de EDUCA. No hay que volver a aplicarla.
- El backend y la app ya usan los endpoints nuevos (resumen y plantilla).
- La función Edge desplegada **todavía es la versión anterior**: ignora la plantilla. Guardar la plantilla y reanalizar funcionan, pero el cálculo no la excluye hasta que se redespliegue.

## Qué hacer

Desde la raíz del repo, con una cuenta que tenga acceso al proyecto:

```bash
npx supabase@latest login
npx supabase@latest functions deploy nivra-originality --project-ref qwfkmijewogksfizdski --use-api --no-verify-jwt
```

Esto solo reemplaza el código. No cambies los secretos (`ORIGINALITY_CRON_SECRET`) ni `ORIGINALITY_EDGE_ENABLED`, que deben seguir como están (procesamiento activo y Cron cada 10 s).

## Cómo comprobar que quedó bien

1. En la app, entra como maestro a una tarea con entregas, abre **Nivra Originality → Plantilla** y pega una línea de al menos 20 caracteres que aparezca idéntica (como línea completa) en las entregas.
2. Guarda: se reanalizan las entregas. Al terminar, el porcentaje debe bajar porque esa línea ya no cuenta.
3. Si algo falla, el rollback de la 0065 está en `supabase/rollback/0065_originality_summary_template.sql`. No lo apliques mientras la app use los endpoints nuevos.

Cuando lo hayas desplegado, borra este archivo.
