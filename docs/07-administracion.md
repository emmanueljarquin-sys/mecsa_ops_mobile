# 7. Administración

Modo administración dentro de la app (desde v1.5.0). Permite a los usuarios con permisos aprobar liquidaciones y reservas, responder solicitudes de corrección y desbloquear empleados sin ir a la web.

Pantallas: [admin/](../lib/screens/admin/). Servicio: [admin_service.dart](../lib/services/admin_service.dart). Servidor: `MecsaOPS/api/approve_liquidacion.php`, `includes/resolve_current_employee.php`.

## 7.1 Quién ve qué

El botón de Administración aparece en el Dashboard si `hasAdminAccess`. El hub muestra de cero a cuatro tarjetas según los permisos calculados en el arranque (ver [Arquitectura 1.6](01-arquitectura.md#16-modelo-de-permisos)).

| Tarjeta | Permiso | Fuente del permiso |
|---------|---------|--------------------|
| Aprobar liquidaciones | `canApproveLiquidaciones` | rol admin, rol contabilidad, responsable de departamento, o `rol_permisos.aprobar_liquidaciones` |
| Aprobar reservas | `canApproveReservas` | `canViewModule('aprobar_reservas')` |
| Correcciones | `canProcesarCorrecciones` | `canViewModule('procesar_correcciones')` |
| Desbloquear reservas | `canDesbloquear` | `canViewModule('desbloquear_reservas')` |

## 7.2 Modelo de confianza con el servidor

La app móvil no tiene sesión PHP. Para las acciones que pasan por el servidor envía `actor_id` (el UUID del empleado) y el servidor **re-lee el rol desde la base de datos** con service_role. El cliente nunca declara su rol.

```mermaid
sequenceDiagram
    autonumber
    participant App as AdminService
    participant PHP as approve_liquidacion.php
    participant Res as resolve_employee_context_by_id
    participant DB as public.Empleados

    App->>PHP: PATCH {actor_id, id, estado, comentario}
    PHP->>PHP: session_start → resolve_current_employee() → sin sesión
    PHP->>Res: fallback móvil con actor_id
    Res->>DB: GET id, rol, departamento WHERE id = actor_id (service_role)
    Res-->>PHP: {empleado_id, is_admin, is_contabilidad, rol, departamento}
    Note over PHP: si no hay fila → contexto vacío → 403
```

> No se valida el JWT de Supabase en este camino. Quien conozca el UUID de un admin podría usarlo. Ver [Observaciones](10-observaciones.md).

## 7.3 Aprobar o rechazar liquidaciones

Fuente: [aprobar_liquidaciones_screen.dart](../lib/screens/admin/aprobar_liquidaciones_screen.dart), [admin_service.dart:24-140](../lib/services/admin_service.dart#L24-L140).

```mermaid
sequenceDiagram
    autonumber
    actor A as Admin
    participant UI as AprobarLiquidacionesScreen
    participant Svc as AdminService
    participant DB as Supabase DB
    participant PHP as approve_liquidacion.php
    participant Helper as fcm_v1_helper.php
    participant RT as Realtime
    participant E as App del empleado

    UI->>Svc: getPendientesParaAprobar(actorId, isAdminOrConta)
    alt admin o contabilidad
        Svc->>DB: viaticos.liquidaciones.eq(estado, 'pendiente')
    else responsable de departamento
        Svc->>DB: viaticos_responsables_departamento.eq(empleado_id) → departamento_ids
        Svc->>DB: Empleados.inFilter(departamento) → empleado_ids
        Svc->>DB: liquidaciones.eq(estado, 'pendiente').inFilter(empleado_id)
    end
    Svc->>DB: Empleados.inFilter(id) + projects.inFilter(project_id)
    Note over Svc: 2 consultas de hidratación (antes era N+1)
    Svc-->>UI: lista

    A->>UI: Aprobar / Rechazar + comentario
    UI->>Svc: aprobarLiquidacion(actorId, id, aprobar, comentario)
    Svc->>PHP: PATCH {actor_id, id, estado: 'aprobada'|'rechazada', comentario}
    PHP->>DB: resolve rol del actor (ver 7.2)
    PHP->>DB: liquidaciones.select(estado, empleado_id) → debe ser 'pendiente'
    alt actor no es admin ni contabilidad
        PHP->>DB: Empleados.departamento del dueño
        PHP->>DB: viaticos_responsables_departamento (actor, departamento)
        alt sin fila
            PHP-->>Svc: 403
        end
    end
    PHP->>DB: facturas.eq(liquidacion_id).limit(1) → debe existir ≥ 1
    PHP->>DB: PATCH liquidaciones {estado, aprobado_por: 'Sistema', fecha_aprobacion, comentario_aprobacion}
    PHP-->>Svc: {success, data}
    PHP->>DB: GET Empleados.fcm_token del dueño
    PHP->>Helper: sendFCMV1Notification(token, "Liquidación Aprobada|Rechazada", cuerpo)
    Helper->>E: push (sin data extra)
    DB-->>RT: UPDATE liquidaciones
    RT->>E: payload → notificación local + refresco
    Svc-->>UI: ok → recarga lista
```

> Desde la app móvil `aprobado_por` queda como `'Sistema'` porque el servidor lo toma de `$_SESSION['nombre']`, que no existe sin sesión web.

## 7.4 Aprobar o rechazar reservas

Fuente: [aprobar_reservas_screen.dart](../lib/screens/admin/aprobar_reservas_screen.dart), [admin_service.dart:143-205](../lib/services/admin_service.dart#L143-L205).

```mermaid
sequenceDiagram
    autonumber
    actor A as Admin
    participant UI as AprobarReservasScreen
    participant Svc as AdminService
    participant DB as Supabase flotilla

    UI->>Svc: getReservasPendientes()
    Svc->>DB: reservas.eq(estado, 'Pendiente').order(fecha_salida)
    Svc->>DB: vehiculos.inFilter(id) + Empleados.inFilter(id)
    Svc-->>UI: lista con vehículo y solicitante
    A->>UI: Aprobar / Rechazar, comentario, opcional reasignar vehículo
    UI->>Svc: decidirReserva(id, aprobar, vehiculoId, comentarios)
    Svc->>DB: UPDATE reservas {estado: 'Aprobada'|'Rechazada', comentarios, vehiculo_id?}
    Note over Svc: directo a Supabase, sin PHP,<br/>sin push al empleado
    Svc-->>UI: ok → recarga
```

## 7.5 Correcciones

Fuente: [correcciones_screen.dart](../lib/screens/admin/correcciones_screen.dart), [admin_service.dart:209-279](../lib/services/admin_service.dart#L209-L279).

```mermaid
sequenceDiagram
    autonumber
    actor A as Admin
    participant UI as CorreccionesScreen
    participant Svc as AdminService
    participant DB as Supabase DB

    UI->>Svc: getCorreccionesPendientes()
    par
        Svc->>DB: viaticos.liquidaciones WHERE solicitud_correccion NOT NULL AND respuesta_admin IS NULL
        Svc->>DB: flotilla.registros_vehiculos WHERE solicitud_correccion NOT NULL AND respuesta_admin IS NULL
    end
    Svc->>DB: Empleados.inFilter(id) para nombres
    Svc-->>UI: lista unificada con origen (viaticos / kilometraje)
    A->>UI: abre ítem, ve motivo, escribe respuesta
    UI->>Svc: procesarCorreccion(actorId, schema, table, id, respuesta)
    alt table == registros_vehiculos
        Svc->>DB: UPDATE {respuesta_admin, fecha_correccion, corregido_por, estado: 'Corregido'}
    else table == liquidaciones
        Svc->>DB: UPDATE {respuesta_admin, fecha_correccion, corregido_por}
    end
    Note over Svc: no usa procesar_correccion.php porque<br/>ese exige sesión web de admin
    Svc-->>UI: ok
```

La app **no modifica el dato corregido** (kilometraje, total). Solo registra la respuesta. La corrección real del valor la hace el admin en la web, donde `procesar_correccion.php` admite `extra_update` con campos permitidos.

## 7.6 Desbloquear reservas

Fuente: [desbloquear_reservas_screen.dart](../lib/screens/admin/desbloquear_reservas_screen.dart), [admin_service.dart:282-306](../lib/services/admin_service.dart#L282-L306).

```mermaid
sequenceDiagram
    autonumber
    actor A as Admin
    participant UI as DesbloquearReservasScreen
    participant Svc as AdminService
    participant DB as public.Empleados

    UI->>Svc: getEmpleadosBloqueados()
    Svc->>DB: SELECT id, nombre, apellido, reservas_bloqueado, sistemas_acceso WHERE reservas_bloqueado = true
    A->>UI: Desbloquear
    UI->>Svc: desbloquearEmpleado(id)
    Svc->>DB: SELECT sistemas_acceso
    Svc->>Svc: agrega 'RESERVAS_EXCEPCION' si no está
    Svc->>DB: UPDATE {reservas_bloqueado: false, sistemas_acceso}
    Note over Svc: la web además cancela las reservas<br/>Pendiente vencidas; la app no
    Svc-->>UI: ok
```

## 7.7 Comparación app vs web

| Acción | App móvil | Web (MecsaOPS) | Diferencia |
|--------|-----------|----------------|------------|
| Aprobar liquidación | `approve_liquidacion.php` con `actor_id` | Mismo endpoint con sesión | `aprobado_por` = 'Sistema' desde la app |
| Aprobar reserva | UPDATE directo | UPDATE directo | Ninguna |
| Procesar corrección | UPDATE directo, solo respuesta | `procesar_correccion.php` con `extra_update` | La web puede corregir el valor |
| Desbloquear | UPDATE directo | `toggle_reservas_bloqueo.php` | La web cancela reservas vencidas |
