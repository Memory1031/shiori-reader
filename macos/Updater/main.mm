#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <sys/mount.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>
#include <set>
#include <vector>
#include <stdexcept>
#include <cerrno>
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
  require(data && data.length > 0 && data.length <= 4 * 1024 * 1024);
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
static void checkpoint(const char *stage);

static NSData *systemTool(NSString *workspace, NSString *program, NSArray<NSString *> *arguments) {
  NSString *output = join(workspace, @"tool-output.plist");
  int fd = open(output.fileSystemRepresentation, O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW, 0600);
  require(fd >= 0, "storage");
  NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
  NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:program];
  task.arguments = arguments; task.standardOutput = handle; task.standardError = NSFileHandle.fileHandleWithNullDevice;
  require([task launchAndReturnError:nullptr], "installation");
  int waited = 0; while (task.running && waited++ < 600) usleep(100000);
  if (task.running) {
    [task terminate]; waited = 0; while (task.running && waited++ < 50) usleep(100000);
    if (task.running) kill(task.processIdentifier, SIGKILL);
  }
  [task waitUntilExit]; [handle closeFile];
  require(task.terminationStatus == 0, "installation");
  require([[fm attributesOfItemAtPath:output error:nullptr][NSFileSize] unsignedLongLongValue] <= 65536);
  return [NSData dataWithContentsOfFile:output];
}

// Only the fixed mountpoint in our owned workspace can be detached, including
// after a helper crash. Never trust a device or path read from the DMG/journal.
static void cleanMount(NSString *workspace) {
  NSString *mount = join(workspace, @"volume");
  struct stat st;
  if (lstat(mount.fileSystemRepresentation, &st) != 0) { require(errno == ENOENT, "storage"); return; }
  require(S_ISDIR(st.st_mode), "workspaceConflict");
  struct statfs *mounts; int count = getmntinfo(&mounts, MNT_NOWAIT);
  require(count > 0, "storage");
  bool mounted = false;
  for (int i = 0; i < count; i++) {
    if (strcmp(mounts[i].f_mntonname, mount.fileSystemRepresentation)) continue;
    require((mounts[i].f_flags & MNT_RDONLY) && !strncmp(mounts[i].f_mntfromname, "/dev/disk", 9), "workspaceConflict");
    mounted = true; break;
  }
  if (mounted) systemTool(workspace, @"/usr/bin/hdiutil", @[@"detach", mount]);
  else require(st.st_uid == getuid(), "workspaceConflict");
  require(rmdir(mount.fileSystemRepresentation) == 0 || errno == ENOENT, "storage");
}

static void validateTree(NSString *bundle) {
  struct stat root; require(lstat(bundle.fileSystemRepresentation, &root) == 0 && S_ISDIR(root.st_mode));
  char base[PATH_MAX]; require(realpath(bundle.fileSystemRepresentation, base));
  std::string prefix = std::string(base) + "/";
  NSDirectoryEnumerator *entries = [fm enumeratorAtPath:bundle];
  int count = 0; int64_t total = 0;
  for (NSString *relative in entries) {
    require(++count <= 20000 && safePath(relative));
    NSString *path = join(bundle, relative); struct stat st;
    require(lstat(path.fileSystemRepresentation, &st) == 0 && !(st.st_mode & 07000));
    if (S_ISLNK(st.st_mode)) {
      NSString *target = [fm destinationOfSymbolicLinkAtPath:path error:nullptr];
      char resolved[PATH_MAX]; require(target && !target.isAbsolutePath && realpath(path.fileSystemRepresentation, resolved));
      require(std::string(resolved).rfind(prefix, 0) == 0);
      [entries skipDescendants];
    } else if (S_ISREG(st.st_mode)) {
      require(st.st_nlink == 1 && st.st_size >= 0 && (total += st.st_size) <= 2LL * 1024 * 1024 * 1024);
    } else require(S_ISDIR(st.st_mode));
  }
}

