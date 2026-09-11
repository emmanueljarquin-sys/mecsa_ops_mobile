# Documentación técnica — MecsaOPS Mobile

Documentación de arquitectura y flujos de la app móvil de operaciones de Grupo Mecsa. Todos los diagramas están en [Mermaid](https://mermaid.js.org/) y se renderizan directamente en GitHub, VS Code (con la extensión *Markdown Preview Mermaid Support*) y la mayoría de visores Markdown.

> Versión documentada: **1.5.8+36**. Las referencias `archivo:línea` apuntan al código en `lib/` y pueden desplazarse con cambios futuros.

## Índice

| # | Documento | Contenido |
|---|-----------|-----------|
| 1 | [Arquitectura](01-arquitectura.md) | Stack, capas, componentes, recursos externos, permisos |
| 2 | [Arranque y autenticación](02-arranque-y-autenticacion.md) | Inicio de la app, login, registro, MFA TOTP, notificaciones push y realtime |
| 3 | [Flotilla](03-flotilla.md) | Reservas, bloqueo por strikes, registro de salida/entrada, tracking GPS, PDF de ruta |
| 4 | [Viáticos](04-viaticos.md) | Liquidaciones, facturas, totales, solicitud de corrección |
| 5 | [Visitas](05-visitas.md) | Wizard de visita en ruta, waypoints, cierre y pago de kilometraje |
| 6 | [Auditorías](06-auditorias.md) | Rúbrica, inspección por ítems, puntaje |
| 7 | [Administración](07-administracion.md) | Quién es admin, aprobar liquidaciones y reservas, correcciones, desbloqueo |
| 8 | [Modo offline](08-modo-offline.md) | SQLite local, cola de sincronización, resincronización automática, copia de seguridad programada, comprobantes y PDF |
| 9 | [Modelo de datos](09-modelo-de-datos.md) | Inventario de tablas, buckets, RPCs, endpoints PHP y estados |
| 10 | [Observaciones y deuda técnica](10-observaciones.md) | Hallazgos encontrados al documentar el código |
| 11 | [Registro de actividad](11-registro-de-actividad.md) | Log local en SQLite, niveles configurables, visor y exportación desde Perfil |
| 12 | [Chat CRM y notificaciones](12-chat-crm.md) | Pestaña de chat WhatsApp vía API de Wapi, configuración, centro de notificaciones (campana) |

## Cómo leer los diagramas de secuencia

Los participantes se repiten en todos los documentos con estos nombres:

| Participante | Qué es |
|--------------|--------|
| `UI` | La pantalla (widget) de Flutter con la que interactúa el usuario |
| `Provider` | `AppProvider`, el estado global de la app ([lib/providers/app_provider.dart](../lib/providers/app_provider.dart)) |
| `Service` | Servicios específicos: `OfflineService`, `SyncService`, `ConnectivityService`, `LiquidacionesService`, `AdminService`, `AuditoriaService`, `MfaService`, `TrackingService`, `RutaPdfService`, `LiquidacionPdfService`, `VisitaPdfService`, `ComprobantesService` |
| `SQLite` | Base local `mecsa_ops_local.db` (`LocalDb`): `cache`, `offline_queue`, `reservas`, `liquidaciones`, `vehiculos`, `id_map`, `app_log` |
| `WorkManager` | Tarea de fondo de Android/iOS que ejecuta la copia de seguridad programada |
| `Supabase` | PostgREST (tablas), Auth, Storage y Realtime del proyecto Supabase |
| `API PHP` | Endpoints en `https://grupomecsa.net/ops/api/*.php` (mismo backend que la web de OPS) |
| `Prefs` | `SharedPreferences`: preferencias (GPS, niveles de log, copia de seguridad) |
| `FS` | Sistema de archivos del teléfono (carpeta de documentos de la app) |
| `Google` | APIs de Google Maps (Directions, Geocoding, Places) |
| `FCM` | Firebase Cloud Messaging |
