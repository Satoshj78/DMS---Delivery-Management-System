import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class DmsImageFullscreenPage extends StatefulWidget {
  final String title;

  /// Deve tornare l’URL “raw” corrente (http/https o gs:// o path)
  final String? Function() getRawUrl;

  final bool canEdit;

  /// richiama il tuo flusso: pick -> editor -> upload -> update firestore
  final Future<void> Function()? onEdit;

  /// rimuovi immagine (firestore + ui)
  final Future<void> Function()? onRemove;

  const DmsImageFullscreenPage({
    super.key,
    required this.title,
    required this.getRawUrl,
    required this.canEdit,
    this.onEdit,
    this.onRemove,
  });

  @override
  State<DmsImageFullscreenPage> createState() => _DmsImageFullscreenPageState();
}

class _DmsImageFullscreenPageState extends State<DmsImageFullscreenPage> {
  Future<String?> _resolveToHttpUrl(String raw) async {
    final u = raw.trim();
    if (u.isEmpty) return null;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;

    try {
      if (u.startsWith('gs://')) {
        return FirebaseStorage.instance.refFromURL(u).getDownloadURL();
      }
      // path in storage
      return FirebaseStorage.instance.ref().child(u).getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _downloadBytes(String httpUrl) async {
    final res = await http.get(Uri.parse(httpUrl));
    if (res.statusCode >= 400) {
      throw Exception('Download fallito (${res.statusCode})');
    }
    return res.bodyBytes;
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _share(String httpUrl) async {
    try {
      if (kIsWeb) {
        await Share.share(httpUrl);
        return;
      }
      final bytes = await _downloadBytes(httpUrl);
      final x = XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: 'dms_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await Share.shareXFiles([x], text: widget.title);
    } catch (e) {
      _snack('Errore condivisione: $e');
    }
  }

  Future<void> _save(String httpUrl) async {
    try {
      if (kIsWeb) {
        // su web: apri in nuova scheda (poi “Salva immagine con nome…”)
        await launchUrl(Uri.parse(httpUrl), webOnlyWindowName: '_blank');
        _snack('Aperta in una nuova scheda. Salvala dal browser.');
        return;
      }

      final bytes = await _downloadBytes(httpUrl);
      final name = 'dms_${DateTime.now().millisecondsSinceEpoch}';

      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        name: name,
      );

      // il plugin può tornare map con chiavi diverse a seconda della piattaforma
      final ok = (result['isSuccess'] == true) ||
          (result['success'] == true) ||
          (result['filePath'] != null);

      _snack(ok ? 'Salvata in galleria ✅' : 'Non salvata (permessi?)');
    } catch (e) {
      _snack('Errore salvataggio: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    final raw = (widget.getRawUrl() ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Condividi',
            icon: const Icon(Icons.share),
            onPressed: raw.isEmpty
                ? null
                : () async {
              final httpUrl = await _resolveToHttpUrl(raw);
              if (httpUrl == null || httpUrl.isEmpty) return _snack('URL non valido');
              await _share(httpUrl);
            },
          ),
          IconButton(
            tooltip: 'Salva',
            icon: const Icon(Icons.download),
            onPressed: raw.isEmpty
                ? null
                : () async {
              final httpUrl = await _resolveToHttpUrl(raw);
              if (httpUrl == null || httpUrl.isEmpty) return _snack('URL non valido');
              await _save(httpUrl);
            },
          ),
          if (widget.canEdit) ...[
            IconButton(
              tooltip: 'Modifica',
              icon: const Icon(Icons.edit),
              onPressed: widget.onEdit == null
                  ? null
                  : () async {
                await widget.onEdit!.call();
                if (mounted) setState(() {}); // rilegge getRawUrl()
              },
            ),
            IconButton(
              tooltip: 'Rimuovi',
              icon: const Icon(Icons.delete_outline),
              onPressed: widget.onRemove == null
                  ? null
                  : () async {
                await widget.onRemove!.call();
                if (mounted) setState(() {});
              },
            ),
          ],
        ],
      ),
      body: Center(
        child: raw.isEmpty
            ? const Text('Nessuna immagine', style: TextStyle(color: Colors.white70))
            : FutureBuilder<String?>(
          future: _resolveToHttpUrl(raw),
          builder: (context, snap) {
            final httpUrl = (snap.data ?? '').trim();
            if (httpUrl.isEmpty) {
              return const Text('Impossibile caricare', style: TextStyle(color: Colors.white70));
            }

            return InteractiveViewer(
              minScale: 0.7,
              maxScale: 6,
              child: CachedNetworkImage(
                imageUrl: httpUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const CircularProgressIndicator(),
                errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white70, size: 80),
              ),
            );
          },
        ),
      ),
    );
  }
}
