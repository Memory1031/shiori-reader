#include "../windows/update/manifest_signature.h"

#include <fstream>
#include <iterator>
#include <iostream>

std::vector<uint8_t> Read(const char* path) {
  std::ifstream stream(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}

int main(int argc, char** argv) {
  if (argc != 4) return 2;
  auto manifest = Read(argv[1]);
  auto signature = Read(argv[2]);
  auto modulus = Read(argv[3]);
  if (!shiori::VerifyManifestSignature(manifest, signature, modulus)) return 3;
  manifest[0] ^= 1;
  if (shiori::VerifyManifestSignature(manifest, signature, modulus)) return 4;
  manifest[0] ^= 1;
  signature[0] ^= 1;
  if (shiori::VerifyManifestSignature(manifest, signature, modulus)) return 5;
  signature[0] ^= 1;
  modulus[8] ^= 1;
  if (shiori::VerifyManifestSignature(manifest, signature, modulus)) return 6;
  if (shiori::VerifyManifestSignature({}, signature, modulus)) return 7;
  std::cout << "Windows CNG accepted valid fixture and rejected tampered manifest, signature and key.\n";
  return 0;
}
