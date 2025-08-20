import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'edit_channel_page.dart'; // 👈 asegúrate de crear este archivo con el formulario de edición

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

  /// 🔹 Stream con stats combinadas de apuesta_resuelta, posts y user
  Stream<Map<String, dynamic>> getStatsStream() {
    final db = FirebaseFirestore.instance;

    // apuestas resueltas
    final apuestasStream = db
        .collection("apuesta_resuelta")
        .where("uid", isEqualTo: tipsterId)
        .snapshots();

    // posts dentro del canal
    final postsStream = db
        .collection("canales")
        .doc(tipsterId) // 👈 canal == tipsterId
        .collection("posts")
        .where("tipsterId", isEqualTo: tipsterId)
        .snapshots();

    // usuario (para unidades)
    final userStream = db.collection("users").doc(tipsterId).snapshots();

    return CombineLatestStream.combine3(
      apuestasStream,
      postsStream,
      userStream,
      (QuerySnapshot apuestasSnap, QuerySnapshot postsSnap,
          DocumentSnapshot userDoc) {
        // =====================
        // 📌 Datos de apuestas
        // =====================
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

        // =====================
        // 📌 Datos de posts
        // =====================
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

        // =====================
        // 📌 Unidades (de users)
        // =====================
        final unidadesField =
            (userDoc.data() as Map<String, dynamic>?)?["unidades"];
        double unidades = (unidadesField is num)
            ? unidadesField.toDouble()
            : double.tryParse("$unidadesField") ?? 0.0;

        // =====================
        // 📌 Yield
        // =====================
        double yield =
            totalStake > 0 ? (unidades / totalStake) * 100 : 0;

        return {
          "apuestas": totalApuestas,
          "acierto": porcentajeAcierto,
          "stake": stakeMedio,
          "cuota": cuotaMedia,
          "unidades": unidades,
          "yield": yield,
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final esPropietario = (currentUid == tipsterId);

    return Scaffold(
      appBar: AppBar(
        title: Text(nombre),
        backgroundColor: Colors.grey[900],
        actions: [
          if (esPropietario)
            IconButton(
              icon: const Icon(Icons.edit),
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

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (foto != null && foto!.isNotEmpty)
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: NetworkImage(foto!),
                    )
                  else
                    const CircleAvatar(
                      radius: 50,
                      child: Icon(Icons.person, size: 40),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    descripcion.isNotEmpty
                        ? descripcion
                        : "Sin descripción disponible.",
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 20),

                  // 🔹 Estadísticas
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 3,
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
    return Column(
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
        Text(
          titulo,
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ],
    );
  }
}
