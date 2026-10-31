#pragma once
// Just enough JSON reading for Firebase REST replies (sign-in, /control).
// Pointers walk the original text; nothing is allocated. Every function
// returns nullptr/false on malformed input instead of guessing.
#include <stddef.h>
#include <stdint.h>
#include <string.h>

inline const char *jsonWs(const char *p) {
  while (p && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) ++p;
  return p;
}

inline const char *jsonSkipString(const char *p) {
  if (!p || *p != '"') return nullptr;
  for (++p; *p; ++p) {
    if (*p == '\\') { if (!*++p) return nullptr; }
    else if (*p == '"') return p + 1;
  }
  return nullptr;
}

// Pointer just after the value starting at p (after whitespace), or nullptr.
inline const char *jsonSkipValue(const char *p, int depth = 0) {
  p = jsonWs(p);
  if (!p || !*p || depth > 16) return nullptr;
  if (*p == '"') return jsonSkipString(p);
  if (*p == '{' || *p == '[') {
    const char close = *p == '{' ? '}' : ']';
    p = jsonWs(p + 1);
    if (p && *p == close) return p + 1;
    for (;;) {
      if (close == '}') {
        p = jsonSkipString(jsonWs(p));
        p = jsonWs(p);
        if (!p || *p != ':') return nullptr;
        ++p;
      }
      p = jsonWs(jsonSkipValue(p, depth + 1));
      if (!p) return nullptr;
      if (*p == close) return p + 1;
      if (*p != ',') return nullptr;
      ++p;
    }
  }
  const char *start = p; // number, true, false, null
  while (*p && strchr("+-.0123456789eEtrufalsn", *p)) ++p;
  return p > start ? p : nullptr;
}

// Value of member `key` of the object at obj (direct children only).
inline const char *jsonMember(const char *obj, const char *key) {
  const char *p = jsonWs(obj);
  if (!p || *p != '{') return nullptr;
  p = jsonWs(p + 1);
  if (*p == '}') return nullptr;
  const size_t keyLen = strlen(key);
  for (;;) {
    const char *name = jsonWs(p), *afterName = jsonSkipString(name);
    if (!afterName) return nullptr;
    p = jsonWs(afterName);
    if (*p != ':') return nullptr;
    const char *value = jsonWs(p + 1);
    // Keys we look up never contain escapes, so a plain compare is exact.
    if (size_t(afterName - name - 2) == keyLen && memcmp(name + 1, key, keyLen) == 0) return value;
    p = jsonWs(jsonSkipValue(value));
    if (!p || *p != ',') return nullptr;
    ++p;
  }
}

// Decodes the string at v into out (UTF-8). False if not a string or too long.
inline bool jsonString(const char *v, char *out, size_t cap) {
  v = jsonWs(v);
  if (!v || *v != '"' || !cap) return false;
  size_t n = 0;
  for (++v; *v != '"'; ++v) {
    if (!*v) return false;
    char c = *v;
    if (c == '\\') {
      ++v;
      switch (*v) {
        case '"': case '\\': case '/': c = *v; break;
        case 'n': c = '\n'; break;
        case 't': c = '\t'; break;
        case 'r': c = '\r'; break;
        case 'b': c = '\b'; break;
        case 'f': c = '\f'; break;
        case 'u': {
          unsigned code = 0;
          for (int i = 1; i <= 4; ++i) {
            char h = v[i];
            unsigned d = h >= '0' && h <= '9' ? unsigned(h - '0')
                       : h >= 'a' && h <= 'f' ? unsigned(h - 'a' + 10)
                       : h >= 'A' && h <= 'F' ? unsigned(h - 'A' + 10) : 16u;
            if (d > 15) return false;
            code = code * 16 + d;
          }
          v += 4;
          if (code >= 0xD800 && code <= 0xDFFF) return false; // No surrogate pairs needed here.
          char utf8[3];
          size_t len;
          if (code < 0x80) { utf8[0] = char(code); len = 1; }
          else if (code < 0x800) { utf8[0] = char(0xC0 | code >> 6); utf8[1] = char(0x80 | (code & 0x3F)); len = 2; }
          else {
            utf8[0] = char(0xE0 | code >> 12); utf8[1] = char(0x80 | ((code >> 6) & 0x3F));
            utf8[2] = char(0x80 | (code & 0x3F)); len = 3;
          }
          if (code == 0 || n + len >= cap) return false;
          memcpy(out + n, utf8, len);
          n += len;
          continue;
        }
        default: return false;
      }
    }
    if (n + 1 >= cap) return false;
    out[n++] = c;
  }
  out[n] = '\0';
  return true;
}

inline bool jsonBool(const char *v, bool &out) {
  v = jsonWs(v);
  if (v && strncmp(v, "true", 4) == 0) { out = true; return true; }
  if (v && strncmp(v, "false", 5) == 0) { out = false; return true; }
  return false;
}

// Non-negative integer (Firebase server timestamps in ms).
inline bool jsonUint64(const char *v, uint64_t &out) {
  v = jsonWs(v);
  if (!v || *v < '0' || *v > '9') return false;
  uint64_t n = 0;
  for (; *v >= '0' && *v <= '9'; ++v) {
    if (n > (UINT64_MAX - 9) / 10) return false;
    n = n * 10 + uint64_t(*v - '0');
  }
  if (*v == '.' || *v == 'e' || *v == 'E') return false;
  out = n;
  return true;
}
