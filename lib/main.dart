// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/cart_provider.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

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
        title: 'Ventas Cell',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        home: const ScannerHomeScreen(),
      ),
    );
  }
}
