# 1. Arquitectura

## 1.1 Resumen

MecsaOPS Mobile es una app Flutter (Android e iOS) para el personal de campo de Grupo Mecsa. Cubre cinco áreas: **flotilla** (reservas y uso de vehículos), **viáticos** (liquidación de gastos), **visitas** (recorridos con pago de kilometraje), **auditorías** de vehículos y un **modo administración** para aprobar y corregir.

No tiene backend propio. Habla directamente con **Supabase** (Postgres vía PostgREST, Auth, Storage, Realtime) y, para las operaciones que necesitan lógica de servidor o notificaciones, con los **endpoints PHP** de la web de OPS (repositorio `MecsaOPS`, carpeta `api/`) publicados en `https://grupomecsa.net/ops/api/`.

## 1.2 Stack

| Capa | Tecnología | Uso |
|------|-----------|-----|
| UI | Flutter 3 (Dart SDK ^3.10) | Pantallas en `lib/screens/` |
| Estado | `provider` (`ChangeNotifier`) | Un `AppProvider` global + `OfflineService` como segundo notifier |
| Backend principal | `supabase_flutter` 2.x | Auth con email/password + MFA TOTP, tablas en varios schemas, Storage, Realtime |
| Backend secundario | HTTP (`http`) a PHP | Versionado, registro de empleados, liquidaciones, cierre de visitas, MFA backup codes |
| Push | `firebase_core` + `firebase_messaging` | Notificaciones de pago de kilometraje |
| Notificaciones locales | `flutter_local_notifications` | Aviso cuando una liquidación cambia de estado (vía Realtime) |
| Geolocalización | `geolocator`, `google_maps_flutter` | Tracking, navegación, mapas |
| Voz | `flutter_tts` | Instrucciones de navegación |
| Offline | `connectivity_plus`, `shared_preferences`, `path_provider` | Cola de sincronización |
| Documentos | `pdf`, `printing`, `gal`, `image_picker`, `share_plus` | PDF de ruta, liquidación y visita; fotos a galería |
| Datos locales | `sqflite`, `path_provider` | SQLite (caché, cola offline, reservas, liquidaciones, vehículos, log) y fotos/comprobantes en la carpeta de la app |
| Fondo | `workmanager` | Copia de seguridad programada (diaria/semanal/mensual) |
| CI | Codemagic (`codemagic.yaml`) | AAB automático en cada push a `main` |

## 1.3 Diagrama de componentes

```mermaid
flowchart TB
    subgraph App["App Flutter"]
        direction TB
        Screens["Pantallas<br/>lib/screens/*"]
        Provider["AppProvider<br/>estado global, sesión, permisos,<br/>fetch de datos, tracking"]
        subgraph Services["Servicios lib/services/*"]
            Offline["OfflineService<br/>cola offline"]
            Sync["SyncService<br/>copia de seguridad"]
            Conn["ConnectivityService<br/>sondeo de internet"]
            Liq["LiquidacionesService"]
            Admin["AdminService"]
            Aud["AuditoriaService"]
            Mfa["MfaService"]
            Track["TrackingService"]
            Pdf["RutaPdfService<br/>LiquidacionPdfService<br/>VisitaPdfService"]
        end
        SQLite[("SQLite mecsa_ops_local.db<br/>cache · offline_queue · reservas<br/>liquidaciones · vehiculos · id_map · app_log")]
        Prefs[("SharedPreferences<br/>gps_*, log_*, backup_*")]
        FS[("Archivos<br/>offline_photos/ · comprobantes/")]
        WM["WorkManager<br/>tarea diaria"]
    end

    subgraph Supabase["Supabase awhuzekjpoapamijlvua"]
        Auth["Auth + MFA"]
        DB[("Postgres<br/>schemas: public, cms, flotilla,<br/>viaticos, visitas, proyectos")]
        Storage[("Storage<br/>empleados, flotilla,<br/>fotos_registro_vehiculos,<br/>facturas_viaticos, visitas_fotos")]
        RT["Realtime"]
    end

    subgraph PHP["grupomecsa.net/ops/api  (repo MecsaOPS)"]
        E1["check_version.php"]
        E2["register_employee_mobile.php<br/>request_password_reset.php"]
        E3["create_liquidacion.php<br/>approve_liquidacion.php"]
        E4["finish_visita.php"]
        E5["mfa/backup_codes_generate.php<br/>mfa/backup_code_verify.php"]
    end

    Google["Google Maps APIs<br/>Directions, Geocoding, Places"]
    FCM["Firebase Cloud Messaging"]

    Screens --> Provider
    Screens --> Services
    Provider --> Auth
    Provider --> DB
    Provider --> Storage
    Provider --> RT
    Provider --> E1
    Provider --> E2
    Provider --> E4
    Provider --> Track
    Offline --> Prefs
    Offline --> FS
    Offline --> DB
    Offline --> Storage
    Offline --> E3
    Liq --> DB
    Liq --> Storage
    Liq --> E3
    Admin --> DB
    Admin --> E3
    Aud --> DB
    Aud --> Storage
    Mfa --> Auth
    Mfa --> E5
    Track --> DB
    Screens --> Google
    FCM --> Screens
    RT --> Provider
    PHP --> DB
    PHP --> FCM
```

