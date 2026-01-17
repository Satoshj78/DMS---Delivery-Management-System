import 'package:shared_preferences/shared_preferences.dart';

class LeaguePickerPrefs {
  static const _kTabOrder = 'league_picker_tab_order';
  static const _kDefaultTab = 'league_picker_default_tab';

  Future<Map<String, dynamic>> load() async {
    final sp = await SharedPreferences.getInstance();

    final order = sp.getStringList(_kTabOrder) ?? const ['all', 'joined', 'invited'];
    final def = sp.getString(_kDefaultTab) ?? 'all';

    return {
      'tabOrder': order,
      'defaultTab': def,
    };
  }

  Future<void> save({required List<String> tabOrder, required String defaultTab}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kTabOrder, tabOrder);
    await sp.setString(_kDefaultTab, defaultTab);
  }
}
