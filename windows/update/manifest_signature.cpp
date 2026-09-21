#include "manifest_signature.h"

#include <windows.h>
#include <bcrypt.h>

#include <cstring>

#pragma comment(lib, "bcrypt.lib")

namespace shiori {
bool VerifyManifestSignature(const std::vector<uint8_t>& manifest,
                             const std::vector<uint8_t>& signature,
                             const std::vector<uint8_t>& trusted_modulus) {
  if (manifest.empty() || manifest.size() > 4 * 1024 * 1024 ||
      signature.size() != 384 || trusted_modulus.size() != 384 ||
      !(trusted_modulus.front() & 0x80) || !(trusted_modulus.back() & 1)) {
    return false;
  }
  BCRYPT_ALG_HANDLE hash_algorithm = nullptr;
  BCRYPT_ALG_HANDLE rsa_algorithm = nullptr;
  BCRYPT_KEY_HANDLE key = nullptr;
  bool valid = false;
  uint8_t hash[32] = {};
  BCRYPT_RSAKEY_BLOB header = {BCRYPT_RSAPUBLIC_MAGIC, 3072, 3, 384, 0, 0};
  std::vector<uint8_t> blob(sizeof(header) + 3 + trusted_modulus.size());
  memcpy(blob.data(), &header, sizeof(header));
  const uint8_t exponent[] = {1, 0, 1};
  memcpy(blob.data() + sizeof(header), exponent, sizeof(exponent));
  memcpy(blob.data() + sizeof(header) + 3, trusted_modulus.data(), trusted_modulus.size());
  BCRYPT_PKCS1_PADDING_INFO padding = {BCRYPT_SHA256_ALGORITHM};
  if (BCryptOpenAlgorithmProvider(&hash_algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0 &&
      BCryptHash(hash_algorithm, nullptr, 0, const_cast<PUCHAR>(manifest.data()),
                 static_cast<ULONG>(manifest.size()), hash, sizeof(hash)) >= 0 &&
      BCryptOpenAlgorithmProvider(&rsa_algorithm, BCRYPT_RSA_ALGORITHM, nullptr, 0) >= 0 &&
      BCryptImportKeyPair(rsa_algorithm, nullptr, BCRYPT_RSAPUBLIC_BLOB, &key,
                          blob.data(), static_cast<ULONG>(blob.size()), 0) >= 0) {
    valid = BCryptVerifySignature(key, &padding, hash, sizeof(hash),
              const_cast<PUCHAR>(signature.data()), static_cast<ULONG>(signature.size()),
              BCRYPT_PAD_PKCS1) >= 0;
  }
  if (key) BCryptDestroyKey(key);
  if (rsa_algorithm) BCryptCloseAlgorithmProvider(rsa_algorithm, 0);
  if (hash_algorithm) BCryptCloseAlgorithmProvider(hash_algorithm, 0);
  return valid;
}
}  // namespace shiori
