// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/cart_provider.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'utils/navigation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VendeMovilApp());
}

class VendeMovilApp extends StatelessWidget {
  const VendeMovilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: MaterialApp(
        title: 'Vende Móvil',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        // Parte 13 (fix): necesario para que ScannerHomeScreen sepa cuándo
        // queda tapada por otra pantalla y pueda pausar su cámara (ver
        // utils/navigation.dart).
        navigatorObservers: [appRouteObserver],
        home: const ScannerHomeScreen(),
      ),
    );
  }
}
