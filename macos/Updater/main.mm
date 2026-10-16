#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include "archive_api.h"
#include <sys/file.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>
#include <set>
#include <vector>
#include <stdexcept>
#include "UpdateTrust.h"

static NSFileManager *fm;
static void checked(int line, bool ok, const char *error = "verification") {
  if (!ok) {
#ifdef SHIORI_UPDATER_TESTING
    fprintf(stderr, "line %d: ", line);
#endif
    throw std::runtime_error(error);
  }
}
#define require(...) checked(__LINE__, __VA_ARGS__)
static NSString *join(NSString *a, NSString *b) { return [a stringByAppendingPathComponent:b]; }
static bool exists(NSString *p) { return [fm fileExistsAtPath:p]; }
static NSDictionary *json(NSData *data) {
  require(data && data.length <= 4 * 1024 * 1024);
  id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nullptr];
  require([value isKindOfClass:NSDictionary.class]); return value;
}
static void writeJSON(NSString *p, NSDictionary *v) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:v options:0 error:nullptr];
  require([data writeToFile:p options:NSDataWritingAtomic error:nullptr], "storage");
}
static void removeOwned(NSString *p) { require([fm removeItemAtPath:p error:nullptr], "storage"); }
static void move(NSString *a, NSString *b) { require([fm moveItemAtPath:a toPath:b error:nullptr], "storage"); }
static NSString *digest(NSString *path) {
  FILE *file = fopen(path.fileSystemRepresentation, "rb"); require(file, "storage");
  CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); unsigned char bytes[65536], hash[32]; size_t n;
  while ((n = fread(bytes, 1, sizeof(bytes), file))) CC_SHA256_Update(&ctx, bytes, (CC_LONG)n);
  bool ok = !ferror(file); fclose(file); require(ok, "storage"); CC_SHA256_Final(hash, &ctx);
  NSMutableString *hex = [NSMutableString string]; for (auto b : hash) [hex appendFormat:@"%02x", b]; return hex;
}
static std::vector<uint8_t> der(uint8_t tag, const std::vector<uint8_t>& data) {
  std::vector<uint8_t> out{tag}; size_t n = data.size();
  if (n < 128) out.push_back(n); else {
    std::vector<uint8_t> length; while (n) { length.insert(length.begin(), n & 255); n >>= 8; }
    out.push_back(0x80 | length.size()); out.insert(out.end(), length.begin(), length.end());
  }
  out.insert(out.end(), data.begin(), data.end()); return out;
}
static void verifySignature(NSData *data, NSData *signature, NSDictionary *trust) {
  NSString *hex = trust[@"publicKey"][@"modulus"]; require(hex.length == 768 && signature.length == 384);
  std::vector<uint8_t> modulus{0};
  for (NSUInteger i = 0; i < hex.length; i += 2) {
    unsigned v = 0; require([[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&v]); modulus.push_back(v);
  }
  auto content = der(2, modulus); auto exponent = der(2, {1, 0, 1});
  content.insert(content.end(), exponent.begin(), exponent.end()); auto encoded = der(0x30, content);
  NSData *keyData = [NSData dataWithBytes:encoded.data() length:encoded.size()];
  NSDictionary *attrs = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,
    (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,
    (__bridge id)kSecAttrKeySizeInBits:@3072};
  SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)keyData, (__bridge CFDictionaryRef)attrs, nullptr);
  require(key); bool valid = SecKeyVerifySignature(key, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
    (__bridge CFDataRef)data, (__bridge CFDataRef)signature, nullptr); CFRelease(key); require(valid);
}
static bool safePath(NSString *path) {
  if (!path.length || path.length > 1024 || [path hasPrefix:@"/"] || [path containsString:@"\\"] || [path containsString:@"\n"]) return false;
  for (NSString *part in path.pathComponents) if ([part isEqual:@".."] || [part isEqual:@"."]) return false;
  return true;
}
static void extract(NSString *zip, NSString *root) {
  require([fm createDirectoryAtPath:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nullptr], "storage");
  archive *a = archive_read_new(); archive_read_support_format_zip(a); archive_read_support_filter_all(a);
  require(archive_read_open_filename(a, zip.fileSystemRepresentation, 65536) == ARCHIVE_OK);
  std::set<std::string> seen; std::vector<std::pair<NSString *, NSString *>> links; int count = 0; int64_t total = 0;
  archive_entry *e; int status;
  try {
    while ((status = archive_read_next_header(a, &e)) == ARCHIVE_OK) {
      NSString *name = [NSString stringWithUTF8String:archive_entry_pathname(e)];
      require(safePath(name) && ([name isEqual:@"Shiori.app"] || [name hasPrefix:@"Shiori.app/"]));
      require(++count <= 20000 && seen.insert(name.UTF8String).second);
      require(!archive_entry_hardlink(e)); NSString *out = join(root, name);
      const auto type = archive_entry_filetype(e);
      if (type == AE_IFLNK) {
        NSString *target = [NSString stringWithUTF8String:archive_entry_symlink(e)];
        require(target && !target.isAbsolutePath);
        NSString *resolved = [[name.stringByDeletingLastPathComponent stringByAppendingPathComponent:target] stringByStandardizingPath];
        require([resolved hasPrefix:@"Shiori.app/"]); links.push_back({out, target}); continue;
      }
      require(type == AE_IFDIR || type == AE_IFREG);
      require([fm createDirectoryAtPath:out.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nullptr], "storage");
      if (type == AE_IFDIR) {
        require([fm createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nullptr], "storage"); continue;
      }
      int64_t size = archive_entry_size(e); require(size >= 0 && (total += size) <= 2LL * 1024 * 1024 * 1024);
      int fd = open(out.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600); require(fd >= 0, "storage");
      char buffer[65536]; ssize_t n; int64_t written = 0; bool ok = true;
      while ((n = archive_read_data(a, buffer, sizeof(buffer))) > 0) {
        written += n; if (written > size) { ok = false; break; }
        ssize_t offset = 0; while (offset < n) { ssize_t w = write(fd, buffer + offset, n - offset); if (w <= 0) {ok = false; break;} offset += w; }
        if (!ok) break;
      }
      ok = ok && n == 0 && written == size && fchmod(fd, archive_entry_perm(e) & 0755) == 0 && fsync(fd) == 0;
      close(fd); require(ok, "storage");
    }
    require(status == ARCHIVE_EOF);
    // Links are created last, so archive entries cannot write through them.
    for (auto &link : links) {
      require([fm createDirectoryAtPath:link.first.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nullptr], "storage");
      require([fm createSymbolicLinkAtPath:link.first withDestinationPath:link.second error:nullptr]);
    }
    NSString *bundle = join(root, @"Shiori.app");
    char base[PATH_MAX]; require(realpath(bundle.fileSystemRepresentation, base));
    std::string prefix = std::string(base) + "/";
    for (auto &link : links) {
      char target[PATH_MAX]; require(realpath(link.first.fileSystemRepresentation, target));
      require(std::string(target).rfind(prefix, 0) == 0);
    }
  } catch (...) { archive_read_free(a); throw; }
  archive_read_free(a);
}
static NSDictionary *verified(NSString *workspace, NSDictionary *trust) {
  NSData *raw = [NSData dataWithContentsOfFile:join(workspace, @"manifest.json")];
  verifySignature(raw, [NSData dataWithContentsOfFile:join(workspace, @"manifest.sig")], trust);
  NSDictionary *m = json(raw), *identity = trust[@"identity"];
  require([m[@"schemaVersion"] isEqual:@1] && [m[@"applicationId"] isEqual:@"dev.shiori.reader"] &&
    [m[@"keyId"] isEqual:trust[@"publicKey"][@"keyId"]] &&
    [m[@"algorithm"] isEqual:@"rsa3072-pkcs1-sha256"]);
  require([m[@"build"] longLongValue] > [identity[@"build"] longLongValue] &&
    [m[@"version"] compare:identity[@"version"] options:NSNumericSearch] != NSOrderedAscending);
  NSArray *assets = m[@"assets"]; require([assets isKindOfClass:NSArray.class] && assets.count == 1);
  NSDictionary *asset = assets[0];
  require([asset[@"platform"] isEqual:@"macos-universal"] && [asset[@"updaterProtocol"] isEqual:@1]);
  require([asset[@"name"] isEqual:[NSString stringWithFormat:@"shiori-reader-%@-macos-universal.zip", m[@"tag"]]]);
  NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
  NSString *currentOS = [NSString stringWithFormat:@"%ld.%ld.%ld", os.majorVersion, os.minorVersion, os.patchVersion];
  require([asset[@"minimumSystem"] isKindOfClass:NSString.class] && [currentOS compare:asset[@"minimumSystem"] options:NSNumericSearch] != NSOrderedAscending, "location");
  long long size = [asset[@"size"] longLongValue]; require(size > 0 && size <= 2LL * 1024 * 1024 * 1024);
  NSString *package = join(workspace, @"package.zip");
  require([[fm attributesOfItemAtPath:package error:nullptr][NSFileSize] longLongValue] == size &&
    [digest(package) isEqual:asset[@"sha256"]]);
  return m;
}
static void checkBundle(NSString *bundle, NSDictionary *manifest) {
  NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:join(bundle, @"Contents/Info.plist")];
  require([info[@"CFBundleIdentifier"] isEqual:@"dev.shiori.reader"] &&
    [info[@"CFBundleShortVersionString"] isEqual:manifest[@"version"]] &&
    [info[@"CFBundleVersion"] longLongValue] == [manifest[@"build"] longLongValue]);
  require([fm isExecutableFileAtPath:join(bundle, @"Contents/MacOS/Shiori")] &&
    [fm isExecutableFileAtPath:join(bundle, @"Contents/MacOS/shiori-updater")]);
  NSDictionary *build = json([NSData dataWithContentsOfFile:join(bundle, @"Contents/Frameworks/App.framework/Resources/flutter_assets/assets/release/build-info.json")]);
  for (NSString *key in @[@"applicationId", @"tag", @"channel", @"version", @"build", @"commit"])
    require([build[@"identity"][key] isEqual:manifest[key]]);
}
static void checkpoint(const char *stage) {
#ifdef SHIORI_UPDATER_TESTING
  if (getenv("SHIORI_UPDATE_STOP") && !strcmp(getenv("SHIORI_UPDATE_STOP"), stage)) _exit(99);
#endif
}
int main(int argc, const char **argv) {
 @autoreleasepool {
  fm = NSFileManager.defaultManager;
  int lock = -1;
  try {
    require(argc >= 3);
    NSString *mode = @(argv[1]), *requested = @(argv[2]);
    char parentPath[PATH_MAX];
    require(requested.isAbsolutePath && realpath(requested.stringByDeletingLastPathComponent.fileSystemRepresentation, parentPath), "location");
    NSString *install = join([NSString stringWithUTF8String:parentPath], requested.lastPathComponent);
    require(install.isAbsolutePath && [install.pathExtension isEqual:@"app"] &&
      ![install hasPrefix:@"/Volumes/"] && ![install containsString:@"/AppTranslocation/"] &&
      access(install.stringByDeletingLastPathComponent.fileSystemRepresentation, W_OK) == 0, "location");
    NSString *workspace = [install stringByAppendingString:@".update"], *marker = join(workspace, @"owner.json");
    bool owned = exists(marker) && [json([NSData dataWithContentsOfFile:marker])[@"installation"] isEqual:install] && [json([NSData dataWithContentsOfFile:marker])[@"format"] isEqual:@"ShioriMacUpdate/1"];
    require(!exists(workspace) || owned, "workspaceConflict");
    if (!exists(workspace)) {
      if ([mode isEqual:@"recover"]) { puts("idle"); return 0; }
      require([fm createDirectoryAtPath:workspace withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nullptr], "storage");
      writeJSON(marker, @{@"installation":install, @"format":@"ShioriMacUpdate/1"});
    }
    struct stat st; require(lstat(workspace.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode) && st.st_uid == getuid(), "workspaceConflict");
    lock = open(join(workspace, @"lock").fileSystemRepresentation, O_RDWR|O_CREAT|O_NOFOLLOW, 0600);
    require(lock >= 0 && flock(lock, LOCK_EX|LOCK_NB) == 0, "busy");
    NSString *backup = join(workspace, @"previous.app"), *payload = join(workspace, @"payload"), *next = join(payload, @"Shiori.app"), *transaction = join(workspace, @"transaction.json");
    NSDictionary *trust = json([NSData dataWithBytes:SHIORI_UPDATE_TRUST length:strlen(SHIORI_UPDATE_TRUST)]);
    if ([mode isEqual:@"recover"]) {
      if (!exists(transaction)) { puts("idle"); return 0; }
      NSDictionary *record = json([NSData dataWithContentsOfFile:transaction]);
      if (!exists(install) && exists(backup)) { move(backup, install); removeOwned(transaction); puts("failed"); return 0; }
      NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:join(install, @"Contents/Info.plist")];
      if ([info[@"CFBundleVersion"] longLongValue] == [record[@"build"] longLongValue]) {
        if (exists(backup)) removeOwned(backup); removeOwned(transaction); if (exists(payload)) removeOwned(payload); puts("installed"); return 0;
      }
      if (!exists(backup)) { removeOwned(transaction); puts("failed"); return 0; }
      puts("failed"); return 0;
    }
    require(!exists(transaction), "busy");
    require([trust[@"development"] boolValue] == NO && trust[@"identity"] && trust[@"publicKey"]);
    if ([mode isEqual:@"prepare"]) {
      require(argc == 6);
      struct stat installed; require(lstat(install.fileSystemRepresentation, &installed) == 0 && S_ISDIR(installed.st_mode), "location");
      for (NSString *name in @[@"package.zip", @"manifest.json", @"manifest.sig", @"payload"]) if (exists(join(workspace,name))) removeOwned(join(workspace,name));
      for (int i = 0; i < 3; i++) require([fm copyItemAtPath:@(argv[i+3]) toPath:join(workspace, @[@"package.zip", @"manifest.json", @"manifest.sig"][i]) error:nullptr], "storage");
      NSDictionary *manifest = verified(workspace, trust);
      extract(join(workspace, @"package.zip"), payload); checkBundle(next, manifest);
      puts("idle"); return 0;
    }
    require([mode isEqual:@"run"] && argc == 4);
    pid_t parent = atoi(argv[3]); require(parent > 1);
#ifndef SHIORI_UPDATER_TESTING
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"dev.shiori.reader"])
      require(app.processIdentifier == parent, "instances");
