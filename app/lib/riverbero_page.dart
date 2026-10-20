import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core.dart';

class Mat {
  final String nome;
  final double a; // α per m² (superfici) oppure m² sabine per unità
  final bool unita, custom, utente;
  const Mat(this.nome, this.a, {this.unita = false, this.custom = false, this.utente = false});
}

// Coefficienti indicativi intorno a 500-1000 Hz (valori di letteratura): si consiglia di usare i dati del produttore.
const materiali = <Mat>[
  Mat('Intonaco liscio / calcestruzzo', 0.03),
  Mat('Muratura a vista', 0.04),
  Mat('Cartongesso su intercapedine', 0.07),
  Mat('Pannello in legno su intercapedine', 0.10),
  Mat('Pavimento in ceramica / pietra', 0.02),
  Mat('Parquet / legno su massetto', 0.07),
  Mat('PVC / linoleum', 0.03),
  Mat('Moquette sottile', 0.15),
  Mat('Moquette spessa', 0.45),
  Mat('Vetro (finestre)', 0.04),
  Mat('Porta in legno', 0.06),
  Mat('Tende pesanti drappeggiate', 0.50),
  Mat('Libreria con libri', 0.30),
  Mat('Controsoffitto fonoassorbente (pannelli minerali)', 0.70),
  Mat('Pannelli in lana minerale (50 mm)', 0.90),
  Mat('Pannelli in schiuma acustica (50 mm)', 0.60),
  Mat('Persona seduta (m² sabine cad.)', 0.45, unita: true),
  Mat('Persona in piedi (m² sabine cad.)', 0.40, unita: true),
  Mat('Sedia in legno o plastica (m² sabine cad.)', 0.02, unita: true),
  Mat('Sedia o poltrona imbottita (m² sabine cad.)', 0.25, unita: true),
  Mat('Scrivania o tavolo (m² sabine cad.)', 0.10, unita: true),
  Mat('Arredi vari, a corpo (quantità in m² sabine)', 1.0, unita: true),
  Mat('Personalizzato: α della superficie', 0.0, custom: true),
  Mat('Personalizzato: m² sabine per unità', 0.0, unita: true, custom: true),
];

class Riga {
  Mat m;
  final q = TextEditingController();
  final al = TextEditingController();
  Riga(this.m);
}

class RiverberoPage extends StatefulWidget {
  const RiverberoPage({super.key});
  @override
  State<RiverberoPage> createState() => _RiverState();
}

class _RiverState extends State<RiverberoPage> {
  final lC = TextEditingController(), wC = TextEditingController(), hC = TextEditingController();
  List<Mat> utente = [];
  late final List<Riga> righe = [Riga(materiali[0])];
  void up() => setState(() {});

  List<Mat> get tutti => [...materiali, ...utente];

  @override
  void initState() {
    super.initState();
    caricaUtente();
  }

