import 'package:flutter/material.dart';
import 'core.dart';
import 'glossario.dart';

class GlossarioPage extends StatelessWidget {
  const GlossarioPage({super.key});
  @override
  Widget build(BuildContext context) => page('Glossario', [
        const InfoBox('Che cosa significano gli indicatori che trovi nell\'app. Lo stesso testo compare toccando l\'icona accanto a ogni campo.'),
        for (final g in gruppiGlossario.entries) ...[
          sezione(g.key.toUpperCase()),
          for (final k in g.value)
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
        ],
      ]);
}
