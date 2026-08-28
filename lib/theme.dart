// lib/theme.dart
//
// Sistema de diseño de la app (Parte 11 del prompt): paleta de colores,
// escala tipográfica y ThemeData centralizados aquí para que cualquier
// pantalla los pueda usar sin crear un import circular con main.dart.
//
// El resto de las pantallas ya consumen `AppColors` directamente (banners,
// overlays sobre la cámara, chips de categoría, etc.), así que este
// archivo se mantiene como la única fuente de verdad de la paleta y,
// además, deja definidos los estilos de componente (botones, inputs,
// tarjetas, diálogos, snackbars...) para que cualquier widget que no
// declare su propio estilo caiga en algo consistente por defecto.

import 'package:flutter/material.dart';

/// Paleta de colores de la app.
class AppColors {
  AppColors._();

  /// Verde azulado / teal — botones principales, chips seleccionadas,
  /// iconos activos, bordes de selección (método de pago, categoría activa).
  static const primary = Color(0xFF00A99D);

  /// Tono más oscuro del primario, usado en estados presionados/realzados
  /// donde no alcanza con la opacidad (p. ej. iconThemes sobre fondo claro).
  static const primaryDark = Color(0xFF00847A);

  /// Verde de éxito — banner de "producto agregado", confirmaciones.
  static const success = Color(0xFF2ECC71);

  /// Naranja/ámbar de advertencia — "código no encontrado", recuadro de
  /// "Vuelto", avisos no destructivos.
  static const warning = Color(0xFFF5A623);

  /// Rojo de peligro — "Eliminar Venta" y confirmaciones destructivas.
  static const danger = Color(0xFFE74C3C);

  /// Overlay oscuro semi-transparente sobre la cámara (menú lateral,
  /// catálogo, etc.), opacidad ~0.8.
  static const overlay = Color(0xCC000000);

  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B6F76);
  static const divider = Color(0xFFE0E0E0);
  static const disabled = Color(0xFFD9D9D9);
  static const cardBackground = Colors.white;
}

/// Escala tipográfica de la app (Parte 11): títulos de pantalla en negrita
/// (~18-20sp), nombres de producto en semibold (~15sp), montos en negrita,
/// textos secundarios en gris (~12-13sp). Se exponen como constantes
/// reutilizables además de quedar conectadas al `textTheme` de más abajo,
/// para que una pantalla nueva pueda usar `AppTextStyles.productName` o,
/// si prefiere heredar del contexto, `Theme.of(context).textTheme.bodyLarge`.
class AppTextStyles {
  AppTextStyles._();

  static const screenTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const productName = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const amount = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const amountLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const secondary = TextStyle(
    fontSize: 12.5,
    color: AppColors.textSecondary,
  );

  static const buttonLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}

final ThemeData appTheme = ThemeData(
  useMaterial3: true,

  // Fuente del sistema (Roboto en Android) en vez de descargar Google
  // Fonts en tiempo de ejecución: la app funciona 100% offline (Supuesto 4
  // del prompt), así que evitamos cualquier dependencia de red para algo
  // tan básico como la tipografía. Si más adelante se quiere usar Inter,
  // conviene empaquetar el .ttf como asset en vez de `google_fonts`
  // (ese paquete intenta bajar el archivo de fuente la primera vez).
  fontFamily: 'Roboto',

  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
  ),
  scaffoldBackgroundColor: const Color(0xFFF5F6F7),
  splashColor: AppColors.primary.withValues(alpha: 0.12),
  highlightColor: AppColors.primary.withValues(alpha: 0.06),

  textTheme: const TextTheme(
    titleLarge: AppTextStyles.screenTitle,
    titleMedium: AppTextStyles.sectionTitle,
    bodyLarge: AppTextStyles.productName,
    bodyMedium: TextStyle(fontSize: 14, color: AppColors.textPrimary),
    bodySmall: AppTextStyles.secondary,
    labelLarge: AppTextStyles.buttonLabel,
  ),

  cardTheme: CardThemeData(
    color: AppColors.cardBackground,
    elevation: 2,
    shadowColor: Colors.black12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: EdgeInsets.zero,
  ),

  // Botones principales: ancho completo, altura ~50, esquinas redondeadas
  // (~12), color primario de fondo y texto blanco; deshabilitado en gris
  // claro.
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.disabled,
      // Antes: Colors.white70 sobre fondo gris claro (AppColors.disabled)
      // era casi invisible (blanco sobre blanco). textSecondary da
      // contraste real para leer el botón aunque esté deshabilitado.
      disabledForegroundColor: AppColors.textSecondary,
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: AppTextStyles.buttonLabel,
    ),
  ),

  // Botones outline de peligro (ej. "Eliminar Venta" en Parte 9).
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.danger,
      side: const BorderSide(color: AppColors.danger),
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: AppTextStyles.buttonLabel,
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  ),

  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: AppTextStyles.screenTitle,
    iconTheme: IconThemeData(color: AppColors.textPrimary),
  ),

  // Tabs de Historial de Ventas (Hoy/Semana/Mes/Todo). Las pantallas que
  // ya fijan `labelColor`/`indicatorColor` explícitamente siguen viéndose
  // igual; esto solo define el valor por defecto para el resto.
  tabBarTheme: TabBarThemeData(
    labelColor: AppColors.primary,
    unselectedLabelColor: AppColors.textSecondary,
    indicatorColor: AppColors.primary,
    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
  ),

  // Chips de categoría (Inventario, Catálogo).
  chipTheme: ChipThemeData(
    backgroundColor: Colors.white70,
    selectedColor: AppColors.primary,
    labelStyle: const TextStyle(color: AppColors.textPrimary),
    secondaryLabelStyle: const TextStyle(color: Colors.white),
    side: BorderSide.none,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),

  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
  ),

  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    titleTextStyle: AppTextStyles.sectionTitle,
    contentTextStyle: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
  ),

  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
  ),

  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF323232),
    contentTextStyle: const TextStyle(color: Colors.white),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),

  dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),

  progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
);
