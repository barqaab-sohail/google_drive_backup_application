import '../core/models.dart';

abstract class DriveAdapter {
  Future<List<BackupSource>> discover();
  Future<CloudFile> stat(String id, Cancellation cancellation);
  Future<List<CloudFile>> children(
    BackupSource source,
    String parentId,
    Cancellation cancellation,
  );
  Future<Stream<List<int>>> download(
    CloudFile file,
    String? exportMime,
    Cancellation cancellation,
  );
}
