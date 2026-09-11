# 6. Auditorías de vehículos

Inspección de un vehículo de la flotilla contra una **rúbrica** de ítems. El resultado es un porcentaje de ítems en buen estado, calculado en la base de datos.

Pantallas: [auditorias/](../lib/screens/auditorias/). Servicio: [auditoria_service.dart](../lib/services/auditoria_service.dart). Modelo: [auditoria.dart](../lib/models/auditoria.dart). Todo va **directo a Supabase**, schema `flotilla`, sin PHP.

Acceso: botón "Auditoría de Vehículo" en el Dashboard, visible si `canAudit` (rol admin, permiso `auditorias` en `rol_permisos`, o token `AUDITORIAS` en `sistemas_acceso`).

## 6.1 Modelo

```mermaid
erDiagram
    auditoria_rubrica {
        uuid id
        text categoria
        text item_slug
        text item_label
        text ayuda
        bool solo_pesados
        int orden
        bool activo
    }
    auditorias {
        uuid id
        uuid vehiculo_id
        uuid auditor_id
        date fecha_auditoria
        int kilometraje
        date fecha_ultimo_cambio_aceite
        date fecha_dekra
        date fecha_venc_peso_dim
        date fecha_venc_extintor
        text num_tarjeta_circulacion
        text encargado_camion
        text tipo_vehiculo
        bool es_pesado
        text estado
        text observaciones_generales
        text firma_conductor
        text firma_coordinador
        json fotos
        json fotos_detalle
        numeric puntaje
        int total_items
        int items_buenos
        int items_malos
        int items_na
    }
    auditoria_items {
        uuid id
        uuid auditoria_id
        uuid rubrica_id
        text item_slug
        text item_label
        text categoria
        text resultado
        text observacion
        json fotos
    }
    vehiculos {
        uuid id
        text marca
        text modelo
        text placa
        text type
        int km_actual
    }
    auditorias ||--o{ auditoria_items : contiene
    auditoria_rubrica ||--o{ auditoria_items : define
    vehiculos ||--o{ auditorias : recibe
```

`resultado` de cada ítem: `buen`, `mal` o `na`. Los `na` se excluyen del denominador del puntaje. `estado` de la auditoría: la app siempre inserta `Completada`; `Borrador` existe solo como default del modelo.

## 6.2 Crear una auditoría

Fuente: [auditoria_form_screen.dart](../lib/screens/auditorias/auditoria_form_screen.dart), [auditoria_service.dart:57-82](../lib/services/auditoria_service.dart#L57-L82).

```mermaid
sequenceDiagram
    autonumber
    actor U as Auditor
    participant UI as AuditoriaFormScreen
    participant Svc as AuditoriaService
    participant DB as Supabase flotilla
    participant Storage as Supabase Storage

    UI->>Svc: getRubrica()
    Svc->>DB: auditoria_rubrica.eq(activo, true).order(orden)
    UI->>Svc: getVehiculos()
    Svc->>DB: vehiculos (id, marca, modelo, placa, type, km_actual)
    UI->>UI: _rebuildItems(): omite solo_pesados si es_pesado == false

    rect rgb(235, 245, 255)
        Note over UI: PASO 1 · Datos
        U->>UI: vehículo (pre-llena km_actual), ¿es pesado?, km, tarjeta, encargado, fechas (aceite, Dekra, peso/dim, extintor)
        UI->>UI: al togglear "pesado" → _rebuildItems()
    end

    rect rgb(240, 255, 240)
        Note over UI: PASO 2 · Inspección
        loop cada categoría / ítem
            U->>UI: buen / mal / na
            opt mal
                U->>UI: observación
            end
            opt fotos del ítem
                U->>UI: cámara (quality 70)
            end
        end
        UI->>UI: puntaje preview = buenos / (total - na) × 100
    end

    rect rgb(255, 245, 235)
        Note over UI: PASO 3 · Cierre
        U->>UI: fotos generales, fotos de detalle con nota, observaciones, firma conductor, firma coordinador (texto)
        U->>UI: Guardar
        opt fotos generales
            UI->>Svc: subirFotos(files)
            Svc->>Storage: fotos_registro_vehiculos/auditorias/{µs}_{i}.ext
        end
        loop cada ítem con fotos
            UI->>Svc: subirFotos(files) → item.fotos = urls
        end
        opt fotos de detalle
            UI->>Svc: subirFotos(files) → FotoDetalle{url, nota}
        end
        UI->>Svc: crearAuditoria(cabecera {estado: 'Completada'}, items)
        Svc->>DB: INSERT auditorias returning id
        Svc->>DB: INSERT auditoria_items (lote)
        Svc->>DB: RPC recompute_auditoria(p_auditoria_id)
        Note over DB: calcula puntaje, total_items,<br/>items_buenos, items_malos, items_na
        Svc-->>UI: ok
        UI->>U: "Auditoría guardada" → pop(true) → lista recarga
    end
```

## 6.3 Lista y detalle

```mermaid
sequenceDiagram
    autonumber
    participant List as AuditoriasListScreen
    participant Svc as AuditoriaService
    participant DB as Supabase flotilla
    participant Det as AuditoriaDetailScreen

    List->>Svc: getMisAuditorias(auditorId, verTodas: isRoleAdmin)
    alt isRoleAdmin
        Svc->>DB: auditorias.order(fecha_auditoria desc).limit(100)
    else
        Svc->>DB: auditorias.eq(auditor_id).order(...).limit(100)
    end
    Svc->>DB: vehiculos.inFilter(id, ids) → _vehCache (estático)
    Svc-->>List: lista con puntaje coloreado (≥90 verde, ≥70 naranja, resto rojo)
    List->>Det: tap (pasa la cabecera completa)
    Det->>Svc: getItems(auditoriaId)
    Svc->>DB: auditoria_items.eq(auditoria_id)
    Det->>Svc: vehiculoInfo(vehiculoId) desde _vehCache
    Note over Det: si se entra sin pasar por la lista<br/>el cache está vacío y muestra "Vehículo"
```

Solo los usuarios con rol admin ven todas las auditorías. Un usuario con permiso `auditorias` pero sin rol admin ve únicamente las suyas.
