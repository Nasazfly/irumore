import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'bande.dart';
import 'core.dart';

/// Banco di filtri a bande di 1/3 d'ottava (25 Hz - 12,5 kHz), fs = 48 kHz.
class Bank {
  static const fs = 48000;
  static final double alphaF = 1 - exp(-1 / (fs * 0.125));
  static const nb = 28;
  final coef = Float64List(nb * 3 * 5);
  final z1 = Float64List(nb * 3);
  final z2 = Float64List(nb * 3);
  final eSum = Float64List(nb);
  final pF = Float64List(nb);
  int n = 0;
  int skip = fs;
  Uint8List? carry;

  Bank() {
    for (var b = 0; b < nb; b++) {
      for (var k = 0; k < 3; k++) {
        for (var j = 0; j < 5; j++) {
          coef[(b * 3 + k) * 5 + j] = bandeSos[b][k][j];
        }
      }
    }
  }

  void reset() {
    z1.fillRange(0, z1.length, 0);
    z2.fillRange(0, z2.length, 0);
    eSum.fillRange(0, nb, 0);
    pF.fillRange(0, nb, 0);
    n = 0;
    skip = fs;
    carry = null;
  }

  double get secondi => n / fs;

  void process(Uint8List input) {
    var bytes = input;
    if (carry != null) {
      bytes = Uint8List.fromList([...carry!, ...bytes]);
      carry = null;
    }
    if (bytes.lengthInBytes.isOdd) {
      carry = bytes.sublist(bytes.lengthInBytes - 1);
      bytes = bytes.sublist(0, bytes.lengthInBytes - 1);
    }
    final bd = ByteData.sublistView(bytes);
    final cnt = bytes.lengthInBytes ~/ 2;
    for (var i = 0; i < cnt; i++) {
      final x = bd.getInt16(i * 2, Endian.little) / 32768.0;
      final on = skip <= 0;
      for (var b = 0; b < nb; b++) {
        var v = x;
        for (var k = 0; k < 3; k++) {
          final o = (b * 3 + k) * 5;
          final y = coef[o] * v + z1[b * 3 + k];
          z1[b * 3 + k] = coef[o + 1] * v - coef[o + 3] * y + z2[b * 3 + k];
          z2[b * 3 + k] = coef[o + 2] * v - coef[o + 4] * y;
          v = y;
        }
        if (on) {
          final e = v * v;
          eSum[b] += e;
          pF[b] += alphaF * (e - pF[b]);
        }
      }
      if (on) {
        n++;
      } else {
        skip--;
      }
    }
  }

  /// Livello della banda b (dB) con offset di taratura, correzione di banda e ponderazione A opzionale.
  double livello(int b, bool leq, bool a, double off, double corr) {
    final p = leq ? (n > 0 ? eSum[b] / n : 0.0) : pF[b];
    if (p <= 1e-20) return double.nan;
    return 10 * log(p) / ln10 + 120 + off + corr + (a ? bandeA[b] : 0);
  }
}

class SpettroPage extends StatefulWidget {
  const SpettroPage({super.key});
  @override
  State<SpettroPage> createState() => _SpettroState();
}

class _SpettroState extends State<SpettroPage> {
  final bank = Bank();
  final rec = AudioRecorder();
  StreamSubscription<Uint8List>? sub;
  Timer? tick;
  bool running = false;
  bool leq = false; // false = Fast, true = Leq dal reset
  bool pond = true; // true = ponderazione A
  double off = 0;
  List<double> corr = List.filled(Bank.nb, 0.0);
  String? err;

