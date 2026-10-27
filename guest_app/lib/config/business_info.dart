/// Real business contact details shown to guests.
///
/// Fill these in before release. Anything left empty is simply not shown:
/// the contact card hides that row, and the catalogue's "WhatsApp" / "Call"
/// enquiry buttons only appear once [whatsAppNumber] / [phoneNumber] are set.
class BusinessInfo {
  static const name = 'Essential Homes Construction';

  /// International format, digits only, e.g. '919876543210' (91 = India).
  static const whatsAppNumber = '917708684155';

  /// As dialled, e.g. '+91 98765 43210'.
  static const phoneNumber = '+91 77086 84155';

  static const email = '';

  static const address = '';

  /// e.g. 'Mon – Sat, 9:00 AM – 6:00 PM'
  static const officeHours = '';

  static bool get hasContactDetails =>
      phoneNumber.isNotEmpty ||
      whatsAppNumber.isNotEmpty ||
      email.isNotEmpty ||
      address.isNotEmpty ||
      officeHours.isNotEmpty;
}
