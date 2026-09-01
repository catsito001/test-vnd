// lib/screens/home_screen.dart
//
// Parte 2 (ScannerHomeScreen: cámara + carrito flotante) + Parte 3 (menú
// lateral tipo overlay) en un solo archivo, ya que el menú solo existe
// para abrirse desde esta pantalla.

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../theme.dart';
import '../utils/camera_error_view.dart';
import '../utils/navigation.dart';
import '../utils/permissions.dart';
import '../utils/utils.dart';
import '../utils/weight_entry_sheet.dart';
import 'catalog_screen.dart';
import 'checkout_screen.dart';
import 'product_screens.dart';
import 'sales_history_screen.dart';
import 'settings_screen.dart';

// ===========================================================================
// Parte 2 — Pantalla principal (Cámara + Carrito flotante)
// ===========================================================================

class ScannerHomeScreen extends StatefulWidget {
  const ScannerHomeScreen({super.key});

  @override
  State<ScannerHomeScreen> createState() => _ScannerHomeScreenState();
}

class _ScannerHomeScreenState extends State<ScannerHomeScreen> with RouteAware {
  final MobileScannerController _controller = MobileScannerController(
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.code128,
    ],
    // Ver el mismo comentario en BarcodeScannerScreen (product_screens.dart):
    // autoStart:false + _startCamera() explícito evita la carrera con el
    // chequeo de permiso que puede tirar "already running".
    autoStart: false,
  );

  // Sonidito de éxito al capturar el código de un producto. `lowLatency`
  // precarga el clip en memoria (mejor para efectos cortos que ReleaseMode
  // normal, pensado para música).
  final AudioPlayer _successSound = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);

  bool _menuOpen = false;
  bool _torchOn = false;

  // Permiso de cámara (Parte 12): se pide apenas se pinta el primer frame
  // para poder mostrar el diálogo explicativo sobre una UI ya visible en
  // vez de una pantalla en blanco. Mientras no esté concedido, no se monta
  // el widget `MobileScanner` (evita el estado de error nativo del
  // paquete y deja usar igual el resto de la app).
  bool _checkingCameraPermission = true;
  bool _cameraPermissionGranted = false;

  // Debounce: evita que el mismo código dispare varias veces seguidas.
  String? _lastCode;
  DateTime? _lastScanTime;
  bool _weightSheetOpen = false;

  // Banners temporales sobre la tarjeta del carrito.
  Product? _foundProduct;
  String? _notFoundCode;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCameraPermission());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _controller.dispose();
    _successSound.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  // --- RouteAware (fix cámara) ------------------------------------------
  //
  // Se dispara al navegar a Inventario, al Catálogo, o a cualquier
  // pantalla que abra su propia cámara (escanear código nuevo/vincular).
  // Frenamos acá la cámara de esta pantalla para no competir por el
  // hardware con el controller de la pantalla nueva — es la causa raíz
  // del error "MobileScannerController is already running" /
  // "controllerAlreadyInitialized". Efecto secundario menor y aceptado:
  // la cámara detrás del Catálogo (que antes se veía "viva" como overlay
  // translúcido) ahora se congela mientras el Catálogo está abierto, pero
  // ya no se rompe.
  @override
  void didPushNext() {
    _controller.stop();
  }

  @override
  void didPopNext() {
    if (_cameraPermissionGranted) _startCamera();
  }

  Future<void> _checkCameraPermission() async {
    final granted = await ensureCameraPermission(context);
    if (!mounted) return;
    setState(() {
      _cameraPermissionGranted = granted;
      _checkingCameraPermission = false;
    });
    if (granted) await _startCamera();
  }

  /// Único lugar que llama a `_controller.start()`. Ver el comentario
  /// gemelo en BarcodeScannerScreen (product_screens.dart).
  Future<void> _startCamera() async {
    try {
      if (_controller.value.isRunning) return;
      await _controller.start();
    } on MobileScannerException catch (e) {
      if (e.errorCode == MobileScannerErrorCode.controllerAlreadyInitialized) {
        try {
          await _controller.stop();
          await _controller.start();
        } catch (_) {
          // Si tampoco arranca así, el errorBuilder muestra el motivo real.
        }
      }
    }
    if (mounted) setState(() {});
  }

  // --- Escaneo -------------------------------------------------------

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handleBarcode(value);
  }

  Future<void> _handleBarcode(String code) async {
    final now = DateTime.now();
    if (_lastCode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(milliseconds: 1500)) {
      return; // mismo código detectado hace muy poco: ignorar
    }
    _lastCode = code;
    _lastScanTime = now;

    final product = await DatabaseHelper.instance.getProductByBarcode(code);
    if (!mounted) return;

    if (product == null) {
      _showNotFoundBanner(code);
      return;
    }

    await _addProductToCart(product);
  }

  /// Agrega [product] al carrito (pidiendo el peso primero si es un
  /// producto a granel) y muestra el banner + sonido de éxito. Lo usan
  /// tanto el escaneo normal (`_handleBarcode`) como el flujo de
  /// "producto nuevo"/"vincular" (`_addNotFoundProduct`), para no
  /// duplicar la lógica de carrito en dos lados.
  Future<void> _addProductToCart(Product product) async {
    if (product.soldByWeight) {
      // Producto por peso con código de barras propio (poco común: lo
      // normal es agregarlos desde el Catálogo, sin escanear, pero puede
      // pasar si se le vinculó un código). Pide el peso en vez de sumar
      // 1 unidad directamente. El guard evita abrir el sheet dos veces
      // si la cámara sigue detectando el mismo código mientras el
      // primero sigue abierto.
      if (_weightSheetOpen) return;
      _weightSheetOpen = true;
      final grams = await showWeightEntrySheet(context, product: product);
      _weightSheetOpen = false;
      if (grams == null || grams <= 0 || !mounted) return;
      context.read<CartProvider>().addWeightedProduct(product, grams);
      _showFoundBanner(product);
      return;
    }

    context.read<CartProvider>().addProduct(product);
    _showFoundBanner(product);
  }

  void _showFoundBanner(Product product) {
    _playSuccessSound();
    _bannerTimer?.cancel();
    setState(() {
      _foundProduct = product;
      _notFoundCode = null;
    });
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _foundProduct = null);
    });
  }

  /// No debe frenar el flujo de escaneo si falla (dispositivo sin salida
  /// de audio, primer play todavía cargando el asset, etc), por eso el
  /// try/catch silencioso: en el peor caso simplemente no suena.
  Future<void> _playSuccessSound() async {
    try {
      await _successSound.stop();
      await _successSound.play(AssetSource('sounds/success.wav'));
    } catch (_) {
      // No pasa nada si no pudo sonar; el carrito ya se actualizó igual.
    }
  }

  void _showNotFoundBanner(String code) {
    _bannerTimer?.cancel();
    setState(() {
      _notFoundCode = code;
      _foundProduct = null;
    });
  }

  Future<void> _addNotFoundProduct() async {
    final code = _notFoundCode;
    if (code == null) return;
    // NewProductScreen ahora devuelve el Product guardado (nuevo o
    // vinculado), no solo `true`/`false`, para poder agregarlo al
    // carrito de una vez y no obligar a volver a escanear el mismo
    // código que el usuario acaba de registrar.
    final saved = await Navigator.of(context).push<Product>(
      MaterialPageRoute(builder: (_) => NewProductScreen(initialBarcode: code)),
    );
    if (saved != null && mounted) {
      setState(() => _notFoundCode = null);
      await _addProductToCart(saved);
    }
  }

  // --- Navegación ------------------------------------------------------

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _toggleTorch() {
    if (!_cameraPermissionGranted) return;
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _flipCamera() {
    if (!_cameraPermissionGranted) return;
    _controller.switchCamera();
  }

  void _openCatalog() {
    // Ruta translúcida: la cámara de esta pantalla sigue viva y visible
    // detrás del fondo oscurecido del catálogo (Parte 6), como overlay.
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => const ProductCatalogScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openReviewOrder() {
    if (context.read<CartProvider>().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReviewOrderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildCameraArea()),
          SafeArea(child: _buildTopBar()),
          Align(
            alignment: Alignment.bottomCenter,
            // Parte 12 (fix): sin SafeArea acá, la tarjeta blanca (y el
            // botón "Revisar Orden") quedaba pegada/tapada por la barra de
            // navegación del sistema en teléfonos con navegación de 3
            // botones (se ve en la captura que mandaste).
            child: SafeArea(top: false, child: _buildBottomArea()),
          ),
          _buildSideMenu(),
        ],
      ),
    );
  }

  // --- Cámara / estado sin permiso (Parte 12) -----------------------------

  Widget _buildCameraArea() {
    if (_checkingCameraPermission) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (!_cameraPermissionGranted) {
      return _buildNoCameraPermissionState();
    }
    return MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
      // Parte 12 (fix): sin este `errorBuilder`, mobile_scanner cae en su
      // pantalla de error por defecto —un ícono blanco de "!" sobre negro,
      // sin texto ni forma de reintentar— cuando la cámara falla al
      // iniciar por algo que NO es falta de permiso. Ver CameraErrorView.
      errorBuilder: (context, error) => CameraErrorView(
        error: error,
        onRetry: _retryCamera,
        onFallback: _openCatalog,
        fallbackLabel: 'Usar el Catálogo de Productos',
      ),
    );
  }

  Future<void> _retryCamera() => _startCamera();

  Widget _buildNoCameraPermissionState() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 56, color: Colors.white38),
              const SizedBox(height: 16),
              const Text(
                'Cámara desactivada',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sin permiso de cámara no se pueden escanear códigos de barra, '
                'pero puedes seguir agregando productos desde el Catálogo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _checkCameraPermission,
                child: const Text('Dar permiso a la cámara'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _openCatalog,
                child: const Text('Usar el Catálogo de Productos'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Barra superior ----------------------------------------------------

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CircleIconButton(icon: Icons.menu, onTap: _toggleMenu),
          Row(
            children: [
              _CircleIconButton(icon: Icons.settings_outlined, onTap: _openSettings),
              const SizedBox(width: 8),
              _CircleIconButton(icon: Icons.grid_view_rounded, onTap: _openCatalog),
              const SizedBox(width: 8),
              _CircleIconButton(
                icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                onTap: _toggleTorch,
                enabled: _cameraPermissionGranted,
              ),
              const SizedBox(width: 8),
              _CircleIconButton(
                icon: Icons.cameraswitch_outlined,
                onTap: _flipCamera,
                enabled: _cameraPermissionGranted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Banners + tarjeta inferior -----------------------------------------

  Widget _buildBottomArea() {
    final cart = context.watch<CartProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_foundProduct != null) _buildFoundBanner(_foundProduct!),
        if (_notFoundCode != null) _buildNotFoundBanner(_notFoundCode!),
        _buildCartCard(cart),
      ],
    );
  }

  Widget _buildFoundBanner(Product product) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${product.name} agregado  ${formatCurrency(product.salePrice)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundBanner(String code) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Código $code no encontrado',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _addNotFoundProduct,
            style: TextButton.styleFrom(backgroundColor: Colors.white24),
            child: const Text('AGREGAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCartCard(CartProvider cart) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text('Artículos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 6),
                    Text('${cart.totalQuantity} items', style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!cart.isEmpty)
                    GestureDetector(
                      onTap: () => cart.clear(),
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('LIMPIAR',
                            style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  Row(
                    children: [
                      const Text('TOTAL  ', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                      Text(
                        formatCurrency(cart.total),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, minHeight: 90),
            child: cart.isEmpty ? _buildEmptyCart() : _buildCartList(cart),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: cart.isEmpty ? null : _openReviewOrder,
            child: const Text('Revisar Orden'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 40, color: Colors.black26),
          SizedBox(height: 8),
          Text('Lista vacía', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Los productos escaneados con la cámara aparecerán en esta lista.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList(CartProvider cart) {
    return ListView.separated(
      itemCount: cart.items.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, i) => _CartItemRow(item: cart.items[i]),
    );
  }

  // --- Menú lateral (Parte 3) --------------------------------------------

  Widget _buildSideMenu() {
    return Stack(
      children: [
        if (_menuOpen)
          GestureDetector(
            onTap: _toggleMenu,
            child: Container(color: AppColors.overlay),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          top: 0,
          bottom: 0,
          left: _menuOpen ? 0 : -300,
          width: 280,
          child: Material(
            color: const Color(0xE6111111),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ventas Cell',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    _MenuOption(
                      icon: Icons.inventory_2_outlined,
                      title: 'Inventario',
                      subtitle: 'Gestionar productos',
                      onTap: () {
                        _toggleMenu();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const InventoryScreen()),
                        );
                      },
                    ),
                    _MenuOption(
                      icon: Icons.history,
                      title: 'Historial de Ventas',
                      subtitle: 'Ver ventas anteriores',
                      onTap: () {
                        _toggleMenu();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
                        );
                      },
                    ),
                    _MenuOption(
                      icon: Icons.settings_outlined,
                      title: 'Ajustes',
                      subtitle: 'Configurar negocio e impresora',
                      onTap: () {
                        _toggleMenu();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _CircleIconButton({required this.icon, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: enabled ? Colors.white : Colors.white30),
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final CartItem item;
  const _CartItemRow({required this.item});

  /// Abre la ficha del producto (misma pantalla que usa Inventario para
  /// editar). Si se guardó un cambio, refresca los datos de esa línea del
  /// carrito (nombre/precio/foto) sin perder la cantidad ya elegida.
  Future<void> _openEdit(BuildContext context, CartProvider cart, Product product) async {
    final saved = await Navigator.of(context).push<Product>(
      MaterialPageRoute(builder: (_) => NewProductScreen(product: product)),
    );
    if (saved == null) return;
    final refreshed = await DatabaseHelper.instance.getProductById(product.id!);
    if (refreshed != null) cart.updateProductData(refreshed);
  }

  /// Reabre el sheet de kg/g con el peso actual precargado, para ajustar
  /// la cantidad de una línea por peso ya agregada al carrito.
  Future<void> _editWeight(BuildContext context, CartProvider cart, Product product) async {
    final grams = await showWeightEntrySheet(context, product: product, initialGrams: item.quantity);
    if (grams == null) return;
    cart.setWeight(product.id!, grams);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();
    final product = item.product;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openEdit(context, cart, product),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEFEFEF),
                  backgroundImage: product.photoPath != null ? FileImage(File(product.photoPath!)) : null,
                  child: product.photoPath == null
                      ? const Icon(Icons.inventory_2_outlined, size: 18, color: Colors.black45)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        product.soldByWeight ? '${formatCurrency(product.salePrice)}/kg' : formatCurrency(product.salePrice),
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (product.soldByWeight) ...[
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _editWeight(context, cart, product),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(formatWeight(item.quantity), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black45, size: 20),
            onPressed: () => cart.removeItem(product.id!),
          ),
        ] else ...[
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.black45),
            onPressed: () => cart.decrementQuantity(product.id!),
          ),
          Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.primary),
            onPressed: () => cart.incrementQuantity(product.id!),
          ),
        ],
        SizedBox(
          width: 64,
          child: Text(
            formatCurrency(item.subtotal),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

