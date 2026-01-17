import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class DmsImageViewerItem {
  final String label;
  final String? url;

  final bool canEdit;
  final bool canRemove;

  /// Deve aprire picker+crop+upload (nel tuo Detail già esiste)
  final Future<void> Function()? onEdit;

  /// Deve rimuovere da Firestore/Storage (nel tuo Detail già esiste)
  final Future<void> Function()? onRemove;

  const DmsImageViewerItem({
    required this.label,
    required this.url,
    required this.canEdit,
    required this.canRemove,
    this.onEdit,
    this.onRemove,
  });
}

class DmsFullScreenImagesPage extends StatefulWidget {
  final List<DmsImageViewerItem> items;
  final int initialIndex;

  const DmsFullScreenImagesPage({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<DmsFullScreenImagesPage> createState() => _DmsFullScreenImagesPageState();
}

class _DmsFullScreenImagesPageState extends State<DmsFullScreenImagesPage> {
  late int _idx;
  final TransformationController _tc = TransformationController();

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex.clamp(0, widget.items.length - 1);
  }

  DmsImageViewerItem get _cur => widget.items[_idx];

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode}');
    }
    return r.bodyBytes;
  }

  Future<void> _shareCurrent() async {
    final url = _cur.url;
    if (url == null || url.trim().isEmpty) return;

    try {
      if (kIsWeb) {
        // su web: prova Web Share, altrimenti apri in nuova scheda
        await Share.share(url);
        return;
      }

      final bytes = await _downloadBytes(url);
      final name = 'dms_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final x = XFile.fromData(bytes, name: name, mimeType: 'image/jpeg');
      await Share.shareXFiles([x]);
    } catch (e) {
      _snack('Errore condivisione: $e');
    }
  }

  Future<void> _saveCurrent() async {
    final url = _cur.url;
    if (url == null || url.trim().isEmpty) return;

    try {
      if (kIsWeb) {
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
        _snack('Aperta in una nuova scheda. Salvala dal browser.');
        return;
      }

      final bytes = await _downloadBytes(url);
      final name = 'dms_${DateTime.now().millisecondsSinceEpoch}';
      final r = await ImageGallerySaverPlus.saveImage(bytes, name: name);

      final ok = (r['isSuccess'] == true) || (r['success'] == true);
      _snack(ok ? 'Salvata in galleria ✅' : 'Non salvata (permessi?)');
    } catch (e) {
      _snack('Errore salvataggio: $e');
    }
  }

  Future<void> _editCurrent() async {
    if (!_cur.canEdit || _cur.onEdit == null) return;
    await _cur.onEdit!.call();
    if (!mounted) return;
    _snack('Immagine aggiornata ✅');
  }

  Future<void> _removeCurrent() async {
    if (!_cur.canRemove || _cur.onRemove == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Rimuovere ${_cur.label}?'),
        content: const Text('Questa azione non è reversibile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );


    if (ok != true) return;

    await _cur.onRemove!.call();
    if (!mounted) return;
    _snack('Rimossa ✅');
  }

  @override
  Widget build(BuildContext context) {
    final hasTwo = widget.items.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_cur.label),
        actions: [
          IconButton(
            tooltip: 'Zoom reset',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => _tc.value = Matrix4.identity(),
          ),
          IconButton(
            tooltip: 'Condividi',
            icon: const Icon(Icons.share),
            onPressed: _cur.url == null ? null : _shareCurrent,
          ),
          IconButton(
            tooltip: 'Salva in galleria',
            icon: const Icon(Icons.download),
            onPressed: _cur.url == null ? null : _saveCurrent,
          ),
          if (_cur.canEdit)
            IconButton(
              tooltip: 'Modifica',
              icon: const Icon(Icons.edit),
              onPressed: _editCurrent,
            ),
          if (_cur.canRemove)
            IconButton(
              tooltip: 'Rimuovi',
              icon: const Icon(Icons.delete_outline),
              onPressed: _removeCurrent,
            ),
        ],
        bottom: hasTwo
            ? PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SegmentedButton<int>(
              segments: [
                for (int i = 0; i < widget.items.length; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(widget.items[i].label),
                    icon: Icon(i == 0 ? Icons.photo_size_select_large : Icons.account_circle),
                  ),
              ],
              selected: {_idx},
              onSelectionChanged: (s) {
                setState(() => _idx = s.first);
                _tc.value = Matrix4.identity();
              },
            ),
          ),
        )
            : null,
      ),
      body: Center(
        child: _cur.url == null || _cur.url!.trim().isEmpty
            ? const Icon(Icons.image_not_supported, color: Colors.white54, size: 90)
            : InteractiveViewer(
          transformationController: _tc,
          minScale: 1.0,
          maxScale: 6.0,
          child: CachedNetworkImage(
            imageUrl: _cur.url!.trim(),
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 90),
          ),
        ),
      ),
    );
  }
}
