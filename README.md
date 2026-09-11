# MecsaOPS Mobile

App móvil de operaciones de **Grupo Mecsa** para el personal de campo. Reservas y uso de vehículos de la flotilla, liquidación de viáticos, visitas con pago de kilometraje, auditorías de vehículos y un modo de administración para aprobar desde el teléfono.

| | |
|---|---|
| **Versión** | 1.5.8+36 |
| **Plataformas** | Android (Play Store, `com.grupomecsa.mecsa_ops_mobile`) e iOS |
| **Framework** | Flutter 3 · Dart SDK ^3.10 |
| **Backend** | Supabase (Postgres, Auth, Storage, Realtime) + API PHP de la web OPS |
| **CI** | Codemagic: AAB automático en cada push a `main` |
| **Documentación técnica** | [docs/](docs/README.md) con diagramas de secuencia por módulo |

---

## Índice

- [Qué hace la app](#qué-hace-la-app)
- [Arquitectura](#arquitectura)
- [Cómo fluye una operación típica](#cómo-fluye-una-operación-típica)
- [Módulos](#módulos)
- [Modo offline](#modo-offline)
- [Seguridad y acceso](#seguridad-y-acceso)
- [Estructura del código](#estructura-del-código)
- [Configuración y ejecución local](#configuración-y-ejecución-local)
- [Build y despliegue](#build-y-despliegue)
- [Documentación detallada](#documentación-detallada)

---

## Qué hace la app

```mermaid
mindmap
  root((MecsaOPS<br/>Mobile))
    Flotilla
      Reservar vehículo
      Registrar salida con 5 fotos
      Navegación GPS con voz
      Registrar entrada
      PDF del recorrido
    Viáticos
      Liquidación con facturas
      Foto del comprobante
      Solicitar corrección
      Aviso de aprobación
    Visitas
      Vehículo personal
      Recorrido con waypoints
      Cierre con odómetro
      Pago por kilómetro
    Auditorías
      Rúbrica por categorías
      Puntaje automático
      Fotos por ítem
    Administración
      Aprobar liquidaciones
      Aprobar reservas
      Responder correcciones
      Desbloquear empleados
    Transversal
      Login + MFA TOTP
      Push FCM
      Cola offline
      Actualización forzada
```

---

## Arquitectura

La app no tiene servidor propio. Habla **directo con Supabase** para la mayoría de lecturas y escrituras, y pasa por los **endpoints PHP** del repositorio `MecsaOPS` (publicados en `https://grupomecsa.net/ops/api/`) cuando hace falta lógica de servidor o enviar notificaciones.

```mermaid
flowchart LR
    subgraph Phone["Teléfono"]
        UI["Pantallas"]
        P["AppProvider<br/>estado global"]
        S["Servicios"]
        Q[("Cola offline<br/>SharedPreferences + fotos")]
        UI --> P
        UI --> S
        S --> Q
    end

    subgraph SB["Supabase"]
        Auth["Auth + MFA"]
        DB[("Postgres<br/>public · cms · flotilla<br/>viaticos · visitas · proyectos")]
        ST[("Storage<br/>5 buckets")]
        RT["Realtime"]
    end

    subgraph OPS["Web OPS · PHP"]
        API["api/*.php"]
    end

    FCM["Firebase<br/>Cloud Messaging"]
    GM["Google Maps<br/>Directions · Geocoding · Places"]
    BX["Bitrix24"]

    P --> Auth
    P --> DB
    P --> ST
    RT --> P
    S --> DB
    S --> ST
    S --> API
    Q --> DB
    Q --> API
    API --> DB
    API --> ST
    API --> FCM
    API --> BX
    FCM --> UI
    UI --> GM
```

### Qué va directo y qué pasa por PHP

| Directo a Supabase | Vía API PHP |
|--------------------|-------------|
| Reservas: crear, cancelar, aprobar | Registro de empleado nuevo |
| Registros de salida/entrada y sus fotos | Crear liquidación (valida y avisa a Bitrix24) |
| Facturas: crear, editar, borrar | Aprobar liquidación (envía push) |
| Visitas: iniciar, waypoints | Finalizar visita (calcula km, tarifa y monto) |
| Auditorías y puntaje (RPC) | Códigos de respaldo MFA |
| Correcciones, perfil, tracking GPS | Versión mínima requerida |

---

## Cómo fluye una operación típica

Ejemplo: un empleado registra la salida de un vehículo reservado.

```mermaid
sequenceDiagram
    autonumber
    actor E as Empleado
    participant App
    participant Offline as Cola offline
    participant Storage as Supabase Storage
    participant DB as Supabase DB

    E->>App: 5 fotos + kilometraje + niveles + estado físico
    App->>App: ¿hay red?
    alt sin red
        App->>Offline: guarda fotos y datos en el teléfono
        App-->>E: "Se subirá cuando haya internet"
        Note over Offline: al reconectar repite los pasos de abajo
    else con red
        App->>DB: ¿ya existe registro para esta reserva y tipo?
        DB-->>App: no
        par 5 fotos en paralelo
            App->>Storage: fotos_registro_vehiculos/registros/...
        end
        App->>App: posición GPS actual
        App->>DB: INSERT flotilla.registros_vehiculos
        App-->>E: "Registro guardado"
    end
```

Cada módulo tiene su propio conjunto de diagramas en [docs/](docs/README.md).

---

## Módulos

### Flotilla

Reservar un vehículo de la empresa, registrar su salida y entrada con fotos, navegar con GPS y voz, y exportar un PDF del recorrido.

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Pendiente: reservar
    Pendiente --> Aprobada: admin
    Pendiente --> Rechazada: admin
    Pendiente --> Cancelada: empleado
    Aprobada --> EnUso: registro de salida
    EnUso --> Completada: registro de entrada
```

- Validación de traslape de horarios y disponibilidad del vehículo.
- **Bloqueo por strikes**: con 3 o más reservas vencidas sin registrar salida, la función SQL `aplicar_bloqueo_si_corresponde` bloquea al empleado. Un admin puede desbloquear y marcar una excepción.
- El tracking GPS inserta puntos en `visitas.ops_tracking` cada 10 metros.
- Detalle en [docs/03-flotilla.md](docs/03-flotilla.md).

### Viáticos

Liquidación de gastos con facturas fotografiadas. Se crea vía `create_liquidacion.php`, que valida al empleado, al proyecto y exige descripción de 15 caracteres cuando no hay proyecto.

- Solo editable mientras está `pendiente`.
- Después de aprobada o rechazada el empleado puede **solicitar corrección**.
- El resultado llega por dos vías: notificación local vía **Realtime** y push **FCM** desde el servidor.
- Detalle en [docs/04-viaticos.md](docs/04-viaticos.md).

### Visitas

Recorridos con el **vehículo personal** del empleado. Un wizard de tres pasos captura odómetro inicial con foto, traza el recorrido con waypoints y cierra con odómetro final y observaciones.

- `finish_visita.php` calcula kilómetros, aplica un tarifario por tipo de vehículo, combustible y antigüedad, y guarda el monto a pagar.
- Cuando un admin confirma el pago en la web, la app recibe un push con `tipo: pago_kilometraje` y abre el detalle con el comprobante.
- Detalle en [docs/05-visitas.md](docs/05-visitas.md).

### Auditorías

Inspección de un vehículo de la flotilla contra una rúbrica de ítems por categoría. Cada ítem se marca `buen`, `mal` o `na`, con observación y fotos. La función SQL `recompute_auditoria` calcula el puntaje excluyendo los N/A.

- Visible solo con permiso `auditorias`.
- Detalle en [docs/06-auditorias.md](docs/06-auditorias.md).

### Administración

Modo admin dentro de la app (desde v1.5.0). Aparece en el Dashboard cuando el empleado tiene al menos uno de estos permisos:

| Tarjeta | Quién |
|---------|-------|
| Aprobar liquidaciones | Rol admin, contabilidad, responsable de departamento o permiso explícito |
| Aprobar reservas | Permiso `aprobar_reservas` |
| Correcciones | Permiso `procesar_correcciones` |
| Desbloquear reservas | Permiso `desbloquear_reservas` |

La app envía `actor_id` y el servidor re-lee el rol desde la base de datos. Detalle en [docs/07-administracion.md](docs/07-administracion.md).

---

## Modo offline

No hay SQLite. La app guarda una **cola de escritura** en `SharedPreferences` (clave `offline_queue_v1`) y copia las fotos a la carpeta de documentos. Al recuperar la red, `connectivity_plus` dispara la sincronización.

```mermaid
flowchart LR
    A["Usuario guarda<br/>sin red"] --> B["Cola local<br/>+ fotos copiadas"]
    B --> C{"¿vuelve<br/>la red?"}
    C -->|sí| D["Sube fotos<br/>a Storage"]
    D --> E["INSERT o<br/>POST al API"]
    E -->|ok| F["Borra de la cola<br/>y fotos locales"]
    E -->|error| G["attempts++<br/>queda pendiente"]
    G --> C
```

- Tipos soportados: registro de vehículo, liquidación con facturas, factura suelta.
- Una operación **nunca se borra** hasta que el servidor confirma.
- Los registros de vehículo tienen chequeo de duplicados; las liquidaciones no.
- Solo escritura. Sin red no se pueden consultar datos que no estén ya en memoria.
- Detalle en [docs/08-modo-offline.md](docs/08-modo-offline.md).

---

## Seguridad y acceso

```mermaid
flowchart TD
    L["Login email + password"] --> A{"¿cuenta activa?"}
    A -->|no| X["Pendiente de activación<br/>por un administrador"]
    A -->|sí| M{"¿tiene TOTP?"}
    M -->|"sí, AAL2"| H["Home"]
    M -->|"sí, AAL1"| C["Desafío: código TOTP<br/>o código de respaldo"]
    M -->|no| G{"RPC mfa_must_enroll"}
    G -->|"gracia vencida"| F["Enrolar obligatorio<br/>QR + 8 códigos de respaldo"]
    G -->|"en gracia"| O["Enrolar opcional"]
    C --> H
    F --> H
    O --> H
```

- **MFA TOTP** con Supabase Auth. El periodo de gracia vive en `Empleados.mfa_grace_until` y lo evalúa el servidor.
- **Códigos de respaldo** generados por PHP con bcrypt. Usar uno acorta la gracia a 24 horas para forzar re-enrolar.
- **Permisos** calculados en el cliente a partir de `Empleados.rol`, `Empleados.sistemas_acceso` y `rol_permisos`. Ver [docs/01-arquitectura.md](docs/01-arquitectura.md#16-modelo-de-permisos).
- **Actualización forzada**: `check_version.php` devuelve `min_version_code`; si el build instalado es menor, la app bloquea con un botón a Play Store.

---

## Estructura del código

```
lib/
├── main.dart                     Inicializa Supabase, Firebase y la cola offline. Login vs Home.
├── providers/app_provider.dart   Estado global: sesión, empleado, permisos, fetchData, reservas, visitas.
├── services/
│   ├── offline_service.dart      Cola de sincronización.
│   ├── liquidaciones_service.dart
│   ├── admin_service.dart
│   ├── auditoria_service.dart
│   ├── mfa_service.dart
│   ├── tracking_service.dart     Stream GPS → visitas.ops_tracking.
│   └── ruta_pdf_service.dart
├── models/                       reservation, liquidacion, auditoria
├── screens/
│   ├── home_screen.dart          Shell con 5 pestañas + Dashboard.
│   ├── login_screen.dart · mfa_*_screen.dart
│   ├── flotilla_screen.dart · reservation_*.dart · vehicle_register_screen.dart · trip_nav_screen.dart
│   ├── viaticos_screen.dart · liquidacion_*.dart
│   ├── visitas_screen.dart · visita_*.dart · map_picker_screen.dart
│   ├── auditorias/
│   ├── admin/
│   └── profile_screen.dart
├── widgets/
├── theme/
└── utils/
```

Dependencias principales: `supabase_flutter`, `provider`, `firebase_messaging`, `flutter_local_notifications`, `geolocator`, `google_maps_flutter`, `flutter_tts`, `connectivity_plus`, `shared_preferences`, `path_provider`, `image_picker`, `pdf`, `printing`, `gal`.

---

## Configuración y ejecución local

### Requisitos

- Flutter estable con Dart ^3.10.
- Android Studio o Xcode según la plataforma.
- `android/app/google-services.json` (Android) y `ios/Runner/GoogleService-Info.plist` (iOS) del proyecto Firebase `mecsa-ops-mobile`. En CI se inyectan desde variables en base64.

### Pasos

```bash
flutter pub get
dart run flutter_launcher_icons
flutter run
```

### Claves y URLs

| Qué | Dónde | Nota |
|-----|-------|------|
| URL y anon key de Supabase | `lib/main.dart` | Hardcodeadas. La anon key es pública por diseño; RLS protege los datos |
| API key de Google Maps | `lib/screens/trip_nav_screen.dart`, `lib/screens/map_picker_screen.dart` | Hardcodeada. Conviene restringirla por paquete y SHA |
| Base del API PHP | `https://grupomecsa.net/ops/api` | En `liquidaciones_service.dart`, `admin_service.dart`, `offline_service.dart`, `mfa_service.dart` y `app_provider.dart` |
| Firma Android | `android/key.properties` | No versionado. `build.gradle.kts` lo lee si existe |

---

## Build y despliegue

### Versionado

`pubspec.yaml` lleva `version: X.Y.Z+N`. El `N` es el `versionCode` de Android y es lo que compara `check_version.php`. **Cada build que suba a Play Store necesita un `N` mayor** al anterior publicado.

### Codemagic

Dos workflows en [codemagic.yaml](codemagic.yaml):

| Workflow | Disparo | Máquina | Produce |
|----------|---------|---------|---------|
| `android-release` | Push a `main` | Linux | AAB + `mapping.txt` de R8 |
| `ios-android-release` | Manual | Mac mini M2 | AAB + IPA |

Ambos decodifican `GOOGLE_SERVICES_JSON_ANDROID` (y `GOOGLE_SERVICE_INFO_IOS`) desde variables de entorno, corren `flutter pub get`, generan íconos y compilan en release. El AAB llega por correo.

### Publicar una actualización obligatoria

```mermaid
flowchart LR
    A["Subir pubspec<br/>version +N"] --> B["Push a main"]
    B --> C["Codemagic<br/>genera AAB"]
    C --> D["Subir AAB a<br/>Play Console"]
    D --> E["Esperar a que<br/>esté live"]
    E --> F["Actualizar<br/>api/app_version.json<br/>en MecsaOPS<br/>min_version_code = N"]
    F --> G["Las apps viejas<br/>ven pantalla de<br/>actualización"]
```

El orden importa: si se sube `app_version.json` antes de que el AAB esté publicado, los usuarios quedan bloqueados sin poder actualizar.

---

## Documentación detallada

La carpeta [docs/](docs/README.md) contiene la documentación técnica completa con diagramas de secuencia por flujo:

| Documento | Contenido |
|-----------|-----------|
| [01 · Arquitectura](docs/01-arquitectura.md) | Componentes, navegación, permisos, ciclo de vida del estado |
| [02 · Arranque y autenticación](docs/02-arranque-y-autenticacion.md) | Startup, login, registro, MFA, push, realtime |
| [03 · Flotilla](docs/03-flotilla.md) | Reservas, strikes, registros, tracking, PDF |
| [04 · Viáticos](docs/04-viaticos.md) | Liquidaciones, facturas, correcciones |
| [05 · Visitas](docs/05-visitas.md) | Wizard, tarifario, pago de kilometraje |
| [06 · Auditorías](docs/06-auditorias.md) | Rúbrica, inspección, puntaje |
| [07 · Administración](docs/07-administracion.md) | Aprobaciones, correcciones, desbloqueo, modelo de confianza |
| [08 · Modo offline](docs/08-modo-offline.md) | Cola, persistencia, reintentos |
| [09 · Modelo de datos](docs/09-modelo-de-datos.md) | Tablas, RPCs, buckets, endpoints, estados |
| [10 · Observaciones](docs/10-observaciones.md) | Deuda técnica y hallazgos |

Repositorio del backend web y API PHP: `MecsaOPS`.
