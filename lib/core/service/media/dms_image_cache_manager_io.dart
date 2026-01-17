import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;

/// IO (Android/iOS/Windows/macOS/Linux):
/// salva i file in una cartella di cache (systemTemp) e li riusa se presenti.
/// Utile per evitare download ripetuti quando apri immagini/PDF più volte.
class DmsImageCacheManager {
  DmsImageCacheManager._();

  static final DmsImageCacheManager instance = DmsImageCacheManager._();

  // Cache temp dell'app (non richiede path_provider)
  static final Directory _baseDir =
  Directory('${Directory.systemTemp.path}/dms_media_cache');

  static bool _dirReady = false;

  // Evita doppio download contemporaneo dello stesso file
  final Map<String, Future<File>> _inflight = {};

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

  Future<void> _ensureDir() async {
    if (_dirReady) return;
    if (!await _baseDir.exists()) {
      await _baseDir.create(recursive: true);
    }
    _dirReady = true;
  }

  String _inferExt(String url) {
    try {
      final uri = Uri.parse(url);
      final p = uri.path;
      final i = p.lastIndexOf('.');
      if (i >= 0 && i < p.length - 1) {
        final e = p.substring(i + 1).toLowerCase();
        if (e.length <= 6) return e;
      }
    } catch (_) {}
    return 'dat';
  }

  String _hashName(String url, {int? v, String? ext}) {
    final finalUrl = withV(url, v: v);
    final digest = sha1.convert(utf8.encode(finalUrl)).toString();
    final safeExt = (ext ?? _inferExt(url)).replaceAll('.', '').trim();
    return '$digest.$safeExt';
  }

  /// Su IO ritorna il PATH locale del file cached (scarica se non presente)
  Future<String> getPathOrUrl(String url, {int? v, String? ext}) async {
    final file = await _getOrDownload(url, v: v, ext: ext);
    return file.path;
  }

  /// Ritorna i bytes dalla cache (scarica se non presente)
  Future<Uint8List> getBytes(String url, {int? v, String? ext}) async {
    final file = await _getOrDownload(url, v: v, ext: ext);
    return file.readAsBytes();
  }

  /// Elimina il file cached (se esiste)
  Future<void> evict(String url, {int? v, String? ext}) async {
    await _ensureDir();
    final name = _hashName(url, v: v, ext: ext);
    final file = File('${_baseDir.path}/$name');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Svuota tutta la cache
  Future<void> clear() async {
    await _ensureDir();
    if (await _baseDir.exists()) {
      await _baseDir.delete(recursive: true);
      _dirReady = false;
    }
  }

  Future<File> _getOrDownload(String url, {int? v, String? ext}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw Exception('URL vuoto.');
    }

    await _ensureDir();

    final name = _hashName(trimmed, v: v, ext: ext);
    final outFile = File('${_baseDir.path}/$name');

    // Se già presente, riusa
    if (await outFile.exists()) {
      return outFile;
    }

    // Se già in download, attendi quello
    final existing = _inflight[name];
    if (existing != null) return existing;

    final future = _downloadToFile(trimmed, outFile, v: v);
    _inflight[name] = future;

    try {
      return await future;
    } finally {
      _inflight.remove(name);
    }
  }

  Future<File> _downloadToFile(String url, File outFile, {int? v}) async {
    final finalUrl = withV(url, v: v);
    final uri = Uri.parse(finalUrl);

    final client = HttpClient()..autoUncompress = true;

    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, '*/*');

      final res = await req.close();

      if (res.statusCode >= 400) {
        throw Exception('Download fallito (${res.statusCode}) per $finalUrl');
      }

      final bytes = await consolidateHttpClientResponseBytes(res);
      if (bytes.isEmpty) {
        throw Exception('Download ok ma file vuoto per $finalUrl');
      }

      await outFile.writeAsBytes(bytes, flush: true);
      return outFile;
    } finally {
      client.close(force: true);
    }
  }
}

/// Comodità (se preferisci usare la variabile invece di .instance)
final DmsImageCacheManager dmsImageCacheManager = DmsImageCacheManager.instance;
