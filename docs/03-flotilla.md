# 3. Flotilla

Módulo de reservas y uso de vehículos de la empresa. Todo el módulo escribe **directo en Supabase** (schema `flotilla`); no usa ningún endpoint PHP.

Pantallas: [flotilla_screen.dart](../lib/screens/flotilla_screen.dart), [reservation_form_screen.dart](../lib/screens/reservation_form_screen.dart), [reservation_detail_screen.dart](../lib/screens/reservation_detail_screen.dart), [vehicle_register_screen.dart](../lib/screens/vehicle_register_screen.dart), [trip_nav_screen.dart](../lib/screens/trip_nav_screen.dart).

## 3.1 Ciclo de vida de una reserva

```mermaid
stateDiagram-v2
    [*] --> Pendiente: createReservation()
    Pendiente --> Aprobada: admin (app o web)
    Pendiente --> Rechazada: admin (app o web)
    Pendiente --> Cancelada: cancelarReserva() antes de fecha_salida
    Aprobada --> Cancelada: cancelarReserva() antes de fecha_salida y sin registro de salida
    Aprobada --> EnUso: registro tipo 'salida'
    EnUso --> Completada: registro tipo 'entrada'
    Rechazada --> [*]
    Cancelada --> [*]
    Completada --> [*]

    note right of EnUso
        No es un estado de la columna.
        Se infiere de flotilla.registros_vehiculos
        (existe salida, no existe entrada).
    end note
```

La columna `flotilla.reservas.estado` toma los valores `Pendiente`, `Aprobada`, `Rechazada`, `Cancelada`. La interfaz compara por substring (`APROB`, `RECHAZ`, `CANCEL`, `COMPLET`).

## 3.2 Crear una reserva

