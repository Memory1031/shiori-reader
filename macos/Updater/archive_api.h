#pragma once
#include <sys/types.h>
#include <sys/stat.h>
#include <stdint.h>
// macOS ships libarchive but omits its development headers from some SDKs.
// Bind only its stable public C ABI; extraction stays in the system library.
extern "C" {
struct archive;
struct archive_entry;
archive *archive_read_new(void);
int archive_read_support_format_zip(archive *);
int archive_read_support_filter_all(archive *);
int archive_read_open_filename(archive *, const char *, size_t);
int archive_read_next_header(archive *, archive_entry **);
int archive_read_free(archive *);
ssize_t archive_read_data(archive *, void *, size_t);
const char *archive_entry_pathname(archive_entry *);
const char *archive_entry_symlink(archive_entry *);
const char *archive_entry_hardlink(archive_entry *);
mode_t archive_entry_filetype(archive_entry *);
mode_t archive_entry_perm(archive_entry *);
int64_t archive_entry_size(archive_entry *);
}
constexpr int ARCHIVE_OK = 0;
constexpr int ARCHIVE_EOF = 1;
constexpr mode_t AE_IFLNK = S_IFLNK, AE_IFDIR = S_IFDIR, AE_IFREG = S_IFREG;
