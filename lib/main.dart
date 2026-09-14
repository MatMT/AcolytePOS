import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const AcolytePosApp());

const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');

const _surface = Color(0xFFF7F9FB);
const _primary = Color(0xFF00236F);
const _primaryContainer = Color(0xFF1E3A8A);
const _secondary = Color(0xFF904D00);
const _secondaryBright = Color(0xFFFE932C);
const _vueltoDark = Color(0xFF003120);
const _vueltoMid = Color(0xFF004A32);
const _aiGreen = Color(0xFF16A34A);

class Product {
  const Product(this.id, this.name, this.price, this.aliases);
  final String id;
  final String name;
  final double price;
  final List<String> aliases;
}

const catalog = <Product>[
  Product('pan', 'Semita de Piña', 0.40, ['pan', 'semita', 'semitas', 'pan dulce', 'panes', 'piña', 'pina']),
  Product('cafe', 'Café Caliente', 0.50, ['cafe', 'café', 'cafes', 'cafés', 'caliente']),
  Product('soda', 'Soda / Gaseosa', 0.75, ['soda', 'sodas', 'gaseosa', 'gaseosas', 'refresco']),
  Product('churro', 'Churro / Snack', 0.35, ['churro', 'churros', 'snack', 'snacks']),
  Product('agua', 'Agua', 0.50, ['agua', 'aguas']),
];

const kioskCards = <Product>[
  Product('pan', 'Semita de Piña', 0.40, ['pan', 'semita', 'semitas', 'pan dulce', 'panes', 'piña', 'pina']),
  Product('cafe', 'Café Caliente', 0.50, ['cafe', 'café', 'cafes', 'cafés', 'caliente']),
  Product('soda', 'Soda / Gaseosa', 0.75, ['soda', 'sodas', 'gaseosa', 'gaseosas', 'refresco']),
  Product('churro', 'Churro / Snack', 0.35, ['churro', 'churros', 'snack', 'snacks']),
];

class CartLine {
  CartLine(this.product, this.qty);
  final Product product;
  int qty;
  double get lineTotal => product.price * qty;
}

class ParsedOrder {
  ParsedOrder({
    required this.items,
    required this.total,
    required this.pagoCon,
    required this.vuelto,
    required this.resumen,
    this.fromAi = false,
  });
  final List<CartLine> items;
  final double total;
  final double pagoCon;
  final double vuelto;
  final String resumen;
  final bool fromAi;
}