  @override
  void initState() {
    super.initState();
    off = Taratura.off;
    SharedPreferences.getInstance().then((p) {
      final c = p.getStringList('bandcorr');
      if (mounted && c != null && c.length == Bank.nb) {
        setState(() => corr = [for (final v in c) double.tryParse(v) ?? 0.0]);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await mostraAvviso(context);
      if (!ok && mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    sub?.cancel();
    rec.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  RecordConfig cfg(AndroidAudioSource s) => RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: Bank.fs,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: AndroidRecordConfig(audioSource: s),
      );

  Future<void> start() async {
    setState(() => err = null);
    try {
      if (!await rec.hasPermission()) {
        setState(() => err = 'Permesso microfono negato: abilitalo dalle impostazioni del telefono.');
        return;
      }
      Stream<Uint8List> st;
      try {
        st = await rec.startStream(cfg(AndroidAudioSource.unprocessed));
      } catch (_) {
        st = await rec.startStream(cfg(AndroidAudioSource.mic));
      }
      sub = st.listen(bank.process);
      WakelockPlus.enable();
      tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
      setState(() => running = true);
    } catch (e) {
      setState(() => err = 'Errore microfono: $e');
    }
  }

  Future<void> stop() async {
    tick?.cancel();
    await sub?.cancel();
    sub = null;
    try {
      await rec.stop();
    } catch (_) {}
    WakelockPlus.disable();
    if (mounted) setState(() => running = false);
  }

  List<double> livelli({bool conCorr = true}) => [for (var b = 0; b < Bank.nb; b++) bank.livello(b, leq, pond, off, conCorr ? corr[b] : 0.0)];

  double totale(List<double> l) {
    var s = 0.0;
    for (final v in l) {
      if (!v.isNaN) s += pw10(v);
    }
    return s > 0 ? db10(s) : double.nan;
  }

  void tara() {
    final raw = livelli(conCorr: false);
    final ctrl = [for (var b = 0; b < Bank.nb; b++) TextEditingController()];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, sc) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            children: [
              const Text('Taratura per banda', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: cInk)),
              const SizedBox(height: 6),
              InfoBox('Con un rumore stazionario (per esempio rumore rosa) e la misura ferma, scrivi per ogni banda il valore del tuo fonometro ${pond ? 'in dB(A)' : 'lineare (Z)'}. L\'app calcola la correzione rispetto ai valori del telefono (${leq ? 'Leq dal reset' : 'Fast'}). Le bande lasciate vuote non cambiano.'),
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  itemCount: Bank.nb,
                  itemBuilder: (_, b) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 56, child: Text('${bandeNom[b]} Hz', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        SizedBox(width: 84, child: Text(raw[b].isNaN ? '–' : 'tel. ${f1(raw[b])}', style: const TextStyle(fontSize: 13, color: cDark))),
                        Expanded(
                          child: TextField(
                            controller: ctrl[b],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: InputDecoration(isDense: true, hintText: 'tuo strumento', suffixText: 'dB', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                          ),
                        ),
                        SizedBox(width: 62, child: Text('${corr[b] >= 0 ? '+' : ''}${f1(corr[b])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: cTeal))),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final p = await SharedPreferences.getInstance();
                        await p.remove('bandcorr');
                        await p.remove('bandcorr_date');
                        Taratura.dataBande = null;
                        setState(() => corr = List.filled(Bank.nb, 0.0));
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Azzera correzioni'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final nuove = [...corr];
                        for (var b = 0; b < Bank.nb; b++) {
                          final t = pn(ctrl[b].text);
                          if (t != null && !raw[b].isNaN) nuove[b] = (t - raw[b]) * 10 ~/ 1 / 10;
                        }
                        final p = await SharedPreferences.getInstance();
                        await p.setStringList('bandcorr', [for (final v in nuove) v.toString()]);
                        final quando = oraTesto(DateTime.now());
                        await p.setString('bandcorr_date', quando);
                        Taratura.dataBande = quando;
                        setState(() => corr = nuove);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Calcola e salva'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = livelli();
    final tot = totale(l);
    return page('Analizzatore di spettro', [
      const InfoBox('Versione di prova: bande di 1/3 d\'ottava da 25 Hz a 12,5 kHz. Sotto circa 100 Hz e sopra 8 kHz il microfono del telefono è poco attendibile (bande in colore chiaro). Per un confronto attendibile si consiglia la taratura per banda con il proprio fonometro.', color: cWarn, icon: Icons.science),
      InfoBox('${Taratura.frase()}\n${Taratura.fraseBande()}', icon: Icons.tune),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cTeal, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Totale delle bande · ${pond ? 'dB(A)' : 'dB (Z)'}', style: const TextStyle(color: Color(0xFFBFE3DC), fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(f1(tot), style: const TextStyle(color: Colors.white, fontSize: 50, fontWeight: FontWeight.w700, height: 1.1)),
                ],
              ),
            ),
            Text(running ? 'In misura\n${f1(bank.secondi, 0)} s' : 'Fermo', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: false, label: Text('Fast')), ButtonSegment(value: true, label: Text('Leq dal reset'))],
              selected: {leq},
              onSelectionChanged: (v) => setState(() => leq = v.first),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: false, label: Text('Z')), ButtonSegment(value: true, label: Text('A'))],
            selected: {pond},
            onSelectionChanged: (v) => setState(() => pond = v.first),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: cLine)),
        child: SizedBox(height: 230, width: double.infinity, child: CustomPaint(painter: BandPainter(l))),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: running ? cBad : cTeal, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: running ? stop : start,
              icon: Icon(running ? Icons.stop : Icons.mic),
              label: Text(running ? 'Ferma' : 'Avvia'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: () => setState(bank.reset),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: running ? null : tara,
        icon: const Icon(Icons.tune),
        label: Text(running ? 'Ferma la misura per tarare le bande' : 'Taratura per banda'),
      ),
      const SizedBox(height: 10),
      Apribile(
        titolo: 'Valori per banda',
        icona: Icons.table_rows,
        child: Column(
          children: [
            for (var b = 0; b < Bank.nb; b++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 80, child: Text('${bandeNom[b]} Hz', style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(child: Text(f1(l[b]), style: const TextStyle(fontSize: 15))),
                    Text(corr[b] == 0 ? '' : 'corr. ${corr[b] >= 0 ? '+' : ''}${f1(corr[b])}', style: const TextStyle(fontSize: 12, color: cTeal)),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: cBad))),
    ]);
  }
}

class BandPainter extends CustomPainter {
  final List<double> v;
  BandPainter(this.v);

