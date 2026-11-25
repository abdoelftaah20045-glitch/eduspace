import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

class LibraryItem {
  LibraryItem({
    required this.id,
    required this.title,
    this.description = '',
    required this.fileUrl,
    this.fileType = 'pdf',
    this.category = 'general',
    this.sizeBytes,
    this.courseId,
    this.courseTitle,
    this.downloads = 0,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final String fileUrl;
  final String fileType;
  final String category;
  final int? sizeBytes;
  final String? courseId;
  final String? courseTitle;
  final int downloads;
  final DateTime createdAt;

  factory LibraryItem.fromMap(Map<String, dynamic> m) {
    final course = m['courses'];
    return LibraryItem(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      fileUrl: (m['file_url'] as String?) ?? '',
      fileType: (m['file_type'] as String?) ?? 'pdf',
      category: (m['category'] as String?) ?? 'general',
      sizeBytes: (m['size_bytes'] as num?)?.toInt(),
      courseId: m['course_id'] as String?,
      courseTitle: course is Map ? course['title'] as String? : null,
      downloads: (m['downloads'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
    );
  }
}

class LibraryRepository {
  LibraryRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// Items visible to the user, optionally filtered by search text and
  /// category. Filters before ordering (PostgREST transform builder).
  static Future<List<LibraryItem>> fetchItems({
    String query = '',
    String? category,
    int limit = 200,
  }) async {
    var q = _c
        .from('library_items')
        .select('*, courses(title)')
        .eq('tenant_id', TenantContext.id);
    final safe = query.replaceAll(',', ' ').replaceAll('(', ' ')
        .replaceAll(')', ' ').trim();
    if (safe.isNotEmpty) {
      q = q.or('title.ilike.%$safe%,description.ilike.%$safe%');
    }
    if (category != null && category.isNotEmpty) {
      q = q.eq('category', category);
    }
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(LibraryItem.fromMap).toList();
  }

  static Future<Set<String>> fetchCategories() async {
    final rows = await _c
        .from('library_items')
        .select('category')
        .eq('tenant_id', TenantContext.id)
        .limit(500);
    return rows
        .map((m) => (m['category'] as String?) ?? 'general')
        .where((c) => c.isNotEmpty)
        .toSet();
  }

  static Future<void> bumpDownloads(String id) async {
    // Best-effort counter; ignore errors so opening a file never fails.
    try {
      final row = await _c
          .from('library_items')
          .select('downloads')
          .eq('id', id)
          .single();
      await _c.from('library_items').update({
        'downloads': ((row['downloads'] as num?)?.toInt() ?? 0) + 1,
      }).eq('id', id);
    } catch (_) {}
  }

  /// Upload a resource file to the private resources bucket and return its
  /// `storage://` reference for library_items.file_url.
  static Future<String> uploadResourceFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        '${TenantContext.id}/uploads/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _c.storage.from('resources').uploadBinary(path, bytes);
    return 'storage://resources/$path';
  }

  /// Resolve a stored file_url to something openable: private storage
  /// references become short-lived signed URLs, external links pass through.
  static Future<String> resolveUrl(String fileUrl) async {
    if (!fileUrl.startsWith('storage://')) return fileUrl;
    final rest = fileUrl.substring('storage://'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return fileUrl;
    final bucket = rest.substring(0, slash);
    final path = rest.substring(slash + 1);
    return _c.storage.from(bucket).createSignedUrl(path, 300);
  }

  static Future<String> create(Map<String, dynamic> values) async {
    final row = await _c
        .from('library_items')
        .insert({
          ...values,
          'created_by': _c.auth.currentUser?.id,
          'tenant_id': TenantContext.id,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> delete(String id) async {
    await _c.from('library_items').delete().eq('id', id);
  }
}
