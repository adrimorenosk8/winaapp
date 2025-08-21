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

  /// 🔹 Stream con stats combinadas de apuesta_resuelta, posts, user y canal
  Stream<Map<String, dynamic>> getStatsStream() {
    final db = FirebaseFirestore.instance;

    final apuestasStream = db
        .collection("apuesta_resuelta")
        .where("uid", isEqualTo: tipsterId)
        .snapshots();

    final postsStream = db
        .collection("canales")
        .doc(tipsterId)
        .collection("posts")
        .where("tipsterId", isEqualTo: tipsterId)
        .snapshots();

    final userStream = db.collection("users").doc(tipsterId).snapshots();

    final canalStream = db.collection("canales").doc(tipsterId).snapshots();

    return CombineLatestStream.combine4(
      apuestasStream,
      postsStream,
      userStream,
      canalStream,
      (QuerySnapshot apuestasSnap, QuerySnapshot postsSnap,
          DocumentSnapshot userDoc, DocumentSnapshot canalDoc) {
        int totalApuestas = apuestasSnap.docs.length;
        int ganadas = 0;
        int perdidas = 0;

        for (var doc in apuestasSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data["status"] == "won") ganadas++;
          if (data["status"] == "lost") perdidas++;
        }

        double porcentajeAcierto =
            (ganadas + perdidas) > 0 ? (ganadas / (ganadas + perdidas)) * 100 : 0;

        double totalStake = 0;
        double totalCuota = 0;
        int totalPosts = 0;

        for (var doc in postsSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final stake = (data["stake"] is num)
              ? (data["stake"] as num).toDouble()
              : double.tryParse("${data["stake"]}") ?? 0.0;
          final cuota = (data["cuota"] is num)
              ? (data["cuota"] as num).toDouble()
              : double.tryParse("${data["cuota"]}") ?? 0.0;

          totalStake += stake;
          totalCuota += cuota;
          totalPosts++;
        }

        double stakeMedio = totalPosts > 0 ? totalStake / totalPosts : 0;
        double cuotaMedia = totalPosts > 0 ? totalCuota / totalPosts : 0;

        final unidadesField =
            (userDoc.data() as Map<String, dynamic>?)?["unidades"];
        double unidades = (unidadesField is num)
            ? unidadesField.toDouble()
            : double.tryParse("$unidadesField") ?? 0.0;

        double yield = totalStake > 0 ? (unidades / totalStake) * 100 : 0;

        final canalData = canalDoc.data() as Map<String, dynamic>?;
        int seguidores = canalData?["numero_seguidores"] is num
            ? (canalData?["numero_seguidores"] as num).toInt()
            : 0;

        return {
          "apuestas": totalApuestas,
          "acierto": porcentajeAcierto,
          "stake": stakeMedio,
          "cuota": cuotaMedia,
          "unidades": unidades,
          "yield": yield,
          "seguidores": seguidores,
        };
      },
    );
  }

  /// 🔹 Formato para abreviar seguidores
  String formatFollowers(int count) {
    if (count >= 1000000) {
      return "${(count / 1000000).toStringAsFixed(1)}M";
    } else if (count >= 1000) {
      double k = count / 1000;
      return k % 1 == 0 ? "${k.toInt()}k" : "${k.toStringAsFixed(1)}k";
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final esPropietario = (currentUid == tipsterId);

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
                      foto: foto ?? "",
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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data!;
          final seguidores = formatFollowers(stats["seguidores"]);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 📌 Foto centrada
                  Center(
                    child: foto != null && foto!.isNotEmpty
                        ? CircleAvatar(
                            radius: 50,
                            backgroundImage: NetworkImage(foto!),
                          )
                        : const CircleAvatar(
                            radius: 50,
                            child: Icon(Icons.person, size: 40),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    descripcion.isNotEmpty
                        ? descripcion
                        : "Sin descripción disponible.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  // 📌 Seguidores
                  Text(
                    "$seguidores Seguidores",
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 25),

                  // 📌 Sección de estadísticas
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
                      statItem("Apuestas", "${stats["apuestas"]}"),
                      statItem("Acierto %",
                          "${stats["acierto"].toStringAsFixed(2)}%"),
                      statItem("Stake medio",
                          "${stats["stake"].toStringAsFixed(2)}"),
                      statItem("Cuota media",
                          "${stats["cuota"].toStringAsFixed(2)}"),
                      statItem("Unidades",
                          "${stats["unidades"].toStringAsFixed(2)}"),
                      statItem("Yield %",
                          "${stats["yield"].toStringAsFixed(2)}%"),
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
