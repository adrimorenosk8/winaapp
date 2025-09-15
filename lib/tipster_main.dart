import 'package:flutter/material.dart';
import 'mi_perfil.dart';
import 'tipster_feed.dart';
import 'tipster_page.dart';
import 'buscar_page.dart';
import 'seguidos_page.dart';

// 🔹 Función para sanitizar texto visible (defensiva, aunque aquí todo es fijo)
String sanitizeText(String value, {String defaultValue = ''}) {
  if (value.isEmpty) return defaultValue;
  return value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
}

class TipsterMainPage extends StatefulWidget {
  const TipsterMainPage({super.key});

  @override
  State<TipsterMainPage> createState() => _TipsterMainPageState();
}

class _TipsterMainPageState extends State<TipsterMainPage> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = List.unmodifiable([
      const TipsterFeedPage(), // Feed
      const TipsterPage(),     // Mi canal
      const BuscarPage(),      // Buscar
      const SeguidosPage(),    // Canales que sigo
    ]);
  }

  void _onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      debugPrint("Índice fuera de rango en BottomNavigationBar: $index");
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = sanitizeText("WINA APP", defaultValue: "APP");

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: Text(
          appTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {
              try {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MiPerfilPage()),
                );
              } catch (e) {
                debugPrint("Error al navegar a MiPerfilPage: $e");
              }
            },
          ),
        ],
      ),
      body: SafeArea(child: _pages[_selectedIndex]),

      // 🔹 Barra de navegación global en estilo dark
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.greenAccent[400],
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.rss_feed),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign),
            label: 'Mi Canal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Buscar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt),
            label: 'Seguidos',
          ),
        ],
      ),
    );
  }
}