class AcolytePosApp extends StatelessWidget {
  const AcolytePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AcolytePOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primary,
          primary: _primary,
          secondary: _secondaryBright,
          surface: _surface,
          brightness: Brightness.light,
        ),
      ),
      home: const PosScreen(),
    );
  }
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _nlController = TextEditingController();
  final _pagoController = TextEditingController();
  final Map<String, CartLine> _cart = {};
  bool _loading = false;
  String? _status;

  double get _total => _cart.values.fold(0.0, (s, l) => s + l.lineTotal);
  double get _pago =>
      double.tryParse(_pagoController.text.replaceAll(',', '.')) ?? 0;
  double get _vuelto {
    final v = _pago - _total;
    return v < 0 ? 0 : v;
  }
  int get _itemCount => _cart.values.fold(0, (s, l) => s + l.qty);
  int _qtyOf(Product p) => _cart[p.id]?.qty ?? 0;

  void _addProduct(Product p, [int qty = 1]) {
    setState(() {
      final existing = _cart[p.id];
      if (existing == null) {
        _cart[p.id] = CartLine(p, qty);
      } else {
        existing.qty += qty;
      }
      _status = null;
    });
  }

  void _setQty(Product p, int qty) {
    setState(() {
      if (qty <= 0) {
        _cart.remove(p.id);
      } else {
        _cart[p.id] = CartLine(p, qty);
      }
    });
  }

  void _setPago(double value) {
    setState(() {
      _pagoController.text = value.toStringAsFixed(2);
    });
  }

  void _clearSale() {
    setState(() {
      _cart.clear();
      _nlController.clear();
      _pagoController.clear();
      _status = 'Nueva orden lista';
    });
  }

  void _confirmSale() {
    if (_cart.isEmpty) {
      setState(() => _status = 'Agrega productos primero');
      return;
    }
    if (_pago < _total) {
      setState(() => _status = 'Pago insuficiente');
      return;
    }
    final msg =
        'Venta OK · Total \$${_total.toStringAsFixed(2)} · Vuelto \$${_vuelto.toStringAsFixed(2)}';
    _clearSale();
    setState(() => _status = msg);
  }

  Future<void> _parseNl() async {
    final text = _nlController.text.trim();
    if (text.isEmpty) {
      setState(() => _status = 'Escribe el pedido');
      return;
    }
    setState(() {
      _loading = true;
      _status = 'Procesando…';
    });
    try {
      ParsedOrder? parsed;
      if (_geminiKey.isNotEmpty) {
        parsed = await _parseWithGemini(text);
      }
      parsed ??= parseLocalOrder(text);
      _applyParsed(parsed);
    } catch (_) {
      _applyParsed(parseLocalOrder(text), fallback: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyParsed(ParsedOrder parsed, {bool fallback = false}) {
    setState(() {
      _cart
        ..clear()
        ..addEntries(parsed.items.map((l) => MapEntry(l.product.id, l)));
      if (parsed.pagoCon > 0) {
        _pagoController.text = parsed.pagoCon.toStringAsFixed(2);
      }
      final prefix = fallback
          ? 'Fallback local'
          : (parsed.fromAi ? 'IA' : 'Local');
      _status = '$prefix: ${parsed.resumen}';
    });
  }

  Future<ParsedOrder?> _parseWithGemini(String userText) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiKey',
    );
    const system = 'Eres el cajero de una tiendita parroquial. Analiza el pedido y responde UNICAMENTE JSON valido (sin markdown). '
        'Precios: Cafe Caliente 0.50, Semita de Pina/Pan 0.40, Soda/Gaseosa 0.75, Agua 0.50, Churro/Snack 0.35. '
        'Esquema: {"resumen":"...","items":[{"nombre":"Cafe Caliente","cant":1,"precio":0.50}],"total":0.0,"pago_con":0.0,"vuelto":0.0}';
    final body = {
      'contents': [
        {
          'parts': [
            {'text': '$system\n\nPedido: $userText'},
          ],
        }
      ],
      'generationConfig': {'temperature': 0.1},
    };
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('Gemini ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (raw == null) throw Exception('Empty Gemini');
    return parsedOrderFromJson(raw, fromAi: true);
  }

  @override
  void dispose() {
    _nlController.dispose();
    _pagoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildAiBar(),
                  const SizedBox(height: 16),
                  _buildCatalogHeader(),
                  const SizedBox(height: 10),
                  _buildProductGrid(),
                  const SizedBox(height: 16),
                  _buildPaymentCard(),
                  const SizedBox(height: 12),
                  _buildTenderRow(),
                  const SizedBox(height: 12),
                  _buildVueltoPanel(),
                  if (_status != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _status!,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildActions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'AcolytePOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _aiGreen,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'AI Activo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Parroquia San Juan Bosco - Kiosco Parroquial',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _secondaryBright,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _loading ? null : _parseNl,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic, size: 18),
                Text('Dictar', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _nlController,
            minLines: 1,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _parseNl(),
            decoration: InputDecoration(
              labelText: 'Asistente IA',
              hintText: '2 semitas y un café, me pagaron con uno de 5',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              suffixIcon: IconButton(
                onPressed: _loading ? null : _parseNl,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: _primary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Tocar para Sumar (+1)',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _primary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$_itemCount en carrito',
            style: const TextStyle(
              color: _primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: [
        for (final p in kioskCards)
          _ProductCard(
            product: p,
            qty: _qtyOf(p),
            onAdd: () => _addProduct(p),
            onMinus: () => _setQty(p, _qtyOf(p) - 1),
            onPlus: () => _addProduct(p),
          ),
      ],
    );
  }

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total a Cobrar',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                Text(
                  '\$${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _pagoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Pagó con',
                prefixText: '\$ ',
                filled: true,
                fillColor: _surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTenderRow() {
    final chips = <(String, VoidCallback)>[
      ('Exacto', () => _setPago(_total)),
      ('\$1', () => _setPago(1)),
      ('\$2', () => _setPago(2)),
      ('\$5', () => _setPago(5)),
      ('\$10', () => _setPago(10)),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in chips)
          ActionChip(
            label: Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: Colors.white,
            side: const BorderSide(color: _secondaryBright, width: 1.5),
            onPressed: c.$2,
          ),
      ],
    );
  }

  Widget _buildVueltoPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_vueltoDark, _vueltoMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            'Entregar Cambio / Vuelto',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '\$${_vuelto.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _confirmSale,
          child: const Text(
            'Confirmar Venta y Cobrar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _primary,
            side: const BorderSide(color: _primary, width: 1.5),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _clearSale,
          child: const Text(
            'Nueva Orden',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.qty,
    required this.onAdd,
    required this.onMinus,
    required this.onPlus,
  });

  final Product product;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: qty > 0 ? _primary : Colors.black12,
          width: qty > 0 ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: _primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${product.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _secondary,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    'Cant $qty',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: qty > 0 ? onMinus : null,
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onPlus,
                    icon: const Icon(Icons.add_circle, color: _primary, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ParsedOrder parseLocalOrder(String raw) {
  final text = raw.toLowerCase();
  final items = <CartLine>[];
  for (final p in catalog) {
    final qty = _qtyForProduct(text, p);
    if (qty > 0) items.add(CartLine(p, qty));
  }
  final pago = _extractPago(text);
  final total = items.fold(0.0, (s, l) => s + l.lineTotal);
  final vuelto =
      pago > 0 ? (pago - total).clamp(0, double.infinity).toDouble() : 0.0;
  final resumen = items.isEmpty
      ? 'No reconoci productos'
      : items.map((l) => '${l.qty}x ${l.product.name}').join(', ');
  return ParsedOrder(
    items: items,
    total: total,
    pagoCon: pago,
    vuelto: vuelto,
    resumen: resumen,
  );
}

int _qtyForProduct(String text, Product p) {
  var best = 0;
  for (final alias in p.aliases) {
    final withNum = RegExp(
      r'(?:^|\s)(?:(\d+)|un|una|unos|unas)\s+' + RegExp.escape(alias) + r'\b',
    );
    var hit = 0;
    for (final m in withNum.allMatches(text)) {
      final g = m.group(1);
      hit += g != null ? (int.tryParse(g) ?? 1) : 1;
    }
    if (hit == 0) {
      final bare = RegExp(r'\b' + RegExp.escape(alias) + r'\b');
      if (bare.hasMatch(text)) hit = 1;
    }
    if (hit > best) best = hit;
  }
  return best;
}

double _extractPago(String text) {
  final patterns = [
    RegExp(r'pag(?:aron|ue|o)?\s+con\s+(?:uno\s+de\s+)?(\d+(?:[.,]\d+)?)'),
    RegExp(r'billete\s+de\s+(\d+(?:[.,]\d+)?)'),
    RegExp(r'con\s+(?:un\s+)?(?:billete\s+de\s+)?(\d+(?:[.,]\d+)?)'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(text);
    if (m != null) {
      return double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    }
  }
  return 0;
}

ParsedOrder parsedOrderFromJson(String raw, {bool fromAi = false}) {
  var s = raw.trim();
  if (s.startsWith('```')) {
    s = s
        .replaceAll(RegExp(r'^```(?:json)?'), '')
        .replaceAll(RegExp(r'```\s*$'), '')
        .trim();
  }
  final map = jsonDecode(s) as Map<String, dynamic>;
  final items = <CartLine>[];
  final rawItems = map['items'] as List? ?? [];
  for (final it in rawItems) {
    final m = it as Map<String, dynamic>;
    final nombre = (m['nombre'] ?? '').toString().toLowerCase();
    final cant = (m['cant'] as num?)?.toInt() ?? 1;
    Product? match;
    for (final p in catalog) {
      if (p.name.toLowerCase() == nombre ||
          p.aliases.any((a) => nombre.contains(a))) {
        match = p;
        break;
      }
    }
    match ??= Product(
      'x',
      m['nombre'].toString(),
      (m['precio'] as num?)?.toDouble() ?? 0,
      const [],
    );
    if (cant > 0 && match.price > 0) {
      items.add(CartLine(match, cant));
    }
  }
  final total = (map['total'] as num?)?.toDouble() ??
      items.fold<double>(0.0, (s, l) => s + l.lineTotal);
  final pago = (map['pago_con'] as num?)?.toDouble() ?? 0.0;
  final vuelto = (map['vuelto'] as num?)?.toDouble() ??
      (pago > 0 ? (pago - total).clamp(0.0, double.infinity).toDouble() : 0.0);
  return ParsedOrder(
    items: items,
    total: total,
    pagoCon: pago,
    vuelto: vuelto,
    resumen: (map['resumen'] ?? '').toString(),
    fromAi: fromAi,
  );
}
