#pragma once
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "board_config.h"

// Alert handed from the sensing loop to the network task (copied by value).
// Only alarms are sent; acknowledging an alarm on the device sends nothing.
// Inactive: no movement for the limit set on the web page; Resumed: the
// wearer moved again after an Inactive alert.
struct NotifyEvent {
  enum class Kind : uint8_t { Fall, Test, Inactive, Resumed };
  Kind kind = Kind::Test;
  uint32_t atMs = 0;       // millis() when it happened
  float impactG = 0;       // Fall only
  float postureDeg = 0;    // Fall only
  uint32_t stillMin = 0;   // Inactive/Resumed: minutes without movement
  uint32_t batteryMv = 0;  // <2000: no battery reading (USB power/switch off)
};

// Bounded string builder: never overflows, remembers truncation.
struct TextOut {
  char *buf;
  size_t cap, len = 0;
  bool ok = true;
  TextOut(char *b, size_t c) : buf(b), cap(c) { if (cap) buf[0] = '\0'; else ok = false; }
  void add(const char *s) { addN(s, strlen(s)); }
  void addN(const char *s, size_t n) {
    if (!ok) return;
    if (len + n >= cap) { ok = false; return; }
    memcpy(buf + len, s, n);
    len += n;
    buf[len] = '\0';
  }
  void addf(const char *format, ...) {
    if (!ok) return;
    va_list args;
    va_start(args, format);
    int n = vsnprintf(buf + len, cap - len, format, args);
    va_end(args);
    if (n < 0 || size_t(n) >= cap - len) { buf[len] = '\0'; ok = false; return; }
    len += size_t(n);
  }
  // Text placed inside HTML (Telegram parse_mode=HTML or e-mail).
  void addHtml(const char *s) {
    for (; *s && ok; ++s) {
      if (*s == '<') add("&lt;");
      else if (*s == '>') add("&gt;");
      else if (*s == '&') add("&amp;");
      else if (*s == '"') add("&quot;");
      else addN(s, 1);
    }
  }
};

enum class NotifyStyle : uint8_t { Telegram, EmailText, EmailHtml };

struct NotifyLook {
  const char *icon, *title, *lead, *action, *color, *tint;
};

inline NotifyLook notifyLook(NotifyEvent::Kind kind) {
  switch (kind) {
    case NotifyEvent::Kind::Fall:
      return {"🚨", "CẢNH BÁO TÉ NGÃ", "Thiết bị vừa ghi nhận một cú ngã và người đeo nằm yên sau đó.",
              "Hãy gọi điện hoặc đến kiểm tra người đeo ngay!", "#dc2626", "#fef2f2"};
    case NotifyEvent::Kind::Inactive:
      return {"⏸️", "CẢNH BÁO BẤT ĐỘNG", "Người đeo không cử động trong thời gian dài hơn mức đã cài đặt.",
              "Hãy gọi điện hoặc đến kiểm tra người đeo!", "#b45309", "#fffbeb"};
    case NotifyEvent::Kind::Resumed:
      return {"✅", "ĐÃ CỬ ĐỘNG TRỞ LẠI", "Người đeo đã cử động sau cảnh báo bất động.",
              nullptr, "#16a34a", "#f0fdf4"};
    default:
      return {"🔔", "TIN NHẮN THỬ NGHIỆM", "Kết nối cảnh báo Telegram/Gmail đang hoạt động bình thường.",
              nullptr, "#2563eb", "#eff6ff"};
  }
}

// Subject line (UTF-8, unencoded): "🚨 CẢNH BÁO TÉ NGÃ – <device>".
inline bool formatNotifySubject(char *out, size_t cap, NotifyEvent::Kind kind, const char *device) {
  NotifyLook look = notifyLook(kind);
  TextOut t(out, cap);
  t.addf("%s %s – %s", look.icon, look.title, device);
  return t.ok;
}

