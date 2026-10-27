import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/contact_actions.dart';
import '../services/guest_api.dart';

const _navy = Color(0xFF0D1B2A);
const _green = Color(0xFF10B981);

/// WhatsApp-Business-style catalogue grid shown after check-in. Items are
/// managed by the admin in the staff app. Renders nothing when the catalogue
/// is empty or can't be loaded, so check-in never looks broken because of it.
class CatalogueSection extends StatefulWidget {
  /// Used to pre-fill WhatsApp enquiries about an item.
  final String guestName;
  final String refNumber;

  const CatalogueSection({
    super.key,
    required this.guestName,
    required this.refNumber,
  });

  @override
  State<CatalogueSection> createState() => _CatalogueSectionState();
}

class _CatalogueSectionState extends State<CatalogueSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = GuestApi.fetchCatalogue();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          debugPrint('Catalogue load error: ${snapshot.error}');
          return const SizedBox.shrink();
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(7.r),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(Icons.storefront_rounded, color: _navy, size: 18.sp),
                ),
                SizedBox(width: 10.w),
                Flexible(
                  child: Text(
                    'Our Catalogue',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4.h),
            Text(
              '${items.length} item${items.length == 1 ? '' : 's'} · tap to view details',
              style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade500),
            ),
            SizedBox(height: 14.h),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12.w,
                mainAxisSpacing: 12.h,
                childAspectRatio: 0.74,
              ),
              itemBuilder: (context, i) => _CatalogueCard(
                item: items[i],
                guestName: widget.guestName,
                refNumber: widget.refNumber,
              ),
            ),
            SizedBox(height: 24.h),
          ],
        );
      },
    );
  }
}

class _CatalogueCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String guestName;
  final String refNumber;
  const _CatalogueCard({
    required this.item,
    required this.guestName,
    required this.refNumber,
  });

  @override
  Widget build(BuildContext context) {
    final price = item['price'] as num?;
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: () => _showDetails(context, item, guestName, refNumber),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CatalogueImage(url: item['image_url'] as String?),
                    if (_images(item).length > 1)
                      Positioned(
                        top: 6.h,
                        right: 6.w,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library_rounded,
                                  size: 11.sp, color: Colors.white),
                              SizedBox(width: 3.w),
                              Text(
                                '${_images(item).length}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 10.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                      height: 1.25,
                    ),
                  ),
                  if (price != null) ...[
                    SizedBox(height: 4.h),
                    Text(
                      formatRupees(price),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                        color: _green,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogueImage extends StatelessWidget {
  final String? url;
  const _CatalogueImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFFE8EDF3),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade400, size: 36.sp),
    );
    if (url == null) return placeholder;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

void _showDetails(
  BuildContext context,
  Map<String, dynamic> item,
  String guestName,
  String refNumber,
) {
  final price = item['price'] as num?;
  final description = (item['description'] as String?) ?? '';
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: [
          Center(
            child: Container(
              margin: EdgeInsets.symmetric(vertical: 10.h),
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4.r),
              ),
            ),
          ),
          if (_images(item).isNotEmpty)
            _PhotoGallery(urls: _images(item)),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 32.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? '',
                  style: TextStyle(
                    fontSize: 19.sp,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                if (price != null) ...[
                  SizedBox(height: 6.h),
                  Text(
                    formatRupees(price),
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w800,
                      color: _green,
                    ),
                  ),
                ],
                if (description.isNotEmpty) ...[
                  SizedBox(height: 14.h),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13.5.sp,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ],
                if (ContactActions.canWhatsApp || ContactActions.canCall) ...[
                  SizedBox(height: 22.h),
                  _EnquiryButtons(
                    message: 'Hi, I\'m $guestName (visitor ref $refNumber). '
                        'I\'m interested in "${item['name']}"'
                        '${price != null ? ' (${formatRupees(price)})' : ''}. '
                        'Could you share more details?',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// "WhatsApp" / "Call" enquiry buttons; each shows only if its number is set
/// in BusinessInfo.
class _EnquiryButtons extends StatelessWidget {
  final String message;
  const _EnquiryButtons({required this.message});

  Future<void> _run(BuildContext context, Future<bool> Function() action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await action()) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open the app on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r));
    final buttons = <Widget>[
      if (ContactActions.canWhatsApp)
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _run(context, () => ContactActions.whatsApp(message)),
            icon: Icon(Icons.chat_rounded, size: 18.sp),
            label: const Text('WhatsApp'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              minimumSize: Size.fromHeight(48.h),
              shape: shape,
            ),
          ),
        ),
      if (ContactActions.canCall)
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _run(context, ContactActions.call),
            icon: Icon(Icons.call_rounded, size: 18.sp),
            label: const Text('Call'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              minimumSize: Size.fromHeight(48.h),
              side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.4),
              shape: shape,
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interested? Ask us about this',
          style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600),
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) SizedBox(width: 10.w),
              buttons[i],
            ],
          ],
        ),
      ],
    );
  }
}

/// All photos of an item (first = cover); falls back to the single cover URL.
List<String> _images(Map<String, dynamic> item) {
  final images = item['images'];
  if (images is List && images.isNotEmpty) return images.cast<String>();
  final cover = item['image_url'] as String?;
  return cover == null ? const [] : [cover];
}

/// Swipeable photos with page dots, for the item details sheet.
class _PhotoGallery extends StatefulWidget {
  final List<String> urls;
  const _PhotoGallery({required this.urls});

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _CatalogueImage(url: urls[i]),
          ),
          if (urls.length > 1) ...[
            Positioned(
              left: 0,
              right: 0,
              bottom: 10.h,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(urls.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.symmetric(horizontal: 3.w),
                    width: active ? 18.w : 7.w,
                    height: 7.w,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  );
                }),
              ),
            ),
            Positioned(
              top: 10.h,
              right: 10.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  '${_page + 1}/${urls.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
