// lib/screens/settings_screen.dart
//
// Parte 10 — Ajustes.
//
// `SettingsScreen`: lista de secciones tipo acordeón (ExpansionTile, cuyo
// chevron ya rota solo al expandir/colapsar). Cada sección edita un pedazo
// de `AppSettings` (o, en el caso de Vendedores/Categorías, sus propias
// tablas) en memoria; el botón fijo "Guardar Configuración" persiste todo
// junto al final, tal como pide el prompt.

import 'dart:async';
import 'dart:io';

import 'package:esc_pos_bluetooth/esc_pos_bluetooth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/permissions.dart';
import '../utils/utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = DatabaseHelper.instance;

  bool _loading = true;
  bool _saving = false;

  late final TextEditingController _businessNameController;
  late final TextEditingController _businessAddressController;
  late final TextEditingController _businessPhoneController;
  late final TextEditingController _footerMessageController;

  String? _yapeQrImagePath;
  bool _yapeJustUploaded = false;

  List<Seller> _sellers = [];
  List<Category> _categories = [];

  /// Vendedor activo (Parte 1/7/8): el que se guarda en cada venta y sale
  /// impreso como "Atendido por" mientras no se cambie desde aquí.
  int? _activeSellerId;

  String _printerSize = '58mm';
  String? _printerMacAddress;
  String? _printerName;

  @override
  void initState() {
    super.initState();
    _businessNameController = TextEditingController();
    _businessAddressController = TextEditingController();
    _businessPhoneController = TextEditingController();
    _footerMessageController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessAddressController.dispose();
    _businessPhoneController.dispose();
    _footerMessageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _db.getSettings();
    final sellers = await _db.getSellers();
    final categories = await _db.getCategories();
    if (!mounted) return;
    setState(() {
      _businessNameController.text = settings.businessName;
      _businessAddressController.text = settings.businessAddress;
      _businessPhoneController.text = settings.businessPhone;
      _footerMessageController.text = settings.receiptFooterMessage;
      _yapeQrImagePath = settings.yapeQrImagePath;
      _printerSize = settings.printerSize;
      _printerMacAddress = settings.printerMacAddress;
      _printerName = settings.printerName;
      _sellers = sellers;
      _categories = categories;
      _activeSellerId = settings.activeSellerId;
      _loading = false;
    });
  }

  // --- Guardar Configuración ----------------------------------------------

  Future<void> _saveAll() async {
    if (_saving) return;
    setState(() => _saving = true);

    final footer = _footerMessageController.text.trim();
    final settings = AppSettings(
      businessName: _businessNameController.text.trim(),
      businessAddress: _businessAddressController.text.trim(),
      businessPhone: _businessPhoneController.text.trim(),
      yapeQrImagePath: _yapeQrImagePath,
      printerSize: _printerSize,
      printerMacAddress: _printerMacAddress,
      printerName: _printerName,
      receiptFooterMessage: footer.isEmpty ? '¡Gracias por su compra!' : footer,
      activeSellerId: _activeSellerId,
    );
    await _db.saveSettings(settings);

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración guardada'), backgroundColor: AppColors.success),
    );
  }

  // --- QR de Yape -----------------------------------------------------

  Future<void> _pickYapeQr() async {
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
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final saved = await persistPickedImage(file, prefix: 'yape_qr');
    if (saved == null || !mounted) return;
    setState(() {
      _yapeQrImagePath = saved;
      _yapeJustUploaded = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _yapeJustUploaded = false);
    });
  }

  void _removeYapeQr() => setState(() {
        _yapeQrImagePath = null;
        _yapeJustUploaded = false;
      });

  void _previewImage(String path) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Image.file(File(path)),
      ),
    );
  }

  // --- Vendedores -----------------------------------------------------

  Future<void> _addSeller() async {
    final name = await _promptForName(title: 'Nuevo vendedor', hint: 'Nombre del vendedor');
    if (name == null || name.trim().isEmpty) return;
    final wasEmpty = _sellers.isEmpty;
    await _db.insertSeller(Seller(name: name.trim()));
    final sellers = await _db.getSellers();
    if (!mounted) return;
    setState(() {
      _sellers = sellers;
      // Si es el primer vendedor que se agrega, lo dejamos como activo de
      // una vez para no obligar a un paso extra.
      if (wasEmpty && sellers.isNotEmpty) _activeSellerId = sellers.first.id;
    });
  }

  Future<void> _deleteSeller(Seller seller) async {
    final confirmed = await _confirmDialog(
      title: 'Eliminar vendedor',
      message: '¿Eliminar a "${seller.name}"?',
    );
    if (confirmed != true) return;
    await _db.deleteSeller(seller.id!);
    final sellers = await _db.getSellers();
    if (!mounted) return;
    setState(() {
      _sellers = sellers;
      // Si era el vendedor activo, la FK en `app_settings` ya lo puso en
      // null en la base de datos (ON DELETE SET NULL); reflejamos lo mismo
      // en el estado local para no dejar seleccionado un id que ya no existe.
      if (_activeSellerId == seller.id) _activeSellerId = null;
    });
  }

  // --- Categorías -----------------------------------------------------

  Future<void> _addCategory() async {
    final name = await _promptForName(title: 'Nueva categoría', hint: 'Nombre de la categoría');
    if (name == null || name.trim().isEmpty) return;
    await _db.insertCategory(Category(name: name.trim()));
    final categories = await _db.getCategories();
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  Future<void> _deleteCategory(Category category) async {
    final confirmed = await _confirmDialog(
      title: 'Eliminar categoría',
      message: '¿Eliminar la categoría "${category.name}"?',
    );
    if (confirmed != true) return;
    final deleted = await _db.deleteCategory(category.id!);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se puede eliminar "${category.name}": todavía tiene productos asociados.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final categories = await _db.getCategories();
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  // --- Diálogos genéricos (agregar / confirmar) --------------------------

  Future<String?> _promptForName({required String title, required String hint}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDialog({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // --- Impresora Bluetooth ----------------------------------------------

  Future<void> _connectPrinter() async {
    final selected = await showModalBottomSheet<_BluetoothPrinterPick>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _PrinterScanSheet(),
    );
    if (selected == null) return;
    setState(() {
      _printerMacAddress = selected.address;
      _printerName = selected.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    children: [
                      _buildBusinessSection(),
                      _buildSubscriptionSection(),
                      _buildPaymentMethodsSection(),
                      _buildSellersSection(),
                      _buildCategoriesSection(),
                      _buildPrinterSection(),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveAll,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Guardar Configuración'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // --- 1. Datos del Negocio -----------------------------------------------

  Widget _buildBusinessSection() {
    return _SettingsSection(
      icon: Icons.storefront_outlined,
      title: 'Datos del Negocio',
      children: [
        TextFormField(
          controller: _businessNameController,
          decoration: const InputDecoration(labelText: 'Nombre del negocio'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _businessAddressController,
          decoration: const InputDecoration(labelText: 'Dirección'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _businessPhoneController,
          decoration: const InputDecoration(labelText: 'Teléfono'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _footerMessageController,
          decoration: const InputDecoration(
            labelText: 'Mensaje del ticket',
            hintText: '¡Gracias por su compra!',
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Estos datos se usan en el ticket impreso y en reportes futuros.',
          style: TextStyle(color: Colors.black45, fontSize: 12),
        ),
      ],
    );
  }

  // --- 2. Suscripción y Nube -----------------------------------------------

  Widget _buildSubscriptionSection() {
    return _SettingsSection(
      icon: Icons.cloud_outlined,
      title: 'Suscripción y Nube',
      children: const [
        Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.black45),
            SizedBox(width: 8),
            Expanded(
              child: Text('Plan actual: Gratis (solo local)', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'Próximamente vas a poder respaldar tus ventas e inventario en la nube y sincronizarlos entre '
          'varios dispositivos. Por ahora toda la información se guarda únicamente en este celular.',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );
  }

  // --- 3. Métodos de Pago (QR de Yape) -------------------------------------

  Widget _buildPaymentMethodsSection() {
    final hasQr = _yapeQrImagePath != null && _yapeQrImagePath!.isNotEmpty;
    return _SettingsSection(
      icon: Icons.qr_code_2,
      title: 'Métodos de Pago',
      children: [
        const Text('QR de Yape', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (hasQr) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(_yapeQrImagePath!), height: 160, fit: BoxFit.contain),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Imagen cargada', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.visibility_outlined),
                tooltip: 'Ver',
                onPressed: () => _previewImage(_yapeQrImagePath!),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Cambiar',
                onPressed: _pickYapeQr,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                tooltip: 'Borrar',
                onPressed: _removeYapeQr,
              ),
            ],
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _pickYapeQr,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Subir QR de Yape'),
          ),
        if (_yapeJustUploaded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: AppColors.success),
                SizedBox(width: 8),
                Text(
                  'Imagen QR cargada correctamente',
                  style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        const Text(
          'Plin y Tarjeta no requieren configuración: quedan registrados en la venta sin procesar '
          'el cobro dentro de la app.',
          style: TextStyle(color: Colors.black45, fontSize: 12),
        ),
      ],
    );
  }

  // --- 4. Vendedores -----------------------------------------------------

  Widget _buildSellersSection() {
    return _SettingsSection(
      icon: Icons.people_outline,
      title: 'Vendedores',
      children: [
        if (_sellers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Todavía no agregaste vendedores.', style: TextStyle(color: Colors.black45, fontSize: 13)),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Toca un vendedor para marcarlo como el "activo": es el que queda '
              'registrado en cada venta y sale como "Atendido por" en el ticket.',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ),
          _buildSellerOption(id: null, name: 'Ninguno (no registrar vendedor)'),
          for (final seller in _sellers)
            _buildSellerOption(id: seller.id, name: seller.name, seller: seller),
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _addSeller,
          icon: const Icon(Icons.add),
          label: const Text('Agregar vendedor'),
        ),
      ],
    );
  }

  Widget _buildSellerOption({required int? id, required String name, Seller? seller}) {
    final selected = _activeSellerId == id;
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _activeSellerId = id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : Colors.black38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: seller == null ? Colors.black54 : Colors.black87,
                    fontStyle: seller == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              if (seller != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: () => _deleteSeller(seller),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 5. Categorías -----------------------------------------------------

  Widget _buildCategoriesSection() {
    return _SettingsSection(
      icon: Icons.category_outlined,
      title: 'Categorías',
      children: [
        if (_categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No hay categorías todavía.', style: TextStyle(color: Colors.black45, fontSize: 13)),
          )
        else
          for (final category in _categories)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined, color: AppColors.primary),
              title: Text(category.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => _deleteCategory(category),
              ),
            ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _addCategory,
          icon: const Icon(Icons.add),
          label: const Text('Agregar categoría'),
        ),
      ],
    );
  }

  // --- 6. Impresora Bluetooth ----------------------------------------------

  Widget _buildPrinterSection() {
    final hasPrinter = _printerMacAddress != null && _printerMacAddress!.isNotEmpty;
    return _SettingsSection(
      icon: Icons.print_outlined,
      title: 'Impresora Bluetooth',
      children: [
        DropdownButtonFormField<String>(
          initialValue: _printerSize,
          decoration: const InputDecoration(labelText: 'Tamaño del Papel'),
          items: const [
            DropdownMenuItem(value: '58mm', child: Text('58 mm (Pequeño)')),
            DropdownMenuItem(value: '80mm', child: Text('80 mm (Grande)')),
          ],
          onChanged: (v) => setState(() => _printerSize = v ?? '58mm'),
        ),
        const SizedBox(height: 12),
        if (hasPrinter)
          Material(
            color: const Color(0xFFF5F6F7),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _connectPrinter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.print, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_printerName ?? 'Impresora', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(_printerMacAddress!, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.black45),
                  ],
                ),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _connectPrinter,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Conectar impresora térmica'),
          ),
      ],
    );
  }
}

// ===========================================================================
// Sección tipo acordeón reutilizable (ExpansionTile con el estilo de
// tarjeta redondeada del sistema de diseño, Parte 11).
// ===========================================================================

class _SettingsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

// ===========================================================================
// Búsqueda de impresoras Bluetooth (usado por "Conectar impresora térmica")
// ===========================================================================

class _BluetoothPrinterPick {
  final String name;
  final String address;
  const _BluetoothPrinterPick({required this.name, required this.address});
}

class _PrinterScanSheet extends StatefulWidget {
  const _PrinterScanSheet();

  @override
  State<_PrinterScanSheet> createState() => _PrinterScanSheetState();
}

class _PrinterScanSheetState extends State<_PrinterScanSheet> {
  final PrinterBluetoothManager _manager = PrinterBluetoothManager();
  StreamSubscription<List<PrinterBluetooth>>? _subscription;

  bool _scanning = true;
  String? _error;
  List<PrinterBluetooth> _devices = [];

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _devices = [];
    });

    // Mismos permisos que la Parte 8 necesita para imprimir (Bluetooth
    // clásico + ubicación en versiones antiguas de Android), centralizados
    // en `permissions.dart` (Parte 12) para mostrar siempre el mismo
    // diálogo explicativo.
    final granted = await ensureBluetoothPermissions(context);
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Se necesitan permisos de Bluetooth para buscar impresoras.';
      });
      return;
    }

    await _subscription?.cancel();
    _subscription = _manager.scanResults.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _manager.startScan(const Duration(seconds: 4));
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _scanning = false);
    });
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
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Impresoras Bluetooth', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (_scanning)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _startScan),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Asegúrate de que la impresora esté encendida y emparejada por Bluetooth en el celular.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                  : _devices.isEmpty
                      ? Center(
                          child: Text(
                            _scanning ? 'Buscando impresoras...' : 'No se encontraron impresoras.',
                            style: const TextStyle(color: Colors.black45),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, i) {
                            final device = _devices[i];
                            final name = device.name ?? 'Impresora sin nombre';
                            final address = device.address ?? '';
                            return ListTile(
                              leading: const Icon(Icons.print_outlined, color: AppColors.primary),
                              title: Text(name),
                              subtitle: Text(address),
                              onTap: () => Navigator.of(context).pop(
                                _BluetoothPrinterPick(name: name, address: address),
                              ),
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
