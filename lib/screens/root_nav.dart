import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'reports_screen.dart';

/// Navegação principal do app: abas Gastos e Relatórios, com deslize entre
/// elas e barra de navegação inferior.
class RootNav extends StatefulWidget {
  /// Aba aberta ao entrar (0 = Gastos, 1 = Relatórios).
  final int initialIndex;

  const RootNav({super.key, this.initialIndex = 0});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  void _onPageChanged(int index) {
    if (index != _index) {
      setState(() => _index = index);
    }
  }

  void _onDestinationSelected(int index) {
    if (index != _index) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: _onPageChanged,
        children: [
          HomeScreen(onVerRelatorios: () => _onDestinationSelected(1)),
          ReportsScreen(onVerGastos: () => _onDestinationSelected(0)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Gastos',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Relatórios',
          ),
        ],
      ),
    );
  }
}
