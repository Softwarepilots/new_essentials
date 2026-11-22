import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Android / iOS: save into the phone's gallery album.
Future<void> savePhotoBytes(Uint8List bytes, String fileName, String album) async {
  if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
    throw Exception('Allow photo access to save photos');
  }
  final dot = fileName.lastIndexOf('.');
  final name = dot > 0 ? fileName.substring(0, dot) : fileName;
  try {
    await Gal.putImageBytes(bytes, album: album, name: name);
  } on GalException catch (e) {
    throw Exception(e.type.message);
  }
}