### Navegación y animaciones

El shell (`HomeScreen`) muestra las 5 pestañas con `AnimatedTabs` ([widgets/animated_tabs.dart](../lib/widgets/animated_tabs.dart)): todas quedan montadas (como `IndexedStack`, sin perder scroll ni formularios) y el cambio hace un deslizamiento corto con desvanecido en la dirección del movimiento. Entre páginas (`Navigator.push`) el tema define `pageTransitionsTheme` con `FadeForwardsPageTransitionsBuilder` en Android y el deslizamiento nativo en iOS. Las fotos de visitas abren en `FotoViewer` ([widgets/foto_viewer.dart](../lib/widgets/foto_viewer.dart)): modal a pantalla completa con zoom, paginación, descarga a la galería y compartir.

## 1.4 Estructura de carpetas

```
lib/
├── main.dart                 # Inicializa Supabase, Firebase, OfflineService y WorkManager; decide Login vs Home
├── providers/
│   └── app_provider.dart     # Estado global (2.4k líneas): sesión, empleado, permisos, fetchData, reservas, visitas, tracking
├── services/
│   ├── local_db.dart         # SQLite: esquema y migraciones (dbVersion 4)
│   ├── offline_service.dart  # Cola offline (registros, facturas, liquidaciones, visitas)
│   ├── sync_service.dart     # Copia de seguridad manual y programada (WorkManager)
│   ├── connectivity_service.dart · cache_service.dart
│   ├── reservas_local.dart · liquidaciones_local.dart · vehiculos_local.dart
│   ├── comprobantes_service.dart · liquidacion_pdf_service.dart · visita_pdf_service.dart
│   ├── liquidaciones_service.dart
│   ├── admin_service.dart
│   ├── auditoria_service.dart
│   ├── mfa_service.dart
│   ├── tracking_service.dart # Stream GPS -> visitas.ops_tracking
│   └── ruta_pdf_service.dart
├── models/                   # reservation, liquidacion (+Factura), auditoria (+RubricaItem, AuditoriaItem)
├── screens/
│   ├── home_screen.dart      # Shell con IndexedStack de 5 pestañas + DashboardTab
│   ├── login_screen.dart, mfa_*.dart
│   ├── flotilla_screen.dart, reservation_*.dart, vehicle_register_screen.dart, trip_nav_screen.dart
│   ├── viaticos_screen.dart, liquidacion_*.dart
│   ├── visitas_screen.dart, visita_*.dart, map_picker_screen.dart
│   ├── auditorias/           # lista, formulario, detalle
│   ├── admin/                # hub, aprobar liquidaciones, aprobar reservas, correcciones, desbloquear
│   └── profile_screen.dart
├── widgets/                  # bottom_nav, correccion_widgets, etc.
├── theme/app_theme.dart
└── utils/
```

## 1.5 Navegación principal

```mermaid
flowchart LR
    Main["main.dart"] -->|"user == null"| Login["LoginScreen"]
    Main -->|"user != null"| Home["HomeScreen"]
    Login -->|"signIn ok + MFA ready"| Home
    Login -->|"MFA challenge"| Chal["MfaChallengeScreen"]
    Login -->|"MFA enroll"| Enr["MfaEnrollScreen"]
    Enr --> Backup["MfaBackupCodesScreen"]
    Chal --> Home
    Backup --> Home

    Home --> Dash["0 · Dashboard"]
    Home --> Flot["1 · Flotilla"]
    Home --> Via["2 · Viáticos"]
    Home --> Vis["3 · Visitas"]
    Home --> Perf["4 · Perfil"]

    Dash -->|"hasAdminAccess"| AdminHub["AdminHubScreen"]
    Dash -->|"canAudit"| AudList["AuditoriasListScreen"]
    Flot --> ResForm["ReservationFormScreen"]
    Flot --> ResDet["ReservationDetailScreen"]
    ResDet --> VehReg["VehicleRegisterScreen<br/>salida / entrada"]
    ResDet --> Trip["TripNavScreen"]
    Via --> LiqForm["LiquidacionFormScreen"]
    Via --> LiqDet["LiquidacionDetailScreen"]
    Vis --> VisIni["VisitaInicioScreen<br/>wizard 3 pasos"]
    Vis --> VisDet["VisitaDetailScreen"]
    Vis --> Trip
```