static void extract(NSString *dmg, NSString *root) {
  NSString *workspace = root.stringByDeletingLastPathComponent, *mount = join(workspace, @"volume");
  cleanMount(workspace);
  require([fm createDirectoryAtPath:mount withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nullptr], "storage");
  try {
    NSData *output = systemTool(workspace, @"/usr/bin/hdiutil", @[@"attach", @"-readonly", @"-nobrowse", @"-noautoopen", @"-mountpoint", mount, @"-plist", dmg]);
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:output options:NSPropertyListImmutable format:nullptr error:nullptr];
    bool found = false;
    for (NSDictionary *entity in plist[@"system-entities"]) if ([entity[@"mount-point"] isEqual:mount]) found = true;
    require(found); checkpoint("mounted");
    NSString *bundle = join(mount, @"Shiori.app"); validateTree(bundle);
    require([fm createDirectoryAtPath:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nullptr], "storage");
    systemTool(workspace, @"/usr/bin/ditto", @[@"--norsrc", @"--noqtn", bundle, join(root, @"Shiori.app")]);
    validateTree(join(root, @"Shiori.app"));
  } catch (...) { cleanMount(workspace); throw; }
  cleanMount(workspace);
}
static NSDictionary *verified(NSString *workspace, NSDictionary *trust) {
  NSData *raw = [NSData dataWithContentsOfFile:join(workspace, @"manifest.json")];
  verifySignature(raw, [NSData dataWithContentsOfFile:join(workspace, @"manifest.sig")], trust);
  NSDictionary *m = json(raw), *identity = trust[@"identity"];
  require([m[@"schemaVersion"] isEqual:@2] && [m[@"applicationId"] isEqual:@"dev.shiori.reader"] &&
    [m[@"keyId"] isEqual:trust[@"publicKey"][@"keyId"]] &&
    [m[@"algorithm"] isEqual:@"rsa3072-pkcs1-sha256"]);
  require([m[@"build"] longLongValue] > [identity[@"build"] longLongValue] &&
    [m[@"version"] compare:identity[@"version"] options:NSNumericSearch] != NSOrderedAscending);
  NSArray *assets = m[@"assets"]; require([assets isKindOfClass:NSArray.class] && assets.count == 4);
  NSDictionary *asset = nil; NSMutableSet *platforms = [NSMutableSet set];
  for (NSDictionary *item in assets) {
    NSString *platform = item[@"platform"];
    require([@[@"android", @"windows-x64-portable", @"windows-x64-setup", @"macos-universal"] containsObject:platform] && ![platforms containsObject:platform]);
    [platforms addObject:platform];
    if ([platform isEqual:@"macos-universal"]) asset = item;
  }
  require(asset && [asset[@"updaterProtocol"] isEqual:@2]);
  require([asset[@"name"] isEqual:[NSString stringWithFormat:@"shiori-reader-%@-macos-universal.dmg", m[@"tag"]]]);
  NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
  NSString *currentOS = [NSString stringWithFormat:@"%ld.%ld.%ld", os.majorVersion, os.minorVersion, os.patchVersion];
  require([asset[@"minimumSystem"] isKindOfClass:NSString.class] && [currentOS compare:asset[@"minimumSystem"] options:NSNumericSearch] != NSOrderedAscending, "location");
  long long size = [asset[@"size"] longLongValue]; require(size > 0 && size <= 2LL * 1024 * 1024 * 1024);
  NSString *package = join(workspace, @"package.dmg");
  require([[fm attributesOfItemAtPath:package error:nullptr][NSFileSize] longLongValue] == size &&
    [digest(package) isEqual:asset[@"sha256"]]);
  return m;
}
static void checkBundle(NSString *bundle, NSDictionary *manifest) {
  validateTree(bundle);
#ifndef SHIORI_UPDATER_TESTING
  SecStaticCodeRef code = nullptr;
  require(SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:bundle], kSecCSDefaultFlags, &code) == errSecSuccess);
  OSStatus signature = SecStaticCodeCheckValidity(code, kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures, nullptr);
  CFRelease(code); require(signature == errSecSuccess);
