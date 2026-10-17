import 'package:flutter/material.dart';
import 'calc_pages.dart';
import 'core.dart';
import 'diff.dart';
import 'glossario_page.dart';
import 'meter_page.dart';
import 'norme_pages.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IRumore',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: cTeal, surface: cBg),
          scaffoldBackgroundColor: cBg,
        ),
        home: const Home(),
      );
}

class Home extends StatelessWidget {
  const Home({super.key});

  void go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  Widget mini(BuildContext c, IconData i, String t, String s, Widget w) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => go(c, w),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: cLine)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: cMint, borderRadius: BorderRadius.circular(12)),
                  child: Icon(i, color: cTeal, size: 24),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cInk)),
                    Text(s, style: const TextStyle(fontSize: 12, color: cDark)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(color: cTeal, borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/logo_bianco.png', height: 30, alignment: Alignment.centerLeft),
                      const SizedBox(height: 18),
                      const Text('IRumore', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
                      const Text('Strumenti di acustica per il campo', style: TextStyle(color: Color(0xFFBFE3DC), fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  Material(
                    color: cDark,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => go(context, const MeterPage()),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: cTeal, borderRadius: BorderRadius.circular(16)),
                              child: const Icon(Icons.mic, color: Colors.white, size: 32),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Fonometro', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                                  Text('dB(A) · LAS · LAeq · LASmax/min', style: TextStyle(color: Color(0xFFBFE3DC), fontSize: 13)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  sezione('CALCOLI IN DECIBEL'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.25,
                    children: [
                      mini(context, Icons.add_circle_outline, 'Somma', 'Più sorgenti, un livello', const SommaPage()),
                      mini(context, Icons.remove_circle_outline, 'Differenza', 'Togli il fondo', const DifferenzaPage()),
                      mini(context, Icons.straighten, 'Propagazione', 'Livello e distanza', const PropagazionePage()),
                      mini(context, Icons.swap_horiz, 'Potenza ⇄ Pressione', 'Lw e Lp', const PotenzaPage()),
                      mini(context, Icons.functions, 'Media energetica', 'Leq di più intervalli', const MediaPage()),
                      mini(context, Icons.graphic_eq, 'Riverberazione', 'Sabine ed Eyring', const RiverberoPage()),
                    ],
                  ),
                  sezione('NORME E VERIFICHE'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.25,
                    children: [
                      mini(context, Icons.gavel, 'Limiti di zona', 'Immissione ed emissione', const ZonePage()),
                      mini(context, Icons.rule, 'Differenziale', 'Verifica da campo', const DiffPage()),
                      mini(context, Icons.apartment, 'Requisiti passivi', 'D.P.C.M. 5/12/1997', const PassiviPage()),
                      mini(context, Icons.menu_book, 'Glossario', 'Cosa sono LA, LR, LAeq...', const GlossarioPage()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Studio Agfor · Misure con microfono di smartphone: indicative, non conformi alla IEC 61672.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cDark, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
