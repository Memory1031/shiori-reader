import Foundation
import Darwin

/// The parent inode survives app exchange and needs no writable startup marker.
func acquireInstallationLease(_ application: URL) throws -> Int32 {
  let parent = application.deletingLastPathComponent().resolvingSymlinksInPath()
  let fd = open(parent.path, O_RDONLY | O_CLOEXEC)
  guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
  guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
    let code = errno
    close(fd)
    throw POSIXError(POSIXErrorCode(rawValue:code) ?? .EIO)
  }
  return fd
}
