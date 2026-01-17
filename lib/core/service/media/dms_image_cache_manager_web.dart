
import 'package:flutter/services.dart';

/// WEB: non possiamo salvare su disco come su IO.
/// Restituiamo sempre l'URL (con cache-buster v) e, se serve, scarichiamo bytes via NetworkAssetBundle.
class DmsImageCacheManager {
  DmsImageCacheManager._();

  static final DmsImageCacheManager instance = DmsImageCacheManager._();

  /// Aggiunge/aggiorna il parametro v (cache-buster) se presente.
  String withV(String url, {int? v}) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (v == null) return u;

    final uri = Uri.parse(u);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['v'] = v.toString();
    return uri.replace(queryParameters: qp).toString();
  }

  /// Su WEB ritorna l'URL (eventualmente con ?v=)
  Future<String> getPathOrUrl(String url, {int? v, String? ext}) async {
    return withV(url, v: v);
  }

  /// Se ti servono i bytes (es. preview custom), li scarica via bundle di rete.
  Future<Uint8List> getBytes(String url, {int? v, String? ext}) async {
    final finalUrl = withV(url, v: v);
    if (finalUrl.trim().isEmpty) {
      throw Exception('URL vuoto.');
    }
    final uri = Uri.parse(finalUrl);

    // Trick standard: baseUri = url, key = '' => scarica proprio quell'url
    final data = await NetworkAssetBundle(uri).load('');
    return data.buffer.asUint8List();
  }

  /// Su WEB non abbiamo file locale da eliminare: no-op.
  Future<void> evict(String url, {int? v, String? ext}) async {}

  /// Su WEB: no-op
  Future<void> clear() async {}
}

/// Comodità
final DmsImageCacheManager dmsImageCacheManager = DmsImageCacheManager.instance;
