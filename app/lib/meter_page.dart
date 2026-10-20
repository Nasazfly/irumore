import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core.dart';
import 'diff.dart';
import 'dsp.dart';
import 'norme_pages.dart';

String stamp(DateTime d) {
  String t(int v) => v.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)}/${d.year} ${t(d.hour)}:${t(d.minute)}';
}

String segno(double v) => v >= 0 ? '+' : '';

class MeterPage extends StatefulWidget {
  const MeterPage({super.key});
  @override
  State<MeterPage> createState() => _MeterPageState();
}

class _MeterPageState extends State<MeterPage> {
  final m = LevelMeter();
  final rec = AudioRecorder();
  final gkey = GlobalKey();
  StreamSubscription<Uint8List>? sub;
  Timer? tick;
  bool running = false;
  String? err;
  String? nota;
  double off = 0;
  String? offDate; // data in cui è stata impostata la taratura
  int modo = 0; // 0 Slow, 1 Fast, 2 LAeq 1 s
  DateTime t0 = DateTime.now();

  static const etichette = ['LAS · ponderazione A · Slow', 'LAF · ponderazione A · Fast', 'LAeq,1s · finestra mobile di 1 s'];
  static const chiavi = ['LAS', 'LAF', 'LAeq1s'];
  static const nMax = ['LASmax', 'LAFmax', 'LAeq,1s max'];
  static const nMin = ['LASmin', 'LAFmin', 'LAeq,1s min'];
  static const kMax = ['LASmax', 'LAFmax', 'LAeq1sMax'];
  static const kMin = ['LASmin', 'LAFmin', 'LAeq1sMin'];

