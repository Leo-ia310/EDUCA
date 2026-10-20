# Contexto de petición y cupo compartido

Aplicar `0035_backend_request_context.sql` antes de publicar el backend. Mantener `SUPABASE_SERVICE_ROLE_KEY` solo en Render/servidor. El frontend no conoce esa clave y no puede ejecutar la RPC privada ni modificar el contador.

Cada petición protegida hace una verificación de su bearer en Supabase Auth y una RPC privada de contexto/cupo. Esta última deriva cuenta, institución, roles, perfiles asociados y permisos desde la base, comprueba la sesión real y MFA, e incrementa atómicamente el contador. Las consultas de negocio siguen usando el JWT del usuario con RLS; la credencial privilegiada se utiliza exclusivamente para la RPC de contexto validada y los servicios internos que ya la requieren.

No se comparten snapshots de autorización entre peticiones ni usuarios. Los permisos precargados solo evitan repetir la misma comprobación de módulo y la búsqueda de identidad durante esa petición. El acceso a un alumno, clase o periodo concreto conserva su comprobación específica y las políticas de la base.

`USER_RATE_LIMIT_MAX` (1200 por defecto) y `RATE_LIMIT_WINDOW_MS` (900000 por defecto, entero entre 1 y 86400000) deben coincidir entre instancias. Un único registro por cuenta serializa incrementos y conserva la misma ventana a través de reinicios/escalado del backend. La primera petición después del vencimiento abre una nueva ventana. Los contadores se eliminan cuando se elimina la cuenta. Los límites por IP de fallos 401 continúan siendo una protección local por proceso; el cupo por usuario es el compartido.

Las respuestas exponen `x-user-ratelimit-limit`, `x-user-ratelimit-remaining` y `x-user-ratelimit-reset`. Un 429 incluye `Retry-After` con segundos restantes. Una indisponibilidad de Auth/autorización devuelve 503, sin confundirla con credenciales incorrectas. Una sesión sin `session_id` válido o eliminada de `auth.sessions` requiere iniciar sesión nuevamente.

La función no es una API pública de Express y está revocada a `anon`/`authenticated`. No recibe token ni contraseña y no los almacena. El backend la invoca únicamente después de verificar ese token con Auth. Si falla la RPC, se rechaza la petición; no se recurre a un contador local ni a un contexto privilegiado para ejecutar la operación.
