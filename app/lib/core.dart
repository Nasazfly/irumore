import 'dart:math';
import 'package:flutter/material.dart';
import 'glossario.dart';
import 'schemi.dart';

const cTeal = Color(0xFF0F6F61);
const cDark = Color(0xFF0A4A41);
const cInk = Color(0xFF10231F);
const cBg = Color(0xFFF2F7F6);
const cMint = Color(0xFFDDEDE9);
const cLine = Color(0xFFCFE0DC);
const cWarn = Color(0xFFB45309);
const cOk = Color(0xFF1B7F4B);
const cBad = Color(0xFFB3261E);

enum Fonte { laeq, lasMax, lasMin, distanza }

/// Ultima misura del fonometro del telefono, disponibile per le altre funzioni.
class UltimaMisura {
  static final i = UltimaMisura();
  double laeq = double.nan, lasMax = double.nan, lasMin = double.nan;
  double distanza = double.nan; // distanza misurata sulla mappa (m)
  int secondi = 0;
  DateTime? quando;
  bool get valida => !laeq.isNaN && secondi >= 3;
  void aggiorna(double a, double b, double c, int s) {
    laeq = a;
    lasMax = b;
    lasMin = c;
    secondi = s;
    quando = DateTime.now();
  }

  void azzera() {
    laeq = double.nan;
    lasMax = double.nan;
    lasMin = double.nan;
    secondi = 0;
    quando = null;
  }
}

double? pn(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String f1(double v, [int d = 1]) => (v.isNaN || v.isInfinite) ? '–' : v.toStringAsFixed(d).replaceAll('.', ',');

double db10(double x) => 10 * log(x) / ln10;
double pw10(double db) => pow(10, db / 10).toDouble();
double r05(double x) => (x * 2).round() / 2;

String mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

Widget page(String title, List<Widget> children) => Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cBg,
        foregroundColor: cInk,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: children)),
    );

void showInfo(BuildContext context, String key) {
  final v = glossario[key];
  if (v == null) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v.titolo, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: cInk)),
            const SizedBox(height: 10),
            Text(v.testo, style: const TextStyle(fontSize: 15.5, height: 1.45, color: cInk)),
            if (key == 'Q') const QSchemi(),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Capito'))),
          ],
        ),
      ),
    ),
  );
}

class InfoDot extends StatelessWidget {
  final String k;
  final Color color;
  const InfoDot(this.k, {super.key, this.color = cTeal});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Che cos\'è?',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        icon: Icon(Icons.info_outline, size: 20, color: color),
        onPressed: () => showInfo(context, k),
      );
}

Widget sezioneInfo(String t, String k) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Row(children: [
        Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cDark, letterSpacing: 0.4)),
        InfoDot(k),
      ]),
    );

class Field extends StatelessWidget {
  final TextEditingController c;
  final String label;
  final String? suffix;
  final VoidCallback onChanged;
  final bool signed;
  final Fonte? fonte;
  final String? info;
  const Field({super.key, required this.c, required this.label, required this.onChanged, this.suffix, this.signed = true, this.fonte, this.info});
  @override
  Widget build(BuildContext context) {
    final um = UltimaMisura.i;
    double? val;
    var nome = '';
    if (fonte == Fonte.distanza) {
      if (!um.distanza.isNaN) {
        val = um.distanza;
        nome = 'distanza';
      }
    } else if (fonte != null && um.valida) {
      if (fonte == Fonte.laeq) {
        val = um.laeq;
        nome = 'LAeq';
      } else if (fonte == Fonte.lasMax) {
        val = um.lasMax;
        nome = 'LASmax';
      } else {
        val = um.lasMin;
        nome = 'LASmin';
      }
    }
    final usa = (val != null && !val.isNaN) ? val : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: c,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              suffixIcon: info == null ? null : InfoDot(info!),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: cLine)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: cLine)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: cTeal, width: 2)),
            ),
          ),
          if (usa != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ActionChip(
                avatar: const Icon(Icons.phone_android, size: 18, color: cTeal),
                label: Text(fonte == Fonte.distanza ? 'Usa distanza misurata sulla mappa: ${f1(usa)} m' : 'Usa dato del fonometro del telefono: $nome ${f1(usa)} dB'),
                onPressed: () {
                  c.text = f1(usa);
                  onChanged();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class ResultCard extends StatelessWidget {
  final String label, value;
  final String? sub, info;
  const ResultCard(this.label, this.value, {super.key, this.sub, this.info});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6, bottom: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: cTeal, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label, style: const TextStyle(color: Color(0xFFBFE3DC), fontSize: 13, fontWeight: FontWeight.w600)),
              if (info != null) InfoDot(info!, color: const Color(0xFFBFE3DC)),
            ]),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub!, style: const TextStyle(color: Color(0xFFD8EEE9), fontSize: 13)),
          ],
        ),
      );
}

class InfoBox extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const InfoBox(this.text, {super.key, this.color = cDark, this.icon = Icons.info_outline});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cMint, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13.5, height: 1.35))),
          ],
        ),
      );
}

class Esito extends StatelessWidget {
  final String titolo, dettaglio;
  final bool? ok;
  const Esito(this.titolo, this.dettaglio, this.ok, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = ok == null ? cWarn : (ok! ? cOk : cBad);
    final i = ok == null ? Icons.remove_circle_outline : (ok! ? Icons.check_circle : Icons.cancel);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: c, width: 1.5)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titolo, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(dettaglio, style: const TextStyle(color: cInk, fontSize: 13.5, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget sezione(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cDark, letterSpacing: 0.4)),
    );

class Apribile extends StatelessWidget {
  final String titolo;
  final IconData icona;
  final Widget child;
  final bool aperto;
  const Apribile({super.key, required this.titolo, required this.icona, required this.child, this.aperto = false});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: cLine)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: aperto,
            maintainState: true,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Icon(icona, color: cTeal),
            title: Text(titolo, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: cInk)),
            children: [child],
          ),
        ),
      );
}
