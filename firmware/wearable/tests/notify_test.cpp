#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "notify_format.h"
#include "notify_settings.h"

static char out[4096];

int main() {
  NotifyEvent e;
  e.kind = NotifyEvent::Kind::Fall;
  e.impactG = 2.64f;
  e.postureDeg = 87.4f;
  e.batteryMv = 3857;
  const char *when = "08:15:00 · 03/10/2026";

  assert(formatNotify(out, sizeof(out), NotifyStyle::Telegram, e, "Ông <Ba> & Bà", when));
  assert(strstr(out, "🚨 <b>CẢNH BÁO TÉ NGÃ</b> 🚨"));
  assert(strstr(out, "<b>Thiết bị:</b> Ông &lt;Ba&gt; &amp; Bà")); // Name cannot break HTML.
  assert(strstr(out, "<b>Thời gian:</b> 08:15:00 · 03/10/2026"));
  assert(strstr(out, "<b>Va đập:</b> 2.6 g") && strstr(out, "lệch 87° · đang nằm"));
  assert(strstr(out, "3.85 V · tốt") && strstr(out, "👉 <b>Hãy gọi điện"));
  printf("--- Telegram ---\n%s\n", out);

  assert(formatNotify(out, sizeof(out), NotifyStyle::EmailHtml, e, "Ông <Ba>", when));
  assert(strstr(out, "<!doctype html>") && strstr(out, "#dc2626") && strstr(out, "Ông &lt;Ba&gt;"));
  assert(strstr(out, "</html>") && strlen(out) < 3584); // Fits notifier's buffer.
  FILE *html = fopen("build/tests/notify_preview.html", "wb");
  if (html) { fputs(out, html); fclose(html); }

  assert(formatNotify(out, sizeof(out), NotifyStyle::EmailText, e, "Ong Ba", when));
  assert(strstr(out, "Thiết bị: Ong Ba\n") && strstr(out, ">> Hãy gọi điện"));
  assert(strlen(out) < 640);

  e.kind = NotifyEvent::Kind::Resumed;
  e.batteryMv = 1667;
  assert(formatNotify(out, sizeof(out), NotifyStyle::Telegram, e, "X", ""));
  assert(strstr(out, "ĐÃ CỬ ĐỘNG TRỞ LẠI") && strstr(out, "chưa đồng bộ giờ"));
  assert(strstr(out, "không đo được") && !strstr(out, "Va đập") && !strstr(out, "Tư thế"));
  e.batteryMv = 3420;
  formatNotify(out, sizeof(out), NotifyStyle::EmailText, e, "X", nullptr);
  assert(strstr(out, "3.42 V · yếu, cần sạc"));
  e.batteryMv = 3600;
  formatNotify(out, sizeof(out), NotifyStyle::EmailText, e, "X", nullptr);
  assert(strstr(out, "3.60 V · trung bình"));
  // Inactivity alert carries the still time.
  NotifyEvent still;
  still.kind = NotifyEvent::Kind::Inactive;
  still.stillMin = 75;
  still.batteryMv = 3900;
  assert(formatNotify(out, sizeof(out), NotifyStyle::Telegram, still, "Ong Ba", when));
  assert(strstr(out, "<b>CẢNH BÁO BẤT ĐỘNG</b>") && strstr(out, "<b>Không cử động:</b> 1 giờ 15 phút"));
  assert(!strstr(out, "Nhịp tim") && !strstr(out, "Va đập"));
  assert(strstr(out, "👉 <b>Hãy gọi điện hoặc đến kiểm tra"));
  printf("--- Telegram (bat dong) ---\n%s\n", out);
  assert(formatNotify(out, sizeof(out), NotifyStyle::EmailHtml, still, "Ong Ba", when));
  assert(strstr(out, "#b45309") && !strstr(out, "Còi và đèn"));
  assert(strlen(out) < 3584);
  assert(formatNotify(out, sizeof(out), NotifyStyle::EmailText, still, "May bao nga - Ong Ba", when));
  assert(strlen(out) < 640);
  still.kind = NotifyEvent::Kind::Resumed;
  still.stillMin = 42;
  assert(formatNotify(out, sizeof(out), NotifyStyle::Telegram, still, "X", when));
  assert(strstr(out, "ĐÃ CỬ ĐỘNG TRỞ LẠI") && strstr(out, "Không cử động:</b> 42 phút"));
  assert(!strstr(out, "Nhịp tim") && !strstr(out, "👉"));

  e.kind = NotifyEvent::Kind::Test;
  assert(formatNotify(out, sizeof(out), NotifyStyle::Telegram, e, "X", ""));
  assert(strstr(out, "THỬ NGHIỆM") && !strstr(out, "👉"));
  assert(!formatNotify(out, 60, NotifyStyle::EmailHtml, e, "X", "")); // Truncation reported.
  assert(strlen(out) < 60);

  char subject[160];
  assert(formatNotifySubject(subject, sizeof(subject), NotifyEvent::Kind::Fall, "Ong Ba"));
  assert(strcmp(subject, "🚨 CẢNH BÁO TÉ NGÃ – Ong Ba") == 0);
  for (size_t at = 0, n; subject[at]; at += n) { // Header chunks never split a character.
    n = utf8Prefix(subject + at, 10);
    assert(n > 0 && (static_cast<unsigned char>(subject[at + n]) & 0xC0) != 0x80);
  }
  assert(utf8Prefix("abc", 10) == 3);

  char json[64];
  assert(jsonEscape(json, sizeof(json), "a\"b\\c\nd\te"));
  assert(strcmp(json, "a\\\"b\\\\c\\nd\\u0009e") == 0);
  assert(jsonEscape(json, sizeof(json), "Té ngã") && strcmp(json, "Té ngã") == 0);
  assert(!jsonEscape(json, 4, "abcd") && json[0] == '\0');

  const char *list = " 123, -100456 ,,a@b.vn ";
  char item[16];
  assert(nextListItem(list, item, sizeof(item)) && strcmp(item, "123") == 0);
  assert(nextListItem(list, item, sizeof(item)) && strcmp(item, "-100456") == 0);
  assert(nextListItem(list, item, sizeof(item)) && strcmp(item, "a@b.vn") == 0);
  assert(!nextListItem(list, item, sizeof(item)));
  // Web-editable recipients: validated so they cannot break JSON or SMTP lines.
  assert(validChatId("123456789") && validChatId("-1001234567890") && validChatId("@kenh_gia_dinh"));
  assert(!validChatId("") && !validChatId("-") && !validChatId("12a") && !validChatId("@abc") &&
         !validChatId("1\"}") && !validChatId("123456789012345678901234567890123"));
  assert(validEmail("a.b+c@gmail.com") && validEmail("x@sub.domain.vn"));
  assert(!validEmail("a@b") && !validEmail("@x.vn") && !validEmail("a@@x.vn") && !validEmail("a@x..vn"));
  assert(!validEmail("a b@x.vn") && !validEmail("a@x.vn\r\nRCPT TO:<z@z.vn>") && !validEmail("a@x.vn>") &&
         !validEmail(".a@x.vn") && !validEmail("a.@x.vn") && !validEmail("a..b@x.vn") && !validEmail("a@-x.vn"));
  NotifySettings ns;
  char bad[NotifySettings::MAIL_ITEM + 1];
  assert(normalizeChatIds(" 123,\n-100456 ;@kenh_abc ,,", ns.chatIds, bad, sizeof(bad)) == ListError::None);
  assert(strcmp(ns.chatIds, "123, -100456, @kenh_abc") == 0);
  assert(normalizeChatIds("123, 12x", ns.chatIds, bad, sizeof(bad)) == ListError::Invalid);
  assert(strcmp(bad, "12x") == 0 && strcmp(ns.chatIds, "123, -100456, @kenh_abc") == 0); // Unchanged on error.
  assert(normalizeChatIds("1,2,3,4,5,6", ns.chatIds, bad, sizeof(bad)) == ListError::TooMany);
  assert(normalizeChatIds("  ", ns.chatIds, bad, sizeof(bad)) == ListError::None && ns.chatIds[0] == '\0');
  assert(normalizeEmails("a@x.vn\nb@y.com", ns.emailTo, bad, sizeof(bad)) == ListError::None);
  assert(strcmp(ns.emailTo, "a@x.vn, b@y.com") == 0);
  assert(normalizeEmails("a@x.vn, <evil>@x.vn", ns.emailTo, bad, sizeof(bad)) == ListError::Invalid);
  char longMail[200];
  memset(longMail, 'a', 150);
  strcpy(longMail + 150, "@x.vn");
  assert(normalizeEmails(longMail, ns.emailTo, bad, sizeof(bad)) == ListError::Invalid);
  const char *five = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@x.vn,"
                     "baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@x.vn,"
                     "caaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@x.vn,"
                     "daaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@x.vn,"
                     "eaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@x.vn";
  assert(normalizeEmails(five, ns.emailTo, bad, sizeof(bad)) == ListError::None); // Max size fits.
  assert(strlen(ns.emailTo) < sizeof(ns.emailTo));
  puts("PASS: recipient validation and list normalisation");
  puts("PASS: alert text (Telegram/HTML/plain), escaping, subject chunks and recipient lists");
}
