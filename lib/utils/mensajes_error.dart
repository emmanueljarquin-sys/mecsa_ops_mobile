// =============================================================================
// mensajes_error.dart — Traduce excepciones a mensajes para el usuario
// -----------------------------------------------------------------------------
// Uso:
//   errorMessage = mensajeError(e, accion: 'crear la reserva');
//   → "No se pudo crear la reserva. Sin conexión a internet. Revisa tu red e
//      intenta de nuevo."
//
// Reglas:
// - Un `String` lanzado a propósito (throw "Tu cuenta está bloqueada…") ya es
//   un mensaje para el usuario: se devuelve tal cual.
// - Errores de red, timeout, sesión, permisos y duplicados tienen texto fijo
//   en español, sin volcar la excepción cruda.
// - Lo demás se limpia (se quita "Exception:", URIs, JSON) y se recorta.
// El detalle técnico completo sigue yendo al log (AppLogger), no a pantalla.
// =============================================================================
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const String kMsgSinConexion =
    'Sin conexión a internet. Revisa tu red e intenta de nuevo.';
const String kMsgTimeout =
    'El servidor tardó demasiado en responder. Revisa tu conexión e intenta de nuevo.';
const String kMsgSesion =
    'Tu sesión expiró. Vuelve a iniciar sesión.';
const String kMsgPermiso =
    'No tienes permiso para realizar esta acción.';
const String kMsgServidor =
    'El servidor no pudo procesar la solicitud. Intenta de nuevo en unos minutos.';

/// Devuelve un mensaje corto y entendible. [accion] describe lo que se
/// intentaba ("crear la reserva", "guardar la visita"); si se da, el mensaje
/// empieza con "No se pudo <accion>."
String mensajeError(Object? e, {String? accion}) {
  final detalle = _detalle(e);
  if (accion == null || accion.isEmpty) return detalle;
  // Los mensajes de negocio lanzados como String ya son autoexplicativos.
  if (e is String) return detalle;
  return 'No se pudo $accion. $detalle';
}

/// true si el error es de red/timeout (útil para decidir si encolar).
bool esErrorDeRed(Object? e) {
  if (e is SocketException || e is TimeoutException || e is http.ClientException) {
    return true;
  }
  if (e is AuthRetryableFetchException) return true;
  final s = e.toString();
  return s.contains('Failed host lookup') ||
      s.contains('Network is unreachable') ||
      s.contains('Connection refused') ||
      s.contains('Connection reset') ||
      s.contains('Connection closed') ||
      s.contains('SocketException') ||
      s.contains('ClientException');
}

String _detalle(Object? e) {
  if (e == null) return kMsgServidor;
  if (e is String) return e.trim();

  if (e is TimeoutException) return kMsgTimeout;
  if (esErrorDeRed(e)) return kMsgSinConexion;

  if (e is AuthException) return _auth(e);
  if (e is PostgrestException) return _postgrest(e);
  if (e is StorageException) return _storage(e);
  if (e is FormatException) {
    return 'El servidor devolvió una respuesta inesperada. Intenta de nuevo.';
  }

  return _limpiar(e.toString());
}

String _auth(AuthException e) {
  final m = e.message.toLowerCase();
  final code = e.statusCode ?? '';
  if (m.contains('invalid login credentials') || m.contains('invalid_credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (m.contains('email not confirmed')) {
    return 'Debes confirmar tu correo antes de iniciar sesión.';
  }
  if (m.contains('already registered') || m.contains('already exists')) {
    return 'Ya existe una cuenta con ese correo.';
  }
  if (m.contains('rate limit') || m.contains('too many') || code == '429') {
    return 'Demasiados intentos. Espera unos minutos e intenta de nuevo.';
  }
  if (m.contains('password') && (m.contains('short') || m.contains('at least'))) {
    return 'La contraseña es muy corta (mínimo 6 caracteres).';
  }
  if (m.contains('invalid') && m.contains('email')) {
    return 'El correo no tiene un formato válido.';
  }
  if (m.contains('refresh token') || m.contains('jwt') || m.contains('expired') ||
      code == '401' || code == '403') {
    return kMsgSesion;
  }
  if (code.startsWith('5')) return kMsgServidor;
  return 'No se pudo validar tu cuenta. ${_limpiar(e.message)}';
}

String _postgrest(PostgrestException e) {
  final code = e.code ?? '';
  final m = e.message.toLowerCase();
  if (code == 'PGRST301' || code == '401' || m.contains('jwt')) return kMsgSesion;
  if (code == '42501' || m.contains('row-level security') || m.contains('permission denied')) {
    return kMsgPermiso;
  }
  if (code == '23505' || m.contains('duplicate key')) {
    return 'Ya existe un registro igual. Revisa que no lo hayas enviado antes.';
  }
  if (code == '23503' || m.contains('foreign key')) {
    return 'El registro hace referencia a datos que ya no existen. Actualiza la pantalla e intenta de nuevo.';
  }
  if (code == '23502' || m.contains('not-null')) {
    return 'Falta un dato obligatorio. Revisa el formulario.';
  }
  if (code == 'PGRST116') {
    return 'No se encontró el registro. Puede que otro usuario lo haya modificado.';
  }
  if (code.startsWith('5') || code == '503') return kMsgServidor;
  return 'El servidor rechazó la operación: ${_limpiar(e.message)}';
}

String _storage(StorageException e) {
  final code = e.statusCode ?? '';
  final m = e.message.toLowerCase();
  if (code == '401' || code == '403' || m.contains('row-level security')) {
    return 'No tienes permiso para subir este archivo.';
  }
  if (code == '413' || m.contains('too large') || m.contains('payload')) {
    return 'El archivo es demasiado grande. Toma la foto con menor resolución.';
  }
  return 'No se pudo subir el archivo. Revisa tu conexión e intenta de nuevo.';
}

/// Quita prefijos técnicos y ruido; recorta a un largo razonable.
String _limpiar(String s) {
  var t = s.trim();
  for (final pref in ['Exception: ', 'Bad state: ', 'Error: ']) {
    while (t.startsWith(pref)) {
      t = t.substring(pref.length).trim();
    }
  }
  // Quitar URIs y JSON largos que solo confunden.
  t = t.replaceAll(RegExp(r',?\s*uri=\S+'), '');
  t = t.replaceAll(RegExp(r'https?://\S+'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return kMsgServidor;
  if (t.length > 180) t = '${t.substring(0, 177)}…';
  // Primera letra mayúscula y punto final.
  t = t[0].toUpperCase() + t.substring(1);
  if (!RegExp(r'[.!?…]$').hasMatch(t)) t = '$t.';
  return t;
}