  void _t(Canvas c, String s, Offset o, {double sz = 9, bool right = false, Color col = cDark}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(color: col, fontSize: sz)), textDirection: TextDirection.ltr)..layout();
    c.save();
    c.translate(o.dx, o.dy);
    tp.paint(c, right ? Offset(-tp.width, -tp.height / 2) : Offset(-tp.width / 2, 0));
    c.restore();
  }

  @override
  void paint(Canvas c, Size s) {
    const l = 30.0, r = 4.0, t = 4.0, b = 22.0;
    final w = s.width - l - r, h = s.height - t - b;
    final ok = v.where((x) => !x.isNaN).toList();
    var lo = 20.0, hi = 100.0;
    if (ok.isNotEmpty) {
      lo = ((ok.reduce(min) - 5) / 10).floor() * 10.0;
      hi = ((ok.reduce(max) + 5) / 10).ceil() * 10.0;
      if (hi - lo < 40) hi = lo + 40;
    }
    double y(double val) => t + h * (1 - (val - lo) / (hi - lo));
    final grid = Paint()
      ..color = cLine
      ..strokeWidth = 1;
    for (var g = lo; g <= hi; g += 10) {
      c.drawLine(Offset(l, y(g)), Offset(l + w, y(g)), grid);
      _t(c, g.toStringAsFixed(0), Offset(l - 4, y(g)), right: true);
    }
    final n = v.length;
    final bw = w / n;
    for (var i = 0; i < n; i++) {
      final fc = bandeFc[i];
      final debole = fc < 100 || fc > 8000;
      if (!v[i].isNaN) {
        final yy = y(v[i].clamp(lo, hi));
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(l + i * bw + 1, yy, l + (i + 1) * bw - 1, y(lo)), const Radius.circular(2)),
          Paint()..color = debole ? const Color(0xFF8CC3B9) : cTeal,
        );
      }
      if (i % 3 == 1) _t(c, bandeNom[i], Offset(l + (i + 0.5) * bw, s.height - 16), sz: 9);
    }
  }

  @override
  bool shouldRepaint(BandPainter o) => true;
}
