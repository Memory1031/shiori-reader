package dev.shiori.importfixture;

import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.*;

/** Separate test APK: private provider with temporary grants, never production. */
public class FixtureProvider extends ContentProvider {
  public boolean onCreate() { return true; }
  public String getType(Uri uri) { return uri.getLastPathSegment().endsWith(".epub") ? "application/epub+zip" : "text/plain"; }
  public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
    MatrixCursor cursor = new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE});
    File file = new File(getContext().getFilesDir(), uri.getLastPathSegment());
    cursor.addRow(new Object[]{file.getName(), file.length()}); return cursor;
  }
  public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
    return ParcelFileDescriptor.open(new File(getContext().getFilesDir(), uri.getLastPathSegment()), ParcelFileDescriptor.MODE_READ_ONLY);
  }
  public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
  public int update(Uri uri, ContentValues values, String s, String[] a) { throw new UnsupportedOperationException(); }
  public int delete(Uri uri, String s, String[] a) { throw new UnsupportedOperationException(); }
}
