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
  static final double alphaF = 1 - exp(-1 / (fs * 0.125)); // Fast: tau = 125 ms
  static const binLen = fs ~/ 10; // finestra mobile LAeq 1 s = 10 blocchi da 100 ms
  static const fineLen = 480; // controllo dei massimi/minimi Fast ogni 10 ms

  final _z1 = [0.0, 0.0, 0.0];
  final _z2 = [0.0, 0.0, 0.0];
  Uint8List? _carry;
  int _skip = fs ~/ 2;
  bool _init = false;
  double slowP = 0, fastP = 0;
  double sumSq = 0;
  int n = 0;
  double secSq = 0;
  int secN = 0;
  final _bins = List<double>.filled(10, 0.0);
  int _binIdx = 0, _binFilled = 0, _binN = 0;
  double _binSum = 0;
  int _fineN = 0;
  // serie campionate ogni secondo (valori grezzi, senza offset)
  final las = <double>[];
  final laf = <double>[];
  final leq1 = <double>[];
  double maxRaw = -1e9, minRaw = 1e9; // LASmax / LASmin
  double fMaxRaw = -1e9, fMinRaw = 1e9; // LAFmax / LAFmin (controllo ogni 10 ms)
  double l1MaxRaw = -1e9, l1MinRaw = 1e9; // LAeq,1s max / min (finestra mobile, ogni 100 ms)
  int clipCount = 0;
  DateTime? lastClip;
  DateTime? _t0;
  int _inSamples = 0;

  void reset() {
    for (var i = 0; i < 3; i++) {
      _z1[i] = 0;
      _z2[i] = 0;
    }
    _carry = null;
    _skip = fs ~/ 2;
    _init = false;
    slowP = 0;
    fastP = 0;
    sumSq = 0;
    n = 0;
    secSq = 0;
    secN = 0;
    for (var i = 0; i < 10; i++) {
      _bins[i] = 0;
    }
    _binIdx = 0;
    _binFilled = 0;
    _binN = 0;
    _binSum = 0;
    _fineN = 0;
    las.clear();
    laf.clear();
    leq1.clear();
    maxRaw = -1e9;
    minRaw = 1e9;
    fMaxRaw = -1e9;
    fMinRaw = 1e9;
    l1MaxRaw = -1e9;
    l1MinRaw = 1e9;
    clipCount = 0;
    lastClip = null;
    _t0 = null;
    _inSamples = 0;
  }

  static double _db(double p) => p <= 1e-20 ? -200.0 : 10 * log(p) / ln10;

  bool get hasData => _init && las.isNotEmpty;
  bool get started => _init;
  int get seconds => las.length;

  /// Frequenza di campionamento effettiva (campioni ricevuti / tempo reale), dopo qualche secondo.
  double? get fsEff {
    if (_t0 == null) return null;
    final dt = DateTime.now().difference(_t0!).inMilliseconds / 1000.0;
    if (dt < 6) return null;
    return _inSamples / dt;
  }

  double lasNow(double off) => _init ? _db(slowP) + base + off : double.nan;
  double lafNow(double off) => _init ? _db(fastP) + base + off : double.nan;
  double _leq1Raw() {
    final cnt = _binFilled * binLen + _binN;
    if (!_init || cnt == 0) return double.nan;
    var s = _binSum;
    for (var i = 0; i < _binFilled; i++) {
      s += _bins[i];
    }
    return _db(s / cnt);
  }

  double leq1s(double off) {
    final v = _leq1Raw();
    return v.isNaN ? v : v + base + off;
  }

  double laeq(double off) => n > 0 ? _db(sumSq / n) + base + off : double.nan;
  double lasMax(double off) => las.isEmpty ? double.nan : maxRaw + base + off;
  double lasMin(double off) => las.isEmpty ? double.nan : minRaw + base + off;
  double lafMax(double off) => fMaxRaw < -1e8 ? double.nan : fMaxRaw + base + off;
  double lafMin(double off) => fMinRaw > 1e8 ? double.nan : fMinRaw + base + off;
  double leq1Max(double off) => l1MaxRaw < -1e8 ? double.nan : l1MaxRaw + base + off;
  double leq1Min(double off) => l1MinRaw > 1e8 ? double.nan : l1MinRaw + base + off;
  List<double> series(double off) => [for (final v in las) v + base + off];
  List<double> seriesF(double off) => [for (final v in laf) v + base + off];
  List<double> seriesL(double off) => [for (final v in leq1) v + base + off];

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
    _t0 ??= DateTime.now();
    _inSamples += cnt;
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
      fastP = slowP;
      _init = true;
    }
    for (var i = start; i < cnt; i++) {
      final ev = e[i];
      slowP += alpha * (ev - slowP);
      fastP += alphaF * (ev - fastP);
      sumSq += ev;
      n++;
      secSq += ev;
      secN++;
      _binSum += ev;
      _binN++;
      _fineN++;
      if (_fineN >= fineLen) {
        _fineN = 0;
        final lf = _db(fastP);
        if (lf > fMaxRaw) fMaxRaw = lf;
        if (lf < fMinRaw) fMinRaw = lf;
      }
      if (_binN >= binLen) {
        _bins[_binIdx] = _binSum;
        _binIdx = (_binIdx + 1) % 10;
        if (_binFilled < 10) _binFilled++;
        _binSum = 0;
        _binN = 0;
        if (_binFilled == 10) {
          var s = 0.0;
          for (final b in _bins) {
            s += b;
          }
          final l1 = _db(s / (10 * binLen));
          if (l1 > l1MaxRaw) l1MaxRaw = l1;
          if (l1 < l1MinRaw) l1MinRaw = l1;
        }
      }
      if (secN >= fs) {
        final l = _db(slowP);
        las.add(l);
        laf.add(_db(fastP));
        final lq = _leq1Raw();
        leq1.add(lq.isNaN ? l : lq);
        if (l > maxRaw) maxRaw = l;
        if (l < minRaw) minRaw = l;
        secSq = 0;
        secN = 0;
      }
    }
  }
}
