import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scansiona QR')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;

          final code = capture.barcodes
              .map((b) => b.rawValue?.trim() ?? '')
              .firstWhere((v) => v.isNotEmpty, orElse: () => '');

          if (code.isEmpty) return;

          _handled = true;
          Navigator.pop(context, code);
        },
      ),
    );
  }
}
