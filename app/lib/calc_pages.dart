import 'dart:math';
import 'package:flutter/material.dart';
import 'core.dart';

// ───────── Somma di sorgenti ─────────
class SommaPage extends StatefulWidget {
  const SommaPage({super.key});
  @override
  State<SommaPage> createState() => _SommaState();
}

class _SommaState extends State<SommaPage> {
  final cs = [TextEditingController(), TextEditingController()];
  void up() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final vals = [for (final x in cs) pn(x.text)].whereType<double>().toList();
    final tot = vals.isEmpty ? double.nan : db10(vals.fold(0.0, (a, b) => a + pw10(b)));
    return page('Somma di sorgenti', [
      const InfoBox('Somma energetica dei livelli: L = 10·log10(Σ 10^(Li/10)). Due sorgenti uguali danno +3 dB, dieci sorgenti uguali +10 dB.'),
      for (var i = 0; i < cs.length; i++)
        Row(
          children: [
            Expanded(child: Field(c: cs[i], label: 'Sorgente ${i + 1}', suffix: 'dB', info: 'Lsorg', fonte: Fonte.laeq, onChanged: up)),
            if (cs.length > 2)
              IconButton(
                onPressed: () => setState(() => cs.removeAt(i).dispose()),
                icon: const Icon(Icons.remove_circle_outline, color: cDark),
              ),
          ],
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() => cs.add(TextEditingController())),
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi sorgente'),
      ),
      ResultCard('Livello totale', '${f1(tot)} dB', sub: '${vals.length} sorgenti considerate'),
    ]);
  }
}

// ───────── Differenza di sorgenti ─────────
class DifferenzaPage extends StatefulWidget {
  const DifferenzaPage({super.key});
  @override
  State<DifferenzaPage> createState() => _DifferenzaState();
}

class _DifferenzaState extends State<DifferenzaPage> {
  final a = TextEditingController(), b = TextEditingController();
  void up() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final lt = pn(a.text), lf = pn(b.text);
    var res = double.nan;
    String? msg;
    var warn = false;
    if (lt != null && lf != null) {
      final d = lt - lf;
      if (d <= 0) {
        msg = 'Il livello totale deve essere maggiore di quello della sorgente da sottrarre.';
        warn = true;
      } else {
        res = db10(pw10(lt) - pw10(lf));
        if (d < 3) {
          msg = 'Differenza inferiore a 3 dB: il risultato è poco affidabile. Si consiglia di migliorare la misura del fondo o di ripeterla.';
          warn = true;
        } else if (d > 10) {
          msg = 'Differenza superiore a 10 dB: la sorgente sottratta è trascurabile (correzione inferiore a 0,5 dB).';
        }
      }
    }
    return page('Differenza di sorgenti', [
      const InfoBox('Sottrazione energetica: L = 10·log10(10^(Ltot/10) − 10^(Lx/10)). Si usa, per esempio, per togliere il rumore di fondo dalla misura a sorgente attiva.'),
      Field(c: a, label: 'Livello totale (sorgente + fondo)', suffix: 'dB', info: 'Ltot', fonte: Fonte.laeq, onChanged: up),
      Field(c: b, label: 'Livello da sottrarre (fondo)', suffix: 'dB', info: 'fondo', fonte: Fonte.laeq, onChanged: up),
      if (msg != null) InfoBox(msg, color: warn ? cWarn : cDark, icon: warn ? Icons.warning_amber : Icons.info_outline),
      ResultCard('Livello della sola sorgente', '${f1(res)} dB', sub: res.isNaN ? null : 'Correzione: ${f1(res - (lt ?? 0))} dB'),
    ]);
  }
}

// ───────── Propagazione ─────────
class PropagazionePage extends StatefulWidget {
  const PropagazionePage({super.key});
  @override
  State<PropagazionePage> createState() => _PropState();
}

