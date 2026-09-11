# 8. Modo offline

Fuente: [offline_service.dart](../lib/services/offline_service.dart).

La app **no tiene caché de lectura**. Sin conexión no se pueden ver reservas, liquidaciones ni visitas que no estén ya en memoria. Lo que sí existe es una **cola de escritura** que guarda operaciones en el teléfono y las sube cuando vuelve la red.

## 8.1 Qué se persiste y dónde

| Dato | Dónde | Formato |
|------|-------|---------|
| Cola de operaciones | `SharedPreferences`, clave `offline_queue_v1` | JSON de una lista de mapas |
| Fotos pendientes | `<documentos de la app>/offline_photos/<uuid>.<ext>` | Copia del archivo original |

No usa SQLite, Hive ni Isar. Cada operación en la cola tiene esta forma:

```json
{
  "id": "uuid",
  "type": "registro_vehiculo | factura | liquidacion",
  "record": { "...campos a insertar..." },
  "photos": { "frente": "/ruta/local.jpg", "kilometraje": "/ruta/local2.jpg" },
  "children": [ { "record": {...}, "photos": { "documento": "/ruta.jpg" } } ],
  "createdAt": "2026-09-11T14:30:00Z",
  "attempts": 0,
  "lastError": "..."
}
```

`children` solo se usa para el tipo `liquidacion`: son las facturas que dependen del id que devuelva el servidor.

## 8.2 Quién encola

| Tipo | Pantalla | Cuándo |
|------|----------|--------|
| `registro_vehiculo` | `VehicleRegisterScreen` | Sin conexión, o si el guardado en línea devolvió `false` o lanzó excepción |
| `liquidacion` | `LiquidacionFormScreen` | Sin conexión al guardar una liquidación **nueva** |
| `factura` | `LiquidacionDetailScreen` | Sin conexión al agregar una factura **nueva** a una liquidación existente |

Editar (no crear) siempre requiere conexión.

## 8.3 Ciclo de vida de la cola

```mermaid
flowchart TD
    Init["init() en main.dart"] --> Load["carga offline_queue_v1<br/>de SharedPreferences"]
    Load --> Listen["escucha connectivity_plus<br/>onConnectivityChanged"]
    Load --> F0["flush() inicial"]
    Listen -->|"vuelve la red"| F["flush()"]
    Enq["enqueue() desde una pantalla"] --> Persist["copia fotos a offline_photos/<br/>guarda op en la cola<br/>_save()"]
    Persist --> F
    F --> G{"¿ya hay un flush<br/>corriendo o cola vacía?"}
    G -->|sí| End([fin])
    G -->|no| H{"hayConexion()?"}
    H -->|no| End
    H -->|sí| Loop["por cada op en orden"]
    Loop --> P["_procesar(op)"]
    P -->|ok| Del["borra fotos locales<br/>quita op de la cola<br/>_save()"]
    P -->|error| Retry["attempts++<br/>lastError = e<br/>_save()  (la op se queda)"]
    Del --> Loop
    Retry --> Loop
    Loop -->|"terminó"| End
```

Reglas:

- **Nunca se borra una operación hasta que el servidor confirma.** En el peor caso queda visible como pendiente en el banner del Dashboard.
- No hay límite de reintentos ni backoff. Cada `flush` intenta todo lo pendiente.
- Solo corre un `flush` a la vez (`_flushing`).
- `hayConexion()` consulta `connectivity_plus`. Si la consulta falla, asume que sí hay red y deja que el upload real decida.

## 8.4 Sincronización de un registro de vehículo

```mermaid
sequenceDiagram
    autonumber
    participant Offline as OfflineService
    participant FS as offline_photos/
    participant DB as flotilla.registros_vehiculos
    participant Storage as fotos_registro_vehiculos

    Offline->>DB: SELECT id WHERE reserva_id AND tipo AND estado != 'Rechazado' LIMIT 1 (timeout 20s)
    alt ya existe
        Note over Offline: un intento en línea sí llegó → no duplica
        Offline->>FS: borra fotos
        Offline->>Offline: quita op
    else no existe (o la consulta falló por red)
        loop cada foto
            Offline->>FS: lee archivo
            Offline->>Storage: upload registros/register_offline_{uuid}.jpg (timeout 40s)
            Storage-->>Offline: nombre → record.foto_{key}
        end
        Offline->>DB: INSERT record (timeout 40s)
        Offline->>FS: borra fotos
        Offline->>Offline: quita op
    end
```

## 8.5 Sincronización de una liquidación con facturas

```mermaid
sequenceDiagram
    autonumber
    participant Offline as OfflineService
    participant PHP as create_liquidacion.php
    participant Storage as facturas_viaticos
    participant DB as viaticos.facturas

    Offline->>PHP: POST record (timeout 45s)
    Note over PHP: mismas validaciones que en línea:<br/>empleado existe, proyecto existe,<br/>descripción ≥ 15 si no hay proyecto
    PHP-->>Offline: {success, data: {id}}
    alt success != true o sin id
        Offline-->>Offline: throw → attempts++, queda pendiente
    end
    loop cada child (factura)
        opt tiene foto
            Offline->>Storage: upload offline_{uuid}.jpg (upsert)
        end
        Offline->>DB: INSERT {..., liquidacion_id: id}
    end
    Note over Offline: si falla una factura después de crear<br/>la liquidación, el reintento crea<br/>OTRA liquidación (sin idempotencia)
```

## 8.6 Indicador en la interfaz

El Dashboard tiene un `Consumer<OfflineService>` que muestra un banner con `pendingCount` y un botón "Subir ahora" que llama `flush()`. Mientras `isFlushing` es `true` muestra un spinner.

## 8.7 Limitaciones conocidas

- Solo tres tipos de operación. Visitas, auditorías, reservas y correcciones no funcionan sin conexión.
- `liquidacion` y `factura` no tienen chequeo de duplicados. Un timeout después de que el servidor insertó puede generar registros repetidos en el siguiente `flush`.
- Si sube la foto pero falla el `INSERT`, el reintento vuelve a subir la foto y deja un archivo huérfano en Storage.
- Toda la cola vive en un solo string JSON en `SharedPreferences`, cargado completo en memoria. Adecuado para decenas de operaciones, no para miles.
- Si en el futuro se necesita caché de lectura o consultas sobre la cola, ese sería el momento de migrar a `sqflite` o Drift.
