import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'edit_channel_page.dart';

class TipsterChannelInfo extends StatelessWidget {
  final String nombre;
  final String descripcion;
  final String? foto;
  final String? tipsterId;
  final String? canalId;

  const TipsterChannelInfo({
    super.key,
    required this.nombre,
    required this.descripcion,
    this.foto,
    this.tipsterId,
    this.canalId,
  });

  /// ---------- Helpers seguros ----------
  static double _toDouble(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  String formatFollowers(int count) {
    if (count >= 1000000) return "${(count / 1000000).toStringAsFixed(1)}M";
    if (count >= 1000) {
      final k = count / 1000;
      return k % 1 == 0 ? "${k.toInt()}k" : "${k.toStringAsFixed(1)}k";
    }
    return count.toString();
  }

  /// ---------- Stats stream que respeta reglas ----------
  ///
  /// - Dueño o seguidor: puede leer `pronostico` (todos) y `resultado`.
  /// - No seguidor: solo `pronostico` con `status='open'` (los `resultado` no son públicos).
  Stream<Map<String, dynamic>> getStatsStream() {
    final db = FirebaseFirestore.instance;

    // Si no hay tipsterId, devolver stats vacías
    if (tipsterId == null || tipsterId!.isEmpty) {
      return Stream.value({
        "apuestas": 0, "acierto": 0.0, "stake": 0.0, "cuota": 0.0,
        "unidades": 0.0, "yield": 0.0, "seguidores": 0,
      });
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final canalRef = db.collection("canales").doc(canalId ?? tipsterId!);
    final postsCol = db.collection("canales").doc(tipsterId!).collection("posts");

    // Canal -> para saber seguidores y decidir filtros
    final canalStream = canalRef.snapshots();

    // Pronósticos visibles según rol (dueño/seguidor vs público)
    final pronosStream = canalStream.switchMap((canalDoc) {
      final data = (canalDoc.data() as Map<String, dynamic>?) ?? {};
      final seguidores = (data['seguidores'] is List) ? List<String>.from(data['seguidores']) : <String>[];
      final isOwner = currentUid == tipsterId;
      final isFollower = currentUid != null && seguidores.contains(currentUid);

      Query<Map<String, dynamic>> q = postsCol.where('type', isEqualTo: 'pronostico');
      if (!(isOwner || isFollower)) {
        // Solo pronósticos abiertos para no seguidores (cumple reglas)
        q = q.where('status', isEqualTo: 'open');
      }
      return q.snapshots().map((snap) => snap.docs.map((d) => d.data()).toList());
    });

    // Resultados visibles solo para dueño/seguidor
    final resultadosStream = canalStream.switchMap((canalDoc) {
      final data = (canalDoc.data() as Map<String, dynamic>?) ?? {};
      final seguidores = (data['seguidores'] is List) ? List<String>.from(data['seguidores']) : <String>[];
      final isOwner = currentUid == tipsterId;
      final isFollower = currentUid != null && seguidores.contains(currentUid);

      if (!(isOwner || isFollower)) {
        // No seguidores: no pueden leer resultados
        return Stream.value(<Map<String, dynamic>>[]);
      }
      return postsCol
          .where('type', isEqualTo: 'resultado')
          .snapshots()
          .map((snap) => snap.docs.map((d) => d.data()).toList());
    });

    // Combinamos: canal + pronos visibles + resultados visibles
    return CombineLatestStream.combine3<
        DocumentSnapshot<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        Map<String, dynamic>>(
      canalStream,
      pronosStream,
      resultadosStream,
      (canalDoc, pronos, resultados) {
        final canalData = canalDoc.data() ?? {};
        final seguidoresNum = _toInt(canalData['numero_seguidores']);

        // Stake/cuota medios sobre los pronósticos visibles
        double totalStake = 0;
        double totalCuota = 0;
        int nPronos = 0;

        for (final p in pronos) {
          totalStake += _toDouble(p['stake']);
          totalCuota += _toDouble(p['cuota']);
          nPronos++;
        }

        final stakeMedio = nPronos > 0 ? totalStake / nPronos : 0.0;
        final cuotaMedia = nPronos > 0 ? totalCuota / nPronos : 0.0;

        // Stats de resultados (solo dueño/seguidor tendrá datos)
        int ganadas = 0, perdidas = 0;
        double unidades = 0.0;
        for (final r in resultados) {
          final status = (r['status'] ?? '').toString().toLowerCase().trim();
          if (status == 'won') ganadas++;
          if (status == 'lost') perdidas++;
          unidades += _toDouble(r['resolucion']);
        }

        final totalApuestas = ganadas + perdidas;
        final acierto = totalApuestas > 0 ? (ganadas / totalApuestas) * 100.0 : 0.0;
        final yieldPct = totalStake > 0 ? (unidades / totalStake) * 100.0 : 0.0;

        return {
          "apuestas": totalApuestas,
          "acierto": acierto,
          "stake": stakeMedio,
          "cuota": cuotaMedia,
          "unidades": unidades,
          "yield": yieldPct,
          "seguidores": seguidoresNum,
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final esPropietario = (currentUid == tipsterId);

    final fotoUrl = (foto ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(nombre),
        backgroundColor: Colors.black,
        actions: [
          if (esPropietario)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.green),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditChannelPage(
                      canalId: canalId ?? tipsterId!,
                      nombre: nombre,
                      descripcion: descripcion,
                      foto: fotoUrl,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: getStatsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text("❌ Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data!;
          final seguidores = formatFollowers(_toInt(stats["seguidores"]));

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Foto
                  Center(
                    child: (fotoUrl.isNotEmpty)
                        ? CircleAvatar(
                            radius: 50,
                            backgroundImage: NetworkImage(fotoUrl),
                            onBackgroundImageError: (_, __) {},
                            child: null,
                          )
                        : const CircleAvatar(
                            radius: 50,
                            child: Icon(Icons.person, size: 40),
                          ),
                  ),
                  const SizedBox(height: 20),

                  // Nombre
                  Text(
                    nombre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Descripción
                  Text(
                    descripcion.isNotEmpty ? descripcion : "Sin descripción disponible.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),

                  // Seguidores
                  Text(
                    "$seguidores Seguidores",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const SizedBox(height: 25),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "ESTADÍSTICAS",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      statItem("Apuestas", "${_toInt(stats["apuestas"])}"),
                      statItem("Acierto %", "${(_toDouble(stats["acierto"])).toStringAsFixed(2)}%"),
                      statItem("Stake medio", "${(_toDouble(stats["stake"])).toStringAsFixed(2)}"),
                      statItem("Cuota media", "${(_toDouble(stats["cuota"])).toStringAsFixed(2)}"),
                      statItem("Unidades", "${(_toDouble(stats["unidades"])).toStringAsFixed(2)}"),
                      statItem("Yield %", "${(_toDouble(stats["yield"])).toStringAsFixed(2)}%"),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      backgroundColor: Colors.black,
    );
  }

  Widget statItem(String titulo, String valor) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              valor,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
