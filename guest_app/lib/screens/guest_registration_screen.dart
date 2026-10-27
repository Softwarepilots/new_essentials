import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/business_info.dart';
import '../services/contact_actions.dart';
import '../services/guest_api.dart';
import '../widgets/catalogue_section.dart';

// Design tokens
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _navy = Color(0xFF0D1B2A);
const _navyMid = Color(0xFF1B3A5C);
const _gold = Color(0xFFF59E0B);
const _green = Color(0xFF10B981);
const _surface = Color(0xFFF5F6FA);
const _line = Color(0xFFE2E8F0);

class GuestRegistrationScreen extends StatefulWidget {
  const GuestRegistrationScreen({super.key});

  @override
  State<GuestRegistrationScreen> createState() =>
      _GuestRegistrationScreenState();
}

class _GuestRegistrationScreenState extends State<GuestRegistrationScreen>
    with SingleTickerProviderStateMixin {
  // "Remember me" storage — on this device only
  static const _kRememberName = 'guest_remember_name';
  static const _kRememberPhone = 'guest_remember_phone';

  static const _purposes = [
    (label: 'Site visit', icon: Icons.apartment_rounded),
    (label: 'Meeting', icon: Icons.groups_rounded),
    (label: 'Enquiry', icon: Icons.help_outline_rounded),
    (label: 'Delivery', icon: Icons.local_shipping_outlined),
    (label: 'Other', icon: Icons.more_horiz_rounded),
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otherPurposeCtrl = TextEditingController();

  String? _purpose;
  bool _rememberMe = false;
  String? _rememberedName; // shows the "Welcome back" card

  bool _isSubmitting = false;
  bool _isSubmitted = false;
  String _refNumber = '';
  DateTime? _checkedInAt;

  late final AnimationController _successCtrl;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loadRemembered();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _otherPurposeCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  // ── Remember me ──────────────────────────────────────────────────
  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kRememberName);
    final phone = prefs.getString(_kRememberPhone);
    if (name == null || phone == null || !mounted) return;
    setState(() {
      _nameCtrl.text = name;
      _phoneCtrl.text = phone;
      _rememberMe = true;
      _rememberedName = name;
    });
  }

  Future<void> _saveRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_kRememberName, _nameCtrl.text.trim());
      await prefs.setString(_kRememberPhone, _phoneCtrl.text.trim());
    } else {
      await prefs.remove(_kRememberName);
      await prefs.remove(_kRememberPhone);
    }
  }

  Future<void> _forgetMe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRememberName);
    await prefs.remove(_kRememberPhone);
    if (!mounted) return;
    setState(() {
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _rememberMe = false;
      _rememberedName = null;
    });
  }

  // ── Check-in ─────────────────────────────────────────────────────
  String _generateRef() => 'GV${1000 + Random().nextInt(9000)}';

  String get _purposeText {
    if (_purpose == null) return '';
    if (_purpose == 'Other') {
      final other = _otherPurposeCtrl.text.trim();
      return other.isEmpty ? 'Other' : other;
    }
    return _purpose!;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final ref = _generateRef();
    try {
      await GuestApi.checkIn(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        purpose: _purposeText,
        ref: ref,
      );
      await _saveRemembered();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _isSubmitting = false;
        _isSubmitted = true;
        _refNumber = ref;
        _checkedInAt = DateTime.now();
      });
      _successCtrl.forward(from: 0);
    } catch (e) {
      debugPrint('Guest submit error: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB91C1C),
          content: const Text(
            'Could not check in. Please check your connection and try again.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _submit,
          ),
        ),
      );
    }
  }

  void _done() {
    setState(() {
      _isSubmitted = false;
      _purpose = null;
      _otherPurposeCtrl.clear();
      if (!_rememberMe) {
        _nameCtrl.clear();
        _phoneCtrl.clear();
        _rememberedName = null;
      } else {
        _rememberedName = _nameCtrl.text.trim();
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _surface,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: _isSubmitted
                ? _buildPostCheckin(key: const ValueKey('done'))
                : _buildCheckinForm(key: const ValueKey('form')),
          ),
        ),
      ),
    );
  }

  // ── Before check-in ──────────────────────────────────────────────
  Widget _buildCheckinForm({Key? key}) {
    return ListView(
      key: key,
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
      children: [
        _buildBrandBar(),
        SizedBox(height: 26.h),
        Text(
          _greeting(),
          style: TextStyle(fontSize: 14.sp, color: _muted, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 4.h),
        Text(
          'Welcome to\nEssential Homes',
          style: TextStyle(
            fontSize: 28.sp,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Check in in under 30 seconds — our team will be notified right away.',
          style: TextStyle(fontSize: 13.sp, color: _muted, height: 1.4),
        ),
        SizedBox(height: 22.h),
        if (_rememberedName != null) ...[
          _buildWelcomeBack(),
          SizedBox(height: 14.h),
        ],
        _buildFormCard(),
        SizedBox(height: 16.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 13.sp, color: _muted),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                'Your details are shared only with Essential Homes staff.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.sp, color: _muted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning 👋';
    if (hour < 17) return 'Good afternoon 👋';
    return 'Good evening 👋';
  }

  Widget _buildBrandBar() {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(6.r),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(color: _navy.withValues(alpha: 0.08), blurRadius: 10.r),
            ],
          ),
          child: Image.asset(
            'assets/images/essential_homes_logo.png',
            height: 30.h,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                BusinessInfo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: _ink),
              ),
              Text(
                'Visitor check-in',
                style: TextStyle(fontSize: 11.sp, color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeBack() {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 6.w, 12.h),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18.r,
            backgroundColor: _gold.withValues(alpha: 0.25),
            child: Text(
              _rememberedName!.isNotEmpty ? _rememberedName![0].toUpperCase() : '?',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF92400E),
                fontSize: 15.sp,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, ${_rememberedName!.split(' ').first}!',
                  style: TextStyle(fontWeight: FontWeight.w700, color: _ink, fontSize: 13.5.sp),
                ),
                Text(
                  'Your details are filled in — just pick a purpose.',
                  style: TextStyle(fontSize: 11.5.sp, color: _muted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _forgetMe,
            child: Text('Not you?', style: TextStyle(fontSize: 12.sp)),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 24.r,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fieldLabel('Full name'),
            _buildField(
              controller: _nameCtrl,
              hint: 'Enter your full name',
              icon: Icons.person_outline_rounded,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Please enter your name' : null,
            ),
            SizedBox(height: 16.h),
            _fieldLabel('Mobile number'),
            _buildField(
              controller: _phoneCtrl,
              hint: '10-digit mobile number',
              icon: Icons.phone_iphone_rounded,
              prefixText: '+91  ',
              keyboardType: TextInputType.phone,
              maxLength: 10,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              formatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final digits = (v ?? '').trim();
                if (digits.isEmpty) return 'Please enter your mobile number';
                if (digits.length != 10 || !RegExp(r'^[6-9]').hasMatch(digits)) {
                  return 'Enter a valid 10-digit mobile number';
                }
                return null;
              },
            ),
            SizedBox(height: 18.h),
            _fieldLabel('Purpose of visit'),
            _buildPurposeChips(),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _purpose == 'Other'
                  ? Padding(
                      padding: EdgeInsets.only(top: 12.h),
                      child: _buildField(
                        controller: _otherPurposeCtrl,
                        hint: 'Tell us briefly why you\'re visiting',
                        icon: Icons.edit_note_rounded,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 120,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            SizedBox(height: 10.h),
            _buildRememberMe(),
            SizedBox(height: 14.h),
            _buildCheckInButton(),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: EdgeInsets.only(bottom: 8.h, left: 2.w),
        child: Text(
          text,
          style: TextStyle(fontSize: 12.5.sp, fontWeight: FontWeight.w600, color: _ink),
        ),
      );

  Widget _buildPurposeChips() {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (final p in _purposes)
          ChoiceChip(
            selected: _purpose == p.label,
            onSelected: (selected) => setState(() => _purpose = selected ? p.label : null),
            showCheckmark: false,
            avatar: Icon(
              p.icon,
              size: 16.sp,
              color: _purpose == p.label ? Colors.white : _navyMid,
            ),
            label: Text(p.label),
            labelStyle: TextStyle(
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w600,
              color: _purpose == p.label ? Colors.white : _ink,
            ),
            selectedColor: _navy,
            backgroundColor: _surface,
            side: BorderSide(color: _purpose == p.label ? _navy : _line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
          ),
      ],
    );
  }

  Widget _buildRememberMe() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: () => setState(() => _rememberMe = !_rememberMe),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: Row(
            children: [
              SizedBox(
                height: 24.h,
                child: Switch.adaptive(
                  value: _rememberMe,
                  activeTrackColor: _navy,
                  onChanged: (v) => setState(() => _rememberMe = v),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Remember my details on this phone',
                  style: TextStyle(fontSize: 12.5.sp, color: _ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInButton() {
    return SizedBox(
      height: 54.h,
      child: FilledButton(
        onPressed: _isSubmitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: _navy,
          disabledBackgroundColor: _navy.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        ),
        child: _isSubmitting
            ? SizedBox(
                width: 22.r,
                height: 22.r,
                child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Check in',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Icon(Icons.arrow_forward_rounded, size: 20.sp, color: Colors.white),
                ],
              ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? prefixText,
    int? maxLength,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    OutlineInputBorder border(Color color, [double width = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: formatters,
      maxLength: maxLength,
      autofillHints: autofillHints,
      validator: validator,
      textInputAction: TextInputAction.next,
      style: TextStyle(fontSize: 14.5.sp, color: _ink, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: const Color(0xFF94A3B8), fontSize: 13.5.sp),
        prefixIcon: Icon(icon, color: _muted, size: 20.sp),
        prefixText: prefixText,
        prefixStyle: TextStyle(fontSize: 14.5.sp, color: _ink, fontWeight: FontWeight.w600),
        counterText: '',
        filled: true,
        fillColor: _surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        focusedBorder: border(_navy, 1.6),
        errorBorder: border(const Color(0xFFDC2626)),
        focusedErrorBorder: border(const Color(0xFFDC2626), 1.6),
        errorStyle: TextStyle(fontSize: 11.5.sp),
      ),
    );
  }

  // ── After check-in ───────────────────────────────────────────────
  Widget _buildPostCheckin({Key? key}) {
    final at = _checkedInAt ?? DateTime.now();
    final time = TimeOfDay.fromDateTime(at).format(context);
    final date = '${at.day.toString().padLeft(2, '0')}/'
        '${at.month.toString().padLeft(2, '0')}/${at.year}';

    return ListView(
      key: key,
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
      children: [
        _buildBrandBar(),
        SizedBox(height: 20.h),
        _buildSuccessCard(time, date),
        SizedBox(height: 14.h),
        _buildVisitSummary(time, date),
        SizedBox(height: 26.h),
        CatalogueSection(guestName: _nameCtrl.text.trim(), refNumber: _refNumber),
        if (BusinessInfo.hasContactDetails) ...[
          _buildContactCard(),
          SizedBox(height: 22.h),
        ],
        SizedBox(
          height: 52.h,
          child: OutlinedButton.icon(
            onPressed: _done,
            icon: Icon(Icons.check_rounded, size: 18.sp),
            label: Text('Done', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _line, width: 1.4),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessCard(String time, String date) {
    final pop = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 20.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, _navyMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.25),
            blurRadius: 24.r,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: pop,
            child: Container(
              width: 64.r,
              height: 64.r,
              decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: Colors.white, size: 38.sp),
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            "You're checked in, ${_nameCtrl.text.trim().split(' ').first}!",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Our team has been notified and will be with you shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12.5.sp, height: 1.4),
          ),
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'VISITOR REF',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 10.sp,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 10.w),
                Text(
                  _refNumber,
                  style: TextStyle(
                    color: _gold,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitSummary(String time, String date) {
    final items = [
      (Icons.schedule_rounded, 'Checked in', '$time · $date'),
      (Icons.phone_iphone_rounded, 'Mobile', '+91 ${_phoneCtrl.text.trim()}'),
      if (_purposeText.isNotEmpty) (Icons.flag_outlined, 'Purpose', _purposeText),
    ];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: _line),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 11.h),
              child: Row(
                children: [
                  Icon(items[i].$1, size: 18.sp, color: _muted),
                  SizedBox(width: 12.w),
                  Text(items[i].$2, style: TextStyle(fontSize: 12.5.sp, color: _muted)),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      items[i].$3,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: _ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    final rows = <Widget>[
      if (BusinessInfo.phoneNumber.isNotEmpty)
        _contactRow(Icons.call_outlined, BusinessInfo.phoneNumber, ContactActions.call),
      if (BusinessInfo.whatsAppNumber.isNotEmpty)
        _contactRow(
          Icons.chat_outlined,
          'Chat on WhatsApp',
          () => ContactActions.whatsApp(
            'Hi, I\'m ${_nameCtrl.text.trim()} (visitor ref $_refNumber).',
          ),
        ),
      if (BusinessInfo.email.isNotEmpty)
        _contactRow(Icons.mail_outline_rounded, BusinessInfo.email,
            () => ContactActions.email(subject: 'Visitor $_refNumber')),
      if (BusinessInfo.address.isNotEmpty)
        _contactRow(Icons.location_on_outlined, BusinessInfo.address, null),
      if (BusinessInfo.officeHours.isNotEmpty)
        _contactRow(Icons.schedule_outlined, BusinessInfo.officeHours, null),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get in touch',
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800, color: _ink),
          ),
          SizedBox(height: 6.h),
          ...rows,
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String text, Future<bool> Function()? onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10.r),
      onTap: onTap == null ? null : () => onTap(),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.r),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, size: 18.sp, color: _navyMid),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13.sp, color: _ink)),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: _muted, size: 20.sp),
          ],
        ),
      ),
    );
  }
}
