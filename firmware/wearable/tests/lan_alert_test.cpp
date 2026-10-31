#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "lan_alert_format.h"

static char out[128];

static void formatTests() {
  assert(formatLanAlert(out, sizeof(out), 7, "baonga-01", LanAlertKind::Fall, 264, 0x3201A8C0u));
  assert(strcmp(out, "BAONGA|1|7|baonga-01|FALL|2.64|192.168.1.50") == 0);
  assert(formatLanAlert(out, sizeof(out), 1, "d", LanAlertKind::Inactive, 5, 0));
  assert(strcmp(out, "BAONGA|1|1|d|INACTIVE|0.05|0.0.0.0") == 0);
  assert(formatLanAlert(out, sizeof(out), 2, "d", LanAlertKind::Resumed, -150, 0x0100000Au));
  assert(strcmp(out, "BAONGA|1|2|d|RESUMED|-1.50|10.0.0.1") == 0);
  assert(formatLanAlert(out, sizeof(out), 4000000000u, "d", LanAlertKind::Inactive, 4200, 0xFFFFFFFFu));
  assert(strcmp(out, "BAONGA|1|4000000000|d|INACTIVE|42.00|255.255.255.255") == 0);
  assert(formatLanAlert(out, sizeof(out), 0, "d", LanAlertKind::Fall, 0, 0));
  assert(strstr(out, "|0.00|"));
  assert(formatLanAlert(out, sizeof(out), 0, "d", LanAlertKind::Fall, INT32_MIN, 0)); // no overflow
  assert(strstr(out, "|-21474836.48|"));

  // Exact fit works, one byte less fails and leaves a valid empty string.
  const char *want = "BAONGA|1|7|baonga-01|FALL|2.64|192.168.1.50";
  assert(formatLanAlert(out, strlen(want) + 1, 7, "baonga-01", LanAlertKind::Fall, 264, 0x3201A8C0u));
  memset(out, 'x', sizeof(out));
  assert(!formatLanAlert(out, strlen(want), 7, "baonga-01", LanAlertKind::Fall, 264, 0x3201A8C0u));
  assert(out[0] == '\0');
  assert(!formatLanAlert(out, 1, 7, "baonga-01", LanAlertKind::Fall, 264, 0));
  assert(!formatLanAlert(out, 0, 7, "baonga-01", LanAlertKind::Fall, 264, 0));

  assert(!formatLanAlert(out, sizeof(out), 1, "a|b", LanAlertKind::Fall, 1, 0) && out[0] == '\0');
  assert(!formatLanAlert(out, sizeof(out), 1, "a\nb", LanAlertKind::Fall, 1, 0));
  assert(!formatLanAlert(out, sizeof(out), 1, "a\rb", LanAlertKind::Fall, 1, 0));
  assert(!formatLanAlert(out, sizeof(out), 1, "", LanAlertKind::Fall, 1, 0));
}

static void burstTests() {
  LanBurst b;
  assert(!b.active() && !b.due(100));
  b.start(1000);
  assert(b.active() && b.due(1000) && !b.due(1000));
  assert(!b.due(1019));
  assert(b.due(1020) && !b.due(1039));
  assert(b.due(1040));
  assert(!b.active() && !b.due(5000));

  b.start(0xFFFFFFF0u); // across the millis() wrap
  assert(b.due(0xFFFFFFF0u));
  assert(!b.due(0xFFFFFFF0u + 19));
  assert(b.due(0xFFFFFFF0u + 20)); // 0x04
  assert(!b.due(0xFFFFFFF0u + 39));
  assert(b.due(0xFFFFFFF0u + 40));
  assert(!b.active());

  b.start(500); // restart mid-burst
  assert(b.due(500));
  b.start(510);
  assert(b.due(510) && b.due(530) && b.due(550) && !b.due(570));

  b.start(100); // late poll: next send is GAP_MS after the actual one
  assert(b.due(150) && !b.due(169) && b.due(170));
}

static void clientTests() {
  RecentClients c;
  uint32_t ips[RecentClients::MAX];
  assert(c.copy(ips) == 0);
  c.note(0);
  c.note(0xFFFFFFFFu);
  assert(c.copy(ips) == 0);
  c.note(1); c.note(2); c.note(3);
  assert(c.copy(ips) == 3 && ips[0] == 3 && ips[1] == 2 && ips[2] == 1);
  c.note(1); // move to front
  assert(c.copy(ips) == 3 && ips[0] == 1 && ips[1] == 3 && ips[2] == 2);
  c.note(4); c.note(5); // fifth drops the oldest (2)
  assert(c.copy(ips) == 4 && ips[0] == 5 && ips[1] == 4 && ips[2] == 1 && ips[3] == 3);
  c.note(3); // last to front
  assert(c.copy(ips) == 4 && ips[0] == 3 && ips[1] == 5 && ips[2] == 4 && ips[3] == 1);
  c.note(0);
  assert(c.copy(ips) == 4 && ips[0] == 3);
}

int main() {
  formatTests();
  burstTests();
  clientTests();
  puts("lan_alert_test OK");
  return 0;
}
