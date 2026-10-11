#pragma once
// Alert destinations the user can change from the web page (stored in NVS).
// Credentials (bot token, sending Gmail account) stay in secrets.h; only the
// on/off switches, the recipients and the inactivity limit live here. Every value is validated
// before use: recipients end up in JSON bodies and SMTP command lines.
#include <ctype.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "notify_format.h"

struct NotifySettings {
  static constexpr size_t CHAT_ITEM = 32, MAIL_ITEM = 96, MAX_ITEMS = 5;
  static constexpr uint16_t INACTIVE_DEFAULT_MIN = 60, INACTIVE_MAX_MIN = 1440;
  bool telegramOn = false, gmailOn = false;
  uint16_t inactiveMin = INACTIVE_DEFAULT_MIN; // Inactivity alert after N minutes, 0 = off
  char chatIds[MAX_ITEMS * (CHAT_ITEM + 2)] = "";  // "123, -100456, @kenh"
  char emailTo[MAX_ITEMS * (MAIL_ITEM + 2)] = "";  // "a@x.vn, b@y.com"
};

// Telegram chat: numeric id (groups are negative) or @public_channel.
inline bool validChatId(const char *s) {
  size_t n = strlen(s);
  if (n == 0 || n >= NotifySettings::CHAT_ITEM) return false;
  if (*s == '@') {
    if (n < 6) return false; // Telegram usernames have at least 5 characters.
    for (const char *p = s + 1; *p; ++p)
      if (!isalnum(static_cast<unsigned char>(*p)) && *p != '_') return false;
    return true;
  }
  const char *p = *s == '-' ? s + 1 : s;
  if (!*p) return false;
  for (; *p; ++p)
    if (!isdigit(static_cast<unsigned char>(*p))) return false;
  return true;
}

// Deliberately strict subset of RFC 5321: no spaces, quotes or control
// characters, so an address can never inject an SMTP command or header.
inline bool validEmail(const char *s) {
  size_t n = strlen(s);
  const char *at = strchr(s, '@');
  if (n >= NotifySettings::MAIL_ITEM || !at || at == s || strchr(at + 1, '@')) return false;
  for (const char *p = s; p < at; ++p) {
    unsigned char c = static_cast<unsigned char>(*p);
    if (!isalnum(c) && !strchr(".!#$%&'*+/=?^_`{|}~-", c)) return false;
  }
  if (*s == '.' || at[-1] == '.' || strstr(s, "..")) return false;
  const char *domain = at + 1;
  size_t dn = strlen(domain);
  if (dn < 3 || !strchr(domain, '.') || domain[0] == '.' || domain[0] == '-' ||
      domain[dn - 1] == '.' || domain[dn - 1] == '-') return false;
  for (const char *p = domain; *p; ++p) {
    unsigned char c = static_cast<unsigned char>(*p);
    if (!isalnum(c) && c != '-' && c != '.') return false;
  }
  return true;
}

enum class ListError : uint8_t { None, Invalid, TooMany, TooLong };

// Cleans a comma/space/newline separated list into "a, b, c". On failure
// `bad` holds the offending item (if any) and `out` is left unchanged.
inline ListError normalizeList(const char *in, char *out, size_t cap, bool (*valid)(const char *),
                               size_t itemCap, char *bad, size_t badCap) {
  char result[NotifySettings::MAX_ITEMS * (NotifySettings::MAIL_ITEM + 2)];
  TextOut t(result, cap < sizeof(result) ? cap : sizeof(result));
  if (bad && badCap) bad[0] = '\0';
  size_t count = 0;
  for (const char *p = in; *p;) {
    while (*p == ',' || *p == ';' || isspace(static_cast<unsigned char>(*p))) ++p;
    if (!*p) break;
    const char *start = p;
    while (*p && *p != ',' && *p != ';' && !isspace(static_cast<unsigned char>(*p))) ++p;
    size_t n = size_t(p - start);
    char item[NotifySettings::MAIL_ITEM + 1];
    size_t keep = n < sizeof(item) - 1 ? n : sizeof(item) - 1;
    memcpy(item, start, keep);
    item[keep] = '\0';
    if (bad && badCap) snprintf(bad, badCap, "%s", item);
    if (n >= itemCap || !valid(item)) return ListError::Invalid;
    if (++count > NotifySettings::MAX_ITEMS) return ListError::TooMany;
    if (count > 1) t.add(", ");
    t.add(item);
    if (!t.ok) return ListError::TooLong;
  }
  if (bad && badCap) bad[0] = '\0';
  memcpy(out, result, t.len + 1);
  return ListError::None;
}