  @override
  void initState() {
    super.initState();
    off = Taratura.off;
    offDate = Taratura.data;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await mostraAvviso(context);
      if (!ok && mounted) Navigator.pop(context);
    });
  }

  void snap() {
    if (m.seconds >= 3) UltimaMisura.i.aggiorna(m.laeq(off), m.lasMax(off), m.lasMin(off), m.seconds);
  }

  @override
  void dispose() {
    snap();
    tick?.cancel();
    sub?.cancel();
    rec.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  RecordConfig cfg(AndroidAudioSource s) => RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: LevelMeter.fs,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: AndroidRecordConfig(audioSource: s),
      );

  Future<void> start() async {
    setState(() {
      err = null;
      nota = null;
    });
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
        nota = 'Sorgente non elaborata non disponibile su questo telefono: usato il microfono standard (possibile elaborazione di sistema).';
      }
      if (!m.started) t0 = DateTime.now();
      sub = st.listen(m.process);
      WakelockPlus.enable();
      tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        snap();
        setState(() {});
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
    snap();
    WakelockPlus.disable();
    if (mounted) setState(() => running = false);
  }

  void reset() {
    m.reset();
    UltimaMisura.i.azzera();
    setState(() => t0 = DateTime.now());
  }

  Future<void> setOff(double v) async {
    final x = (v.clamp(-60.0, 60.0) * 10).round() / 10;
    final quando = oraTesto(DateTime.now());
    setState(() {
      off = x;
      offDate = quando;
    });
    snap();
    await Taratura.imposta(x, quando);
  }

  void taratura() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) {
          void set(double v) {
            setOff(v);
            ss(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Text('Taratura (offset)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cInk)),
                    InfoDot('offset'),
                  ]),
                  const SizedBox(height: 8),
                  Center(child: Text('${segno(off)}${f1(off)} dB', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: cTeal))),
                  Center(child: Text(offDate == null ? 'Nessuna taratura memorizzata' : 'Memorizzata, impostata il $offDate', style: const TextStyle(fontSize: 13, color: cDark))),
                  Slider(min: -60, max: 60, divisions: 1200, value: off, onChanged: set),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      for (final d in [-1.0, -0.1, 0.1, 1.0]) OutlinedButton(onPressed: () => set(off + d), child: Text(d > 0 ? '+${f1(d)}' : f1(d))),
                      TextButton(onPressed: () => set(0), child: const Text('Azzera')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const InfoBox(
                    'La taratura resta memorizzata: alla prossima apertura l\'app userà lo stesso offset. Per tararla, accosta il telefono al microfono del fonometro professionale, con un rumore stazionario (per esempio una ventilazione), e regola l\'offset finché il LAS del telefono coincide con quello dello strumento. Si consiglia di verificare poi un secondo livello: se le letture divergono, il microfono non è lineare su tutta la dinamica. L\'offset vale per questo telefono, con questa posizione e senza custodia.',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> condividi() async {
    try {
      final ctx = gkey.currentContext;
      if (ctx == null) return;
      final b = ctx.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 3);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/envinoise_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bd!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path)], text: 'EnviNoise - LAeq ${f1(m.laeq(off))} dB(A) in ${mmss(m.seconds)}');
    } catch (e) {
      setState(() => err = 'Condivisione non riuscita: $e');
    }
  }

  Widget stat(String l, String v, String k) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: cLine)),
          child: Column(
            children: [
              GestureDetector(
                onTap: () => showInfo(context, k),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(l, style: const TextStyle(color: cDark, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 3),
                  const Icon(Icons.info_outline, size: 14, color: cTeal),
                ]),
              ),
              const SizedBox(height: 2),
              Text(v, style: const TextStyle(color: cInk, fontSize: 22, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final big = modo == 0 ? m.lasNow(off) : (modo == 1 ? m.lafNow(off) : m.leq1s(off));
    final leq = m.laeq(off);
    final mx = modo == 0 ? m.lasMax(off) : (modo == 1 ? m.lafMax(off) : m.leq1Max(off));
    final mn = modo == 0 ? m.lasMin(off) : (modo == 1 ? m.lafMin(off) : m.leq1Min(off));
    final ser = modo == 0 ? m.series(off) : (modo == 1 ? m.seriesF(off) : m.seriesL(off));
    final fsE = m.fsEff;
    final rich = DiffState.i.richiesto(leq, m.seconds);
    final clip = m.lastClip != null && DateTime.now().difference(m.lastClip!).inSeconds < 3;
    const didascalie = [
      'LAS: livello ponderato A, costante Slow (1 s), campionato ogni secondo.',
      'LAF: livello ponderato A, costante Fast (125 ms), campionato ogni secondo.',
      'LAeq,1s: livello equivalente su finestra mobile di 1 s, campionato ogni secondo.',
    ];
    return page('Fonometro', [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(color: cTeal, borderRadius: BorderRadius.circular(24)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(etichette[modo], style: const TextStyle(color: Color(0xFFBFE3DC), fontSize: 13, fontWeight: FontWeight.w600))),
                    InfoDot(chiavi[modo], color: const Color(0xFFBFE3DC)),
                  ]),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(f1(big), style: const TextStyle(color: Colors.white, fontSize: 68, fontWeight: FontWeight.w700, height: 1.1)),
                      const SizedBox(width: 6),
                      const Text('dB(A)', style: TextStyle(color: Colors.white, fontSize: 20)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: running ? const Color(0xFF2E9E6B) : cDark, borderRadius: BorderRadius.circular(20)),
              child: Text(running ? 'In misura' : 'Fermo', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 0, label: Text('Slow')), ButtonSegment(value: 1, label: Text('Fast')), ButtonSegment(value: 2, label: Text('LAeq 1 s'))],
          selected: {modo},
          onSelectionChanged: (v) => setState(() => modo = v.first),
        ),
      ),
      const SizedBox(height: 8),
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: taratura,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: offDate == null ? const Color(0xFFFFF1E0) : cMint, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Icon(Icons.tune, size: 20, color: offDate == null ? cWarn : cTeal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  offDate == null ? 'Nessuna taratura (offset 0,0 dB): tocca per tarare il telefono.' : 'Taratura attiva: ${segno(off)}${f1(off)} dB · impostata il $offDate',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: offDate == null ? cWarn : cInk),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: cDark),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (clip) const InfoBox('Saturazione del microfono: livello non attendibile. Si consiglia di allontanare il telefono dalla sorgente.', color: cBad, icon: Icons.warning_amber),
      if (rich == true) InfoBox('Il LAeq supera la soglia di applicabilità del differenziale (${f1(soglia(DiffState.i.notte, DiffState.i.aperte), 0)} dB(A)): verifica differenziale necessaria. Vedi il riquadro in fondo alla pagina.', color: cWarn, icon: Icons.rule),
      Row(children: [stat('LAeq', f1(leq), 'LAeq'), stat(nMax[modo], f1(mx), kMax[modo]), stat(nMin[modo], f1(mn), kMin[modo])]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: cLine)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Livelli statistici · ${['LAS', 'LAF', 'LAeq,1s'][modo]}', style: const TextStyle(color: cDark, fontSize: 12, fontWeight: FontWeight.w700)),
              const InfoDot('LN'),
            ]),
            Row(
              children: [
                for (final n in [1, 10, 50, 90, 99])
                  Expanded(
                    child: Column(children: [
                      Text('L$n', style: const TextStyle(color: cDark, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      Text(f1(m.livStat(modo, n.toDouble(), off)), style: const TextStyle(color: cInk, fontSize: 18, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      RepaintBoundary(
        key: gkey,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: cLine)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/logo_verde.png', height: 22),
                  Text(stamp(t0), style: const TextStyle(color: cDark, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Misura fonometrica indicativa', style: TextStyle(fontWeight: FontWeight.w700, color: cInk, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                'LAeq ${f1(leq)} dB(A)  ·  ${nMax[modo]} ${f1(mx)}  ·  ${nMin[modo]} ${f1(mn)}  ·  durata ${mmss(m.seconds)}',
                style: const TextStyle(color: cInk, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'L1 ${f1(m.livStat(modo, 1, off))}  ·  L10 ${f1(m.livStat(modo, 10, off))}  ·  L50 ${f1(m.livStat(modo, 50, off))}  ·  L90 ${f1(m.livStat(modo, 90, off))}  ·  L99 ${f1(m.livStat(modo, 99, off))}',
                style: const TextStyle(color: cInk, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(height: 190, width: double.infinity, child: CustomPaint(painter: ChartPainter(ser, leq))),
              const SizedBox(height: 6),
              Text(
                '${didascalie[modo]} Offset di taratura ${segno(off)}${f1(off)} dB${offDate == null ? '' : ' (impostato il $offDate)'}. Misura con microfono di smartphone: indicativa, non conforme alla IEC 61672.',
                style: const TextStyle(color: cDark, fontSize: 10.5, height: 1.3),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: running ? cBad : cTeal, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: running ? stop : start,
              icon: Icon(running ? Icons.stop : Icons.mic),
              label: Text(running ? 'Ferma' : (m.started ? 'Riprendi' : 'Avvia misura')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: m.seconds >= 2 ? condividi : null,
          icon: const Icon(Icons.ios_share),
          label: const Text('Condividi grafico'),
        ),
      ),
      const SizedBox(height: 10),
      const InfoBox('I valori misurati si possono importare nelle altre funzioni con il pulsante "Usa dato del fonometro del telefono" accanto ai campi. Tutte le funzioni accettano anche dati scritti a mano.'),
      if (fsE != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Campionamento effettivo: ${f1(fsE / 1000)} kHz (atteso 48,0)', style: const TextStyle(fontSize: 11.5, color: cDark))),
      if (fsE != null && (fsE - 48000).abs() / 48000 > 0.03)
        const InfoBox('La frequenza di campionamento effettiva differisce da quella attesa: i tempi di integrazione e la ponderazione A potrebbero risultare alterati su questo telefono. Si consiglia di confrontare con il fonometro professionale.', color: cWarn, icon: Icons.warning_amber),
      const Apribile(titolo: 'Limiti di zona', icona: Icons.gavel, child: ZoneCard()),
      Apribile(
        titolo: 'Verifica differenziale',
        icona: Icons.rule,
        child: DiffCard(nudo: true, currentLaeq: () => m.laeq(off), currentSeconds: () => m.seconds, onCaptured: reset),
      ),
      if (nota != null) Padding(padding: const EdgeInsets.only(top: 10), child: InfoBox(nota!, color: cWarn, icon: Icons.warning_amber)),
      if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: cBad))),
    ]);
  }
}

class ChartPainter extends CustomPainter {
  final List<double> v;
  final double leq;
  ChartPainter(this.v, this.leq);

  void _t(Canvas c, String s, Offset o, {Color col = cDark, double sz = 10, bool right = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(color: col, fontSize: sz)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, right ? Offset(o.dx - tp.width, o.dy - tp.height / 2) : o);
  }

  @override
  void paint(Canvas c, Size s) {
    const l = 34.0, r = 8.0, t = 8.0, b = 20.0;
    final w = s.width - l - r, h = s.height - t - b;
    if (v.length < 2) {
      _t(c, 'Il grafico compare dopo i primi secondi di misura', Offset(l, s.height / 2 - 6), sz: 12);
      return;
    }
    var lo = v.reduce(min), hi = v.reduce(max);
    if (!leq.isNaN) {
      lo = min(lo, leq);
      hi = max(hi, leq);
    }
    lo = (lo / 5).floor() * 5.0 - 5;
    hi = (hi / 5).ceil() * 5.0 + 5;
    final step = (hi - lo) <= 30 ? 5.0 : 10.0;
    double y(double val) => t + h * (1 - (val - lo) / (hi - lo));
    final grid = Paint()
      ..color = cLine
      ..strokeWidth = 1;
    for (var g = (lo / step).ceil() * step; g <= hi; g += step) {
      c.drawLine(Offset(l, y(g)), Offset(l + w, y(g)), grid);
      _t(c, g.toStringAsFixed(0), Offset(l - 4, y(g)), right: true);
    }
    final n = v.length;
    final stride = max(1, (n / 500).ceil());
    final path = Path();
    var first = true;
    for (var i = 0; i < n; i += stride) {
      final x = l + w * (i / (n - 1));
      final yy = y(v[i]);
      if (first) {
        path.moveTo(x, yy);
        first = false;
      } else {
        path.lineTo(x, yy);
      }
    }
    path.lineTo(l + w, y(v[n - 1]));
    c.drawPath(
      path,
      Paint()
        ..color = cTeal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (!leq.isNaN) {
      final p = Paint()
        ..color = const Color(0xFFE8704A)
        ..strokeWidth = 2;
      final yy = y(leq);
      for (var x = l; x < l + w; x += 10) {
        c.drawLine(Offset(x, yy), Offset(min(x + 6, l + w), yy), p);
      }
      _t(c, 'LAeq ${f1(leq)}', Offset(l + 4, yy - 14), col: const Color(0xFFB4492A), sz: 11);
    }
    _t(c, '0', Offset(l, s.height - 15));
    final end = mmss(n);
    _t(c, end, Offset(l + w - 8.0 * end.length, s.height - 15));
  }

  @override
  bool shouldRepaint(ChartPainter o) => true;
}
