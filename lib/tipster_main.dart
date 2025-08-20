import 'package:flutter/material.dart';
import 'mi_perfil.dart';
import 'tipster_feed.dart';
import 'tipster_page.dart'; // ✅ este es tu canal ya creado

class TipsterMainPage extends StatefulWidget {
  const TipsterMainPage({super.key});

  @override
  State<TipsterMainPage> createState() => _TipsterMainPageState();
}

class _TipsterMainPageState extends State<TipsterMainPage> {
  int _selectedIndex = 0;

  // Páginas que se mostrarán según la pestaña elegida
  final List<Widget> _pages = const [
    TipsterFeedPage(),
    TipsterPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text(
          "WINA APP", // 👈 Cambiado aquí
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MiPerfilPage()),
              );
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],

      // 🔹 Barra de navegación global en estilo dark
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.greenAccent[400],
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.rss_feed),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign),
            label: 'Mi Canal',
          ),
        ],
      ),
    );
  }
}
