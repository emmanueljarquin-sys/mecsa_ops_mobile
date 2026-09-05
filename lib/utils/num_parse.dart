// Parseo numérico tolerante a locale: acepta coma o punto como decimal, con o sin
// separador de miles. Evita los crashes de `double.parse` con montos/kilometrajes
// escritos en formato español (ej. "1.000,50", "1000,50", "1000.50").
// Si el texto es inválido, devuelve `fallback` en vez de lanzar excepción.
double parseNum(String? s, [double fallback = 0]) {
  if (s == null) return fallback;
  var t = s.trim();
  if (t.isEmpty) return fallback;
  final lc = t.lastIndexOf(',');
  final ld = t.lastIndexOf('.');
  if (lc > -1 && ld > -1) {
    // Tiene ambos separadores → el ÚLTIMO es el decimal.
    t = (lc > ld)
        ? t.replaceAll('.', '').replaceAll(',', '.') // 1.000,50 → 1000.50
        : t.replaceAll(',', '');                     // 1,000.50 → 1000.50
  } else if (lc > -1) {
    t = t.replaceAll(',', '.');                      // 1000,50  → 1000.50
  }
  return double.tryParse(t) ?? fallback;
}

// Coacciona cualquier valor de JSON (num, String, null) a double sin reventar.
// Úsalo en los `fromJson` en vez de `(json['x'] as num).toDouble()`, que lanza
// si el valor viene null o como texto (una sola fila mala tumbaba toda la lista).
double toDoubleSafe(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return parseNum(v.toString(), fallback);
}

// Coacciona cualquier valor de JSON (num, String, null) a int sin reventar.
int toIntSafe(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? parseNum(v.toString(), fallback.toDouble()).round();
}

// ¿El texto representa un número válido? (para validadores de formulario)
bool isNum(String? s) {
  if (s == null || s.trim().isEmpty) return false;
  var t = s.trim();
  final lc = t.lastIndexOf(','), ld = t.lastIndexOf('.');
  if (lc > -1 && ld > -1) {
    t = (lc > ld) ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
  } else if (lc > -1) {
    t = t.replaceAll(',', '.');
  }
  return double.tryParse(t) != null;
}