## 1.6 Modelo de permisos

Toda la autorización se calcula en el cliente a partir de la fila del empleado en `public.Empleados` y de dos tablas auxiliares. Se resuelve en `_fetchCurrentEmployeeId()` ([app_provider.dart:111-189](../lib/providers/app_provider.dart#L111-L189)).

```mermaid
flowchart TB
    Emp["public.Empleados<br/>rol, sistemas_acceso, departamento, activo"]
    RP["public.rol_permisos<br/>rol_nombre, vista_slug, puede_ver"]
    RD["public.viaticos_responsables_departamento<br/>empleado_id, departamento_id"]

    Emp --> isAdmin["isRoleAdmin<br/>rol ∈ administrador, admin,<br/>superadmin, superadministrador"]
    Emp --> isConta["isContabilidad<br/>rol == contabilidad"]
    Emp --> sistemas["_sistemas<br/>sistemas_acceso en MAYÚSCULAS"]
    RP --> allowed["_allowedViews<br/>slugs con puede_ver = true"]
    RD --> isResp["isResponsable"]

    isAdmin --> canView["canViewModule(slug) =<br/>isRoleAdmin OR allowed ∋ slug OR sistemas ∋ SLUG"]
    allowed --> canView
    sistemas --> canView

    canView --> canAudit["canAudit = canViewModule('auditorias')"]
    canView --> canRes["canApproveReservas = canViewModule('aprobar_reservas')"]
    canView --> canCorr["canProcesarCorrecciones = canViewModule('procesar_correcciones')"]
    canView --> canDes["canDesbloquear = canViewModule('desbloquear_reservas')"]
    isAdmin --> canLiq["canApproveLiquidaciones =<br/>isRoleAdmin OR isContabilidad OR isResponsable<br/>OR allowed ∋ aprobar_liquidaciones"]
    isConta --> canLiq
    isResp --> canLiq
    allowed --> canLiq

    canLiq --> hasAdmin["hasAdminAccess = OR de los cuatro<br/>→ botón Administración en Dashboard"]
    canRes --> hasAdmin
    canCorr --> hasAdmin
    canDes --> hasAdmin
```

Además, `sistemas_acceso` contiene el token `RESERVAS_EXCEPCION` que exime del bloqueo por strikes (ver [Flotilla](03-flotilla.md#33-bloqueo-por-strikes)).

## 1.7 Ciclo de vida del estado

- `AppProvider` se crea una sola vez en `main.dart` y vive toda la sesión.
- `fetchData()` es la carga completa (con spinner). Se llama al construir el provider, al hacer login, y en cada pull-to-refresh.
- `refreshSilent()` recarga solo reservas, viáticos y visitas sin spinner. Se dispara cuando la app vuelve a primer plano.
- Al hacer `signOut` el listener de Auth limpia vehículos y proyectos y cierra el canal Realtime.
- `OfflineService` es un singleton independiente que sobrevive a login/logout.

## 1.8 Dos caminos hacia los datos

Es importante distinguir cuándo la app escribe **directo en Supabase** y cuándo pasa **por PHP**, porque solo el segundo camino dispara notificaciones y lógica de negocio del servidor.

```mermaid
flowchart LR
    subgraph Directo["Directo a Supabase (anon key + RLS)"]
        d1["Reservas: crear, cancelar, aprobar"]
        d2["Registros de vehículo"]
        d3["Facturas: crear, editar, borrar"]
        d4["Visitas: iniciar, waypoints"]
        d5["Auditorías"]
        d6["Correcciones"]
        d7["Perfil y foto"]
        d8["Tracking GPS"]
    end
    subgraph ViaPHP["Vía API PHP (lógica de servidor)"]
        p1["Registro de empleado"]
        p2["Crear liquidación"]
        p3["Aprobar liquidación → push"]
        p4["Finalizar visita → km, tarifa, monto"]
        p5["MFA backup codes"]
        p6["Check de versión"]
    end
```
