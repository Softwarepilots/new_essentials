import 'package:url_launcher/url_launcher.dart';

import '../config/business_info.dart';

/// Opens WhatsApp, the dialer or email for the business in [BusinessInfo].
/// Each returns false if the number/address isn't configured or nothing
/// could handle it.
class ContactActions {
  static bool get canWhatsApp => BusinessInfo.whatsAppNumber.isNotEmpty;
  static bool get canCall => BusinessInfo.phoneNumber.isNotEmpty;
  static bool get canEmail => BusinessInfo.email.isNotEmpty;

  /// wa.me works with or without the WhatsApp app (falls back to the web).
  static Future<bool> whatsApp(String message) {
    if (!canWhatsApp) return Future.value(false);
    final digits = BusinessInfo.whatsAppNumber.replaceAll(RegExp(r'\D'), '');
    return _open(Uri.https('wa.me', '/$digits', {'text': message}));
  }

  static Future<bool> call() {
    if (!canCall) return Future.value(false);
    final number = BusinessInfo.phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    return _open(Uri(scheme: 'tel', path: number));
  }

  static Future<bool> email({String? subject}) {
    if (!canEmail) return Future.value(false);
    return _open(Uri(
      scheme: 'mailto',
      path: BusinessInfo.email,
      query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
    ));
  }

  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
