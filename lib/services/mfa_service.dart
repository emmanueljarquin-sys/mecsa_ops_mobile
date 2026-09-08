import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado de evaluar el estado MFA tras un login con password.
enum MfaNextStep {
  /// Usuario tiene factor TOTP verified — debe ingresar código antes de continuar.
  challenge,

  /// Usuario sin factor y su grace_period venció — enroll obligatorio.
  enrollForced,

  /// Usuario sin factor, dentro del grace — puede continuar pero conviene activar.
  enrollOptional,

  /// Sin pendientes — login completo.
  ready,
}

/// Servicio centralizado para MFA en Flutter.
/// Encapsula listFactors, enroll, challenge, verify + backup codes (vía endpoint PHP).
class MfaService {
  MfaService(this._supabase);

  final SupabaseClient _supabase;

  // Endpoint base de los APIs PHP para backup codes / admin reset
  static const String _apiBase = 'https://grupomecsa.net/ops/api/mfa';

  /// Decide el próximo paso tras un signInWithPassword exitoso.
  Future<MfaNextStep> evaluateAfterLogin() async {
    try {
      final factors = await _supabase.auth.mfa.listFactors();
      final verifiedTotp = factors.all.where((f) =>
          f.factorType == FactorType.totp && f.status == FactorStatus.verified);

      if (verifiedTotp.isNotEmpty) {
        // ¿La sesión ya está en AAL2? (puede pasar si hubo refresh).
        final aal = _supabase.auth.mfa.getAuthenticatorAssuranceLevel();
        if (aal.currentLevel == AuthenticatorAssuranceLevels.aal2) {
          return MfaNextStep.ready;
        }
        return MfaNextStep.challenge;
      }

      // Sin factor verified → consultar RPC mfa_must_enroll
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return MfaNextStep.ready;

      final res = await _supabase.rpc('mfa_must_enroll',
          params: {'p_user_id': uid});
      if (res == true) return MfaNextStep.enrollForced;

      return MfaNextStep.enrollOptional;
    } catch (e) {
      // Si falla la consulta, no bloqueamos el login.
      return MfaNextStep.ready;
    }
  }

  /// Inicia el enroll TOTP. Devuelve {factorId, qrCode (svg), secret, uri}.
  /// Si ya existe un factor `unverified`, lo borra antes de crear uno nuevo.
  Future<({String factorId, String? qrCode, String? secret, String? uri})>
      enrollStart() async {
    final mfa = _supabase.auth.mfa;
    final factors = await mfa.listFactors();
    for (final f in factors.all) {
      if (f.factorType == FactorType.totp && f.status == FactorStatus.unverified) {
        await mfa.unenroll(f.id);
      }
    }

    final res = await mfa.enroll(
      factorType: FactorType.totp,
      friendlyName: 'MecsaOPS Mobile',
    );

    return (
      factorId: res.id,
      qrCode: res.totp?.qrCode,
      secret: res.totp?.secret,
      uri: res.totp?.uri,
    );
  }

  /// Verifica el primer código TOTP del enroll. Si es correcto, promueve la
  /// sesión a AAL2 y solicita al backend PHP generar los 8 backup codes.
  /// Devuelve la lista de códigos en texto plano (mostrar UNA vez).
  Future<List<String>> enrollVerify({
    required String factorId,
    required String code,
  }) async {
    final challenge = await _supabase.auth.mfa.challenge(factorId: factorId);
    await _supabase.auth.mfa.verify(
      factorId: factorId,
      challengeId: challenge.id,
      code: code,
    );

    // Generar backup codes a través del endpoint PHP (BD valida y hashea)
    // Reutilizamos enroll_verify.php pero ya con factor verified envía un código real,
    // así que mejor llamamos a un endpoint específico de backup que sí tenemos:
    // backup_codes_generate.php (ver server-side).
    final accessToken = _supabase.auth.currentSession?.accessToken ?? '';
    final res = await http.post(
      Uri.parse('$_apiBase/backup_codes_generate.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (res.statusCode != 200) {
      throw "No se pudieron generar los códigos de respaldo (HTTP ${res.statusCode})";
    }
    final j = json.decode(res.body) as Map<String, dynamic>;
    if (j['success'] != true) throw j['error']?.toString() ?? 'Error desconocido';
    return List<String>.from(j['codigos'] ?? []);
  }

  /// Verifica un código TOTP en el challenge post-login.
  /// Lanza si es incorrecto.
  Future<void> challengeVerify({required String code}) async {
    final factors = await _supabase.auth.mfa.listFactors();
    final verified = factors.all.firstWhere(
      (f) => f.factorType == FactorType.totp && f.status == FactorStatus.verified,
      orElse: () => throw "No hay factor TOTP activo",
    );

    final challenge =
        await _supabase.auth.mfa.challenge(factorId: verified.id);
    await _supabase.auth.mfa.verify(
      factorId: verified.id,
      challengeId: challenge.id,
      code: code,
    );
  }

  /// Verifica un código de respaldo. Solo el backend valida el bcrypt
  /// contra public.mfa_backup_codes y promueve la sesión.
  Future<void> backupCodeVerify({required String backupCode}) async {
    final accessToken = _supabase.auth.currentSession?.accessToken ?? '';
    final res = await http.post(
      Uri.parse('$_apiBase/backup_code_verify.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: json.encode({'backup_code': backupCode.toUpperCase()}),
    );
    if (res.statusCode != 200) {
      final j = (() {
        try { return json.decode(res.body) as Map<String, dynamic>; }
        catch (_) { return <String, dynamic>{}; }
      })();
      throw j['error']?.toString() ?? 'Código de respaldo inválido';
    }
  }
}
