package dev.shiori.importfixture;

import android.app.Activity;
import android.content.*;
import android.net.Uri;
import android.os.Bundle;
import java.io.*;
import java.util.ArrayList;

public class SendActivity extends Activity {
  public void onCreate(Bundle state) {
    super.onCreate(state);
    String mode = getIntent().getStringExtra("mode");
    String name = getIntent().getStringExtra("name");
    if (name == null) name = "fixture.txt";
    name = new File(name).getName();
    File file = new File(getFilesDir(), name);
    try {
      if ("delete".equals(mode)) { file.delete(); finish(); return; }
      if (!"missing".equals(mode)) {
        try (FileOutputStream out = new FileOutputStream(file)) {
          out.write((name.endsWith(".epub") ? "PK\u0003\u0004offline fixture" : "Offline TXT fixture\nChapter 1\nHello Shiori.").getBytes("UTF-8"));
        }
      } else { file.delete(); }
      Uri uri = Uri.parse("content://dev.shiori.importfixture.files/" + name);
      Intent target = new Intent("view".equals(mode) ? Intent.ACTION_VIEW : Intent.ACTION_SEND);
      target.setClassName("dev.shiori.reader", "dev.shiori.reader.MainActivity");
      target.setType(name.endsWith(".epub") ? "application/epub+zip" : "text/plain");
      if ("view".equals(mode)) target.setDataAndType(uri, getContentResolver().getType(uri));
      else target.putExtra(Intent.EXTRA_STREAM, uri);
      target.setClipData(ClipData.newRawUri("fixture", uri));
      if ("multiple".equals(mode)) {
        target.setAction(Intent.ACTION_SEND_MULTIPLE);
        ArrayList<Uri> files = new ArrayList<>(); files.add(uri); files.add(uri);
        target.putParcelableArrayListExtra(Intent.EXTRA_STREAM, files);
        target.getClipData().addItem(new ClipData.Item(uri));
      }
      target.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
      startActivity(target);
    } catch (Exception error) { throw new RuntimeException(error); }
    finish();
  }
}
