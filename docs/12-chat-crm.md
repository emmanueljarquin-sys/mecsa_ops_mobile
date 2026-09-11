# 12. Chat CRM (WhatsApp) y centro de notificaciones

## 12.1 Estado: pendiente de conectar

La pestaña **Chat** (lista y conversación) está terminada y `ChatService` ([services/chat_service.dart](../lib/services/chat_service.dart)) ya consulta el esquema **`waba_crm`** de Supabase. Pero hoy la app **no puede leerlo**: probado con la clave anónima y con la sesión de un usuario, Postgres responde `permission denied` en las tablas detectadas (`conversations`, `conversation_events`, `conversation_notes`, `queues`, `queue_members`). El rol `authenticated` no tiene GRANT sobre el esquema; la web lo lee con la clave de servicio.

Por eso la pestaña muestra "Pendiente de conectar" y el servicio devuelve solo caché. Para activarla:

1. En Supabase: exponer `waba_crm` en la API, `GRANT USAGE` en el esquema y `GRANT SELECT` en esas tablas a `authenticated`, con políticas RLS (admin ve todo; los demás solo conversaciones con `assigned_to` = su empleado o `queue_id` en una cola de la que son miembros en `queue_members`).
2. Confirmar los nombres de columna en la clase `WabaCrm` (un solo lugar; el resto del código no cambia).
3. Compilar con `--dart-define=WABA_CHAT=true` (o cambiar el valor por defecto de `ChatConfig.conectado`).

## 12.2 Consultas previstas

| Uso | Consulta |
|-----|----------|
| Lista de chats | `waba_crm.conversations` ordenadas por `last_message_at`; si no es admin, `or(assigned_to.eq.<empleado>, queue_id.in.(<colas del empleado>))` con las colas de `queue_members` |
| Historial | `waba_crm.conversation_events` por `conversation_id`, orden `created_at` |
| Responder (apagado, `WABA_ENVIO`) | `insert` en `conversation_events` con `direction = outbound`; el backend del CRM lo envía a WhatsApp |

Sin conexión, lista e historial se leen de la caché (`chat_lista`, `chat_msgs:<conversación>`).

## 12.3 Quién lo ve

`AppProvider.puedeVerChat`: rol que contiene `admin`, `vendedor`, `ventas` o `asesor`, o `Empleados.chat_role` no vacío. Cuando aplica, `HomeScreen` agrega la pestaña **Chat** antes de Perfil y `BottomNav` muestra el destino. El botón "CHAT CRM" del Dashboard (que abría la web con SSO) se eliminó. Regla de datos: admin ve todas las conversaciones; los demás solo las asignadas a ellos o a sus colas.

## 12.4 Pantallas

- `ChatListScreen`: avatar de iniciales con punto verde si la ventana de 24 h está abierta, nombre, último mensaje (con ✓/✓✓ si es saliente), hora, contador de no leídos, buscador, banner sin conexión.
- `ChatDetailScreen`: burbujas entrantes/salientes con fondo estilo WhatsApp (claro y oscuro), separadores por día, estado del mensaje, adjuntos como descripción (📷 Foto, 🎤 Audio…), etiquetas del contacto, barra de respuesta. Refresco cada 10 s mientras está abierta.

Sin conexión ambas pantallas muestran lo que quedó en la caché (`chat_lista`, `chat_msgs:<waId>`).

## 12.5 Centro de notificaciones (campana)

La campana del Dashboard abre `NotificationsScreen` con el historial guardado en la tabla `notificaciones` de SQLite (`NotificacionesService`, v5). Alimentan la campana:

| Origen | Tipo | Al tocar |
|--------|------|----------|
| Push FCM recibido con la app abierta (`onMessage`) | `visita` (pago de kilometraje) o `info` | Abre el detalle de la visita |
| Realtime: liquidación aprobada/rechazada | `liquidacion` | Va a la pestaña Viáticos |
| Operación offline que subió | `visita`, `liquidacion`, `reserva` o `sync` | Pestaña correspondiente |
| Fin de una copia de seguridad | `sync` | Perfil → Copias de seguridad |
| Nueva versión disponible | `version` | — |

El icono muestra el número de no leídas; la pantalla permite marcar todas como leídas, borrar una (deslizar) o todas. Se conservan las últimas 200 por usuario.
