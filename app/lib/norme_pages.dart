import 'package:flutter/material.dart';
import 'core.dart';
import 'glossario.dart';

// ───────── Limiti di zona e differenziale (D.P.C.M. 14/11/1997) ─────────
const _limEm = [[45, 35], [50, 40], [55, 45], [60, 50], [65, 55], [65, 65]];
const _limIm = [[50, 40], [55, 45], [60, 50], [65, 55], [70, 60], [70, 70]];
const _classi = ['I', 'II', 'III', 'IV', 'V', 'VI'];

class ZonePage extends StatelessWidget {
  const ZonePage({super.key});
  @override
  Widget build(BuildContext context) => page('Limiti di zona', const [ZoneCard()]);
}

class ZoneCard extends StatefulWidget {
  const ZoneCard({super.key});
  @override
  State<ZoneCard> createState() => _ZoneState();
}

class _ZoneState extends State<ZoneCard> {
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

class PassiviPage extends StatelessWidget {
  const PassiviPage({super.key});

  Widget cella(String t, {bool h = false, bool first = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
        child: Text(
          t,
          textAlign: first ? TextAlign.left : TextAlign.center,
          style: TextStyle(fontSize: h ? 11.5 : 13.5, fontWeight: (h || first) ? FontWeight.w700 : FontWeight.w500, color: h ? Colors.white : cInk),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const intest = ["R'w ≥", 'D2m,nT,w ≥', "L'n,w ≤", 'LASmax ≤', 'LAeq ≤'];
    var n = 0;
    final righe = <TableRow>[
      TableRow(decoration: const BoxDecoration(color: cTeal), children: [cella('Categoria', h: true, first: true), for (final h in intest) cella(h, h: true)]),
      for (final e in _cat.entries)
        TableRow(
          decoration: BoxDecoration(color: (n++).isEven ? Colors.white : cBg),
          children: [cella('${e.key} · ${e.value[1]}', first: true), for (final v in _passivi[e.value[0]]!) cella('$v')],
        ),
    ];
    return page('Requisiti acustici passivi', [
      const InfoBox('Tabelle del D.P.C.M. 5/12/1997: categorie degli edifici (Tab. A) e limiti per ciascun indice (Tab. B). Valori in dB; LASmax e LAeq in dB(A). Si consiglia di verificare sempre il testo vigente e le norme di misura applicabili.'),
      sezione('LIMITI PER CATEGORIA DI EDIFICIO'),
      Table(
        border: TableBorder.all(color: cLine, borderRadius: BorderRadius.circular(12)),
        columnWidths: const {0: FlexColumnWidth(2.3)},
        defaultColumnWidth: const FlexColumnWidth(1),
        children: righe,
      ),
      const SizedBox(height: 6),
      const Text('≥ il valore misurato deve essere maggiore o uguale; ≤ minore o uguale.', style: TextStyle(fontSize: 12, color: cDark)),
      sezione('COSA SIGNIFICANO GLI INDICI'),
      for (final k in ['Rw', 'D2m', 'Ln', 'LASmaxImp', 'LAeqImp', 'categoria'])
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: cLine)),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(glossario[k]!.titolo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: cInk)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(glossario[k]!.testo, style: const TextStyle(fontSize: 14, height: 1.4, color: cInk))],
          ),
        ),
    ]);
  }
}
