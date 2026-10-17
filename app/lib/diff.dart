import 'package:flutter/material.dart';
import 'core.dart';

/// Soglia di applicabilità del criterio differenziale (D.P.C.M. 14/11/1997, art. 4).
double soglia(bool notte, bool aperte) => aperte ? (notte ? 40.0 : 50.0) : (notte ? 25.0 : 35.0);

class DiffState {
  static final i = DiffState();
  bool notte = false, aperte = true, classe6 = false, esclusa = false;
  double? la, lr;
  int? laSec, lrSec;

  /// true se il livello supera la soglia e la verifica è necessaria; false se non lo è; null se non valutabile.
  bool? richiesto(double leq, int secondi) {
    if (leq.isNaN || secondi < 5) return null;
    if (classe6 || esclusa) return false;
    return r05(leq) >= soglia(notte, aperte);
  }

  void azzera() {
    la = null;
    lr = null;
    laSec = null;
    lrSec = null;
  }
}

class DiffCard extends StatefulWidget {
  final double Function()? currentLaeq;
  final int Function()? currentSeconds;
  final VoidCallback? onCaptured;
  final bool nudo;
  const DiffCard({super.key, this.currentLaeq, this.currentSeconds, this.onCaptured, this.nudo = false});
  @override
  State<DiffCard> createState() => _DiffCardState();
}

class _DiffCardState extends State<DiffCard> {
  final st = DiffState.i;
  late final TextEditingController laC = TextEditingController(text: st.la == null ? '' : f1(st.la!));
  late final TextEditingController lrC = TextEditingController(text: st.lr == null ? '' : f1(st.lr!));

  @override
  void dispose() {
    laC.dispose();
    lrC.dispose();
    super.dispose();
  }

