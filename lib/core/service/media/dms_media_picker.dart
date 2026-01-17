import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum DmsMediaSource { gallery, camera, file }

class DmsPickedImage {
  final Uint8List bytes;
  final String name;
  const DmsPickedImage({required this.bytes, required this.name});
}

class DmsMediaPicker {
  static final ImagePicker _picker = ImagePicker();

  static Future<DmsMediaSource?> pickSourceDialog(
      BuildContext context, {
        bool allowCamera = true,
      }) async {
    return showModalBottomSheet<DmsMediaSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galleria / Foto'),
              onTap: () => Navigator.pop(ctx, DmsMediaSource.gallery),
            ),
            if (allowCamera && !kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Fotocamera'),
                onTap: () => Navigator.pop(ctx, DmsMediaSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('File (cloud: Google Foto, Amazon Foto, Drive, ecc.)'),
              subtitle: const Text('Apre il selettore documenti del sistema'),
              onTap: () => Navigator.pop(ctx, DmsMediaSource.file),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Annulla'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  static Future<DmsPickedImage?> pickImage(
      BuildContext context, {
        bool allowCamera = true,
      }) async {
    final src = await pickSourceDialog(context, allowCamera: allowCamera);
    if (src == null) return null;

    if (src == DmsMediaSource.file) {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return null;

      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) return null;

      return DmsPickedImage(bytes: bytes, name: f.name);
    }

    final x = await _picker.pickImage(
      source: src == DmsMediaSource.camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (x == null) return null;

    final bytes = await x.readAsBytes();
    if (bytes.isEmpty) return null;

    return DmsPickedImage(bytes: bytes, name: x.name);
  }
}
