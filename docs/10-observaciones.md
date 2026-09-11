# 10. Observaciones y deuda técnica

Hallazgos encontrados al leer el código para escribir esta documentación. No son cambios aplicados, son puntos a evaluar. Se agrupan por impacto.

## 10.1 Seguridad

| # | Hallazgo | Dónde | Riesgo |
|---|----------|-------|--------|
| S1 | `approve_liquidacion.php` acepta `actor_id` sin validar el JWT. Quien conozca el UUID de un admin puede aprobar liquidaciones | `MecsaOPS/api/approve_liquidacion.php`, `includes/resolve_current_employee.php` | Alto |
| S2 | `create_liquidacion.php` y `finish_visita.php` no autentican. Confían en `empleado_id` e `id` del cliente | `MecsaOPS/api/` | Alto |
| S3 | API key de Google Maps y anon key de Supabase hardcodeadas en el código Dart. La anon key es esperada, pero la key de Google debería restringirse por paquete/SHA | `trip_nav_screen.dart:16`, `map_picker_screen.dart:10`, `main.dart` | Medio |
| S4 | `config/supabase.php` del servidor tiene fallback con service_role real comiteado | `MecsaOPS/config/supabase.php` | Alto (repo servidor) |
| S5 | Al arrancar con sesión persistida no se re-evalúa MFA. Un dispositivo con sesión AAL1 antigua entra directo a Home. (La **validez** del token sí se verifica ahora: ver §8.0 del doc de offline y `renovarSesion()` / modal de sesión expirada en `HomeScreen`) | `main.dart`, `app_provider.dart` (`_verificarSesionAlArrancar`) | Medio |
| S6 | El endpoint `mfa/backup_codes_generate.php` documenta que exige AAL2 pero solo verifica que el JWT sea válido | `MecsaOPS/api/mfa/backup_codes_generate.php` | Bajo |

## 10.2 Consistencia de datos

| # | Hallazgo | Dónde | Efecto |
|---|----------|-------|--------|
| D1 | Las facturas se insertan una por una después de crear la liquidación, sin transacción. Si falla una, la liquidación queda sin esa factura | `liquidacion_form_screen.dart:674-687` | Datos parciales |
| D2 | La cola offline no tiene idempotencia para `liquidacion`, `factura` ni `visita_fin`. Un timeout tras el insert genera duplicados en el reintento. (`registro_vehiculo`, `visita_inicio` y `visita_crear` sí son idempotentes) | `offline_service.dart` | Duplicados |
| D3 | Fotos huérfanas en Storage si la subida funciona pero el insert falla y se reintenta | `offline_service.dart`, `app_provider.dart:1394-1448` | Basura en Storage |
| D4 | ~~`liquidacionesPendientes` compara `estado != 'Aprobado'`~~ **Resuelto**: compara en minúsculas (`aprobada`/`aprobado`). Además el contador ahora solo considera el último mes | `app_provider.dart` (`_fetchViaticos`) | — |
| D5 | `_saveFcmToken` corre en `_init()` antes de que exista `currentEmployeeId`, así que en el primer arranque no guarda el token. Se guarda en arranques posteriores si Firebase inicializa antes que `fetchData` termine, lo cual no está garantizado | `app_provider.dart:216, 320-338` | Push puede no llegar |
| D6 | `aprobado_por` queda como `'Sistema'` cuando se aprueba desde la app | `MecsaOPS/api/approve_liquidacion.php` | Trazabilidad |
| D7 | `finish_visita.php` deja `km_recorridos` en null si `odometro_inicial` es 0 | `MecsaOPS/api/finish_visita.php:78-80` | Sin pago |
| D8 | `update_liquidacion.php` no aplica la regla de descripción mínima; solo `create_liquidacion.php` | `MecsaOPS/api/update_liquidacion.php` | Regla evadible al editar |

## 10.3 Funcionalidad rota o incompleta

| # | Hallazgo | Dónde |
|---|----------|-------|
| F1 | El servicio de PDF hace `http.get` sobre el valor de `foto_*`, pero esas columnas guardan solo el nombre de archivo, no la URL. Falta un `getPublicUrl` | `ruta_pdf_service.dart:48-57`, `app_provider.dart:1545` |
| F2 | La paginación de viáticos nunca avanza: `currentPage` no se incrementa y no hay scroll listener. Queda un spinner permanente al final | `viaticos_screen.dart:94, 322-329` |
| F3 | `VisitaFormScreen` (alta manual de visita) y `LiveMapScreen` no tienen navegación desde ninguna pantalla. `VisitaFormScreen` ya soporta offline y banner por si se conecta | `visita_form_screen.dart`, `live_map_screen.dart` |
| F4 | `_showCompleteDialog` en el detalle de visita está definido pero ningún botón lo llama | `visita_detail_screen.dart` |
| F5 | El botón "Finalizar viaje" de `TripNavScreen` solo hace `pop`; el `TrackingService` sigue insertando en `ops_tracking` hasta que se registre la entrada | `trip_nav_screen.dart:808-817` |
| F6 | `AuditoriaDetailScreen` depende de un cache estático que solo se llena en la lista. Si se llega por otro camino muestra "Vehículo" | `auditoria_service.dart:107-116` |
| F7 | La versión mostrada en Perfil (`1.0.0 (Beta)`) y en el diálogo del Dashboard (`1.1.2`) son literales; la real es 1.5.8+36 | `profile_screen.dart:186-208`, `home_screen.dart:748` |
| F8 | El modelo `Reservation` no se usa; las pantallas trabajan con mapas crudos | `models/reservation.dart` |