  void cattura(bool isLA) {
    final v = widget.currentLaeq!.call();
    final s = widget.currentSeconds!.call();
    if (v.isNaN || s < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Misura troppo breve: attendi qualche secondo.')));
      return;
    }
    final x = (v * 10).round() / 10;
    setState(() {
      if (isLA) {
        st.la = x;
        st.laSec = s;
        laC.text = f1(x);
      } else {
        st.lr = x;
        st.lrSec = s;
        lrC.text = f1(x);
      }
    });
    widget.onCaptured?.call();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registrato ${isLA ? 'LA' : 'LR'} = ${f1(x)} dB(A) (durata ${mmss(s)}). Misura azzerata: puoi misurare l\'altra condizione.')));
  }

  Widget risultato() {
    final per = st.notte ? 'notturno' : 'diurno';
    final fin = st.aperte ? 'aperte' : 'chiuse';
    final sg = soglia(st.notte, st.aperte);
    if (st.classe6) return const Esito('Criterio differenziale', 'Non si applica nelle aree di classe VI.', null);
    if (st.esclusa) {
      return const Esito('Criterio differenziale', 'Sorgente esclusa dal criterio differenziale (per esempio infrastrutture di trasporto o impianti di comfort interni all\'edificio).', null);
    }
    if (st.la == null) return const InfoBox('Registra o inserisci il rumore ambientale LA (sorgente attiva, al ricettore) per verificare se il differenziale si applica.');
    final a = r05(st.la!);
    if (a < sg) {
      return Esito('Differenziale non applicabile', 'LA = ${f1(a)} dB(A) è inferiore alla soglia di ${f1(sg, 0)} dB(A) (periodo $per, finestre $fin).', null);
    }
    if (st.lr == null) {
      return Esito('Verifica necessaria', 'LA = ${f1(a)} dB(A) ≥ soglia di ${f1(sg, 0)} dB(A). Misura ora il rumore residuo LR con la sorgente spenta e registralo.', null);
    }
    final r = r05(st.lr!);
    final d = a - r;
    final lim = st.notte ? 3 : 5;
    final ok = d <= lim;
    return Esito(ok ? 'Differenziale rispettato' : 'Differenziale superato', 'ΔL = LA − LR = ${f1(a)} − ${f1(r)} = ${f1(d)} dB, limite $lim dB (periodo $per, finestre $fin).', ok);
  }

  @override
  Widget build(BuildContext context) {
    final conMeter = widget.currentLaeq != null;
    final cur = widget.currentLaeq?.call() ?? double.nan;
    final secs = widget.currentSeconds?.call() ?? 0;
    final sg = soglia(st.notte, st.aperte);
    final ric = st.richiesto(cur, secs);
    return Container(
      width: double.infinity,
      padding: widget.nudo ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: widget.nudo ? null : BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: cLine)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.nudo)
            const Row(children: [
            Icon(Icons.rule, color: cTeal),
            SizedBox(width: 8),
            Text('Verifica differenziale', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: cInk)),
            InfoDot('dL'),
          ]),
          sezioneInfo('CONDIZIONI DI MISURA AL RICETTORE', 'condizioni'),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: false, label: Text('Diurno 6-22')), ButtonSegment(value: true, label: Text('Notturno 22-6'))],
              selected: {st.notte},
              onSelectionChanged: (s) => setState(() => st.notte = s.first),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: true, label: Text('Finestre aperte')), ButtonSegment(value: false, label: Text('Finestre chiuse'))],
              selected: {st.aperte},
              onSelectionChanged: (s) => setState(() => st.aperte = s.first),
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Row(children: [Text('Esclusioni', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cDark)), InfoDot('esclusioni')]),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Area in classe VI', style: TextStyle(fontSize: 14)),
                value: st.classe6,
                onChanged: (v) => setState(() => st.classe6 = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sorgente esclusa (infrastrutture di trasporto, impianti di comfort dell\'edificio)', style: TextStyle(fontSize: 14)),
                value: st.esclusa,
                onChanged: (v) => setState(() => st.esclusa = v),
              ),
            ],
          ),
          InfoBox('Con queste condizioni il differenziale si applica se LA ≥ ${f1(sg, 0)} dB(A); limite ΔL = ${st.notte ? 3 : 5} dB.'),
          if (conMeter && ric != null)
            ric
                ? Esito('Verifica differenziale necessaria', 'Il LAeq in corso (${f1(r05(cur))} dB(A)) supera la soglia di ${f1(sg, 0)} dB(A). Registra la misura come LA, poi misura il residuo LR a sorgente spenta.', null)
                : Esito('Soglia non superata', st.classe6 || st.esclusa ? 'Per le esclusioni indicate il differenziale non si applica.' : 'Il LAeq in corso (${f1(r05(cur))} dB(A)) è sotto la soglia di ${f1(sg, 0)} dB(A): differenziale non applicabile.', true),
          const SizedBox(height: 4),
          Field(c: laC, label: 'LA rumore ambientale (sorgente attiva)', suffix: 'dB(A)', info: 'LA', fonte: conMeter ? null : Fonte.laeq, onChanged: () => setState(() {
                st.la = pn(laC.text);
                st.laSec = null;
              })),
          if (conMeter)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(onPressed: () => cattura(true), icon: const Icon(Icons.download), label: const Text('Registra LAeq attuale come LA')),
              ),
            ),
          Field(c: lrC, label: 'LR rumore residuo (sorgente spenta)', suffix: 'dB(A)', info: 'LR', fonte: conMeter ? null : Fonte.laeq, onChanged: () => setState(() {
                st.lr = pn(lrC.text);
                st.lrSec = null;
              })),
          if (conMeter)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(onPressed: () => cattura(false), icon: const Icon(Icons.download), label: const Text('Registra LAeq attuale come LR')),
              ),
            ),
          risultato(),
          const Text('Livelli arrotondati a 0,5 dB (D.M. 16/03/1998). Si consiglia di verificare il caso specifico e il testo normativo vigente.', style: TextStyle(fontSize: 11.5, color: cDark, height: 1.3)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                st.azzera();
                laC.clear();
                lrC.clear();
              }),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Azzera verifica'),
            ),
          ),
        ],
      ),
    );
  }
}

class DiffPage extends StatelessWidget {
  const DiffPage({super.key});
  @override
  Widget build(BuildContext context) => page('Verifica differenziale', const [
        InfoBox('Limite differenziale di immissione (D.P.C.M. 14/11/1997, art. 4): inserisci a mano LA e LR misurati con il tuo strumento. Se hai una misura del telefono, compare il pulsante per importarla; la verifica integrata nel Fonometro registra LA e LR direttamente dalla misura in corso.'),
        DiffCard(),
      ]);
}
