import 'dart:io';

import '../../config/supabase_config.dart';
import '../../models/models.dart';
import '../supabase_client.dart';

/// Uploads syllabi/notes to private Storage and tracks them in `materials`.
class MaterialRepository {
  const MaterialRepository();

  Future<List<StudyMaterial>> getMaterials({String? goalId}) async {
    var query = db.from('materials').select();
    if (goalId != null) query = query.eq('goal_id', goalId);
    final rows = await query.order('created_at', ascending: false);
    return rows.map(StudyMaterial.fromMap).toList();
  }

  Future<StudyMaterial?> getMaterial(String id) async {
    final row =
        await db.from('materials').select().eq('id', id).maybeSingle();
    return row == null ? null : StudyMaterial.fromMap(row);
  }

  /// Uploads a picked file and records it. The object key is always
  /// `{uid}/{timestamp}_{filename}` — the Storage policies key off that first
  /// segment, so it must stay the user's id.
  Future<StudyMaterial> uploadFile({
    required File file,
    required String fileName,
    String? goalId,
    MaterialType sourceType = MaterialType.syllabusPdf,
  }) async {
    final uid = requireUserId;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$uid/${stamp}_$safeName';

    await db.storage.from(SupabaseConfig.materialsBucket).upload(path, file);

    final row = await db
        .from('materials')
        .insert({
          'user_id': uid,
          'source_type': sourceType.db,
          'title': fileName,
          'storage_path': path,
          'status': IngestStatus.uploaded.db,
          'goal_id': ?goalId,
        })
        .select()
        .single();
    return StudyMaterial.fromMap(row);
  }

  /// Records a video/article link — nothing to upload.
  Future<StudyMaterial> addLink({
    required String url,
    String? title,
    String? goalId,
  }) async {
    final row = await db
        .from('materials')
        .insert({
          'user_id': requireUserId,
          'source_type': MaterialType.videoLink.db,
          'title': title ?? url,
          'external_url': url,
          'status': IngestStatus.uploaded.db,
          'goal_id': ?goalId,
        })
        .select()
        .single();
    return StudyMaterial.fromMap(row);
  }

  /// Emits whenever this material's row changes — lets the upload screen show
  /// uploaded → processing → embedded as the Edge Function works.
  Stream<StudyMaterial> watchMaterial(String id) {
    return db
        .from('materials')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => StudyMaterial.fromMap(rows.first));
  }

  Future<void> deleteMaterial(StudyMaterial material) async {
    final path = material.storagePath;
    if (path != null) {
      await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
    }
    await db.from('materials').delete().eq('id', material.id);
  }

  /// Signed URL for previewing a private object.
  Future<String> signedUrl(String storagePath, {int expiresIn = 3600}) {
    return db.storage
        .from(SupabaseConfig.materialsBucket)
        .createSignedUrl(storagePath, expiresIn);
  }
}
