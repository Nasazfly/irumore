import 'dart:math';
import 'dart:typed_data';

// Biquad della ponderazione A a 48 kHz (trasformazione bilineare, normalizzata a 0 dB a 1 kHz).
const _sos = [
  [0.2341830426035607, 0.4683660852071214, 0.2341830426035607, -0.22455845805977914, 0.012606625271546396],
  [1.0, -2.0, 1.0, -1.8938704947230707, 0.8951597690946617],
  [1.0, -2.0, 1.0, -1.9946144559930215, 0.9946217070140843],
];

class LevelMeter {
  static const fs = 48000;
  static const base = 120.0; // dB equivalenti al fondo scala digitale, prima dell'offset di taratura
  static final double alpha = 1 - exp(-1 / (fs * 1.0)); // Slow: tau = 1 s

  final _z1 = [0.0, 0.0, 0.0];
  final _z2 = [0.0, 0.0, 0.0];
  Uint8List? _carry;
  int _skip = fs ~/ 2;
  bool _init = false;
  double slowP = 0;
  double sumSq = 0;
  int n = 0;
  double secSq = 0;
  int secN = 0;
  final las = <double>[]; // LAS campionato ogni secondo (valori grezzi, senza offset)
  double maxRaw = -1e9, minRaw = 1e9;
  int clipCount = 0;
  DateTime? lastClip;

  void reset() {
    for (var i = 0; i < 3; i++) {
      _z1[i] = 0;
      _z2[i] = 0;
    }
    _carry = null;
    _skip = fs ~/ 2;
    _init = false;
    slowP = 0;
    sumSq = 0;
    n = 0;
    secSq = 0;
    secN = 0;
    las.clear();
    maxRaw = -1e9;
    minRaw = 1e9;
    clipCount = 0;
    lastClip = null;
  }

  static double _db(double p) => p <= 1e-20 ? -200.0 : 10 * log(p) / ln10;

  bool get hasData => _init && las.isNotEmpty;
  bool get started => _init;
  int get seconds => las.length;

  double lasNow(double off) => _init ? _db(slowP) + base + off : double.nan;
  double laeq(double off) => n > 0 ? _db(sumSq / n) + base + off : double.nan;
  double lasMax(double off) => las.isEmpty ? double.nan : maxRaw + base + off;
  double lasMin(double off) => las.isEmpty ? double.nan : minRaw + base + off;
  List<double> series(double off) => [for (final v in las) v + base + off];

  void process(Uint8List input) {
    var bytes = input;
    if (_carry != null) {
      bytes = Uint8List.fromList([..._carry!, ...bytes]);
      _carry = null;
    }
    if (bytes.lengthInBytes.isOdd) {
      _carry = bytes.sublist(bytes.lengthInBytes - 1);
      bytes = bytes.sublist(0, bytes.lengthInBytes - 1);
    }
    final bd = ByteData.sublistView(bytes);
    final cnt = bytes.lengthInBytes ~/ 2;
    final e = Float64List(cnt);
    for (var i = 0; i < cnt; i++) {
      final x = bd.getInt16(i * 2, Endian.little) / 32768.0;
      if (x.abs() >= 0.995) {
        clipCount++;
        lastClip = DateTime.now();
      }
      var v = x;
      for (var k = 0; k < 3; k++) {
        final c = _sos[k];
        final y = c[0] * v + _z1[k];
        _z1[k] = c[1] * v - c[3] * y + _z2[k];
        _z2[k] = c[2] * v - c[4] * y;
        v = y;
      }
      e[i] = v * v;
    }
    var start = 0;
    if (_skip > 0) {
      final s = min(_skip, cnt);
      _skip -= s;
      start = s;
    }
    if (start >= cnt) return;
    if (!_init) {
      var m = 0.0;
      for (var i = start; i < cnt; i++) {
        m += e[i];
      }
      slowP = m / (cnt - start);
      _init = true;
    }
    for (var i = start; i < cnt; i++) {
      final ev = e[i];
      slowP += alpha * (ev - slowP);
      sumSq += ev;
      n++;
      secSq += ev;
      secN++;
      if (secN >= fs) {
        final l = _db(slowP);
        las.add(l);
        if (l > maxRaw) maxRaw = l;
        if (l < minRaw) minRaw = l;
        secSq = 0;
        secN = 0;
      }
    }
  }
}