// Message body for one channel. timeText may be empty before NTP sync.
inline bool formatNotify(char *out, size_t cap, NotifyStyle style, const NotifyEvent &e,
                         const char *device, const char *timeText) {
  const NotifyLook look = notifyLook(e.kind);
  const bool fall = e.kind == NotifyEvent::Kind::Fall;
  const bool still = e.kind == NotifyEvent::Kind::Inactive || e.kind == NotifyEvent::Kind::Resumed;
  char battery[48], impact[24], posture[48], stillFor[40];
  if (e.batteryMv < 2000) {
    snprintf(battery, sizeof(battery), "không đo được (đang cắm USB?)");
  } else {
    const char *state = e.batteryMv < Board::BATTERY_LOW_MV ? "yếu, cần sạc"
                        : e.batteryMv < Board::BATTERY_RECOVER_MV ? "trung bình" : "tốt";
    snprintf(battery, sizeof(battery), "%u.%02u V · %s", unsigned(e.batteryMv / 1000),
             unsigned(e.batteryMv % 1000 / 10), state);
  }
  snprintf(impact, sizeof(impact), "%.1f g", e.impactG);
  snprintf(posture, sizeof(posture), "lệch %.0f° · %s", e.postureDeg,
           e.postureDeg >= 60 ? "đang nằm" : "nghiêng");
  if (e.stillMin >= 60)
    snprintf(stillFor, sizeof(stillFor), "%u giờ %u phút", unsigned(e.stillMin / 60), unsigned(e.stillMin % 60));
  else
    snprintf(stillFor, sizeof(stillFor), "%u phút", unsigned(e.stillMin));
  struct Row { const char *emoji, *label, *value; };
  const Row rows[] = {
    {"📟", "Thiết bị", device},
    {"🕒", "Thời gian", timeText && *timeText ? timeText : "chưa đồng bộ giờ"},
    {"💥", "Va đập", fall ? impact : nullptr},
    {"🛏", "Tư thế sau ngã", fall ? posture : nullptr},
    {"⏱", "Không cử động", still ? stillFor : nullptr},
    {"🔋", "Pin", battery},
  };
  TextOut t(out, cap);
  if (style == NotifyStyle::Telegram) {
    t.addf("%s <b>%s</b> %s\n<i>", look.icon, look.title, look.icon);
    t.addHtml(look.lead);
    t.add("</i>\n\n");
    for (const Row &r : rows) {
      if (!r.value) continue;
      t.addf("%s <b>%s:</b> ", r.emoji, r.label);
      t.addHtml(r.value);
      t.add("\n");
    }
    if (look.action) t.addf("\n👉 <b>%s</b>", look.action);
  } else if (style == NotifyStyle::EmailText) {
    t.addf("%s %s\n%s\n\n", look.icon, look.title, look.lead);
    for (const Row &r : rows)
      if (r.value) t.addf("%s: %s\n", r.label, r.value);
    if (look.action) t.addf("\n>> %s\n", look.action);
  } else {
    t.add("<!doctype html><html><head><meta charset=\"utf-8\"></head>"
          "<body style=\"margin:0;padding:24px 12px;background:#f3f4f6;"
          "font-family:Arial,Helvetica,sans-serif;color:#111827\">"
          "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" "
          "style=\"max-width:520px;margin:0 auto;background:#ffffff;border-radius:12px;"
          "overflow:hidden;border:1px solid #e5e7eb\">");
    t.addf("<tr><td style=\"background:%s;padding:22px 24px;color:#ffffff\">"
           "<div style=\"font-size:30px;line-height:1\">%s</div>"
           "<div style=\"font-size:21px;font-weight:bold;margin-top:10px;letter-spacing:.5px\">%s</div>"
           "<div style=\"font-size:14px;margin-top:6px;opacity:.92\">%s</div></td></tr>",
           look.color, look.icon, look.title, look.lead);
    t.add("<tr><td style=\"padding:8px 24px 4px\"><table role=\"presentation\" width=\"100%\" "
          "cellpadding=\"0\" cellspacing=\"0\" style=\"font-size:15px\">");
    for (const Row &r : rows) {
      if (!r.value) continue;
      t.addf("<tr><td style=\"padding:11px 0;color:#6b7280;border-bottom:1px solid #f3f4f6;width:44%%\">"
             "%s&nbsp; %s</td><td style=\"padding:11px 0;font-weight:bold;border-bottom:1px solid #f3f4f6\">",
             r.emoji, r.label);
      t.addHtml(r.value);
      t.add("</td></tr>");
    }
    t.add("</table></td></tr>");
    if (look.action)
      t.addf("<tr><td style=\"padding:16px 24px 24px\"><div style=\"background:%s;border-left:4px solid %s;"
             "padding:13px 15px;border-radius:6px;font-size:15px;font-weight:bold;color:%s\">👉 %s</div>"
             "</td></tr>", look.tint, look.color, look.color, look.action);
    t.add("<tr><td style=\"padding:12px 24px;background:#f9fafb;color:#9ca3af;font-size:12px\">"
          "Tin tự động từ thiết bị báo ngã.");
    if (e.kind == NotifyEvent::Kind::Fall)
      t.add(" Còi và đèn vẫn báo tại chỗ cho đến khi người đeo chạm để tắt.");
    t.add("</td></tr></table></body></html>");
  }
  return t.ok;
}

// JSON string body (without quotes). Returns false if it does not fit.
inline bool jsonEscape(char *out, size_t cap, const char *in) {
  TextOut t(out, cap);
  for (const unsigned char *p = reinterpret_cast<const unsigned char *>(in); *p && t.ok; ++p) {
    if (*p == '"') t.add("\\\"");
    else if (*p == '\\') t.add("\\\\");
    else if (*p == '\n') t.add("\\n");
    else if (*p < 0x20) t.addf("\\u%04x", *p);
    else t.addN(reinterpret_cast<const char *>(p), 1);
  }
  if (!t.ok && cap) out[0] = '\0';
  return t.ok;
}

// Longest prefix of s, at most max bytes, that does not split a UTF-8 character.
inline size_t utf8Prefix(const char *s, size_t max) {
  size_t n = strlen(s);
  if (n <= max) return n;
  while (max > 0 && (static_cast<unsigned char>(s[max]) & 0xC0) == 0x80) --max;
  return max;
}

// Next comma-separated item (spaces trimmed). Returns false when none is left.
inline bool nextListItem(const char *&cursor, char *out, size_t cap) {
  while (*cursor == ',' || *cursor == ' ') ++cursor;
  if (!*cursor) return false;
  size_t n = 0;
  while (*cursor && *cursor != ',') {
    if (n + 1 < cap) out[n++] = *cursor;
    ++cursor;
  }
  while (n && out[n - 1] == ' ') --n;
  out[n] = '\0';
  return n > 0;
}
