#pragma once

#include <cstdint>
#include <vector>

namespace shiori {
// RSA-3072, exponent 65537, PKCS#1 v1.5 with SHA-256. The caller supplies
// the trusted modulus from the installed application, not from the manifest.
bool VerifyManifestSignature(const std::vector<uint8_t>& manifest,
                             const std::vector<uint8_t>& signature,
                             const std::vector<uint8_t>& trusted_modulus);
}  // namespace shiori
