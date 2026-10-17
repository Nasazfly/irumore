import 'package:flutter/material.dart';
import 'core.dart';

// ───────── Limiti di zona e differenziale (D.P.C.M. 14/11/1997) ─────────
const _limEm = [[45, 35], [50, 40], [55, 45], [60, 50], [65, 55], [65, 65]];
const _limIm = [[50, 40], [55, 45], [60, 50], [65, 55], [70, 60], [70, 70]];
const _classi = ['I', 'II', 'III', 'IV', 'V', 'VI'];

class ZonePage extends StatefulWidget {
  const ZonePage({super.key});
  @override
  State<ZonePage> createState() => _ZoneState();
}

class _ZoneState extends State<ZonePage> {
  int cls = 2;
  bool notte = false;
  final la = TextEditingController(), ls = TextEditingController();
  void up() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = notte ? 1 : 0;
    final em = _limEm[cls][p], im = _limIm[cls][p];
    final vla = pn(la.text), vls = pn(ls.text);
    final esiti = <Widget>[];
    if (vla != null) {
      final a = r05(vla);
      final ok = a <= im;
      esiti.add(Esito('Immissione assoluta', 'LA = ${f1(a)} dB(A) (arrotondato a 0,5) rispetto al limite di $im dB(A): ${ok ? 'rispettato' : 'superato di ${f1(a - im)} dB'}.', ok));
    }
    if (vls != null) {
      final a = r05(vls);
      final ok = a <= em;
      esiti.add(Esito('Emissione della sorgente', 'LS = ${f1(a)} dB(A) rispetto al limite di $em dB(A): ${ok ? 'rispettato' : 'superato di ${f1(a - em)} dB'}.', ok));
    }
    return page('Limiti di zona', [
      const InfoBox('Tabelle B e C del D.P.C.M. 14/11/1997 per la classe di zonizzazione acustica comunale. I livelli sono arrotondati a 0,5 dB (D.M. 16/03/1998). Per il criterio differenziale usa la funzione dedicata. Si consiglia di verificare il testo vigente e la zonizzazione del comune.'),
      sezioneInfo('CLASSE DI ZONIZZAZIONE', 'classe'),
      Wrap(spacing: 8, children: [for (var i = 0; i < 6; i++) ChoiceChip(label: Text(_classi[i]), selected: cls == i, onSelected: (_) => setState(() => cls = i))]),
      sezioneInfo('PERIODO DI RIFERIMENTO', 'periodo'),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('Diurno 6-22')), ButtonSegment(value: true, label: Text('Notturno 22-6'))],
        selected: {notte},
        onSelectionChanged: (s) => setState(() => notte = s.first),
      ),
      const SizedBox(height: 10),
      InfoBox('Classe ${_classi[cls]}, ${notte ? 'notturno' : 'diurno'}: limite assoluto di immissione $im dB(A); limite di emissione $em dB(A).'),
      sezioneInfo('IMMISSIONE', 'immissione'),
      Field(c: la, label: 'Rumore ambientale LA', suffix: 'dB(A)', info: 'LA', fonte: Fonte.laeq, onChanged: up),
      sezioneInfo('EMISSIONE (FACOLTATIVO)', 'emissione'),
      Field(c: ls, label: 'Livello della sola sorgente LS', suffix: 'dB(A)', info: 'LS', fonte: Fonte.laeq, onChanged: up),
      ...esiti,
    ]);
  }
}

// ───────── Requisiti acustici passivi (D.P.C.M. 5/12/1997) ─────────
// Tabella B: [R'w >=, D2m,nT,w >=, L'n,w <=, LASmax <=, LAeq <=]
const _passivi = {
  'D': [55, 45, 58, 35, 25],
  'A, C': [50, 40, 63, 35, 35],
  'E': [50, 48, 58, 35, 25],
  'B, F, G': [50, 42, 55, 35, 35],
};
const _cat = {
  'A': ['A, C', 'Residenze'],
  'B': ['B, F, G', 'Uffici'],
  'C': ['A, C', 'Alberghi'],
  'D': ['D', 'Ospedali'],
  'E': ['E', 'Scuole'],
  'F': ['B, F, G', 'Ricreative/culto'],
  'G': ['B, F, G', 'Commerciali'],
};

class PassiviPage extends StatefulWidget {
  const PassiviPage({super.key});
  @override
  State<PassiviPage> createState() => _PassiviState();
}

class _PassiviState extends State<PassiviPage> {
  String cat = 'A';
  final cs = List.generate(5, (_) => TextEditingController());
  void up() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final lim = _passivi[_cat[cat]![0]]!;
    const nomi = ["R'w partizioni", 'D2m,nT,w facciata', "L'n,w calpestio", 'LASmax impianti discontinui', 'LAeq impianti continui'];
    const unita = ['dB', 'dB', 'dB', 'dB(A)', 'dB(A)'];
    const minimo = [true, true, false, false, false];
    final esiti = <Widget>[];
    for (var i = 0; i < 5; i++) {
      final v = pn(cs[i].text);
      if (v == null) continue;
      final ok = minimo[i] ? v >= lim[i] : v <= lim[i];
      esiti.add(Esito(nomi[i], 'Misurato ${f1(v)} ${unita[i]}, limite ${minimo[i] ? '≥' : '≤'} ${lim[i]} ${unita[i]}: ${ok ? 'rispettato' : 'non rispettato'}.', ok));
    }
    return page('Requisiti acustici passivi', [
      const InfoBox('Tabella B del D.P.C.M. 5/12/1997 per gli edifici classificati nella Tabella A. I limiti si riferiscono ai valori misurati secondo le norme di misura applicabili: si consiglia di verificare il testo vigente e le eventuali tolleranze.'),
      sezioneInfo('CATEGORIA DELL\'EDIFICIO', 'categoria'),
      Wrap(
        spacing: 8,
        children: [for (final e in _cat.entries) ChoiceChip(label: Text('${e.key} · ${e.value[1]}'), selected: cat == e.key, onSelected: (_) => setState(() => cat = e.key))],
      ),
      const SizedBox(height: 10),
      InfoBox("Categoria $cat: R'w ≥ ${lim[0]}, D2m,nT,w ≥ ${lim[1]}, L'n,w ≤ ${lim[2]}, LASmax ≤ ${lim[3]} dB(A), LAeq ≤ ${lim[4]} dB(A)."),
      for (var i = 0; i < 5; i++) Field(c: cs[i], label: nomi[i], suffix: unita[i], info: const ['Rw', 'D2m', 'Ln', 'LASmaxImp', 'LAeqImp'][i], fonte: i == 3 ? Fonte.lasMax : (i == 4 ? Fonte.laeq : null), onChanged: up),
      ...esiti,
    ]);
  }
}
