import 'package:drift/drift.dart';
import '../../domain/models/models.dart';
import 'database/user_database.dart' show UserDatabase;
import 'record_codec.dart';

/// Called within the owner's transaction, including atomic local import.
Future<void> writeBookshelfRow(
  UserDatabase db,
  BookshelfEntry entry,
  DateTime now,
) => db
    .customUpdate(
      'INSERT INTO bookshelf(source_id,novel_id,summary_json,added_at,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(source_id,novel_id) DO UPDATE SET summary_json=excluded.summary_json,updated_at=excluded.updated_at',
      variables: [
        Variable(entry.snapshot.key.sourceId.value),
        Variable(entry.snapshot.key.novelId),
        Variable(RecordCodec.summary(entry.snapshot)),
        Variable(entry.addedAt.millisecondsSinceEpoch),
        Variable(now.millisecondsSinceEpoch),
      ],
      updates: {db.bookshelf},
    )
    .then((_) {});

Future<void> writeProgressRow(
  UserDatabase db,
  ReadingProgress progress,
  DateTime now,
) async {
  final position = progress.position;
  await db.customUpdate(
    '''INSERT INTO reading_progress(source_id,novel_id,chapter_id,summary_json,chapter_ordinal,catalog_revision,content_revision,block_key,block_index,block_fraction,chapter_fraction,completed,pixel_offset,layout_key,position_version,last_read_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?) ON CONFLICT(source_id,novel_id) DO UPDATE SET
      chapter_id=excluded.chapter_id,summary_json=excluded.summary_json,chapter_ordinal=excluded.chapter_ordinal,catalog_revision=excluded.catalog_revision,content_revision=excluded.content_revision,block_key=excluded.block_key,block_index=excluded.block_index,block_fraction=excluded.block_fraction,chapter_fraction=excluded.chapter_fraction,completed=excluded.completed,pixel_offset=excluded.pixel_offset,layout_key=excluded.layout_key,position_version=excluded.position_version,last_read_at=excluded.last_read_at,updated_at=excluded.updated_at''',
    variables: [
      Variable(progress.novelKey.sourceId.value),
      Variable(progress.novelKey.novelId),
      Variable(progress.chapterKey.chapterId),
      Variable(RecordCodec.summary(progress.snapshot)),
      Variable(progress.chapterOrdinalSnapshot),
      Variable(progress.catalogRevision),
      Variable(position.contentRevision),
      Variable(position.blockKey),
      Variable(position.blockIndex),
      Variable(position.blockFraction),
      Variable(position.chapterFraction),
      Variable(progress.completed ? 1 : 0),
      Variable<double>(position.pixelOffset),
      Variable<String>(position.layoutKey),
      Variable(progress.lastReadAt.millisecondsSinceEpoch),
      Variable(now.millisecondsSinceEpoch),
    ],
    updates: {db.readingProgress},
  );
}