inline ListError normalizeChatIds(const char *in, char *out, char *bad, size_t badCap) {
  return normalizeList(in, out, sizeof(NotifySettings::chatIds), validChatId,
                       NotifySettings::CHAT_ITEM, bad, badCap);
}
inline ListError normalizeEmails(const char *in, char *out, char *bad, size_t badCap) {
  return normalizeList(in, out, sizeof(NotifySettings::emailTo), validEmail,
                       NotifySettings::MAIL_ITEM, bad, badCap);
}

inline void describeListError(char *out, size_t cap, const char *what, ListError err, const char *bad) {
  if (err == ListError::TooMany)
    snprintf(out, cap, "Tối đa %u %s.", unsigned(NotifySettings::MAX_ITEMS), what);
  else if (err == ListError::TooLong)
    snprintf(out, cap, "Danh sách %s quá dài.", what);
  else
    snprintf(out, cap, "%s không hợp lệ: \"%.40s\"", what, bad);
}

// Whole number of minutes typed on the local page: digits only.
inline bool parseMinutes(const char *s, uint32_t &out) {
  uint32_t n = 0;
  if (!*s) return false;
  for (; *s; ++s) {
    if (!isdigit(static_cast<unsigned char>(*s)) || n > 100000) return false;
    n = n * 10 + uint32_t(*s - '0');
  }
  out = n;
  return true;
}

// Settings requested by the local page or the cloud page. telegramAvailable /
// gmailAvailable: credentials present in secrets.h. On failure `message`
// says why (Vietnamese, shown to the user) and `out` must not be used.
inline bool buildSettings(NotifySettings &out, bool telegramOn, bool gmailOn, const char *chats,
                          const char *mails, uint32_t inactiveMin, bool telegramAvailable,
                          bool gmailAvailable, char *message, size_t cap) {
  char bad[NotifySettings::MAIL_ITEM + 1];
  if (inactiveMin > NotifySettings::INACTIVE_MAX_MIN) {
    snprintf(message, cap, "Cảnh báo bất động: tối đa %u phút (24 giờ), 0 để tắt.",
             unsigned(NotifySettings::INACTIVE_MAX_MIN));
    return false;
  }
  out.inactiveMin = uint16_t(inactiveMin);
  out.telegramOn = telegramOn;
  out.gmailOn = gmailOn;
  ListError err = normalizeChatIds(chats, out.chatIds, bad, sizeof(bad));
  if (err != ListError::None) { describeListError(message, cap, "Chat ID", err, bad); return false; }
  err = normalizeEmails(mails, out.emailTo, bad, sizeof(bad));
  if (err != ListError::None) { describeListError(message, cap, "Email", err, bad); return false; }
  const char *problem = nullptr;
  if (telegramOn && !telegramAvailable)
    problem = "Chưa có TELEGRAM_BOT_TOKEN trong secrets.h, không bật được Telegram.";
  else if (gmailOn && !gmailAvailable)
    problem = "Chưa có tài khoản Gmail gửi trong secrets.h, không bật được Gmail.";
  else if (telegramOn && !*out.chatIds)
    problem = "Bật Telegram thì cần ít nhất một Chat ID.";
  else if (gmailOn && !*out.emailTo)
    problem = "Bật Gmail thì cần ít nhất một email nhận.";
  if (problem) { snprintf(message, cap, "%s", problem); return false; }
  return true;
}

inline bool sameSettings(const NotifySettings &a, const NotifySettings &b) {
  return a.telegramOn == b.telegramOn && a.gmailOn == b.gmailOn && a.inactiveMin == b.inactiveMin &&
         strcmp(a.chatIds, b.chatIds) == 0 && strcmp(a.emailTo, b.emailTo) == 0;
}