#endif
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
  const char *paused = getenv("SHIORI_UPDATE_PAUSE"), *gate = getenv("SHIORI_UPDATE_GATE");
  if (paused && gate && !strcmp(paused, stage)) {
    writeJSON([@(gate) stringByAppendingString:@".ready"], @{});
    NSString *release = [@(gate) stringByAppendingString:@".release"];
    int waited = 0; while (!exists(release) && waited++ < 1000) usleep(10000);
    require(exists(release), "busy");
  }
#endif
}
static void checkInstances(pid_t allowed) {
#ifndef SHIORI_UPDATER_TESTING
  for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"dev.shiori.reader"])
    if (app.processIdentifier != allowed)
      require(kill(app.processIdentifier, 0) != 0 && errno == ESRCH, "instances");
#else
  require(!getenv("SHIORI_UPDATE_OTHER_INSTANCE") && (allowed != 0 || !getenv("SHIORI_UPDATE_LATE_INSTANCE")), "instances");
#endif
}
static int lockCommit(const char *parent) {
  int fd = open(parent, O_RDONLY | O_CLOEXEC | O_NOFOLLOW); require(fd >= 0, "location");
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
    int code = errno; close(fd);
    require(false, code == EWOULDBLOCK ? "instances" : "location");
  }
  return fd;
}
static bool entryExists(NSString *path) {
  struct stat st;
  if (lstat(path.fileSystemRepresentation, &st) == 0) return true;
  require(errno == ENOENT, "storage"); return false;
}

