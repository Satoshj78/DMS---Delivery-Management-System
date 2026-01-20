// lib/core/service/media/dms_image_upload_service.dart
// Service: selezione, compressione e upload immagini profilo/cover (Storage + Users)

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class DmsImageUploadService {
  static const int _profileMaxBytes = 200 * 1024; // 200 KB
  static const int _coverMaxBytes = 300 * 1024; // 300 KB

  static const int _profileMaxSide = 768; // lato lungo max (profilo)
  static const int _coverMaxSide = 1600; // lato lungo max (cover)

  static const int _startQuality = 88;
  static const int _minQuality = 55;

  /// Scegli sorgente (camera/galleria)
  static Future<ImageSource?> pickSourceDialog(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galleria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Fotocamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  /// Upload foto profilo
  static Future<void> uploadProfilePhoto({
    required BuildContext context,
    required String leagueId,
    required String uid,
  }) async {
    final src = await pickSourceDialog(context);
    if (src == null) return;

    final picker = ImagePicker();
    final x = await picker.pickImage(source: src);
    if (x == null) return;

    await _runWithProgressDialog(
      context: context,
      title: 'Aggiornamento foto profilo',
      job: (setProgress) async {
        setProgress(0.02, 'Lettura immagine...');
        final inputBytes = await x.readAsBytes();
        if (inputBytes.isEmpty) throw Exception('Immagine vuota.');

        setProgress(0.10, 'Ridimensionamento/Compressione...');
        final resized = await _compressToTarget(
          inputBytes,
          maxBytes: _profileMaxBytes,
          maxSide: _profileMaxSide,
          setProgress: (p, msg) {
            final v = 0.10 + (0.60 * p); // 10% -> 70%
            setProgress(v, msg);
          },
        );

        setProgress(0.70, 'Upload su cloud...');
        final url = await _uploadBytes(
          leagueId: leagueId,
          uid: uid,
          bytes: resized,
          storageFileName: 'profile.jpg',
          setProgress: (uploadP) {
            final v = 0.70 + (0.25 * uploadP);
            setProgress(v, 'Upload su cloud... ${(uploadP * 100).toStringAsFixed(0)}%');
          },
        );

        setProgress(0.96, 'Aggiornamento Firestore...');
        await _updateFirestorePhoto(
          leagueId: leagueId,
          uid: uid,
          fieldUrlUserDot: 'profile.photoUrl',
          fieldVUserDot: 'profile.photoV',
          fieldUrlMember: 'photoUrl',
          fieldVMember: 'photoV',
          url: url,
        );

        setProgress(1.0, 'Completato ✅');
      },
    );
  }

  /// Upload copertina
  static Future<void> uploadCoverPhoto({
    required BuildContext context,
    required String leagueId,
    required String uid,
  }) async {
    final src = await pickSourceDialog(context);
    if (src == null) return;

    final picker = ImagePicker();
    final x = await picker.pickImage(source: src);
    if (x == null) return;

    await _runWithProgressDialog(
      context: context,
      title: 'Aggiornamento copertina',
      job: (setProgress) async {
        setProgress(0.02, 'Lettura immagine...');
        final inputBytes = await x.readAsBytes();
        if (inputBytes.isEmpty) throw Exception('Immagine vuota.');

        setProgress(0.10, 'Ridimensionamento/Compressione...');
        final resized = await _compressToTarget(
          inputBytes,
          maxBytes: _coverMaxBytes,
          maxSide: _coverMaxSide,
          setProgress: (p, msg) {
            final v = 0.10 + (0.60 * p); // 10% -> 70%
            setProgress(v, msg);
          },
        );

        setProgress(0.70, 'Upload su cloud...');
        final url = await _uploadBytes(
          leagueId: leagueId,
          uid: uid,
          bytes: resized,
          storageFileName: 'cover.jpg',
          setProgress: (uploadP) {
            final v = 0.70 + (0.25 * uploadP);
            setProgress(v, 'Upload su cloud... ${(uploadP * 100).toStringAsFixed(0)}%');
          },
        );

        setProgress(0.96, 'Aggiornamento Firestore...');
        await _updateFirestorePhoto(
          leagueId: leagueId,
          uid: uid,
          fieldUrlUserDot: 'profile.coverUrl',
          fieldVUserDot: 'profile.coverV',
          fieldUrlMember: 'coverUrl',
          fieldVMember: 'coverV',
          url: url,
        );

        setProgress(1.0, 'Completato ✅');
      },
    );
  }

  // -----------------------------
  // Internals
  // -----------------------------

  static Future<void> _runWithProgressDialog({
    required BuildContext context,
    required String title,
    required Future<void> Function(void Function(double, String)) job,
  }) async {
    final progress = ValueNotifier<double>(0);
    final message = ValueNotifier<String>('...');
    Object? error;

    void setProgress(double v, String msg) {
      progress.value = v.clamp(0.0, 1.0);
      message.value = msg;
    }

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false, // blocca il back
        onPopInvoked: (didPop) {
          // non fare nulla: back disabilitato
        },
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, p, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: p == 0 ? null : p),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: message,
                    builder: (_, m, __) => Text(m),
                  ),
                  const SizedBox(height: 6),
                  Text('${(p * 100).toStringAsFixed(0)}%'),
                ],
              );
            },
          ),
        ),
      ),
    ));


    try {
      await job(setProgress);
    } catch (e) {
      error = e;
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
      message.dispose();
    }

    if (error != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $error')),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Immagine aggiornata ✅')),
      );
    }
  }

  static Future<Uint8List> _compressToTarget(
      Uint8List input, {
        required int maxBytes,
        required int maxSide,
        required void Function(double p, String msg) setProgress,
      }) async {
    setProgress(0.05, 'Decodifica immagine...');
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw Exception('Immagine non valida / impossibile decodificare.');
    }

    var im = img.bakeOrientation(decoded);

    int currentMaxSide = maxSide;

    setProgress(0.15, 'Ridimensionamento...');
    im = _resizeIfNeeded(im, currentMaxSide);

    int quality = _startQuality;
    int tries = 0;

    while (true) {
      tries++;

      setProgress(
        (tries / 12).clamp(0.15, 0.85),
        'Compressione... (tentativo $tries)',
      );

      final out = Uint8List.fromList(img.encodeJpg(im, quality: quality));

      if (out.lengthInBytes <= maxBytes) {
        setProgress(1.0, 'Ok: ${(out.lengthInBytes / 1024).toStringAsFixed(0)} KB');
        return out;
      }

      if (quality > _minQuality) {
        quality = (quality - 8).clamp(_minQuality, 100);
        continue;
      }

      final nextSide = (currentMaxSide * 0.85).round();
      if (nextSide < 320) {
        throw Exception(
          'Impossibile raggiungere ${(maxBytes / 1024).toStringAsFixed(0)}KB senza degradare troppo. '
              'Prova una foto meno “pesante”.',
        );
      }

      currentMaxSide = nextSide;
      im = _resizeIfNeeded(im, currentMaxSide);
      quality = _startQuality;
    }
  }

  static img.Image _resizeIfNeeded(img.Image im, int maxSide) {
    final w = im.width;
    final h = im.height;

    if (w <= maxSide && h <= maxSide) return im;

    if (w >= h) {
      final newW = maxSide;
      final newH = (h * maxSide / w).round();
      return img.copyResize(im, width: newW, height: newH, interpolation: img.Interpolation.average);
    } else {
      final newH = maxSide;
      final newW = (w * maxSide / h).round();
      return img.copyResize(im, width: newW, height: newH, interpolation: img.Interpolation.average);
    }
  }

  static Future<String> _uploadBytes({
    required String leagueId,
    required String uid,
    required Uint8List bytes,
    required String storageFileName,
    required void Function(double p) setProgress,
  }) async {
    final storage = FirebaseStorage.instance;

    final ref = storage.ref().child('users/$uid/public/$storageFileName');

    final task = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

    task.snapshotEvents.listen((snap) {
      final total = snap.totalBytes;
      final sent = snap.bytesTransferred;
      if (total > 0) setProgress(sent / total);
    });

    await task;
    return ref.getDownloadURL();
  }

  static Future<void> _updateFirestorePhoto({
    required String leagueId,
    required String uid,
    required String fieldUrlUserDot,
    required String fieldVUserDot,
    required String fieldUrlMember,
    required String fieldVMember,
    required String url,
  }) async {
    // NOTE: per le rules attuali, il client NON scrive mai su Leagues/*/members.
    // Aggiorniamo solo Users/{uid}. La propagazione verso members/UsersPublic/sharedProfiles
    // deve essere fatta dalla Cloud Function (onUserProfileWrite).

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('Users').doc(uid);

    final isCover = fieldUrlUserDot.toLowerCase().contains('cover');
    final urlKey = isCover ? 'coverUrl' : 'photoUrl';
    final vKey = isCover ? 'coverV' : 'photoV';

    await userRef.set({
      urlKey: url,
      vKey: FieldValue.increment(1),
      'profile': {
        urlKey: url,
        vKey: FieldValue.increment(1),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
