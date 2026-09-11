# 2. Arranque y autenticación

## 2.1 Arranque de la app

Fuente: [main.dart](../lib/main.dart), [app_provider.dart:202-253](../lib/providers/app_provider.dart#L202-L253), [home_screen.dart:188-244](../lib/screens/home_screen.dart#L188-L244). Lado servidor: `MecsaOPS/api/check_version.php`, que solo devuelve el contenido de `api/app_version.json` sin tocar la base de datos.

```mermaid
sequenceDiagram
    autonumber
    participant OS as Sistema
    participant Main as main.dart
    participant Supabase
    participant Firebase
    participant Offline as OfflineService
    participant Provider as AppProvider
    participant PHP as API PHP
    participant Home as HomeScreen

    OS->>Main: runApp
    Main->>Main: initializeDateFormatting('es_MX')
    Main->>Supabase: Supabase.initialize(url, anonKey)
    Main->>Firebase: Firebase.initializeApp()
    alt Firebase falla
        Firebase-->>Main: excepción → firebaseAvailable = false
    else ok
        Main->>Firebase: onBackgroundMessage(handler)
    end
    Main->>Offline: init()
    Note over Offline: crea offline_photos/, carga cola<br/>de SharedPreferences, escucha conectividad,<br/>flush() inicial
    Main->>Provider: new AppProvider(firebaseAvailable)
    Provider->>Supabase: auth.onAuthStateChange.listen
    opt firebaseAvailable
        Provider->>Provider: _initNotifications()
        Note over Provider: _saveFcmToken() corre aquí pero<br/>currentEmployeeId aún es null
    end
    Provider->>Provider: _loadGpsPreferences()
    Provider->>PHP: GET check_version.php
    PHP-->>Provider: min_version_code, update_url, force_update, message
    Note over PHP: lee api/app_version.json, sin BD.<br/>La comparación la hace el cliente.
    Provider->>Provider: fetchData()
    Main->>Main: Consumer de AppProvider
    alt auth.currentUser == null
        Main->>OS: muestra LoginScreen
    else sesión persistida
        Main->>Home: muestra HomeScreen
        Note over Home: no se re-evalúa MFA en este camino
        alt forceUpdate && updateUrl
            Home->>OS: pantalla bloqueante "Actualización requerida"
        else updateUrl sin forzar
            Home->>OS: diálogo opcional (una vez)
        end
    end
```

### `fetchData()` en detalle

```mermaid
sequenceDiagram
    autonumber
    participant Provider as AppProvider
    participant Supabase

    Provider->>Provider: isLoading = true
    par siempre, incluso sin sesión
        Provider->>Supabase: cms.departamento (id, nombre, id_empresa)
        Provider->>Supabase: public.Empresas (id, nombre_comercial)
    end
    alt user == null
        Provider-->>Provider: return (finally: isLoading=false)
    end
    Provider->>Supabase: public.Empleados ilike(email) maybeSingle
    alt activo == false
        Provider->>Supabase: auth.signOut()
        Provider-->>Provider: throw "Cuenta desactivada"
    end
    Provider->>Supabase: viaticos_responsables_departamento eq(empleado_id)
    Provider->>Supabase: rol_permisos eq(rol_nombre)
    Note over Provider: calcula isRoleAdmin, isContabilidad,<br/>_sistemas, _allowedViews, isResponsable
    par en paralelo
        Provider->>Supabase: flotilla.vehiculos
        Provider->>Supabase: viaticos.liquidaciones eq(empleado_id)
        Provider->>Supabase: visitas.visitas eq(empleado_id)
        Provider->>Supabase: proyectos.projects
        Provider->>Supabase: flotilla.reservas + vehiculos(*) eq(empleado_id)
        Provider->>Supabase: public.Empleados (id, nombre, apellido)
        Provider->>Supabase: visitas.vehiculos_personales eq(empleado_id)
    end
    Note over Provider: _fetchFlotilla y _fetchViaticos hacen rethrow;<br/>el resto traga errores
    Provider->>Provider: isLoading = false, notifyListeners
    Provider->>Supabase: Realtime channel liquidaciones_user_{id}
```

> **Sin verificación de conectividad al arrancar.** La app no hace ping ni health-check. Simplemente intenta las llamadas y, si fallan, muestra "Error de conexión". `check_version.php` y `fetchData` no tienen timeout. Ver [Observaciones](10-observaciones.md).

## 2.2 Login

Fuente: [login_screen.dart:605-686](../lib/screens/login_screen.dart#L605-L686), [app_provider.dart:340-376](../lib/providers/app_provider.dart#L340-L376).

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant UI as LoginScreen
    participant Provider as AppProvider
    participant Supabase
    participant Mfa as MfaService

    U->>UI: email + password
    UI->>Provider: signIn(email, password)
    Provider->>Supabase: auth.signInWithPassword
    Supabase-->>Provider: session (AAL1)
    Note over Provider,Supabase: el listener onAuthStateChange(signedIn)<br/>dispara fetchData() en paralelo
    Provider->>Supabase: Empleados.select('activo').ilike(email)
    alt activo == false
        Provider->>Supabase: auth.signOut()
        Provider-->>UI: false + errorMessage "pendiente de activación"
    else activo
        Provider-->>UI: true
        UI->>Mfa: evaluateAfterLogin()
        Mfa-->>UI: MfaNextStep
        alt ready
            UI->>UI: pushReplacement HomeScreen
        else challenge
            UI->>UI: pushReplacement MfaChallengeScreen
        else enrollForced / enrollOptional
            UI->>UI: pushReplacement MfaEnrollScreen(forced)
        end
    end
```

## 2.3 Registro de cuenta

Fuente: [app_provider.dart:405-495](../lib/providers/app_provider.dart#L405-L495). Servidor: `MecsaOPS/api/register_employee_mobile.php`.

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant UI as LoginScreen
    participant Provider as AppProvider
    participant Supabase
    participant PHP as register_employee_mobile.php
    participant DB as Supabase (service_role)

    U->>UI: nombre, apellido, email, teléfono, empresa, departamento, foto opcional
    Note over UI: empresas y departamentos ya vienen<br/>de fetchData() sin sesión
    UI->>Provider: signUp(...)
    Provider->>Supabase: auth.signUp(email, password, data: full_name)
    Supabase-->>Provider: user.id
    opt foto
        Provider->>Supabase: Storage empleados/temp_registration/register_{uid}_{ms}.ext
        Supabase-->>Provider: publicUrl (si falla, sigue sin foto)
    end
    Provider->>PHP: POST {id_user, nombre, apellido, email, telefono, departamento, empresa_id, photo}
    PHP->>PHP: valida id_user, nombre, email, empresa_id
    PHP->>DB: GET Empleados?codigo_empleado=like.GM-*&order=id.desc&limit=1
    PHP->>PHP: genera codigo_empleado GM-{n+1}
    PHP->>DB: INSERT public.Empleados {rol:'empleado', activo:false, sistemas_acceso:[], tenant_id: empresa_id}
    alt duplicate key
        PHP-->>Provider: 500 "Este correo ya está registrado"
        Provider->>Supabase: auth.signOut()
        Provider-->>UI: throw error
    else ok
        PHP-->>Provider: {success, codigo_empleado}
        Provider->>Supabase: auth.signOut()
        Provider-->>UI: ok
        UI->>U: "Cuenta creada. Pendiente de confirmación por un administrador"
    end
    Note over DB: la activación la hace un admin<br/>desde la web (approve_employee.php)
```

### Recuperar contraseña

`POST request_password_reset.php {email}` ([app_provider.dart:378-403](../lib/providers/app_provider.dart#L378-L403)). El servidor genera un enlace de recuperación con `auth/v1/admin/generate_link` y lo envía por SMTP propio. Si el SMTP falla, cae a `auth/v1/recover` para que Supabase envíe el correo. Siempre responde `success: true` para no revelar si el email existe.

## 2.4 MFA TOTP

Fuente: [mfa_service.dart](../lib/services/mfa_service.dart), [mfa_enroll_screen.dart](../lib/screens/mfa_enroll_screen.dart), [mfa_challenge_screen.dart](../lib/screens/mfa_challenge_screen.dart), [mfa_backup_codes_screen.dart](../lib/screens/mfa_backup_codes_screen.dart). Servidor: `MecsaOPS/api/mfa/backup_codes_generate.php`, `backup_code_verify.php`, `_bearer.php`.

### Decisión después del login

```mermaid
flowchart TD
    A["evaluateAfterLogin()"] --> B["auth.mfa.listFactors()"]
    B --> C{"¿factor TOTP<br/>verified?"}
    C -->|sí| D["getAuthenticatorAssuranceLevel()"]
    D --> E{"currentLevel == aal2"}
    E -->|sí| R["ready → Home"]
    E -->|no| CH["challenge → MfaChallengeScreen"]
    C -->|no| F["RPC mfa_must_enroll(p_user_id)"]
    F --> G{"true?"}
    G -->|sí| EF["enrollForced → MfaEnrollScreen(forced)"]
    G -->|no| EO["enrollOptional → MfaEnrollScreen"]
    B -.->|cualquier excepción| R
    F -.->|cualquier excepción| R
```

> El periodo de gracia **no vive en la app**. Lo decide la RPC `mfa_must_enroll` en Postgres, que compara `Empleados.mfa_grace_until` con la fecha actual. Un admin puede reiniciarlo a 14 días con `mfa_admin_reset_user` desde la web. Si la RPC falla, la app deja pasar al usuario.

### Enrolamiento

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant UI as MfaEnrollScreen
    participant Mfa as MfaService
    participant Auth as Supabase Auth
    participant PHP as backup_codes_generate.php
    participant DB as public.mfa_backup_codes
    participant BK as MfaBackupCodesScreen

    UI->>Mfa: enrollStart()
    Mfa->>Auth: listFactors()
    loop factores TOTP unverified
        Mfa->>Auth: mfa.unenroll(id)
    end
    Mfa->>Auth: mfa.enroll(totp, 'MecsaOPS Mobile')
    Auth-->>Mfa: factorId, qrCode svg, secret, uri
    Mfa-->>UI: muestra QR (SvgPicture) y secret copiable
    U->>UI: código de 6 dígitos
    UI->>Mfa: enrollVerify(factorId, code)
    Mfa->>Auth: mfa.challenge(factorId)
    Mfa->>Auth: mfa.verify(factorId, challengeId, code)
    Note over Auth: sesión promovida a AAL2
    Mfa->>PHP: POST (Authorization: Bearer accessToken, sin body)
    PHP->>Auth: GET /auth/v1/user (valida el JWT, obtiene uid)
    PHP->>PHP: genera 8 códigos XXXX-XXXX, bcrypt cost 10
    PHP->>DB: DELETE where user_id = uid
    PHP->>DB: INSERT 8 filas {user_id, code_hash}
    PHP-->>Mfa: {success, codigos[]} en claro, una sola vez
    Mfa-->>UI: codigos
    UI->>BK: pushReplacement(codigos)
    BK->>U: grilla de códigos, copiar, checkbox "los guardé"
    U->>BK: confirmar
    BK->>BK: pushAndRemoveUntil HomeScreen
```

### Desafío al iniciar sesión

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant UI as MfaChallengeScreen
    participant Mfa as MfaService
    participant Auth as Supabase Auth
    participant PHP as backup_code_verify.php
    participant DB as Postgres

    alt código TOTP (6 dígitos)
        U->>UI: 123456
        UI->>Mfa: challengeVerify(code)
        Mfa->>Auth: listFactors → factor totp verified
        Mfa->>Auth: mfa.challenge(factorId)
        Mfa->>Auth: mfa.verify(factorId, challengeId, code)
        Auth-->>Mfa: sesión AAL2
    else código de respaldo (XXXX-XXXX)
        U->>UI: A1B2-C3D4
        UI->>Mfa: backupCodeVerify(code)
        Mfa->>PHP: POST {backup_code} (Bearer accessToken)
        PHP->>Auth: GET /auth/v1/user → uid
        PHP->>DB: RPC mfa_consume_backup_code(p_user_id, p_code_plain, p_ip)
        Note over DB: compara bcrypt, marca el código como usado (atómico)
        alt false
            PHP-->>Mfa: 400 "Código de respaldo inválido o ya usado"
        else true
            PHP->>DB: PATCH Empleados set mfa_grace_until = now + 24h
            Note over DB: fuerza re-enrolar el TOTP en 1 día
            PHP-->>Mfa: {success, grace_until}
        end
    end
    UI->>UI: pushAndRemoveUntil HomeScreen
```

## 2.5 Notificaciones push (FCM)

Fuente app: [app_provider.dart:295-338](../lib/providers/app_provider.dart#L295-L338), [home_screen.dart:58-137](../lib/screens/home_screen.dart#L58-L137). Servidor: `MecsaOPS/api/fcm_v1_helper.php`, `pago_visita.php`, `approve_liquidacion.php`.

El servidor envía push desde dos endpoints. Solo uno de ellos incluye datos que la app interpreta:

| Endpoint | Cuándo | `notification` | `data` extra | La app lo usa |
|----------|--------|----------------|--------------|---------------|
| `pago_visita.php` | Admin confirma pago de kilometraje desde la web | "✅ Pago de Kilometraje Confirmado" | `tipo: pago_kilometraje`, `visita_id` | Sí: banner y navegación al detalle |
| `approve_liquidacion.php` | Admin aprueba o rechaza una liquidación | "Liquidación Aprobada/Rechazada" | ninguno | Solo se muestra la notificación del sistema |

```mermaid
sequenceDiagram
    autonumber
    participant Provider as AppProvider
    participant FCM
    participant Supabase
    participant Home as HomeScreen
    participant PHP as pago_visita.php
    participant Helper as fcm_v1_helper.php

    Note over Provider: _initNotifications() al arrancar (si Firebase ok)
    Provider->>Provider: flutter_local_notifications.initialize
    Provider->>Provider: requestNotificationsPermission (Android 13+)
    Provider->>FCM: getToken()
    FCM-->>Provider: token
    Provider->>Supabase: Empleados.update({fcm_token}).eq(id, currentEmployeeId)
    Note over Provider: solo si currentEmployeeId != null

    Note over PHP: admin sube comprobante en la web
    PHP->>Supabase: Storage facturas_viaticos/pago_{ts}_{nombre}
    PHP->>Supabase: PATCH visitas.visitas {pago_kilometraje: true, fecha_pago, comprobante_pago, pago_reportado_por}
    PHP->>Supabase: GET visitas.visitas.empleado_id → GET Empleados.fcm_token
    PHP->>Helper: sendFCMV1Notification(token, título, cuerpo, {tipo, visita_id})
    Helper->>Helper: JWT RS256 con firebase_key.json → access_token OAuth
    Helper->>FCM: POST v1/projects/{id}/messages:send
    alt app en primer plano
        FCM->>Home: onMessage
        Home->>Home: MaterialBanner "¡Tu pago fue confirmado!" VER / CERRAR
    else app en segundo plano, usuario toca
        FCM->>Home: onMessageOpenedApp
        Home->>Home: setIndex(3) + push VisitaDetailScreen
    else app cerrada
        FCM->>Home: getInitialMessage()
        Home->>Home: setIndex(3) + push VisitaDetailScreen
    end
```

## 2.6 Realtime de liquidaciones

Fuente: [app_provider.dart:1596-1667](../lib/providers/app_provider.dart#L1596-L1667).

Este es el segundo mecanismo por el que el empleado se entera de que su liquidación fue aprobada o rechazada. Funciona aunque el push FCM no llegue, porque escucha el cambio de fila directamente.

```mermaid
sequenceDiagram
    autonumber
    participant Provider as AppProvider
    participant RT as Supabase Realtime
    participant DB as viaticos.liquidaciones
    participant Local as flutter_local_notifications

    Note over Provider: al terminar fetchData() con sesión
    Provider->>RT: channel('public:liquidaciones_user_{id}')
    Provider->>RT: onPostgresChanges(UPDATE, schema viaticos, table liquidaciones, filter empleado_id = id)
    RT-->>Provider: subscribed

    DB-->>RT: UPDATE (approve_liquidacion.php cambió estado)
    RT->>Provider: payload.newRecord
    alt estado == 'aprobada' || 'rechazada'
        Provider->>Local: show("IMPORTANTE", "Tu liquidación ha sido {estado}") canal channel_liquidaciones
        Provider->>DB: re-consulta liquidaciones del empleado
        Provider->>Provider: notifyListeners
    else otro estado (Correccion Solicitada, Corregido)
        Provider->>Provider: ignora
    end

    Note over Provider: en signedOut → removeChannel
```