  Future<void> caricaUtente() async {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('mat_utente') ?? [];
    final out = <Mat>[];
    for (final s in l) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        out.add(Mat('${j['n']}', (j['a'] as num).toDouble(), unita: j['u'] == true, utente: true));
      } catch (_) {}
    }
    if (mounted) setState(() => utente = out);
  }

  Future<void> salvaUtente() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('mat_utente', [for (final m in utente) jsonEncode({'n': m.nome, 'a': m.a, 'u': m.unita})]);
  }

  void nuovoMateriale() {
    final nome = TextEditingController(), alfa = TextEditingController();
    var unita = false;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Nuovo materiale personale'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome del materiale')),
                TextField(
                  controller: alfa,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: unita ? 'm² sabine per unità' : 'Coefficiente α (0-1)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Elemento a quantità (non è una superficie)', style: TextStyle(fontSize: 14)),
                  value: unita,
                  onChanged: (v) => ss(() => unita = v),
                ),
                const Text('Il materiale resta in archivio e compare nei menù a tendina delle prossime volte.', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            FilledButton(
              onPressed: () async {
                final a = pn(alfa.text);
                final n = nome.text.trim();
                if (n.isEmpty || a == null || a < 0 || (!unita && a > 1)) return;
                final mat = Mat(n, a, unita: unita, utente: true);
                setState(() {
                  utente = [...utente, mat];
                  righe.last.m = mat;
                });
                await salvaUtente();
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (d) => AlertDialog(
                    icon: const Icon(Icons.check_circle, color: cOk, size: 36),
                    title: const Text('Materiale aggiunto'),
                    content: Text('"${mat.nome}" (${mat.unita ? '${f1(mat.a, 2)} m² sabine per unità' : 'α = ${f1(mat.a, 2)}'}) è stato salvato nell\'archivio ed è già selezionato nell\'ultima riga. Lo ritroverai nei menù a tendina anche le prossime volte.'),
                    actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
                  ),
                );
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  void gestisci() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Materiali personali'),
          content: SizedBox(
            width: double.maxFinite,
            child: utente.isEmpty
                ? const Text('Nessun materiale personale salvato.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in utente)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(m.nome),
                          subtitle: Text(m.unita ? '${f1(m.a, 2)} m² sabine per unità' : 'α = ${f1(m.a, 2)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              setState(() {
                                utente = utente.where((x) => x != m).toList();
                                for (final r in righe) {
                                  if (r.m == m) r.m = materiali[0];
                                }
                              });
                              await salvaUtente();
                              ss(() {});
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi'))],
        ),
      ),
    );
  }

  Mat trova(String inizio) => materiali.firstWhere((m) => m.nome.startsWith(inizio));

  void precompila(double l, double w, double h) {
    setState(() {
      final r1 = Riga(trova('Pavimento'))..q.text = f1(l * w, 1);
      final r2 = Riga(trova('Intonaco'))..q.text = f1(l * w, 1);
      final r3 = Riga(trova('Intonaco'))..q.text = f1(2 * h * (l + w), 1);
      righe
        ..clear()
        ..addAll([r1, r2, r3]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = pn(lC.text), w = pn(wC.text), h = pn(hC.text);
    final okDim = l != null && w != null && h != null && l > 0 && w > 0 && h > 0;
    final vol = okDim ? l * w * h : double.nan;
    final sTot = okDim ? 2 * (l * w + l * h + w * h) : double.nan;
    var aTot = 0.0, sIns = 0.0;
    for (final r in righe) {
      final q = pn(r.q.text) ?? 0;
      final a = r.m.custom ? (pn(r.al.text) ?? 0) : r.m.a;
      aTot += q * a;
      if (!r.m.unita) sIns += q;
    }
    Widget esito = const SizedBox.shrink();
    var completo = false;
    if (okDim) {
      final diff = sIns - sTot;
      final tol = max(0.5, 0.01 * sTot);
      if (diff.abs() <= tol) {
        completo = true;
        esito = Esito('Superfici complete', 'Superfici inserite ${f1(sIns)} m² su ${f1(sTot)} m² di superficie dell\'ambiente.', true);
      } else if (diff < 0) {
        esito = Esito('Superfici in difetto', 'Inserite ${f1(sIns)} m² su ${f1(sTot)} m²: mancano ${f1(-diff)} m².', null);
      } else {
        esito = Esito('Superfici in eccesso', 'Inserite ${f1(sIns)} m² su ${f1(sTot)} m²: ${f1(diff)} m² in più.', false);
      }
    }
    var tS = double.nan, tE = double.nan, am = double.nan;
    if (okDim && aTot > 0) {
      tS = 0.161 * vol / aTot;
      am = aTot / sTot;
      if (am < 1) tE = 0.161 * vol / (-sTot * log(1 - am));
    }
    return page('Tempo di riverberazione', [
      const InfoBox('Sabine: T = 0,161·V / A. Eyring: T = 0,161·V / (−S·ln(1 − α medio)). A è l\'area di assorbimento equivalente (Σ Si·αi più persone e arredi). Formule per campo sonoro diffuso: si consiglia prudenza con ambienti molto assorbenti o di forma irregolare.'),
      sezioneInfo('DIMENSIONI DELLA STANZA', 'dim'),
      Row(
        children: [
          Expanded(child: Field(c: lC, label: 'Lunghezza', suffix: 'm', onChanged: up, signed: false)),
          const SizedBox(width: 8),
          Expanded(child: Field(c: wC, label: 'Larghezza', suffix: 'm', onChanged: up, signed: false)),
          const SizedBox(width: 8),
          Expanded(child: Field(c: hC, label: 'Altezza', suffix: 'm', onChanged: up, signed: false)),
        ],
      ),
      if (okDim) InfoBox('Volume ${f1(vol)} m³ · pavimento ${f1(l * w)} m² · soffitto ${f1(l * w)} m² · pareti ${f1(2 * h * (l + w))} m² · superficie totale ${f1(sTot)} m².'),
      if (okDim)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: OutlinedButton.icon(onPressed: () => precompila(l, w, h), icon: const Icon(Icons.auto_fix_high), label: const Text('Precompila pavimento, soffitto e pareti')),
        ),
      sezioneInfo('SUPERFICI E MATERIALI', 'mat'),
      for (final r in righe) _riga(r),
      OutlinedButton.icon(
        onPressed: () => setState(() => righe.add(Riga(materiali[0]))),
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi superficie o elemento'),
      ),
      Row(
        children: [
          TextButton.icon(onPressed: nuovoMateriale, icon: const Icon(Icons.playlist_add), label: const Text('Nuovo materiale')),
          TextButton.icon(onPressed: gestisci, icon: const Icon(Icons.inventory_2_outlined), label: Text('Archivio (${utente.length})')),
        ],
      ),
      const SizedBox(height: 8),
      esito,
      ResultCard('T60 secondo Sabine', '${f1(tS, 2)} s', info: 'T60', sub: okDim ? 'A totale ${f1(aTot, 2)} m² · α medio ${f1(am, 2)}' : null),
      ResultCard('T60 secondo Eyring', '${f1(tE, 2)} s', info: 'T60'),
      if (okDim && !completo && aTot > 0) const InfoBox('Le superfici non risultano complete: i tempi di riverbero sono indicativi. Si consiglia di completare l\'elenco prima di usarli.', color: cWarn, icon: Icons.warning_amber),
      const InfoBox('Coefficienti α indicativi, valutati intorno a 500-1000 Hz. Per un calcolo di dettaglio si consiglia di usare i dati del produttore (materiale personale) e di ripetere il calcolo per bande di frequenza.'),
    ]);
  }

  Widget _riga(Riga r) {
    final m = r.m;
    final q = pn(r.q.text) ?? 0;
    final a = m.custom ? (pn(r.al.text) ?? 0) : m.a;
    final lista = tutti;
    return Container(
      key: ObjectKey(r),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: cLine)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Mat>(
                  key: ValueKey('${identityHashCode(r)}-${lista.length}-${identityHashCode(m)}'),
                  initialValue: m,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Materiale / elemento', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
                  items: [
                    for (final k in lista)
                      DropdownMenuItem(
                        value: k,
                        child: Text(
                          k.custom ? k.nome : '${k.utente ? '★ ' : ''}${k.nome} · ${f1(k.a, 2)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => r.m = v ?? r.m),
                ),
              ),
              if (righe.length > 1)
                IconButton(
                  onPressed: () => setState(() => righe.remove(r)),
                  icon: const Icon(Icons.remove_circle_outline, color: cDark),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Field(c: r.q, label: m.unita ? 'Quantità' : 'Area', suffix: m.unita ? (m.nome.startsWith('Arredi') || m.custom ? 'm² sab.' : 'n.') : 'm²', info: 'Sup', onChanged: up, signed: false)),
              if (m.custom) ...[
                const SizedBox(width: 8),
                Expanded(child: Field(c: r.al, label: m.unita ? 'm² sab./unità' : 'α (0-1)', info: 'alfa', onChanged: up, signed: false)),
              ],
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 14, right: 8),
                child: Text('A = ${f1(q * a, 2)}', style: const TextStyle(fontWeight: FontWeight.w700, color: cTeal)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
