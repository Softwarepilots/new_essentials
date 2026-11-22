import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'photo_download_io.dart'
    if (dart.library.js_interop) 'photo_download_web.dart' as platform;

/// Saves site photos for the admin: to the phone's gallery (album
/// "Essential Homes") on Android/iOS, or to Downloads in the browser.
class PhotoDownload {
  static const album = 'Essential Homes';

  /// Downloads [url] and saves it as [name] (no extension needed).
  /// Throws with a readable message on failure.
  static Future<void> save(String url, String name) async {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception('Could not download the photo (${response.statusCode})');
    }
    await platform.savePhotoBytes(response.bodyBytes, _fileName(name, url), album);
  }

  /// Saves several photos one after another. Returns how many were saved;
  /// [onProgress] gets (done, total) after each one.
  static Future<int> saveAll(
    List<({String url, String name})> photos, {
    void Function(int done, int total)? onProgress,
  }) async {
    var saved = 0;
    for (var i = 0; i < photos.length; i++) {
      try {
        await save(photos[i].url, photos[i].name);
        saved++;
      } catch (e) {
        debugPrint('[PHOTO DOWNLOAD] ${photos[i].url}: $e');
      }
      onProgress?.call(i + 1, photos.length);
    }
    return saved;
  }

  /// "Sudesh house 2026-11-22 morning" + ".jpg" — safe for every platform.
  static String _fileName(String name, String url) {
    final clean = name.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final ext = RegExp(r'\.(jpe?g|png|webp|heic)$', caseSensitive: false)
            .firstMatch(Uri.parse(url).path)
            ?.group(0) ??
        '.jpg';
    return '${clean.isEmpty ? 'site_photo' : clean}$ext';
  }
}
