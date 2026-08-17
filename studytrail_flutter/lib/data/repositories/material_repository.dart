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
  ///
  /// Storage and Postgres can't share a transaction, so the row insert is
  /// wrapped in compensating cleanup: if it fails, the object just written is
  /// removed again. Without it every failed upload left a paid-for object in the
  /// bucket that nothing referenced and no screen could ever show (REVIEW.md P1).
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

    try {
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
    } catch (_) {
      // Best-effort: if the cleanup itself fails there is nothing further the
      // client can do, and the insert error is the one worth surfacing.
      try {
        await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
      } catch (_) {
        // Swallowed deliberately — see above.
      }
      rethrow;
    }
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

  /// Records that ingestion didn't happen, so the row reads as retryable rather
  /// than sitting on `uploaded` looking like it's still queued.
  ///
  /// Called when the `embed-material` invocation itself fails — a function that
  /// never ran can't mark its own failure.
  Future<void> markIngestFailed(String materialId) =>
      _setStatus(materialId, IngestStatus.failed);

  /// Puts a failed material back in the queue. The caller re-invokes
  /// `embed-material` afterwards; this only resets the row the UI reads.
  ///
  /// `embedded` is deliberately not settable from here — 0009_atomicity.sql has
  /// a trigger that rejects it unless embedded chunks actually exist.
  Future<StudyMaterial> retryIngest(String materialId) =>
      _setStatus(materialId, IngestStatus.uploaded);

  Future<StudyMaterial> _setStatus(String id, IngestStatus status) async {
    final row = await db
        .from('materials')
        .update({'status': status.db})
        .eq('id', id)
        .select()
        .single();
    return StudyMaterial.fromMap(row);
  }

  /// Deletes the row first, then the object.
  ///
  /// That order matters: a row whose object is already gone breaks preview and
  /// re-ingestion with no way for the student to clear it, whereas an object
  /// whose row is gone is invisible and costs only storage. If the two can't
  /// both succeed, leave the recoverable failure.
  Future<void> deleteMaterial(StudyMaterial material) async {
    await db.from('materials').delete().eq('id', material.id);

    final path = material.storagePath;
    if (path != null) {
      await db.storage.from(SupabaseConfig.materialsBucket).remove([path]);
    }
  }

  /// Signed URL for previewing a private object.
  Future<String> signedUrl(String storagePath, {int expiresIn = 3600}) {
    return db.storage
        .from(SupabaseConfig.materialsBucket)
        .createSignedUrl(storagePath, expiresIn);
  }
}