class _PropState extends State<PropagazionePage> {
  final l1 = TextEditingController(), d1 = TextEditingController(), d2 = TextEditingController(), lt = TextEditingController();
  bool lineare = false;
  int modo = 0;
  void up() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final k = lineare ? 10.0 : 20.0;
    final vl1 = pn(l1.text), vd1 = pn(d1.text), vd2 = pn(d2.text), vlt = pn(lt.text);
    var res = double.nan;
    String sub = '';
    if (vl1 != null && vd1 != null && vd1 > 0) {
      if (modo == 0 && vd2 != null && vd2 > 0) {
        res = vl1 - k * log(vd2 / vd1) / ln10;
        sub = 'Variazione: ${f1(res - vl1)} dB';
      } else if (modo == 1 && vlt != null) {
        res = vd1 * pow(10, (vl1 - vlt) / k);
        sub = 'Attenuazione richiesta: ${f1(vl1 - vlt)} dB';
      }
    }
    return page('Propagazione', [
      InfoBox(lineare
          ? 'Sorgente lineare in campo libero: L2 = L1 − 10·log10(d2/d1), cioè −3 dB per raddoppio della distanza. Non considera aria, suolo, barriere.'
          : 'Sorgente puntiforme in campo libero (legge dell\'inverso del quadrato): L2 = L1 − 20·log10(d2/d1), cioè −6 dB per raddoppio della distanza. Non considera aria, suolo, barriere.'),
      sezioneInfo('TIPO DI SORGENTE', 'puntiforme'),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('Puntiforme')), ButtonSegment(value: true, label: Text('Lineare'))],
        selected: {lineare},
        onSelectionChanged: (s) => setState(() => lineare = s.first),
      ),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: const [ButtonSegment(value: 0, label: Text('Livello a distanza')), ButtonSegment(value: 1, label: Text('Distanza per livello'))],
        selected: {modo},
        onSelectionChanged: (s) => setState(() => modo = s.first),
      ),
      const SizedBox(height: 14),
      Field(c: l1, label: 'Livello L1 misurato', suffix: 'dB', info: 'L1', fonte: Fonte.laeq, onChanged: up),
      Field(c: d1, label: 'Distanza d1 della misura', suffix: 'm', info: 'd1', fonte: Fonte.distanza, onChanged: up, signed: false),
      if (modo == 0) Field(c: d2, label: 'Distanza d2 di interesse', suffix: 'm', info: 'd1', fonte: Fonte.distanza, onChanged: up, signed: false) else Field(c: lt, label: 'Livello da raggiungere', suffix: 'dB', info: 'Lt', onChanged: up),
      ResultCard(modo == 0 ? 'Livello alla distanza d2' : 'Distanza necessaria', modo == 0 ? '${f1(res)} dB' : '${f1(res)} m', sub: sub.isEmpty ? null : sub),
    ]);
  }
}

// ───────── Potenza ⇄ Pressione ─────────
class PotenzaPage extends StatefulWidget {
  const PotenzaPage({super.key});
  @override
  State<PotenzaPage> createState() => _PotenzaState();
}

