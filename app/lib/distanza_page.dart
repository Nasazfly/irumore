import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'core.dart';

double distM(LatLng a, LatLng b) {
  const r = 6371000.0;
  final p1 = a.latitude * pi / 180, p2 = b.latitude * pi / 180;
  final dp = (b.latitude - a.latitude) * pi / 180, dl = (b.longitude - a.longitude) * pi / 180;
  final h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
  return 2 * r * asin(min(1.0, sqrt(h)));
}

class _Ed {
  final LatLng p;
  final String tipo;
  _Ed(this.p, this.tipo);
}

const _abitativi = {'house', 'residential', 'apartments', 'detached', 'semidetached_house', 'terrace', 'bungalow', 'dormitory', 'farm'};

class DistanzaPage extends StatefulWidget {
  const DistanzaPage({super.key});
  @override
  State<DistanzaPage> createState() => _DistState();
}

class _DistState extends State<DistanzaPage> {
  final mc = MapController();
  bool mapReady = false;
  StreamSubscription<Position>? sub;
  LatLng? me, origin, b;
  int modo = 0;
  double raggio = 100;
  final ric = <LatLng>[];
  List<_Ed> edifici = [];
  double? raggioEd;
  bool cerco = false;
  String? err, nota;
  bool centrato = false;

  LatLng? get a => origin ?? me;

  @override
  void initState() {
    super.initState();
    avvia();
  }

  @override
  void dispose() {
    sub?.cancel();
    mc.dispose();
    super.dispose();
  }

