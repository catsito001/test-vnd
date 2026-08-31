// lib/screens/product_screens.dart
//
// Parte 4 (InventoryScreen) + Parte 5 (NewProductScreen y el bottom sheet
// "Vincular a producto existente") en un solo archivo, más un
// BarcodeScannerScreen reutilizable que también usarán la pantalla
// principal (Parte 2) y el catálogo (Parte 6) más adelante.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/camera_error_view.dart';
import '../utils/permissions.dart';
import '../utils/utils.dart';

// ===========================================================================
// Escáner de código de barras reutilizable
// ===========================================================================

/// Pantalla de cámara en modo detección continua con un marco cuadrado de
/// referencia. Devuelve el primer código detectado con Navigator.pop(code).
/// Si el usuario prefiere no escanear, "Ingresar manualmente" cambia a un
/// campo de texto simple.
class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  const BarcodeScannerScreen({super.key, this.title = 'Escanear código de barras'});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.code128,
    ],
    // Fix cámara (Inventario > Código del nuevo producto): con autoStart
    // en true (el default), el propio widget MobileScanner intenta
    // arrancar la cámara apenas se monta, al mismo tiempo que el chequeo
    // de permiso de más abajo también puede disparar un start(). Esa
    // carrera es justo lo que tira "MobileScannerController is already
    // running". Con autoStart:false, el único que arranca la cámara es
    // _startCamera() acá abajo.
    autoStart: false,
  );
  final TextEditingController _manualController = TextEditingController();
  bool _manualMode = false;
  bool _handled = false;

  // Permiso de cámara (Parte 12). Si no está concedido, la pantalla entra
  // directo en modo manual (no tiene sentido intentar montar
  // `MobileScanner` sin permiso) pero deja un atajo para pedirlo de nuevo.
  bool _checkingCameraPermission = true;
  bool _cameraPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCameraPermission());
  }

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    final granted = await ensureCameraPermission(context);
    if (!mounted) return;
    setState(() {
      _cameraPermissionGranted = granted;
      _checkingCameraPermission = false;
      if (!granted) _manualMode = true;
    });
    if (granted) await _startCamera();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  /// Único lugar que llama a `_controller.start()`. El guard de
  /// `isRunning` evita pedir un segundo arranque si ya está corriendo, y
  /// si igual llega a chocar con "ya estaba corriendo" (carrera rara),
  /// hace un stop+start limpio en vez de dejar ese error en pantalla.
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

  Future<void> _retryCamera() => _startCamera();

  void _confirmManual() {
    final value = _manualController.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: _checkingCameraPermission
          ? const ColoredBox(
              color: Colors.black,
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          : (_manualMode ? _buildManualEntry() : _buildScannerView()),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => CameraErrorView(
            error: error,
            onRetry: _retryCamera,
            onFallback: () => setState(() => _manualMode = true),
            fallbackLabel: 'Ingresar manualmente',
          ),
        ),
        Center(
          child: Container(
            width: 260,
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Column(
            children: [
              const Text(
                'Apunta la cámara al código de barras',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => setState(() => _manualMode = true),
                child: const Text(
                  'Ingresar manualmente',
                  style: TextStyle(color: Colors.white, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualEntry() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_cameraPermissionGranted) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'La cámara está desactivada. Escribe el código a mano o activa el permiso.',
                style: TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _manualController,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Código de barras',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
            ),
            onSubmitted: (_) => _confirmManual(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _confirmManual, child: const Text('Confirmar')),
          const SizedBox(height: 8),
          if (_cameraPermissionGranted)
            TextButton(
              onPressed: () => setState(() => _manualMode = false),
              child: const Text('Volver a la cámara', style: TextStyle(color: Colors.white70)),
            )
          else
            TextButton(
              onPressed: () async {
                await _checkCameraPermission();
                if (_cameraPermissionGranted && mounted) {
                  setState(() => _manualMode = false);
                }
              },
              child: const Text('Dar permiso a la cámara', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Parte 4 — Inventario
// ===========================================================================

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _db = DatabaseHelper.instance;
  final _searchController = TextEditingController();

  List<Category> _categories = [];
  int? _selectedCategoryId; // null = "Todos"
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final categories = await _db.getCategories();
    final products = await _db.getProducts(
      query: _searchController.text,
      categoryId: _selectedCategoryId,
    );
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _products = products;
      _loading = false;
    });
  }

  /// FAB "+": escanear (o ingresar manualmente) y abrir Nuevo Producto con
  /// el código ya cargado.
  Future<void> _openNewProductFlow() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'Código del nuevo producto'),
      ),
    );
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewProductScreen(initialBarcode: code)),
    );
    if (saved == true) _load();
  }

  /// Icono de la app bar: escanea un código y lo vincula directamente a un
  /// producto existente, sin pasar por el formulario de producto nuevo.
  Future<void> _openQuickLink() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'Código a vincular'),
      ),
    );
    if (code == null || !mounted) return;
    final linked = await showLinkExistingProductSheet(context, code);
    if (linked == true) _load();
  }

  Future<void> _openProduct(Product product) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewProductScreen(product: product)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link_outlined),
            tooltip: 'Vincular código a producto existente',
            onPressed: _openQuickLink,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar producto o código',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _load(),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _CategoryChip(
                  label: 'Todos',
                  selected: _selectedCategoryId == null,
                  onTap: () {
                    setState(() => _selectedCategoryId = null);
                    _load();
                  },
                ),
                for (final c in _categories)
                  _CategoryChip(
                    label: c.name,
                    selected: _selectedCategoryId == c.id,
                    onTap: () {
                      setState(() => _selectedCategoryId = c.id);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_products.length} productos',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: _products.length,
                        itemBuilder: (context, i) => _ProductTile(
                          product: _products[i],
                          categoryName: _categoryNameFor(_products[i].categoryId),
                          onTap: () => _openProduct(_products[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewProductFlow,
        child: const Icon(Icons.add),
      ),
    );
  }

  String _categoryNameFor(int? categoryId) {
    if (categoryId == null) return '';
    final match = _categories.where((c) => c.id == categoryId);
    return match.isNotEmpty ? match.first.name : '';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inventory_2_outlined, size: 56, color: Colors.black26),
          SizedBox(height: 12),
          Text('No hay productos', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text('Toca + para agregar', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? AppColors.primary : Colors.black12),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final String categoryName;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.categoryName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      product.barcodes.isNotEmpty ? product.barcodes.first : 'Sin código',
      if (categoryName.isNotEmpty) categoryName,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFFEFEFEF),
          backgroundImage: product.photoPath != null ? FileImage(File(product.photoPath!)) : null,
          child: product.photoPath == null
              ? const Icon(Icons.inventory_2_outlined, color: Colors.black45)
              : null,
        ),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.soldByWeight ? '${formatCurrency(product.salePrice)}/kg' : formatCurrency(product.salePrice),
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
              ),
              Text(
                subtitleParts.join(' • '),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        trailing: Text(
          product.soldByWeight ? formatWeight(product.currentStock) : '${product.currentStock} uds',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ===========================================================================
// Parte 5 — Nuevo Producto / Editar Producto
// ===========================================================================

class NewProductScreen extends StatefulWidget {
  /// Si viene un [product], la pantalla funciona en modo edición.
  final Product? product;

  /// Código de barras pre-cargado cuando se llega desde el flujo de
  /// escaneo (producto no encontrado en Inventario o en la pantalla
  /// principal).
  final String? initialBarcode;

  const NewProductScreen({super.key, this.product, this.initialBarcode});

  @override
  State<NewProductScreen> createState() => _NewProductScreenState();
}

class _NewProductScreenState extends State<NewProductScreen> {
  final _db = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _salePriceController;
  late final TextEditingController _stockController;
  late final TextEditingController _minStockController;

  int? _categoryId;
  String? _photoPath;
  List<Category> _categories = [];

  /// Producto a granel (fruta, verdura, etc.): precio por kilo y stock en
  /// kg en vez de unidades. Ver `Product.soldByWeight`.
  bool _soldByWeight = false;

  bool get _isEditing => widget.product != null;

  /// Texto inicial del campo de stock: en kg (con decimales) si el
  /// producto ya es por peso, o el entero de unidades si no.
  String _stockFieldText(int? grams, bool byWeight) {
    final value = grams ?? 0;
    if (!byWeight) return value.toString();
    var text = (value / 1000).toStringAsFixed(3);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _soldByWeight = product?.soldByWeight ?? false;
    _barcodeController = TextEditingController(
      text: product != null ? product.barcodes.join(', ') : (widget.initialBarcode ?? ''),
    );
    _nameController = TextEditingController(text: product?.name ?? '');
    _descController = TextEditingController(text: product?.description ?? '');
    _purchasePriceController =
        TextEditingController(text: product != null ? product.purchasePrice.toStringAsFixed(2) : '');
    _salePriceController =
        TextEditingController(text: product != null ? product.salePrice.toStringAsFixed(2) : '');
    _stockController = TextEditingController(text: _stockFieldText(product?.currentStock, _soldByWeight));
    _minStockController = TextEditingController(text: _stockFieldText(product?.minStock, _soldByWeight));
    _categoryId = product?.categoryId;
    _photoPath = product?.photoPath;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await _db.getCategories();
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Elegir de galería'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    final saved = await persistPickedImage(file, prefix: 'product');
    if (saved != null && mounted) setState(() => _photoPath = saved);
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null) return;
    final current = _barcodeController.text.trim();
    final existing = current.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (!existing.contains(code)) {
      _barcodeController.text = existing.isEmpty ? code : '${existing.join(', ')}, $code';
    }
  }

  Future<void> _openLinkSheet() async {
    final code = _barcodeController.text.trim().split(',').first.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escanea o escribe un código de barras primero')),
      );
      return;
    }
    final linked = await showLinkExistingProductSheet(context, code);
    if (linked == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final barcodes = _barcodeController.text
        .split(',')
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    int parseStock(TextEditingController controller) {
      if (!_soldByWeight) return int.tryParse(controller.text) ?? 0;
      final kg = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
      return (kg * 1000).round();
    }

    final product = Product(
      id: widget.product?.id,
      name: _nameController.text.trim(),
      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      barcodes: barcodes,
      categoryId: _categoryId,
      purchasePrice: double.tryParse(_purchasePriceController.text.replaceAll(',', '.')) ?? 0,
      salePrice: double.tryParse(_salePriceController.text.replaceAll(',', '.')) ?? 0,
      currentStock: parseStock(_stockController),
      minStock: parseStock(_minStockController),
      photoPath: _photoPath,
      soldByWeight: _soldByWeight,
    );

    if (_isEditing) {
      await _db.updateProduct(product);
    } else {
      await _db.insertProduct(product);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar Producto' : 'Nuevo Producto')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFFEFEFEF),
                      backgroundImage: _photoPath != null ? FileImage(File(_photoPath!)) : null,
                      child: _photoPath == null
                          ? const Icon(Icons.camera_alt, size: 32, color: Colors.black45)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    const Text('Añadir foto', style: TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _openLinkSheet,
                icon: const Icon(Icons.link),
                label: const Text('Vincular a producto existente'),
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _barcodeController,
              decoration: InputDecoration(
                labelText: 'Código de Barras',
                hintText: 'Ej. 7750... o varios separados por coma',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                  onPressed: _scanBarcode,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del Producto',
                hintText: 'Ej: Inca Kola 500ml',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa un nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                hintText: 'Descripción breve...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              hint: const Text('Seleccionar categoría'),
              items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _soldByWeight,
              onChanged: (v) => setState(() => _soldByWeight = v),
              title: const Text('Se vende por peso (kg)'),
              subtitle: const Text(
                'Para productos a granel (fruta, verdura...). El precio será por kilo '
                'y al venderlo se va a pedir el peso en kg o g.',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _purchasePriceController,
                    decoration: InputDecoration(
                      labelText: _soldByWeight ? 'Precio Compra /kg (S/)' : 'Precio Compra (S/)',
                      prefixIcon: const Icon(Icons.sell_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _salePriceController,
                    decoration: InputDecoration(
                      labelText: _soldByWeight ? 'Precio Venta /kg (S/)' : 'Precio Venta (S/)',
                      prefixIcon: const Icon(Icons.attach_money),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final value = double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0;
                      return value <= 0 ? 'Requerido' : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _stockController,
                    decoration: InputDecoration(
                      labelText: _soldByWeight ? 'Stock Actual (kg)' : 'Stock Actual',
                      prefixIcon: const Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: _soldByWeight),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _minStockController,
                    decoration: InputDecoration(
                      labelText: _soldByWeight ? 'Stock Mínimo (kg)' : 'Stock Mínimo',
                      prefixIcon: const Icon(Icons.warning_amber_outlined),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: _soldByWeight),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _save, child: const Text('Guardar Producto')),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Bottom sheet "Vincular a producto existente" (usado desde Inventario y
// desde Nuevo Producto)
// ===========================================================================

Future<bool?> showLinkExistingProductSheet(BuildContext context, String barcode) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => _LinkExistingProductSheet(barcode: barcode),
  );
}

class _LinkExistingProductSheet extends StatefulWidget {
  final String barcode;
  const _LinkExistingProductSheet({required this.barcode});

  @override
  State<_LinkExistingProductSheet> createState() => _LinkExistingProductSheetState();
}

class _LinkExistingProductSheetState extends State<_LinkExistingProductSheet> {
  final _db = DatabaseHelper.instance;
  final _searchController = TextEditingController();
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final products = await _db.getProducts(query: _searchController.text);
    if (!mounted) return;
    setState(() => _products = products);
  }

  Future<void> _link(Product product) async {
    await _db.addBarcodeToProduct(product.id!, widget.barcode);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Código vinculado a "${product.name}"'),
        backgroundColor: AppColors.success,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Vincular a producto existente',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Busca y selecciona el producto al que quieres añadir este nuevo código',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _load(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _products.isEmpty
                  ? const Center(
                      child: Text('No se encontraron productos', style: TextStyle(color: Colors.black45)),
                    )
                  : ListView.builder(
                      itemCount: _products.length,
                      itemBuilder: (context, i) {
                        final product = _products[i];
                        final codes = product.barcodes.join(', ');
                        final truncated = codes.length > 18 ? '${codes.substring(0, 18)}...' : codes;
                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFEFEFEF),
                            child: Icon(Icons.inventory_2_outlined, color: Colors.black45),
                          ),
                          title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'Stock: ${product.soldByWeight ? formatWeight(product.currentStock) : product.currentStock} | Cód: $truncated',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          trailing: const Icon(Icons.link, color: AppColors.primary),
                          onTap: () => _link(product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
