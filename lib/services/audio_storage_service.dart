import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class AudioStorageService {
  static const bucket = 'instrumentos';
  final SupabaseClient _client;

  AudioStorageService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  String publicUrl(String path) => _client.storage.from(bucket).getPublicUrl(path);

  Future<String> subir({
    required String path,
    required Uint8List bytes,
    String contentType = 'audio/mpeg',
  }) async {
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return publicUrl(path);
  }

  Future<void> eliminar(String path) =>
      _client.storage.from(bucket).remove([path]).then((_) {});
}