class _PotenzaState extends State<PotenzaPage> {
  final v = TextEditingController(), r = TextEditingController();
  int modo = 0;
  int q = 1;
  void up() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final vv = pn(v.text), rr = pn(r.text);
    var res = double.nan;
    if (vv != null && rr != null && rr > 0) {
      final term = db10(4 * pi * rr * rr / q.toDouble());
      res = modo == 0 ? vv + term : vv - term;
    }
    const qs = {1: 'Q=1 sfera', 2: 'Q=2 semisfera', 4: 'Q=4 spigolo', 8: 'Q=8 angolo'};
    return page('Potenza ⇄ Pressione', [
      const InfoBox('Campo libero con sorgente direttiva Q: Lp = Lw + 10·log10(Q / (4π·r²)). Q=1 sorgente in aria, Q=2 su piano riflettente, Q=4 in uno spigolo, Q=8 in un angolo.'),
      SegmentedButton<int>(
        segments: const [ButtonSegment(value: 0, label: Text('Lp → Lw')), ButtonSegment(value: 1, label: Text('Lw → Lp'))],
        selected: {modo},
        onSelectionChanged: (s) => setState(() => modo = s.first),
      ),
      const SizedBox(height: 10),
      sezioneInfo('DIREZIONALITÀ DELLA SORGENTE (Q)', 'Q'),
      Wrap(
        spacing: 8,
        children: [for (final e in qs.entries) ChoiceChip(label: Text(e.value), selected: q == e.key, onSelected: (_) => setState(() => q = e.key))],
      ),
      const SizedBox(height: 12),
      Field(c: v, label: modo == 0 ? 'Pressione sonora Lp' : 'Potenza sonora Lw', suffix: 'dB', info: modo == 0 ? 'Lp' : 'Lw', fonte: modo == 0 ? Fonte.laeq : null, onChanged: up),
      Field(c: r, label: 'Distanza r dalla sorgente', suffix: 'm', info: 'r', fonte: Fonte.distanza, onChanged: up, signed: false),
      ResultCard(modo == 0 ? 'Potenza sonora Lw' : 'Pressione sonora Lp', '${f1(res)} dB', sub: 'Campo libero, Q = $q'),
    ]);
  }
}

// ───────── Media energetica ─────────
class MediaPage extends StatefulWidget {
  const MediaPage({super.key});
  @override
  State<MediaPage> createState() => _MediaState();
}

class _MediaState extends State<MediaPage> {
  final ls = [TextEditingController(), TextEditingController()];
  final ts = [TextEditingController(), TextEditingController()];
  void up() => setState(() {});

  @override
  Widget build(BuildContext context) {
    var sum = 0.0, tot = 0.0;
    var n = 0;
    for (var i = 0; i < ls.length; i++) {
      final l = pn(ls[i].text), t = pn(ts[i].text);
      if (l != null && t != null && t > 0) {
        sum += t * pw10(l);
        tot += t;
        n++;
      }
    }
    final res = tot > 0 ? db10(sum / tot) : double.nan;
    return page('Media energetica', [
      const InfoBox('Livello equivalente di più intervalli: Leq = 10·log10(Σ ti·10^(Li/10) / Σ ti). La durata può essere espressa in qualsiasi unità, purché la stessa per tutte le righe.'),
      for (var i = 0; i < ls.length; i++)
        Row(
          children: [
            Expanded(child: Field(c: ls[i], label: 'Livello ${i + 1}', suffix: 'dB', info: 'Li', onChanged: up)),
            const SizedBox(width: 8),
            Expanded(child: Field(c: ts[i], label: 'Durata', suffix: 'min', info: 'ti', onChanged: up, signed: false)),
            if (ls.length > 2)
              IconButton(
                onPressed: () => setState(() {
                  ls.removeAt(i).dispose();
                  ts.removeAt(i).dispose();
                }),
                icon: const Icon(Icons.remove_circle_outline, color: cDark),
              ),
          ],
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          ls.add(TextEditingController());
          ts.add(TextEditingController());
        }),
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi intervallo'),
      ),
      if (UltimaMisura.i.valida)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.tonalIcon(
            onPressed: () => setState(() {
              final um = UltimaMisura.i;
              var k = -1;
              for (var i = 0; i < ls.length; i++) {
                if (ls[i].text.trim().isEmpty && ts[i].text.trim().isEmpty) {
                  k = i;
                  break;
                }
              }
              if (k < 0) {
                ls.add(TextEditingController());
                ts.add(TextEditingController());
                k = ls.length - 1;
              }
              ls[k].text = f1(um.laeq);
              ts[k].text = f1(um.secondi / 60);
            }),
            icon: const Icon(Icons.phone_android),
            label: Text('Aggiungi misura del fonometro del telefono: LAeq ${f1(UltimaMisura.i.laeq)} dB(A), ${mmss(UltimaMisura.i.secondi)}'),
          ),
        ),
      ResultCard('Livello equivalente', '${f1(res)} dB', sub: n == 0 ? null : '$n intervalli · durata totale ${f1(tot)} min'),
    ]);
  }
}
