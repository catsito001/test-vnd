// lib/screens/checkout_screen.dart
//
// Parte 7 — Revisar Orden / Checkout / Métodos de pago.
// Ahora integrado con la Parte 8 (printing.dart): al confirmar la venta se
// intenta imprimir el ticket de verdad y, si falla, se ofrece
// "Reintentar impresión" sin perder la venta ya guardada.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../theme.dart';
import '../utils/printing.dart';
import '../utils/utils.dart';

class ReviewOrderScreen extends StatefulWidget {
  const ReviewOrderScreen({super.key});

  @override
  State<ReviewOrderScreen> createState() => _ReviewOrderScreenState();
}

class _ReviewOrderScreenState extends State<ReviewOrderScreen> {
  final _db = DatabaseHelper.instance;
  final _amountReceivedController = TextEditingController();

  static const _denominations = [5, 10, 20, 50, 100, 200];

  PaymentMethod _method = PaymentMethod.efectivo;
  String? _yapeQrPath;
  int? _activeSellerId;
  bool _loadingSettings = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountReceivedController.addListener(() => setState(() {}));
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _db.getSettings();
    if (!mounted) return;
    setState(() {
      _yapeQrPath = settings.yapeQrImagePath;
      _activeSellerId = settings.activeSellerId;
      _loadingSettings = false;
    });
  }

  @override
  void dispose() {
    _amountReceivedController.dispose();
    super.dispose();
  }

  double get _received =>
      double.tryParse(_amountReceivedController.text.replaceAll(',', '.')) ?? 0;

  double _changeFor(double total) => _received - total;

  bool _canConfirm(double total) {
    if (_saving || total <= 0) return false;
    if (_method == PaymentMethod.efectivo) return _received >= total;
    return true;
  }

  void _addDenomination(int value) {
    final next = _received + value;
    _amountReceivedController.text =
        next == next.roundToDouble() ? next.toStringAsFixed(0) : next.toStringAsFixed(2);
  }

  // --- Confirmar venta -----------------------------------------------------

  Future<void> _confirmSale(CartProvider cart) async {
    if (_saving) return;
    setState(() => _saving = true);

    final total = cart.total;
    final totalCost = cart.totalCost;
    final saleId = _db.generateSaleId();
    final isCash = _method == PaymentMethod.efectivo;

    final sale = Sale(
      id: saleId,
      date: DateTime.now(),
      total: total,
      totalCost: totalCost,
      paymentMethod: _method,
      amountReceived: isCash ? _received : null,
      change: isCash ? _changeFor(total) : null,
      sellerId: _activeSellerId,
    );

    final items = cart.items
        .map(
          (item) => SaleItem(
            saleId: saleId,
            productId: item.product.id!,
            productName: item.product.name,
            unitPrice: item.product.salePrice,
            unitCost: item.product.purchasePrice,
            quantity: item.quantity,
            subtotal: item.subtotal,
          ),
        )
        .toList();

    // 1-2. Guarda la venta + líneas y descuenta stock (transacción única).
    await _db.insertSaleWithItems(sale, items);

    // 3. Intenta imprimir el ticket (Parte 8). Si falla, la venta ya quedó
    // guardada: no bloqueamos el flujo, solo avisamos y ofrecemos reintentar.
    var printResult = await printReceipt(sale, items);

    if (!mounted) return;

    // 4. Vacía el carrito. Volvemos a la pantalla principal recién cuando
    // el vendedor cierra este diálogo (para darle tiempo a reintentar la
    // impresión si hizo falta).
    cart.clear();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool retrying = false;

          Future<void> retryPrint() async {
            setDialogState(() => retrying = true);
            final result = await printReceipt(sale, items);
            printResult = result;
            setDialogState(() => retrying = false);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success),
                SizedBox(width: 10),
                Text('Venta registrada'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Venta #$saleId', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Total: ${formatCurrency(total)}'),
                if (!printResult.isSuccess) ...[
                  const SizedBox(height: 12),
                  Text(
                    printResult.message,
                    style: const TextStyle(color: AppColors.warning, fontSize: 13),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.print, size: 16, color: AppColors.success),
                      SizedBox(width: 6),
                      Text('Ticket impreso', style: TextStyle(color: AppColors.success, fontSize: 13)),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              if (!printResult.isSuccess)
                TextButton(
                  onPressed: retrying ? null : retryPrint,
                  child: retrying
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reintentar impresión'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      ),
    );

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final total = cart.total;

    return Scaffold(
      appBar: AppBar(title: const Text('Revisar Orden')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                Text('${cart.totalQuantity} artículos', style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 12),
                for (final item in cart.items) _OrderLine(item: item),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                    Text(
                      formatCurrency(total),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text('Método de Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                _buildPaymentMethodRow(),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_method),
                    child: _buildMethodBody(total),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ElevatedButton(
                onPressed: _canConfirm(total) ? () => _confirmSale(cart) : null,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirmar Venta'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Selector de método de pago -----------------------------------------

  Widget _buildPaymentMethodRow() {
    return Row(
      children: [
        Expanded(
          child: _PaymentMethodCard(
            label: 'Efectivo',
            icon: Icons.payments_outlined,
            color: AppColors.success,
            selected: _method == PaymentMethod.efectivo,
            onTap: () => setState(() => _method = PaymentMethod.efectivo),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PaymentMethodCard(
            label: 'Yape',
            icon: Icons.qr_code_2,
            color: const Color(0xFF6E2A8E),
            selected: _method == PaymentMethod.yape,
            onTap: () => setState(() => _method = PaymentMethod.yape),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PaymentMethodCard(
            label: 'Plin',
            icon: Icons.smartphone,
            color: const Color(0xFF00AEEF),
            selected: _method == PaymentMethod.plin,
            onTap: () => setState(() => _method = PaymentMethod.plin),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PaymentMethodCard(
            label: 'Tarjeta',
            icon: Icons.credit_card,
            color: Colors.blueGrey,
            selected: _method == PaymentMethod.tarjeta,
            onTap: () => setState(() => _method = PaymentMethod.tarjeta),
          ),
        ),
      ],
    );
  }

  // --- Cuerpo según método seleccionado ------------------------------------

  Widget _buildMethodBody(double total) {
    switch (_method) {
      case PaymentMethod.efectivo:
        return _buildCashSection(total);
      case PaymentMethod.yape:
        return _buildYapeSection();
      case PaymentMethod.plin:
      case PaymentMethod.tarjeta:
        return _buildSimpleRegisteredSection();
    }
  }

  Widget _buildCashSection(double total) {
    final change = _changeFor(total);
    final isNegative = change < 0;
    final boxColor = isNegative ? AppColors.danger : AppColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _amountReceivedController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monto Recibido',
            prefixText: 'S/ ',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in _denominations)
              OutlinedButton(
                onPressed: () => _addDenomination(d),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('S/$d'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: boxColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: boxColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vuelto',
                style: TextStyle(fontWeight: FontWeight.w600, color: boxColor),
              ),
              Text(
                formatCurrency(change),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: boxColor),
              ),
            ],
          ),
        ),
        if (isNegative) ...[
          const SizedBox(height: 6),
          const Text(
            'El monto recibido es menor al total. Completa el monto para continuar.',
            style: TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildYapeSection() {
    if (_loadingSettings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_yapeQrPath == null || _yapeQrPath!.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning),
        ),
        child: const Row(
          children: [
            Icon(Icons.qr_code_2, color: AppColors.warning),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Todavía no configuraste tu QR de Yape. Ve a Ajustes > Métodos de Pago para subirlo.',
                style: TextStyle(color: AppColors.warning, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        const Text('Escanea para pagar', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_yapeQrPath!), height: 220, fit: BoxFit.contain),
        ),
      ],
    );
  }

  Widget _buildSimpleRegisteredSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.black45),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este método queda registrado en la venta. El cobro se procesa por fuera de la app.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Widgets auxiliares
// ===========================================================================

class _OrderLine extends StatelessWidget {
  final CartItem item;
  const _OrderLine({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('x${item.quantity}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Text(formatCurrency(item.subtotal), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.black12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? AppColors.primary : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