  Future<void> avvia() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => err = 'Permesso di posizione negato: abilitalo dalle impostazioni del telefono.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => err = 'Attiva i servizi di localizzazione (GPS) del telefono.');
        return;
      }
      sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 1)).listen((p) {
        if (!mounted) return;
        final pos = LatLng(p.latitude, p.longitude);
        setState(() => me = pos);
        if (!centrato && mapReady) {
          centrato = true;
          mc.move(pos, 18);
        }
      });
    } catch (e) {
      if (mounted) setState(() => err = 'Posizione non disponibile: $e');
    }
  }

  Future<void> contaEdifici() async {
    final c = a;
    if (c == null) {
      setState(() => nota = 'Serve un punto A: attendi il GPS o tieni premuto sulla mappa.');
      return;
    }
    setState(() {
      cerco = true;
      nota = null;
    });
    try {
      final rr = raggio.round();
      final q = '[out:json][timeout:25];(way["building"](around:$rr,${c.latitude},${c.longitude});relation["building"](around:$rr,${c.latitude},${c.longitude}););out center tags;';
      final r = await http
          .post(Uri.parse('https://overpass-api.de/api/interpreter'), headers: {'User-Agent': 'EnviNoise/0.6 (Studio Agfor)'}, body: {'data': q})
          .timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) throw 'Servizio OpenStreetMap non disponibile (${r.statusCode}). Riprova tra poco.';
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final out = <_Ed>[];
      for (final e in (j['elements'] as List)) {
        final cen = e['center'];
        if (cen == null) continue;
        final tags = (e['tags'] as Map?) ?? {};
        out.add(_Ed(LatLng((cen['lat'] as num).toDouble(), (cen['lon'] as num).toDouble()), '${tags['building'] ?? 'yes'}'));
      }
      setState(() {
        edifici = out;
        raggioEd = raggio;
      });
    } catch (e) {
      setState(() => nota = '$e');
    }
    if (mounted) setState(() => cerco = false);
  }

  Marker pin(LatLng p, String t, Color col) => Marker(
        point: p,
        width: 28,
        height: 28,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pa = a;
    final dentro = pa == null ? 0 : ric.where((r) => distM(pa, r) <= raggio).length;
    final markers = <Marker>[
      if (origin != null) pin(origin!, 'A', const Color(0xFF1F6FB2)),
      if (modo == 0 && b != null) pin(b!, 'B', const Color(0xFFE8704A)),
      if (modo == 1)
        for (var i = 0; i < ric.length; i++) pin(ric[i], '${i + 1}', const Color(0xFFB4492A)),
    ];
    final cerchi = <CircleMarker>[
      if (me != null) CircleMarker(point: me!, radius: 8, color: const Color(0xFF1F6FB2), borderColor: Colors.white, borderStrokeWidth: 3),
      if (modo == 1 && pa != null)
        CircleMarker(point: pa, radius: raggio, useRadiusInMeter: true, color: const Color(0x33E8704A), borderColor: const Color(0xFFE8704A), borderStrokeWidth: 2),
      if (modo == 1)
        for (final e in edifici.take(600))
          CircleMarker(point: e.p, radius: 4.5, color: _abitativi.contains(e.tipo) ? const Color(0xFFE8704A) : const Color(0xFF0F6F61), borderColor: Colors.white, borderStrokeWidth: 1),
    ];
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        title: const Text('Distanze su mappa', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cBg,
        foregroundColor: cInk,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 0, label: Text('Distanza A-B')), ButtonSegment(value: 1, label: Text('Raggio ed edifici'))],
                  selected: {modo},
                  onSelectionChanged: (s) => setState(() => modo = s.first),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: FlutterMap(
                mapController: mc,
                options: MapOptions(
                  initialCenter: me ?? const LatLng(45.07, 7.69),
                  initialZoom: me == null ? 6 : 18,
                  maxZoom: 19.5,
                  onMapReady: () {
                    mapReady = true;
                    if (me != null && !centrato) {
                      centrato = true;
                      mc.move(me!, 18);
                    }
                  },
                  onTap: (tp, p) => setState(() {
                    if (modo == 0) {
                      b = p;
                    } else {
                      ric.add(p);
                    }
                  }),
                  onLongPress: (tp, p) => setState(() => origin = p),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'it.studioagfor.irumore',
                    maxNativeZoom: 19,
                  ),
                  if (modo == 0 && pa != null && b != null) PolylineLayer(polylines: [Polyline(points: [pa, b!], color: const Color(0xFFE8704A), strokeWidth: 4)]),
                  CircleLayer(circles: cerchi),
                  MarkerLayer(markers: markers),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (err != null) InfoBox(err!, color: cBad, icon: Icons.warning_amber),
                    if (modo == 0) ..._pannelloDistanza(pa) else ..._pannelloRaggio(pa, dentro),
                    if (origin != null)
                      TextButton.icon(onPressed: () => setState(() => origin = null), icon: const Icon(Icons.my_location, size: 18), label: const Text('Punto A = la mia posizione')),
                    const Text(
                      'Precisione indicativa: il GPS di un telefono ha di norma un errore di alcuni metri. Tocca la mappa per il punto B (o per aggiungere un ricettore); tieni premuto per spostare il punto A.',
                      style: TextStyle(fontSize: 11.5, color: cDark, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _pannelloDistanza(LatLng? pa) {
    if (pa == null) return const [InfoBox('In attesa della posizione GPS. In alternativa tieni premuto sulla mappa per fissare il punto A.')];
    if (b == null) return const [InfoBox('Tocca la mappa per scegliere il punto B: comparirà la distanza dal punto A.')];
    final d = distM(pa, b!);
    return [
      ResultCard('Distanza A-B', '${f1(d, 1)} m', sub: origin == null ? 'A = posizione del telefono' : 'A = punto fissato sulla mappa'),
      FilledButton.tonalIcon(
        onPressed: () {
          UltimaMisura.i.distanza = d;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Distanza ${f1(d, 1)} m disponibile nei calcoli di propagazione.')));
        },
        icon: const Icon(Icons.send),
        label: const Text('Usa nei calcoli di propagazione'),
      ),
      const SizedBox(height: 8),
    ];
  }

  List<Widget> _pannelloRaggio(LatLng? pa, int dentro) {
    final res = edifici.where((e) => _abitativi.contains(e.tipo)).length;
    final vicini = [...edifici]..sort((x, y) => distM(pa ?? x.p, x.p).compareTo(distM(pa ?? y.p, y.p)));
    return [
      Text('Raggio: ${f1(raggio, 0)} m', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cInk)),
      Slider(min: 10, max: 1000, divisions: 99, value: raggio.clamp(10.0, 1000.0), label: '${f1(raggio, 0)} m', onChanged: (v) => setState(() => raggio = v)),
      if (pa == null) const InfoBox('In attesa della posizione GPS: il cerchio è centrato sul punto A.'),
      FilledButton.icon(
        onPressed: cerco ? null : contaEdifici,
        icon: cerco ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.home_work),
        label: Text(cerco ? 'Cerco gli edifici...' : 'Conta gli edifici nel raggio (OpenStreetMap)'),
      ),
      if (nota != null) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBox(nota!, color: cBad, icon: Icons.warning_amber)),
      if (edifici.isNotEmpty && raggioEd != null) ...[
        const SizedBox(height: 8),
        Esito('Edifici nel raggio di ${f1(raggioEd!, 0)} m', '${edifici.length} edifici, di cui $res con destinazione residenziale nei dati OpenStreetMap (arancione); gli altri o senza destinazione specificata sono in verde. La completezza dei dati varia da zona a zona: si consiglia di verificare sul posto.', true),
        for (final e in vicini.take(5))
          Text('${_abitativi.contains(e.tipo) ? 'Residenziale' : (e.tipo == 'yes' ? 'Edificio' : e.tipo)} · ${f1(distM(pa ?? e.p, e.p), 0)} m dal punto A', style: const TextStyle(fontSize: 13, color: cInk)),
        const SizedBox(height: 8),
      ],
      if (ric.isNotEmpty) ...[
        Esito('Ricettori inseriti a mano', '$dentro di ${ric.length} sono entro ${f1(raggio, 0)} m dal punto A.', true),
        for (var i = 0; i < ric.length && pa != null; i++)
          Text('R${i + 1} · ${f1(distM(pa, ric[i]), 0)} m · ${distM(pa, ric[i]) <= raggio ? 'dentro' : 'fuori'}', style: const TextStyle(fontSize: 13, color: cInk)),
      ],
      Row(children: [
        TextButton.icon(onPressed: ric.isEmpty ? null : () => setState(() => ric.removeLast()), icon: const Icon(Icons.undo, size: 18), label: const Text('Rimuovi ultimo')),
        TextButton.icon(
          onPressed: (ric.isEmpty && edifici.isEmpty) ? null : () => setState(() {
                ric.clear();
                edifici = [];
              }),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Azzera'),
        ),
      ]),
    ];
  }
}
