import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolve a stored file reference to something openable: private storage
/// references (`storage://bucket/path`) become short-lived signed URLs,
/// anything else passes through unchanged.
Future<String> resolveStorageUrl(String fileUrl) async {
  if (!fileUrl.startsWith('storage://')) return fileUrl;
  final rest = fileUrl.substring('storage://'.length);
  final slash = rest.indexOf('/');
  if (slash <= 0) return fileUrl;
  final bucket = rest.substring(0, slash);
  final path = rest.substring(slash + 1);
  return Supabase.instance.client.storage
      .from(bucket)
      .createSignedUrl(path, 300);
}
