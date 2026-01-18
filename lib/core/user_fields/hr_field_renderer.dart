// lib/core/user_fields/hr_field_renderer.dart
// Renderer unico per tutti i campi HR

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'hr_field_types.dart';
import 'hr_address_dialog.dart';

class HrFieldRenderer extends StatelessWidget {
  final HrField field;
  final dynamic value;
  final bool editable;
  final Function(String key, dynamic value) onChanged;

  const HrFieldRenderer({
    super.key,
    required this.field,
    required this.value,
    required this.editable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case HrFieldType.text:
        return _text(context);
      case HrFieldType.multiline:
        return _multiline(context);
      case HrFieldType.date:
        return _date(context);
      case HrFieldType.boolean:
        return _boolean(context);
      case HrFieldType.select:
        return _select(context);
      case HrFieldType.address:
        return _address(context);
      default:
        return const SizedBox.shrink();
    }
  }

  // ======================
  // TEXT
  // ======================
  Widget _text(BuildContext context) {
    return ListTile(
      title: Text(field.label),
      subtitle: Text(value?.toString() ?? '—'),
      trailing: editable ? const Icon(Icons.edit) : null,
      onTap: editable
          ? () => _openTextDialog(context, multiline: false)
          : null,
    );
  }

  Widget _multiline(BuildContext context) {
    return ListTile(
      title: Text(field.label),
      subtitle: Text(value?.toString() ?? '—'),
      trailing: editable ? const Icon(Icons.edit_note) : null,
      onTap: editable
          ? () => _openTextDialog(context, multiline: true)
          : null,
    );
  }

  // ======================
  // DATE
  // ======================
  Widget _date(BuildContext context) {
    final formatted = value is DateTime
        ? DateFormat('dd/MM/yyyy').format(value)
        : value is String && value.isNotEmpty
        ? value
        : '—';

    return ListTile(
      title: Text(field.label),
      subtitle: Text(formatted),
      trailing: editable ? const Icon(Icons.calendar_today) : null,
      onTap: editable ? () => _pickDate(context) : null,
    );
  }

  // ======================
  // BOOLEAN
  // ======================
  Widget _boolean(BuildContext context) {
    return SwitchListTile(
      title: Text(field.label),
      value: value == true,
      onChanged: editable ? (v) => onChanged(field.key, v) : null,
    );
  }

  // ======================
  // SELECT
  // ======================
  Widget _select(BuildContext context) {
    return ListTile(
      title: Text(field.label),
      subtitle: Text(value?.toString() ?? '—'),
      trailing: editable ? const Icon(Icons.arrow_drop_down) : null,
      onTap: editable
          ? () => _openSelectDialog(context)
          : null,
    );
  }

  // ======================
  // ADDRESS
  // ======================
  Widget _address(BuildContext context) {
    final formatted = value is Map ? value['formatted'] : null;

    return ListTile(
      title: Text(field.label),
      subtitle: formatted != null
          ? Text(
        formatted,
        style: const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      )
          : const Text('Non impostato'),
      trailing: editable ? const Icon(Icons.location_on) : null,
      onTap: editable
          ? () async {
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => HrAddressDialog(initialValue: value),
        );
        if (result != null) {
          onChanged(field.key, result);
        }
      }
          : null,
    );
  }

  // ======================
  // DIALOGS
  // ======================
  void _openTextDialog(BuildContext context, {required bool multiline}) {
    final controller = TextEditingController(text: value?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(field.label),
        content: TextField(
          controller: controller,
          maxLines: multiline ? 4 : 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              onChanged(field.key, controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  void _pickDate(BuildContext context) async {
    final initial = value is DateTime ? value : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      onChanged(field.key, picked);
    }
  }

  void _openSelectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(field.label),
        children: field.options!
            .map(
              (opt) => SimpleDialogOption(
            child: Text(opt),
            onPressed: () {
              onChanged(field.key, opt);
              Navigator.pop(context);
            },
          ),
        )
            .toList(),
      ),
    );
  }
}
