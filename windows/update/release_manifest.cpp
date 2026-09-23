#include "release_manifest.h"

#include <map>
#include <memory>
#include <stdexcept>

namespace shiori::update {
namespace {
constexpr size_t kMaxManifest = 4 * 1024 * 1024;
constexpr int kMaxDepth = 16;
constexpr uint64_t kMaxBytes = 2ull * 1024 * 1024 * 1024;
constexpr size_t kMaxFiles = 10000;

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

struct Value {
  enum class Kind { null, boolean, number, string, array, object };
  Kind kind = Kind::null;
  bool boolean = false;
  int64_t number = 0;
  std::string text;
  std::vector<Value> items;
  std::map<std::string, Value> fields;
};

class Parser {
 public:
  explicit Parser(const std::string& input) : input_(input) {}

  Value Document() {
    auto value = Parse(0);
    Space();
    Require(at_ == input_.size(), "Trailing manifest data");
    return value;
  }

 private:
  void Space() {
    while (at_ < input_.size() && (input_[at_] == ' ' || input_[at_] == '\n' ||
                                   input_[at_] == '\r' || input_[at_] == '\t')) {
      ++at_;
    }
  }
  char Peek() {
    Require(at_ < input_.size(), "Truncated manifest");
    return input_[at_];
  }
  void Expect(char c) {
    Require(Peek() == c, "Malformed manifest");
    ++at_;
  }
  void Literal(const char* word) {
    for (; *word; ++word) Expect(*word);
  }

  Value Parse(int depth) {
    Require(depth < kMaxDepth, "Manifest nesting too deep");
    Space();
    Value value;
    switch (Peek()) {
      case '{':
        value.kind = Value::Kind::object;
        ++at_;
        Space();
        if (Peek() == '}') {
          ++at_;
          return value;
        }
        for (;;) {
          Space();
          auto key = String();
          Space();
          Expect(':');
          Require(value.fields.emplace(std::move(key), Parse(depth + 1)).second,
                  "Duplicate manifest field");
          Space();
          if (Peek() == '}') {
            ++at_;
            return value;
          }
          Expect(',');
        }
      case '[':
        value.kind = Value::Kind::array;
        ++at_;
        Space();
        if (Peek() == ']') {
          ++at_;
          return value;
        }
        for (;;) {
          value.items.push_back(Parse(depth + 1));
          Require(value.items.size() <= kMaxFiles, "Manifest array too large");
          Space();
          if (Peek() == ']') {
            ++at_;
            return value;
          }
          Expect(',');
        }
      case '"':
        value.kind = Value::Kind::string;
        value.text = String();
        return value;
      case 't':
        Literal("true");
        value.kind = Value::Kind::boolean;
        value.boolean = true;
        return value;
      case 'f':
        Literal("false");
        value.kind = Value::Kind::boolean;
        return value;
      case 'n':
        Literal("null");
        return value;
      default:
        value.kind = Value::Kind::number;
        value.number = Integer();
        return value;
    }
  }

  int64_t Integer() {
    const bool negative = Peek() == '-';
    if (negative) ++at_;
    const auto start = at_;
    int64_t result = 0;
    while (at_ < input_.size() && input_[at_] >= '0' && input_[at_] <= '9') {
      Require(result <= (INT64_MAX - 9) / 10, "Manifest number too large");
      result = result * 10 + (input_[at_++] - '0');
    }
    Require(at_ > start && (at_ - start == 1 || input_[start] != '0'),
            "Malformed manifest number");
    Require(at_ == input_.size() || (input_[at_] != '.' && input_[at_] != 'e' &&
                                     input_[at_] != 'E'),
            "Only integer manifest numbers are supported");
    return negative ? -result : result;
  }

  unsigned Hex4() {
    unsigned result = 0;
    for (int i = 0; i < 4; ++i) {
      const char c = Peek();
      ++at_;
      result <<= 4;
      if (c >= '0' && c <= '9') result |= c - '0';
      else if (c >= 'a' && c <= 'f') result |= c - 'a' + 10;
      else if (c >= 'A' && c <= 'F') result |= c - 'A' + 10;
      else throw std::runtime_error("Malformed manifest escape");
    }
    return result;
  }