## 10.4 Conectividad y resiliencia

| # | Hallazgo | Dónde |
|---|----------|-------|
| C1 | ~~No hay verificación de conectividad al arrancar. `fetchData` no tiene timeout; en Wi-Fi cautivo puede colgarse~~ **Resuelto**: timeout de 20 s por consulta, caché de lectura, `loadError` + `ConnectionBanner`. `check_version.php` sigue sin timeout (no bloquea la UI) | `app_provider.dart` (`fetchData`, `_consulta`), `widgets/connection_banner.dart` |
| C2 | ~~`hayConexion()` solo consulta si hay red~~ **Resuelto**: delega en `ConnectivityService.checkInternet()` (sondeo HTTP con timeout 4 s). Sigue devolviendo `true` si el propio sondeo lanza una excepción inesperada | `offline_service.dart`, `services/connectivity_service.dart` |
| C3 | La cola offline no tiene backoff ni límite de reintentos. Una operación que siempre falla se reintenta en cada flush (al volver la red, cada 45 s y en la copia programada) indefinidamente. Ahora al menos es visible: Perfil → Copias de seguridad muestra intentos y último error | `offline_service.dart` |
| C5 | ~~El botón "Guardar registro" usaba `provider.isLoading`, que enciende la recarga general~~ **Resuelto**: bandera propia `_isSaving` y tope único de 45 s antes de encolar | `vehicle_register_screen.dart` |
| C6 | La tarea de WorkManager corre todos los días a la hora elegida; la frecuencia semanal/mensual se decide en `sincronizarSiToca()`. Android puede desplazarla minutos u horas (Doze, batería); no es un reloj exacto | `sync_service.dart`, `main.dart` |
| C4 | `fcm_v1_helper.php` pide un token OAuth nuevo por cada push y nadie verifica la respuesta de FCM | `MecsaOPS/api/fcm_v1_helper.php` |

## 10.5 Duplicación

| # | Hallazgo |
|---|----------|
| U1 | Dos streams de GPS simultáneos en viajes y visitas (pantalla + `TrackingService`) con el mismo `distanceFilter`. Podría unificarse en uno que alimente ambos destinos |
| U2 | El empleado recibe dos avisos por la misma aprobación: notificación local por Realtime y push FCM |
| U3 | `LiquidacionesService.approveLiquidacion` existe pero no se usa; la pantalla admin usa `AdminService.aprobarLiquidacion`. Conviene eliminar la primera |
| U4 | Chequeo de `activo == false` duplicado en `signIn` y en `_fetchCurrentEmployeeId` con mensajes distintos, y ambos pueden ejecutarse en paralelo tras el login |

## 10.6 Cambios aplicados el 11/09/2026

- Cola offline migrada a SQLite (`offline_queue`) con historial de subidas; reservas, liquidaciones (último mes) y vehículos en tablas propias; visitas completas sin conexión con ids locales.
- Resincronización automática al recuperar internet, reintento periódico y refresco de la lista afectada al subir.
- Perfil → Copias de seguridad: `SyncService` + WorkManager (diaria/semanal/mensual, hora, solo WiFi o datos), notificación de progreso.
- Banners de "sin conexión" en registro de vehículo, liquidación, visita en ruta y formulario de visita; el formulario de reserva bloquea sin red.
- Visor integrado de comprobantes con caché local; PDF de liquidación (con comprobantes) y de visita (con fotos), compartibles; fotos de visita a la galería.
- Mensajes de error unificados (`utils/mensajes_error.dart`); avatar placeholder externo eliminado; `build.gradle.kts` con firma release condicional.

## 10.7 Cambios aplicados el 11/09/2026 (segunda tanda)

- Modo claro/oscuro con `AppColors` y `ThemeController`; banners y avisos adaptativos.
- Pestaña **Chat CRM** sobre Supabase `waba_crm` (pendiente de conectar: el rol autenticado no tiene permiso de lectura) para roles comerciales/admin, en lugar del botón que abría la web con SSO por `app_uid` (ese puente sigue existiendo en el servidor; ver S1/S2). Envío construido pero apagado (`WABA_ENVIO`).
- Campana del Dashboard funcional: centro de notificaciones en SQLite (`notificaciones`, v5).
- Historial de reservas con búsqueda (propias o todas si admin).
- Auditorías sin conexión (cola `auditoria` con fotos) y catálogos en caché.
- GitHub Actions: APK de debug como pre-release en la rama de trabajo.

## 10.8 Sugerencias de próximos pasos

1. Validar el JWT de Supabase en los endpoints PHP que hoy confían en `actor_id` o `empleado_id` (S1, S2). El helper `mfa/_bearer.php` ya hace exactamente eso y puede reutilizarse.
2. Añadir `getPublicUrl` en el servicio de PDF de rutas (F1).
3. Mover `_saveFcmToken` al final de `_fetchCurrentEmployeeId` (D5).
4. Dar idempotencia a la cola offline para liquidaciones y cierre de visita, por ejemplo enviando el `localId` como `client_id` que el servidor use como clave única (D2).
5. Backoff exponencial y límite de intentos en la cola, con opción de descartar desde Perfil → Copias de seguridad (C3).
