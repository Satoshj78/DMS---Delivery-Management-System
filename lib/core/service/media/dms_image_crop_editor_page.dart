import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class DmsImageCropEditorPage extends StatefulWidget {
  final Uint8List bytes;
  final String title;

  /// null = libero
  final double? initialAspectRatio;

  /// se true puoi passare a “Libero”
  final bool allowFreeAspect;

  /// se true mostra UI circolare (utile per profilo)
  final bool circleUi;

  const DmsImageCropEditorPage({
    super.key,
    required this.bytes,
    required this.title,
    this.initialAspectRatio,
    this.allowFreeAspect = true,
    this.circleUi = false,
  });

  @override
  State<DmsImageCropEditorPage> createState() => _DmsImageCropEditorPageState();
}

class _DmsImageCropEditorPageState extends State<DmsImageCropEditorPage> {
  final CropController _controller = CropController();

  late Uint8List _workBytes; // bytes modificabili (rotate/reset)
  double? _aspect; // null = libero
  bool _cropping = false;

  // forzo rebuild del Crop quando cambiano i bytes (rotate/reset)
  int _rebuildKey = 0;

  @override
  void initState() {
    super.initState();
    _workBytes = widget.bytes;
    _aspect = widget.initialAspectRatio;
  }

  Future<void> _rotateRight() async {
    final decoded = img.decodeImage(_workBytes);
    if (decoded == null) return;

    final baked = img.bakeOrientation(decoded);
    final rotated = img.copyRotate(baked, angle: 90);

    final out = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));

    if (!mounted) return;
    setState(() {
      _workBytes = out;
      _rebuildKey++;
    });
  }

  void _resetAll() {
    setState(() {
      _workBytes = widget.bytes;
      _aspect = widget.initialAspectRatio;
      _cropping = false;
      _rebuildKey++;
    });
  }

  void _doCrop() {
    if (_cropping) return;
    setState(() => _cropping = true);
    _controller.crop();
  }

  Uint8List? _extractBytes(dynamic result) {
    // Compatibile sia con versioni che ritornano direttamente Uint8List
    // sia con versioni che ritornano un oggetto con .croppedImage
    if (result is Uint8List) return result;
    try {
      final dynamic bytes = (result as dynamic).croppedImage;
      if (bytes is Uint8List) return bytes;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final presets = <String, double?>{
      if (widget.allowFreeAspect) 'Libero': null,
      '1:1': 1.0,
      '16:9': 16 / 9,
      '3:1': 3 / 1,
      '4:3': 4 / 3,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Ruota',
            icon: const Icon(Icons.rotate_right),
            onPressed: _rotateRight,
          ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.refresh),
            onPressed: _resetAll,
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double?>(
                value: _aspect,
                items: presets.entries
                    .map((e) => DropdownMenuItem<double?>(
                  value: e.value,
                  child: Text(e.key),
                ))
                    .toList(),
                onChanged: (v) => setState(() => _aspect = v),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: _cropping ? null : _doCrop,
            icon: const Icon(Icons.check),
            label: const Text('OK'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          Crop(
            key: ValueKey(_rebuildKey),
            controller: _controller,
            image: _workBytes,
            aspectRatio: _aspect,
            withCircleUi: widget.circleUi,
            onCropped: (dynamic result) {
              if (!mounted) return;
              final out = _extractBytes(result);
              if (out != null) {
                Navigator.pop<Uint8List>(context, out);
              } else {
                setState(() => _cropping = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Errore ritaglio')),
                );
              }
            },
          ),
          if (_cropping)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