  static void Utf8(std::string& output, unsigned code) {
    if (code < 0x80) {
      output += static_cast<char>(code);
    } else if (code < 0x800) {
      output += static_cast<char>(0xC0 | (code >> 6));
      output += static_cast<char>(0x80 | (code & 0x3F));
    } else if (code < 0x10000) {
      output += static_cast<char>(0xE0 | (code >> 12));
      output += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
      output += static_cast<char>(0x80 | (code & 0x3F));
    } else {
      output += static_cast<char>(0xF0 | (code >> 18));
      output += static_cast<char>(0x80 | ((code >> 12) & 0x3F));
      output += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
      output += static_cast<char>(0x80 | (code & 0x3F));
    }
  }

  std::string String() {
    Expect('"');
    std::string output;
    for (;;) {
      const auto c = static_cast<unsigned char>(Peek());
      ++at_;
      Require(c >= 0x20 && c < 0x80, "Unexpected manifest character");
      if (c == '"') return output;
      if (c != '\\') {
        output += static_cast<char>(c);
        continue;
      }
      const char escape = Peek();
      ++at_;
      switch (escape) {
        case '"': output += '"'; break;
        case '\\': output += '\\'; break;
        case '/': output += '/'; break;
        case 'b': output += '\b'; break;
        case 'f': output += '\f'; break;
        case 'n': output += '\n'; break;
        case 'r': output += '\r'; break;
        case 't': output += '\t'; break;
        case 'u': {
          auto code = Hex4();
          Require(code < 0xDC00 || code > 0xDFFF, "Unpaired manifest surrogate");
          if (code >= 0xD800 && code <= 0xDBFF) {
            Expect('\\');
            Expect('u');
            const auto low = Hex4();
            Require(low >= 0xDC00 && low <= 0xDFFF, "Unpaired manifest surrogate");
            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
          }
          Utf8(output, code);
          break;
        }
        default:
          throw std::runtime_error("Malformed manifest escape");
      }
    }
  }

  const std::string& input_;
  size_t at_ = 0;
};

const Value& Field(const Value& object, const char* name, Value::Kind kind) {
  Require(object.kind == Value::Kind::object, "Expected manifest object");
  const auto found = object.fields.find(name);
  Require(found != object.fields.end() && found->second.kind == kind,
          "Missing or invalid manifest field");
  return found->second;
}

const std::string& Text(const Value& object, const char* name) {
  return Field(object, name, Value::Kind::string).text;
}

int64_t Number(const Value& object, const char* name) {
  return Field(object, name, Value::Kind::number).number;
}

bool Sha256(const std::string& value) {
  return value.size() == 64 &&
         value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
}  // namespace

WindowsRelease ReadWindowsRelease(const std::string& manifest) {
  Require(!manifest.empty() && manifest.size() <= kMaxManifest, "Invalid manifest size");
  const auto root = Parser(manifest).Document();
  Require(Number(root, "schemaVersion") == 1 &&
              Text(root, "algorithm") == "rsa3072-pkcs1-sha256" &&
              Text(root, "applicationId") == "dev.shiori.reader",
          "Unsupported update manifest");
  WindowsRelease release{Text(root, "tag"), Number(root, "build"), {}};
  Require(release.build > 0, "Invalid release build");
  const Value* asset = nullptr;
  for (const auto& item : Field(root, "assets", Value::Kind::array).items) {
    if (Text(item, "platform") != "windows-x64") continue;
    Require(asset == nullptr, "Duplicate Windows asset");
    asset = &item;
  }
  Require(asset != nullptr, "Missing Windows asset");
  Require(Number(*asset, "updaterProtocol") == 1, "Unsupported updater protocol");
  uint64_t total = 0;
  for (const auto& item : Field(*asset, "files", Value::Kind::array).items) {
    const auto size = Number(item, "size");
    Require(size >= 0 && static_cast<uint64_t>(size) <= kMaxBytes, "Invalid file size");
    total += static_cast<uint64_t>(size);
    Require(total <= kMaxBytes, "Package exceeds size limit");
    const auto& digest = Text(item, "sha256");
    Require(Sha256(digest), "Invalid file SHA-256");
    release.files.push_back({Text(item, "path"), static_cast<uint64_t>(size), digest});
  }
  Require(!release.files.empty() && release.files.size() <= kMaxFiles, "Invalid file count");
  return release;
}
}  // namespace shiori::update
