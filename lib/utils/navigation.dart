// lib/utils/navigation.dart
//
// Parte 12 (fix cámara): RouteObserver global.
//
// Causa raíz de "MobileScannerController is already running" /
// "controllerAlreadyInitialized" al abrir la cámara para agregar o
// vincular un producto: ScannerHomeScreen (la vista principal) mantiene su
// propia cámara encendida todo el tiempo, incluso cuando navegas a
// Inventario, al Catálogo, o a BarcodeScannerScreen (escanear código
// nuevo/vincular). Esas pantallas crean SU PROPIO MobileScannerController,
// pero el hardware de cámara del teléfono solo admite una sesión activa a
// la vez, así que el segundo controller choca con el de la vista
// principal que sigue vivo de fondo.
//
// Con este RouteObserver, ScannerHomeScreen se entera cuando queda
// "tapada" por cualquier otra ruta (didPushNext) y para su cámara ahí
// mismo, y la reanuda al volver a quedar visible (didPopNext). Esto
// arregla el choque de raíz en vez de parchar cada pantalla que usa
// cámara.
import 'package:flutter/material.dart';

final RouteObserver<PageRoute<dynamic>> routeObserver = RouteObserver<PageRoute<dynamic>>();
