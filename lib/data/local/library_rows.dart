import 'package:drift/drift.dart';
import '../../domain/models/models.dart';
import 'database/user_database.dart';
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