// Retire an idle, entirely owned v1 workspace, without accepting a v1 manifest
// or launching a legacy executable. The shared flock excludes old helpers.
static void retireLegacyWorkspace(NSString *workspace, NSString *install) {
  struct stat installed;
  require(lstat(install.fileSystemRepresentation, &installed) == 0 && S_ISDIR(installed.st_mode), "workspaceConflict");
  for (NSString *name in @[@"transaction.json", @"previous.app"])
    require(!entryExists(join(workspace, name)), "workspaceConflict");
  NSArray *disposable = @[@"package.zip", @"manifest.json", @"manifest.sig", @"payload", @"started.json", @"handoff"];
  NSArray *names = [fm contentsOfDirectoryAtPath:workspace error:nullptr]; require(names, "storage");
  for (NSString *name in names) {
    require([disposable containsObject:name] || [@[@"owner.json", @"lock"] containsObject:name], "workspaceConflict");
    NSString *path = join(workspace, name); struct stat st;
    require(lstat(path.fileSystemRepresentation, &st) == 0 && st.st_uid == getuid(), "workspaceConflict");
    if ([name isEqual:@"payload"]) {
      require(S_ISDIR(st.st_mode), "workspaceConflict"); validateTree(path);
    } else require(S_ISREG(st.st_mode) && st.st_nlink == 1, "workspaceConflict");
  }
  for (NSString *name in disposable) if (entryExists(join(workspace, name))) removeOwned(join(workspace, name));
  writeJSON(join(workspace, @"owner.json"), @{@"installation":install, @"format":@"ShioriMacUpdate/2"});
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
    if (!entryExists(workspace)) {
      if ([mode isEqual:@"recover"]) { puts("idle"); return 0; }
      require([fm createDirectoryAtPath:workspace withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nullptr], "storage");
      writeJSON(marker, @{@"installation":install, @"format":@"ShioriMacUpdate/2"});
    }
    struct stat st; require(lstat(workspace.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode) && st.st_uid == getuid() && !(st.st_mode & 0022), "workspaceConflict");
    require(lstat(marker.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == getuid() && st.st_nlink == 1 && st.st_size <= 4096, "workspaceConflict");
    NSDictionary *owner = json([NSData dataWithContentsOfFile:marker]);
    bool legacy = [owner[@"format"] isEqual:@"ShioriMacUpdate/1"];
    require(owner.count == 2 && [owner[@"installation"] isEqual:install] &&
      (legacy || [owner[@"format"] isEqual:@"ShioriMacUpdate/2"]), "workspaceConflict");
    lock = open(join(workspace, @"lock").fileSystemRepresentation, O_RDWR|O_CREAT|O_NOFOLLOW, 0600);
    require(lock >= 0 && fstat(lock, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == getuid() && st.st_nlink == 1, "workspaceConflict");
    require(flock(lock, LOCK_EX|LOCK_NB) == 0, "busy");
    if (legacy) retireLegacyWorkspace(workspace, install);
    NSString *backup = join(workspace, @"previous.app"), *payload = join(workspace, @"payload"), *next = join(payload, @"Shiori.app"), *transaction = join(workspace, @"transaction.json");
    NSDictionary *trust = json([NSData dataWithBytes:SHIORI_UPDATE_TRUST length:strlen(SHIORI_UPDATE_TRUST)]);
    cleanMount(workspace);
    if ([mode isEqual:@"recover"]) {
      if (!exists(transaction)) { puts("idle"); return 0; }
      NSDictionary *record = json([NSData dataWithContentsOfFile:transaction]);
      if (!exists(install) && exists(backup)) {
        int lease = lockCommit(parentPath); checkInstances(0);
        move(backup, install); removeOwned(transaction); close(lease); puts("failed"); return 0;
      }
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
      for (NSString *name in @[@"package.dmg", @"manifest.json", @"manifest.sig", @"payload"]) if (exists(join(workspace,name))) removeOwned(join(workspace,name));
      for (int i = 0; i < 3; i++) require([fm copyItemAtPath:@(argv[i+3]) toPath:join(workspace, @[@"package.dmg", @"manifest.json", @"manifest.sig"][i]) error:nullptr], "storage");
      NSDictionary *manifest = verified(workspace, trust);
      extract(join(workspace, @"package.dmg"), payload); checkBundle(next, manifest);
      puts("idle"); return 0;
    }
    require([mode isEqual:@"run"] && argc == 4);
    pid_t parent = atoi(argv[3]); require(parent > 1);
    checkInstances(parent);
    NSDictionary *manifest = verified(workspace, trust); checkBundle(next, manifest);
    // Parent waits for this handshake before closing its stores and exiting.
    writeJSON(join(workspace, @"started.json"), @{@"pid":@(getpid()), @"parent":@(parent)});
    int waited = 0; while (kill(parent, 0) == 0 && waited++ < 600) usleep(100000);
    require(kill(parent, 0) != 0, "busy");
    // Re-mount and copy the signed disk image at commit, rejecting staging tampering.
    removeOwned(payload); verified(workspace, trust); extract(join(workspace, @"package.dmg"), payload); checkBundle(next, manifest);
    checkpoint("before-commit");
    int lease = lockCommit(parentPath); checkpoint("committing"); checkInstances(0);
    writeJSON(transaction, @{@"build":manifest[@"build"]}); checkpoint("planned");
    // Same-volume exchange always leaves a complete bundle at the app path.
    require(renameatx_np(AT_FDCWD, install.fileSystemRepresentation, AT_FDCWD, next.fileSystemRepresentation, RENAME_SWAP) == 0, "storage");
    checkpoint("swapped");
    move(next, backup); checkpoint("backed-up");
    checkpoint("replaced");
    // A relaunched app can acquire its lifetime lease only after the swap.
    close(lease);
    NSTask *launch = [NSTask new]; launch.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
    launch.arguments = @[@"-n",install]; NSError *error = nil;
#ifdef SHIORI_UPDATER_TESTING
    bool opened = !getenv("SHIORI_UPDATE_LAUNCH_FAIL");
#else
    bool opened = [launch launchAndReturnError:&error]; if (opened) { [launch waitUntilExit]; opened = launch.terminationStatus == 0; }
#endif
    if (!opened) {
      lease = lockCommit(parentPath); checkInstances(0);
      require(renameatx_np(AT_FDCWD, install.fileSystemRepresentation, AT_FDCWD, backup.fileSystemRepresentation, RENAME_SWAP) == 0, "storage");
      removeOwned(backup); removeOwned(transaction); close(lease); throw std::runtime_error("installation");
    }
    puts("installed"); return 0;
  } catch (const std::exception &e) { fprintf(stderr, "%s\n",e.what()); return 1; }
  if (lock >= 0) close(lock);
 }
}