#else
    require(!getenv("SHIORI_UPDATE_OTHER_INSTANCE"), "instances");
#endif
    NSDictionary *manifest = verified(workspace, trust); checkBundle(next, manifest);
    // Parent waits for this handshake before closing its stores and exiting.
    writeJSON(join(workspace, @"started.json"), @{@"pid":@(getpid()), @"parent":@(parent)});
    int waited = 0; while (kill(parent, 0) == 0 && waited++ < 600) usleep(100000);
    require(kill(parent, 0) != 0, "busy");
    // Re-extract the signed archive at commit, rejecting staging tampering.
    removeOwned(payload); verified(workspace, trust); extract(join(workspace, @"package.zip"), payload); checkBundle(next, manifest);
    writeJSON(transaction, @{@"build":manifest[@"build"]}); checkpoint("planned");
    // Same-volume exchange always leaves a complete bundle at the app path.
    require(renameatx_np(AT_FDCWD, install.fileSystemRepresentation, AT_FDCWD, next.fileSystemRepresentation, RENAME_SWAP) == 0, "storage");
    checkpoint("swapped");
    move(next, backup); checkpoint("backed-up");
    checkpoint("replaced");
    NSTask *launch = [NSTask new]; launch.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
    launch.arguments = @[@"-n",install]; NSError *error = nil;
#ifdef SHIORI_UPDATER_TESTING
    bool opened = !getenv("SHIORI_UPDATE_LAUNCH_FAIL");
#else
    bool opened = [launch launchAndReturnError:&error]; if (opened) { [launch waitUntilExit]; opened = launch.terminationStatus == 0; }
#endif
    if (!opened) {
      require(renameatx_np(AT_FDCWD, install.fileSystemRepresentation, AT_FDCWD, backup.fileSystemRepresentation, RENAME_SWAP) == 0, "storage");
      removeOwned(backup); removeOwned(transaction); throw std::runtime_error("installation");
    }
    puts("installed"); return 0;
  } catch (const std::exception &e) { fprintf(stderr, "%s\n",e.what()); return 1; }
  if (lock >= 0) close(lock);
 }
}
