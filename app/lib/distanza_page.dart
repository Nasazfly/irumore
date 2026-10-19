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

// ───────── Geometria locale (metri, origine nel punto A) ─────────
class _Pol {
  final List<double> x, y;
  final List<LatLng> ll;
  late double minX, maxX, minY, maxY, dMin;
  bool contieneA = false, primo = false;
  _Pol(this.x, this.y, this.ll) {
    minX = x.reduce(min);
    maxX = x.reduce(max);
    minY = y.reduce(min);
    maxY = y.reduce(max);
  }
  double get area {
    var s = 0.0;
    for (var i = 0; i < x.length; i++) {
      final j = (i + 1) % x.length;
      s += x[i] * y[j] - x[j] * y[i];
    }
    return s.abs() / 2;
  }

  LatLng get centro => LatLng(ll.map((p) => p.latitude).reduce((a, b) => a + b) / ll.length, ll.map((p) => p.longitude).reduce((a, b) => a + b) / ll.length);
}

double _ptSeg(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  var t = l2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

bool _inside(double px, double py, _Pol p) {
  var in_ = false;
  for (var i = 0, j = p.x.length - 1; i < p.x.length; j = i++) {
    if (((p.y[i] > py) != (p.y[j] > py)) && (px < (p.x[j] - p.x[i]) * (py - p.y[i]) / (p.y[j] - p.y[i]) + p.x[i])) in_ = !in_;
  }
  return in_;
}

double _orient(double ax, double ay, double bx, double by, double cx, double cy) => (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);

bool _onSeg(double ax, double ay, double bx, double by, double px, double py) =>
    px >= min(ax, bx) - 1e-9 && px <= max(ax, bx) + 1e-9 && py >= min(ay, by) - 1e-9 && py <= max(ay, by) + 1e-9;

// Intersezione tra segmenti, compresi i contatti e i tratti sovrapposti.
bool _cross(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy) {
  const e = 1e-6;
  final o1 = _orient(ax, ay, bx, by, cx, cy), o2 = _orient(ax, ay, bx, by, dx, dy);
  final o3 = _orient(cx, cy, dx, dy, ax, ay), o4 = _orient(cx, cy, dx, dy, bx, by);
  if (((o1 > e && o2 < -e) || (o1 < -e && o2 > e)) && ((o3 > e && o4 < -e) || (o3 < -e && o4 > e))) return true;
  if (o1.abs() <= e && _onSeg(ax, ay, bx, by, cx, cy)) return true;
  if (o2.abs() <= e && _onSeg(ax, ay, bx, by, dx, dy)) return true;
  if (o3.abs() <= e && _onSeg(cx, cy, dx, dy, ax, ay)) return true;
  if (o4.abs() <= e && _onSeg(cx, cy, dx, dy, bx, by)) return true;
  return false;
}

// Il segmento dal punto A (0,0) al punto (px,py) è schermato da un altro edificio?
// Il tratto finale di 0,5 m è escluso, per non contare le pareti in comune tra edifici adiacenti.
bool _schermato(double px0, double py0, _Pol self, List<_Pol> blockers) {
  final len = sqrt(px0 * px0 + py0 * py0);
  final f = len > 1.0 ? (len - 0.5) / len : 1.0;
  final px = px0 * f, py = py0 * f;
  final sMinX = min(0.0, px), sMaxX = max(0.0, px), sMinY = min(0.0, py), sMaxY = max(0.0, py);
  for (final q in blockers) {
    if (identical(q, self)) continue;
    if (q.maxX < sMinX || q.minX > sMaxX || q.maxY < sMinY || q.minY > sMaxY) continue;
    for (var i = 0; i < q.x.length; i++) {
      final j = (i + 1) % q.x.length;
      if (_cross(0, 0, px, py, q.x[i], q.y[i], q.x[j], q.y[j])) return true;
    }
  }
  return false;
}

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
  bool aerea = false;
  final ric = <LatLng>[];
  List<_Pol> primi = [];
  List<_Pol> altri = [];
  int totEdifici = 0;
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

  Future<void> contaPrimoFronte() async {
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
      final q = '[out:json][timeout:25];way["building"](around:$rr,${c.latitude},${c.longitude});out geom;';
      final r = await http
          .post(Uri.parse('https://overpass-api.de/api/interpreter'), headers: {'User-Agent': 'EnviNoise/7.0 (Studio Agfor)'}, body: {'data': q})
          .timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) throw 'Servizio OpenStreetMap non disponibile (${r.statusCode}). Riprova tra poco.';
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final kx = cos(c.latitude * pi / 180) * 111320.0, ky = 110540.0;
      final pols = <_Pol>[];
      for (final e in (j['elements'] as List)) {
        final g = e['geometry'];
        if (g == null) continue;
        final ll = <LatLng>[];
        final xs = <double>[], ys = <double>[];
        for (final p in (g as List)) {
          final la = (p['lat'] as num).toDouble(), lo = (p['lon'] as num).toDouble();
          ll.add(LatLng(la, lo));
          xs.add((lo - c.longitude) * kx);
          ys.add((la - c.latitude) * ky);
        }
        if (ll.length > 1 && ll.first.latitude == ll.last.latitude && ll.first.longitude == ll.last.longitude) {
          ll.removeLast();
          xs.removeLast();
          ys.removeLast();
        }
        if (ll.length < 3) continue;
        final p = _Pol(xs, ys, ll);
        if (p.area < 10) continue; // manufatti molto piccoli
        pols.add(p);
      }
      if (pols.length > 1500) throw 'Troppi edifici nel raggio (${pols.length}): riduci il raggio.';
      await Future.delayed(const Duration(milliseconds: 30));
      for (final p in pols) {
        p.contieneA = _inside(0, 0, p);
        var d = double.infinity;
        for (var i = 0; i < p.x.length; i++) {
          final k = (i + 1) % p.x.length;
          d = min(d, _ptSeg(0, 0, p.x[i], p.y[i], p.x[k], p.y[k]));
        }
        p.dMin = p.contieneA ? 0 : d;
      }
      final blockers = pols.where((p) => !p.contieneA).toList()..sort((u, v) => u.dMin.compareTo(v.dMin));
      for (final p in blockers) {
        if (p.dMin > raggio) continue;
        final stride = max(1, p.x.length ~/ 12);
        final cand = <List<double>>[];
        for (var i = 0; i < p.x.length; i += stride) {
          final k = (i + 1) % p.x.length;
          cand.add([p.x[i], p.y[i]]);
          cand.add([(p.x[i] + p.x[k]) / 2, (p.y[i] + p.y[k]) / 2]);
        }
        cand.sort((u, v) => (u[0] * u[0] + u[1] * u[1]).compareTo(v[0] * v[0] + v[1] * v[1]));
        for (final s in cand) {
          if (!_schermato(s[0], s[1], p, blockers)) {
            p.primo = true;
            break;
          }
        }
      }
      setState(() {
        primi = blockers.where((p) => p.primo).toList();
        altri = blockers.where((p) => !p.primo && p.dMin <= raggio).toList();
        totEdifici = blockers.where((p) => p.dMin <= raggio).length;
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
        for (var i = 0; i < ric.length; i++) pin(ric[i], 'R${i + 1}', const Color(0xFFB4492A)),
      if (modo == 1)
        for (var i = 0; i < primi.length && i < 12; i++) pin(primi[i].centro, '${i + 1}', const Color(0xFFE8704A)),
    ];
    final cerchi = <CircleMarker>[
      if (me != null) CircleMarker(point: me!, radius: 8, color: const Color(0xFF1F6FB2), borderColor: Colors.white, borderStrokeWidth: 3),
      if (modo == 1 && pa != null) CircleMarker(point: pa, radius: raggio, useRadiusInMeter: true, color: const Color(0x22E8704A), borderColor: const Color(0xFFE8704A), borderStrokeWidth: 2),
    ];
    final poligoni = <Polygon>[
      if (modo == 1)
        for (final p in altri.take(400)) Polygon(points: p.ll, color: const Color(0x00000000), borderColor: const Color(0xAA8A9A96), borderStrokeWidth: 1),
      if (modo == 1)
        for (final p in primi) Polygon(points: p.ll, color: const Color(0x88E8704A), borderColor: const Color(0xFFB4492A), borderStrokeWidth: 2),
    ];
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        title: const Text('Distanze su mappa', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cBg,
        foregroundColor: cInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.layers),
            onSelected: (v) => setState(() => aerea = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('Mappa OpenStreetMap')),
              PopupMenuItem(value: true, child: Text('Foto aerea (2009-2012)')),
            ],
          ),
        ],
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
                  segments: const [ButtonSegment(value: 0, label: Text('Distanza A-B')), ButtonSegment(value: 1, label: Text('Raggio e primo fronte'))],
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
                  if (aerea)
                    TileLayer(
                      wmsOptions: WMSTileLayerOptions(
                        baseUrl: 'http://wms.pcn.minambiente.it/ogc?map=/ms_ogc/WMS_v1.3/raster/ortofoto_colore_12.map&',
                        layers: const ['OI.ORTOIMMAGINI.2012'],
                        format: 'image/jpeg',
                        transparent: false,
                      ),
                      userAgentPackageName: 'it.studioagfor.irumore',
                      maxNativeZoom: 19,
                    )
                  else
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'it.studioagfor.irumore',
                      maxNativeZoom: 19,
                    ),
                  if (modo == 0 && pa != null && b != null) PolylineLayer(polylines: [Polyline(points: [pa, b!], color: const Color(0xFFE8704A), strokeWidth: 4)]),
                  PolygonLayer(polygons: poligoni),
                  CircleLayer(circles: cerchi),
                  MarkerLayer(markers: markers),
                  RichAttributionWidget(attributions: [
                    const TextSourceAttribution('© OpenStreetMap contributors'),
                    if (aerea) const TextSourceAttribution('Ortofoto AGEA 2009-2012: Geoportale Nazionale (MASE)'),
                  ]),
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
                      'Precisione indicativa: il GPS di un telefono ha di norma un errore di alcuni metri. Tocca la mappa per il punto B (o per aggiungere un ricettore); tieni premuto per spostare il punto A, per esempio sulla sorgente.',
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
    return [
      Text('Raggio: ${f1(raggio, 0)} m', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cInk)),
      Slider(min: 10, max: 1000, divisions: 99, value: raggio.clamp(10.0, 1000.0), label: '${f1(raggio, 0)} m', onChanged: (v) => setState(() => raggio = v)),
      if (pa == null) const InfoBox('In attesa della posizione GPS: il cerchio è centrato sul punto A.'),
      FilledButton.icon(
        onPressed: cerco ? null : contaPrimoFronte,
        icon: cerco ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.home_work),
        label: Text(cerco ? 'Calcolo in corso...' : 'Conta i ricettori di primo fronte'),
      ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => showInfo(context, 'primoFronte'), icon: const Icon(Icons.info_outline, size: 18), label: const Text('Cosa significa primo fronte'))),
      if (nota != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: InfoBox(nota!, color: cBad, icon: Icons.warning_amber)),
      if (raggioEd != null) ...[
        Esito('Ricettori di primo fronte', '${primi.length} edifici affacciati direttamente sul punto A, su $totEdifici edifici nel raggio di ${f1(raggioEd!, 0)} m (sagome OpenStreetMap). Gli altri edifici sono schermati e non vengono conteggiati.', true),
        for (var i = 0; i < primi.length && i < 10; i++)
          Text('R${i + 1} · facciata più vicina a ${f1(primi[i].dMin, 0)} m dal punto A', style: const TextStyle(fontSize: 13, color: cInk)),
        if (primi.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton.tonalIcon(
              onPressed: () {
                UltimaMisura.i.distanza = primi.first.dMin;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Distanza ${f1(primi.first.dMin, 0)} m (ricettore più vicino) disponibile nei calcoli di propagazione.')));
              },
              icon: const Icon(Icons.send),
              label: const Text('Usa la distanza del più vicino nei calcoli'),
            ),
          ),
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
          onPressed: (ric.isEmpty && primi.isEmpty) ? null : () => setState(() {
                ric.clear();
                primi = [];
                altri = [];
                raggioEd = null;
              }),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Azzera'),
        ),
      ]),
    ];
  }
}
