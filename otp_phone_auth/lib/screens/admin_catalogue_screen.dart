import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/catalogue_service.dart';

/// Admin screen for the guest catalogue — like a WhatsApp Business catalogue.
/// Guests see the active items in the guest app after they check in.
class AdminCatalogueScreen extends StatefulWidget {
  const AdminCatalogueScreen({super.key});

  @override
  State<AdminCatalogueScreen> createState() => _AdminCatalogueScreenState();
}

class _AdminCatalogueScreenState extends State<AdminCatalogueScreen> {
  static const _navy = Color(0xFF1A1A2E);

  final _service = CatalogueService();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _service.getItems();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _openEditor([Map<String, dynamic>? item]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _CatalogueItemEditor(item: item)),
    );
    if (saved == true) _loadItems();
  }

  Future<void> _toggleActive(Map<String, dynamic> item, bool value) async {
    setState(() => item['is_active'] = value);
    try {
      await _service.setActive(item['id'], value);
    } catch (e) {
      if (!mounted) return;
      setState(() => item['is_active'] = !value);
      _showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('"${item['name']}" will be removed from the guest catalogue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteItem(item['id']);
      _showMessage('Item deleted');
      _loadItems();
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Guest Catalogue',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _navy,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _loadItems, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'No catalogue items yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
              ),
              const SizedBox(height: 6),
              Text(
                'Add projects, plots or services. Guests see them in the guest app after they check in.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadItems,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _buildItemTile(_items[i]),
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item) {
    final isActive = item['is_active'] == true;
    final price = item['price'];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openEditor(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: item['image_url'] != null
                      ? Image.network(
                          item['image_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: isActive ? 1 : 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: _navy),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        price != null ? formatRupees(price) : 'No price',
                        style: TextStyle(
                          color: price != null ? const Color(0xFF059669) : Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (!isActive)
                        const Text(
                          'Hidden from guests',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              Switch(
                value: isActive,
                activeThumbColor: const Color(0xFF059669),
                onChanged: (v) => _toggleActive(item, v),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        color: const Color(0xFFE8EAF2),
        child: const Icon(Icons.image_outlined, color: Colors.grey),
      );
}

/// ₹ with Indian digit grouping, e.g. 1250000 → ₹12,50,000
String formatRupees(num value) {
  final whole = value.truncate();
  final paise = ((value - whole) * 100).round();
  var digits = whole.abs().toString();
  var grouped = digits.length > 3 ? digits.substring(digits.length - 3) : digits;
  digits = digits.length > 3 ? digits.substring(0, digits.length - 3) : '';
  while (digits.isNotEmpty) {
    final cut = digits.length > 2 ? digits.length - 2 : 0;
    grouped = '${digits.substring(cut)},$grouped';
    digits = digits.substring(0, cut);
  }
  final sign = value < 0 ? '-' : '';
  return paise > 0
      ? '$sign₹$grouped.${paise.toString().padLeft(2, '0')}'
      : '$sign₹$grouped';
}

// ── Add / edit form ─────────────────────────────────────────────────────────

class _CatalogueItemEditor extends StatefulWidget {
  final Map<String, dynamic>? item;
  const _CatalogueItemEditor({this.item});

  @override
  State<_CatalogueItemEditor> createState() => _CatalogueItemEditorState();
}

class _CatalogueItemEditorState extends State<_CatalogueItemEditor> {
  static const _navy = Color(0xFF1A1A2E);

  final _formKey = GlobalKey<FormState>();
  final _service = CatalogueService();
  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late bool _isActive;

  static const _maxImages = 10;
  static const _maxImageBytes = 5 * 1024 * 1024;

  // Photos are shown and saved in this order: kept existing ones, then new
  // ones. The first photo is the cover.
  late final List<String> _keptImageUrls;
  final List<CatalogueImageUpload> _newImages = [];
  bool _isSaving = false;

  bool get _isEditing => widget.item != null;
  int get _imageCount => _keptImageUrls.length + _newImages.length;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?['name'] ?? '');
    _descCtrl = TextEditingController(text: item?['description'] ?? '');
    final price = item?['price'];
    _priceCtrl = TextEditingController(
      text: price == null
          ? ''
          : (price as num) == price.truncate()
              ? price.truncate().toString()
              : price.toString(),
    );
    _isActive = item?['is_active'] ?? true;
    _keptImageUrls = List<String>.from(item?['images'] ?? const []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final room = _maxImages - _imageCount;
    if (room <= 0) return;
    final picked = await _picker.pickMultiImage(
      maxWidth: 1600,
      imageQuality: 85,
      limit: room > 1 ? room : null,
    );
    if (picked.isEmpty) return;

    var skippedLarge = 0;
    final added = <CatalogueImageUpload>[];
    for (final file in picked.take(room)) {
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        skippedLarge++;
        continue;
      }
      added.add(CatalogueImageUpload(bytes, file.name));
    }
    if (!mounted) return;
    setState(() => _newImages.addAll(added));

    final problems = [
      if (picked.length > room) 'Only $_maxImages photos per item — extra ones skipped',
      if (skippedLarge > 0) '$skippedLarge photo(s) over 5 MB skipped',
    ];
    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problems.join('. ')), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _service.saveItem(
        id: widget.item?['id'],
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        price: _priceCtrl.text.trim(),
        isActive: _isActive,
        keptImageUrls: _keptImageUrls,
        newImages: _newImages,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Item' : 'Add Item',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPhotos(),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Item name *', Icons.label_outline),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('Price (₹, optional)', Icons.currency_rupee),
              validator: (v) {
                final text = (v ?? '').trim().replaceAll(',', '');
                if (text.isEmpty) return null;
                final value = double.tryParse(text);
                if (value == null) return 'Enter a number, e.g. 2500000';
                if (value < 0) return 'Price cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Description', Icons.notes),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              activeThumbColor: const Color(0xFF059669),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show to guests'),
              subtitle: const Text('Hidden items stay saved but guests won\'t see them'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing ? 'Save changes' : 'Add to catalogue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotos() {
    final tiles = <Widget>[
      for (var i = 0; i < _keptImageUrls.length; i++)
        _photoTile(
          image: Image.network(_keptImageUrls[i], fit: BoxFit.cover),
          isCover: i == 0,
          onRemove: () => setState(() => _keptImageUrls.removeAt(i)),
        ),
      for (var i = 0; i < _newImages.length; i++)
        _photoTile(
          image: Image.memory(_newImages[i].bytes, fit: BoxFit.cover),
          isCover: _keptImageUrls.isEmpty && i == 0,
          onRemove: () => setState(() => _newImages.removeAt(i)),
        ),
      if (_imageCount < _maxImages) _addPhotoTile(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Photos',
              style: TextStyle(fontWeight: FontWeight.bold, color: _navy),
            ),
            const SizedBox(width: 6),
            Text(
              '$_imageCount / $_maxImages · first photo is the cover',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => tiles[i],
          ),
        ),
      ],
    );
  }

  Widget _photoTile({
    required Widget image,
    required bool isCover,
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      width: 110,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
          if (isCover)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Cover',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPhotoTile() {
    return InkWell(
      onTap: _pickImages,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EAF2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 32, color: Colors.grey.shade600),
            const SizedBox(height: 4),
            Text('Add photos', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