Fuente: [reservation_form_screen.dart:482-519](../lib/screens/reservation_form_screen.dart#L482-L519), [app_provider.dart:1089-1212](../lib/providers/app_provider.dart#L1089-L1212).

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant UI as ReservationFormScreen
    participant Map as MapPickerScreen
    participant Provider as AppProvider
    participant Supabase

    U->>UI: vehículo (solo status == available), fechas, motivo, proyecto, personal
    opt ubicación
        UI->>Map: push
        Map->>Map: Google Places autocomplete / geocode
        Map-->>UI: {lat, lng, address} → "LAT,LNG|ADDRESS"
    end
    U->>UI: Guardar
    UI->>Provider: createReservation({vehiculo_id, fecha_salida, fecha_regreso, motivo, proyecto_id, ubicacion, personal_incluido, estado: 'Pendiente'})
    Provider->>Supabase: Empleados.select(reservas_bloqueado, sistemas_acceso).eq(id)
    alt sistemas_acceso NO contiene RESERVAS_EXCEPCION
        Provider->>Supabase: RPC flotilla.aplicar_bloqueo_si_corresponde(p_empleado_id)
        Note over Supabase: bloquea si hay ≥3 reservas vencidas<br/>sin registro de salida (strikes)
        Provider->>Supabase: Empleados.select(reservas_bloqueado)
        alt reservas_bloqueado == true
            Provider-->>UI: throw "Tu cuenta está bloqueada para hacer reservas"
        end
    else tiene excepción
        Note over Provider: salta la RPC (fix v1.5.x: antes re-bloqueaba)
    end
    Provider->>Provider: verifica vehículo available en memoria
    Provider->>Supabase: reservas.select(id).eq(vehiculo_id).neq(Cancelada).neq(Rechazada).lt(fecha_salida, fin).gt(fecha_regreso, inicio).limit(1)
    alt hay traslape
        Provider-->>UI: throw "El vehículo ya está reservado en ese horario"
    end
    Provider->>Supabase: INSERT flotilla.reservas {..., empleado_id}
    par refresco
        Provider->>Supabase: flotilla.vehiculos
        Provider->>Supabase: flotilla.reservas + vehiculos(*)
    end
    Provider-->>UI: true
    UI->>U: "Reserva creada exitosamente"
```

## 3.3 Bloqueo por strikes

La regla vive en la función SQL `flotilla.aplicar_bloqueo_si_corresponde`. Un "strike" es una reserva cuya fecha de salida ya pasó y para la que el empleado nunca registró la salida del vehículo. Con tres o más, la función pone `Empleados.reservas_bloqueado = true`.

```mermaid
flowchart TD
    A["createReservation()"] --> B["lee Empleados.reservas_bloqueado,<br/>sistemas_acceso"]
    B --> C{"¿tiene token<br/>RESERVAS_EXCEPCION?"}
    C -->|sí| OK["continúa sin evaluar strikes"]
    C -->|no| D["RPC aplicar_bloqueo_si_corresponde"]
    D --> E["re-lee reservas_bloqueado"]
    E --> F{"bloqueado?"}
    F -->|sí| ERR["error: cuenta bloqueada"]
    F -->|no| OK
    D -.->|"RPC falla (red/permisos)"| OK

    subgraph Desbloqueo["Desbloqueo manual (admin)"]
        G["DesbloquearReservasScreen<br/>o toggle_reservas_bloqueo.php en web"]
        G --> H["reservas_bloqueado = false"]
        G --> I["agrega RESERVAS_EXCEPCION<br/>a sistemas_acceso"]
        G -.->|"solo la web"| J["cancela reservas Pendiente<br/>con fecha_regreso pasada"]
    end
```

## 3.4 Detalle de reserva y acciones disponibles

Fuente: [reservation_detail_screen.dart](../lib/screens/reservation_detail_screen.dart).

```mermaid
flowchart TD
    Det["ReservationDetailScreen"] --> Q["SELECT flotilla.registros_vehiculos<br/>WHERE reserva_id"]
    Q --> S{"estado de la reserva"}
    S -->|"Pendiente / Rechazada / Cancelada"| NoReg["sin sección de registro"]
    S -->|"Aprobada u otro"| R{"¿registros?"}
    R -->|"ninguno"| B1["REGISTRAR SALIDA"]
    R -->|"solo salida"| B2["INICIAR VIAJE (app)<br/>REGISTRAR ENTRADA"]
    R -->|"salida + entrada"| B3["Resumen: km salida, km entrada,<br/>km totales, duración"]
    B3 --> B4["Exportar PDF · Guardar fotos"]
    B3 --> B5["Corregir salida / entrada<br/>(solicitud de corrección)"]
    S -->|"Pendiente o Aprobada,<br/>fecha_salida futura"| C["CANCELAR RESERVA"]
```

### Cancelación

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant UI as ReservationDetailScreen
    participant Provider as AppProvider
    participant Supabase

    U->>UI: CANCELAR RESERVA + motivo opcional
    UI->>Provider: cancelarReserva(reservaId, motivo)
    Provider->>Supabase: reservas.select(id, estado, fecha_salida, empleado_id)
    alt estado contiene CANCEL / RECHAZ / COMPLET
        Provider-->>UI: error "ya no se puede cancelar"
    else fecha_salida ya pasó
        Provider-->>UI: error
    else empleado_id != currentEmployeeId
        Provider-->>UI: error "Solo el solicitante puede cancelar"
    end
    Provider->>Supabase: registros_vehiculos.select(id, tipo).eq(reserva_id)
    alt existe tipo 'salida'
        Provider-->>UI: error "Ya iniciaste el viaje"
    end
    Provider->>Supabase: UPDATE reservas {estado: 'Cancelada', comentarios: 'Cancelada por el solicitante: ...'}
    Provider->>Supabase: refresca vehículos y reservas
    Provider-->>UI: ok
```

## 3.5 Registro de salida y entrada del vehículo

Fuente: [vehicle_register_screen.dart:114-223](../lib/screens/vehicle_register_screen.dart#L114-L223), [app_provider.dart:1356-1551](../lib/providers/app_provider.dart#L1356-L1551).

Se piden **cinco fotos obligatorias**: frente, lateral derecho, lateral izquierdo, trasera y tablero con kilometraje. En la salida se capturan además niveles de aceite y combustible, estado físico (pintura, llantas, interiores) y equipamiento (kit, refacción, compás). En la entrada el kilometraje se pre-llena con el de salida más la distancia acumulada por el GPS del viaje.

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant UI as VehicleRegisterScreen
    participant Offline as OfflineService
    participant Provider as AppProvider
    participant Storage as Supabase Storage
    participant DB as flotilla.registros_vehiculos
    participant Track as TrackingService

    U->>UI: 5 fotos + kilometraje + datos según tipo
    U->>UI: Guardar
    UI->>Offline: hayConexion()
    alt sin conexión
        UI->>Offline: enqueue('registro_vehiculo', record, photos)
        Note over Offline: ver doc 08. Fotos copiadas a offline_photos/
        UI->>U: "Guardado sin conexión. Se subirá solo cuando haya internet."
    else con conexión
        UI->>Provider: saveVehicleRegister(reservaId, tipo, fotos, datos)
        Provider->>DB: SELECT id WHERE reserva_id AND tipo AND estado != 'Rechazado' LIMIT 1 (timeout 15s)
        alt ya existe
            Provider-->>UI: true (idempotente, no duplica)
        end
        par 5 subidas en paralelo (timeout 40s c/u)
            Provider->>Storage: fotos_registro_vehiculos/registros/register_{reserva}_{key}_{ms}.jpg
        end
        Storage-->>Provider: nombres de archivo
        Provider->>Provider: Geolocator.getCurrentPosition (timeout 10s) → ubicacion "lat,lng"
        Provider->>DB: INSERT {reserva_id, empleado_id, tipo, kilometraje, niveles, estado físico, equipamiento, ubicacion, foto_*} (timeout 30s)
        Provider->>Provider: fetchData() sin await
        alt success
            Provider-->>UI: true
            opt tipo == entrada
                UI->>Provider: clearTripDistance(reservaId)
                UI->>Track: stopTracking()
            end
            UI->>U: "Registro guardado con éxito"
        else false (señal débil)
            UI->>Offline: enqueue(...)
            UI->>U: "No se pudo subir ahora. Se subirá automáticamente."
        else excepción
            UI->>Offline: enqueue(...)
            alt encolar también falla
                UI->>U: ofrece registro manual
                U->>UI: comentario
                UI->>Provider: saveVehicleRegisterManual → INSERT {estado: 'Pendiente', es_manual: true, comentario}
            end
        end
    end
```

### Estados de un registro

| `estado` | Quién lo pone | Significado |
|----------|---------------|-------------|
| *(default de la tabla)* | Registro normal | Registro válido |
| `Pendiente` | Registro manual desde la app | Requiere revisión de un admin (`aprobar_registro_manual.php` en la web) |
| `Rechazado` | Admin en la web | Se ignora para la idempotencia, permite volver a registrar |
| `Correccion Solicitada` | Empleado desde el detalle de reserva | Pidió corregir kilometraje u otro dato |
| `Corregido` | Admin desde la app o la web | Corrección aplicada |

## 3.6 Navegación del viaje y tracking GPS

Fuente: [trip_nav_screen.dart](../lib/screens/trip_nav_screen.dart), [tracking_service.dart](../lib/services/tracking_service.dart).

Hay **dos streams de GPS independientes** mientras dura un viaje:

| Stream | Dónde | `distanceFilter` | Qué hace |
|--------|-------|------------------|----------|
| `TrackingService` | Provider, persiste toda la sesión | 10 m | INSERT en `visitas.ops_tracking` por cada punto |
| `TripNavScreen` local | Solo mientras la pantalla está abierta | 5 m | Acumula distancia en memoria, mueve la cámara, recalcula ruta, habla instrucciones |

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant Det as ReservationDetailScreen
    participant Track as TrackingService
    participant Nav as TripNavScreen
    participant Geo as Geolocator
    participant DB as visitas.ops_tracking
    participant Google as Google Directions
    participant TTS as flutter_tts
    participant Provider as AppProvider

    U->>Det: INICIAR VIAJE (DENTRO DE APP)
    Det->>Track: startTracking(activityId: reservaId)
    Track->>Geo: checkPermission / requestPermission
    Track->>Geo: getPositionStream(high, distanceFilter 10)
    Det->>Nav: push(entity: reserva, destination: ubicacion)
    Nav->>TTS: init es-MX, voz de preferencias
    Nav->>Geo: getCurrentPosition (15s)
    Nav->>Track: startTracking (idempotente)
    Nav->>Google: GET directions/json?origin&destination&waypoints&mode=driving&language=es
    Google-->>Nav: polyline + steps
    Nav->>TTS: "Bienvenido {nombre}, iniciaremos el viaje..."
    Nav->>Geo: getPositionStream(high, distanceFilter 5)

    loop cada punto GPS
        Geo->>Track: position
        Track->>DB: INSERT {user_id, user_email, lat, lng, accuracy, speed, heading, activity_id}
        Geo->>Nav: position
        Nav->>Provider: updateTripDistance(reservaId, km)
        Nav->>Nav: cámara zoom 17, tilt 45, bearing
        alt desvío > 60 m en 3 lecturas
            Nav->>Google: recalcula ruta
        end
        alt a < 30 m del siguiente step
            Nav->>TTS: habla instrucción
        end
    end

    U->>Nav: FINALIZAR VIAJE
    Nav->>Nav: Navigator.pop (NO detiene TrackingService)
    Note over Track: sigue insertando hasta que se<br/>registre la entrada del vehículo
```

## 3.7 PDF del registro de ruta y fotos

Fuente: [reservation_detail_screen.dart:455-573](../lib/screens/reservation_detail_screen.dart#L455-L573), [ruta_pdf_service.dart](../lib/services/ruta_pdf_service.dart).

Disponible solo cuando la reserva tiene registro de salida y de entrada.

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant Det as ReservationDetailScreen
    participant Pdf as RutaPdfService
    participant HTTP as http
    participant Print as printing
    participant Gal as gal

    alt Exportar PDF
        U->>Det: Exportar PDF
        Det->>Det: diálogo "Generando PDF..."
        Det->>Pdf: construirPdf(vehículo, placa, conductor, destino, regSalida, regEntrada)
        loop cada foto_* de salida y entrada
            Pdf->>HTTP: GET url (timeout 25s)
        end
        Pdf-->>Det: bytes (A4: datos, resumen km, fotos salida, fotos entrada)
        Det->>Print: sharePdf(bytes, 'visita_{placa}_{reservaId}.pdf')
        Print->>U: menú del sistema: compartir / guardar / imprimir
    else Guardar fotos
        U->>Det: Guardar fotos
        Det->>Pdf: urlsDeFotos(regSalida, regEntrada)
        Det->>Gal: hasAccess / requestAccess
        loop cada URL
            Det->>Pdf: descargarBytes(url)
            Det->>Gal: putImageBytes(bytes, album: 'MecsaOPS')
        end
        Det->>U: "N fotos guardadas"
    end
```

> Las columnas `foto_*` guardan solo el **nombre de archivo**, pero el servicio de PDF hace `http.get` asumiendo una URL absoluta. Ver [Observaciones](10-observaciones.md).

## 3.8 Vehículos personales

Aunque `fetchPersonalVehicles` vive en el provider junto con la flotilla, los vehículos personales pertenecen al módulo de **Visitas**: son los vehículos propios del empleado con los que hace recorridos que luego se pagan por kilometraje. Tabla `visitas.vehiculos_personales` con `alias`, `antiguedad`, `tipo`, `combustible`. Ver [Visitas](05-visitas.md).
