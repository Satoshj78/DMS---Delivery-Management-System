// lib/core/user_fields/hr_address_dialog.dart
// Dialog selezione indirizzo (Google Maps)

import 'package:flutter/material.dart';
import 'package:google_places_flutter/google_places_flutter.dart';

class HrAddressDialog extends StatefulWidget {
  final Map<String, dynamic>? initialValue;

  const HrAddressDialog({super.key, this.initialValue});

  @override
  State<HrAddressDialog> createState() => _HrAddressDialogState();
}

class _HrAddressDialogState extends State<HrAddressDialog> {
  Map<String, dynamic>? selected;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialValue?['formatted'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleziona indirizzo'),
      content: GooglePlaceAutoCompleteTextField(
        textEditingController: _controller,
        googleAPIKey: const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
        debounceTime: 800,
        isLatLngRequired: true,
        inputDecoration: const InputDecoration(
          hintText: 'Via, città...',
        ),
        getPlaceDetailWithLatLng: (prediction) {
          selected = {
            'placeId': prediction.placeId,
            'formatted': prediction.description,
            'lat': prediction.lat,
            'lng': prediction.lng,
          };
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: selected == null
              ? null
              : () => Navigator.pop(context, selected),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
