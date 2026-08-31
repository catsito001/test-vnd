// lib/utils/navigation.dart
//
// Parte 13 (fix) — RouteObserver global de la app.
//
// `ScannerHomeScreen` (Parte 2) mantiene su propia cámara encendida todo
// el tiempo para el escaneo de ventas. El paquete `mobile_scanner` NO se
// entera solo de que esa pantalla quedó tapada por otra (Inventario, el
// Catálogo, Nuevo Producto...): su cámara se queda usando el hardware en
// segundo plano aunque no sea visible. Si desde esa otra pantalla se abre
// OTRO `MobileScanner` (por ejemplo al escanear el código de un producto
// nuevo o al vincular un código), las dos cámaras compiten por el mismo
// hardware y se ve el error "MobileScannerController is already running.
// Stop it before starting again." en vez de la cámara — justo lo que
// pasaba al agregar o vincular un producto.
//
// La solución es que `ScannerHomeScreen` se entere de cuándo deja de estar
// en primer plano (para soltar la cámara) y de cuándo vuelve a estarlo
// (para reencenderla). Eso es exactamente lo que resuelve un `RouteAware`
// suscrito a este `RouteObserver`, que se registra una sola vez como
// `navigatorObservers` del `MaterialApp` en `main.dart`.
//
// Vive en su propio archivo (en vez de en main.dart) por la misma razón
// que `theme.dart`: cualquier pantalla lo puede importar sin generar un
// import circular con main.dart.

import 'package:flutter/material.dart';

final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
