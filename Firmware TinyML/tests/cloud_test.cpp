#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "cloud_json.h"
#include "notify_settings.h"
#include "wifi_config.h"
#include "status_led.h"

int main() {
  // Firebase sign-in replies are pretty-printed.
  const char *signIn = "{\n  \"kind\": \"identitytoolkit#VerifyPasswordResponse\",\n"
                       "  \"localId\": \"abc\",\n  \"idToken\": \"eyJh.eyJz.c2ln\",\n"
                       "  \"registered\": true,\n  \"expiresIn\": \"3600\"\n}";
  char out[64];
  assert(jsonString(jsonMember(signIn, "idToken"), out, sizeof(out)) && strcmp(out, "eyJh.eyJz.c2ln") == 0);
  assert(!jsonMember(signIn, "idTok") && !jsonMember(signIn, "missing"));
  assert(!jsonString(jsonMember(signIn, "idToken"), out, 5)); // Too small: refused, not truncated.

  const char *error = "{\"error\":{\"code\":400,\"message\":\"INVALID_LOGIN_CREDENTIALS\",\"errors\":[{\"a\":1}]}}";
  assert(jsonString(jsonMember(jsonMember(error, "error"), "message"), out, sizeof(out)));
  assert(strcmp(out, "INVALID_LOGIN_CREDENTIALS") == 0);

  // /control as written by the page; members in any order, nested objects skipped.
  const char *control = "{\"settings\":{\"chatIds\":\"123, -100456\",\"emailTo\":\"a@x.vn\","
                        "\"gmailOn\":false,\"telegramOn\":true},\"testAt\":1759650000123}";
  const char *settings = jsonMember(control, "settings");
  bool on = false;
  uint64_t at = 0;
  assert(settings && jsonBool(jsonMember(settings, "telegramOn"), on) && on);
  assert(jsonBool(jsonMember(settings, "gmailOn"), on) && !on);
  assert(jsonUint64(jsonMember(control, "testAt"), at) && at == 1759650000123ULL);
  assert(!jsonMember(control, "chatIds")); // Only direct children are found.
  assert(!jsonMember("null", "settings") && !jsonMember("{}", "settings"));
  assert(!jsonUint64(jsonMember("{\"testAt\":1.5}", "testAt"), at));
  assert(!jsonBool(jsonMember("{\"x\":\"true\"}", "x"), on));

  // Escapes decode; strings containing quotes/braces do not confuse skipping.
  const char *tricky = "{\"a\":\"}\\\",{\",\"b\":[1,{\"c\":\"]\"}],\"k\":\"T\\u00e9 \\\"ng\\u00e3\\\"\\n\"}";
  assert(jsonString(jsonMember(tricky, "k"), out, sizeof(out)));
  assert(strcmp(out, "Té \"ngã\"\n") == 0);
  assert(!jsonString(jsonMember("{\"k\":\"\\ud83d\\ude00\"}", "k"), out, sizeof(out))); // Surrogates refused.
  assert(!jsonString(jsonMember("{\"k\":\"\\u0000\"}", "k"), out, sizeof(out)));
  assert(!jsonMember("{\"a\":\"unterminated}", "b") && !jsonMember("{\"a\" 1}", "a"));
  assert(!jsonSkipValue("[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]")); // Depth bounded.

  // Same rules for the local page and the cloud page.
  NotifySettings s;
  char msg[192];
  assert(buildSettings(s, true, false, " 123 ,-100456", "", 60, true, false, msg, sizeof(msg)));
  assert(s.telegramOn && !s.gmailOn && strcmp(s.chatIds, "123, -100456") == 0);
  assert(!buildSettings(s, false, true, "", "a@x.vn", 60, true, false, msg, sizeof(msg)) && strstr(msg, "Gmail"));
  assert(!buildSettings(s, true, false, "", "", 60, true, true, msg, sizeof(msg)) && strstr(msg, "Chat ID"));
  assert(!buildSettings(s, false, false, "12x", "", 60, true, true, msg, sizeof(msg)) && strstr(msg, "\"12x\""));
  assert(!buildSettings(s, false, false, "", "a@x.vn,b", 60, true, true, msg, sizeof(msg)) && strstr(msg, "Email"));
  assert(buildSettings(s, false, false, "", "", 60, false, false, msg, sizeof(msg))); // Both off is allowed.
  assert(s.inactiveMin == 60);
  assert(buildSettings(s, false, false, "", "", 0, true, true, msg, sizeof(msg)) && s.inactiveMin == 0); // Off.
  assert(buildSettings(s, false, false, "", "", 1440, true, true, msg, sizeof(msg)) && s.inactiveMin == 1440);
  assert(!buildSettings(s, false, false, "", "", 1441, true, true, msg, sizeof(msg)) && strstr(msg, "bất động"));
  uint32_t minutes = 7;
  assert(parseMinutes("45", minutes) && minutes == 45 && parseMinutes("0", minutes) && minutes == 0);
  assert(!parseMinutes("", minutes) && !parseMinutes("-5", minutes) && !parseMinutes("1.5", minutes) &&
         !parseMinutes("12a", minutes) && !parseMinutes("99999999999999999999", minutes));
  NotifySettings a, b;
  assert(sameSettings(a, b));
  b.gmailOn = true;
  assert(!sameSettings(a, b));
  b = a;
  b.inactiveMin = 30;
  assert(!sameSettings(a, b));
  // Wi-Fi networks set on the device's page.
  assert(validSsid("Nha Toi 2.4G") && validSsid("Wi-Fi T\xe1\xba\xa7ng 2") && !validSsid("") &&
         !validSsid("123456789012345678901234567890123") && !validSsid("a\"b") && !validSsid("a\\b") &&
         !validSsid("a\nb"));
  assert(validWifiPassword("") && validWifiPassword("12345678") && !validWifiPassword("1234567") &&
         !validWifiPassword("caf\xc3\xa9 1234") && !validWifiPassword("abc\tdefgh"));
  char hex[65];
  memset(hex, 'a', 64);
  hex[64] = '\0';
  assert(validWifiPassword(hex));
  hex[10] = 'g';
  assert(!validWifiPassword(hex));
  WifiNetworks w;
  char wm[160];
  assert(addWifiNetwork(w, "Nha", "matkhau123", wm, sizeof(wm)) && w.count == 1);
  assert(addWifiNetwork(w, "Hotspot", "", wm, sizeof(wm)) && w.count == 2 && strcmp(w.ssid[0], "Hotspot") == 0);
  assert(addWifiNetwork(w, "Nha", "matkhaumoi1", wm, sizeof(wm)) && w.count == 2); // Moves to top, new password.
  assert(strcmp(w.ssid[0], "Nha") == 0 && strcmp(w.pass[0], "matkhaumoi1") == 0 && strcmp(w.ssid[1], "Hotspot") == 0);
  assert(addWifiNetwork(w, "C", "", wm, sizeof(wm)) && addWifiNetwork(w, "D", "", wm, sizeof(wm)));
  assert(w.count == 3 && strcmp(w.ssid[0], "D") == 0 && w.find("Hotspot") < 0); // Oldest dropped.
  WifiNetworks before = w;
  assert(!addWifiNetwork(w, "E", "short", wm, sizeof(wm)) && strstr(wm, "8-63"));
  assert(memcmp(&before, &w, sizeof(w)) == 0); // Unchanged on error.
  assert(removeWifiNetwork(w, "C") && w.count == 2 && strcmp(w.ssid[1], "Nha") == 0 && w.find("C") < 0);
  assert(!removeWifiNetwork(w, "C") && removeWifiNetwork(w, "D") && removeWifiNetwork(w, "Nha") && w.count == 0);
  puts("PASS: Wi-Fi network list (validation, priority order, limit, remove)");

  // Network LED: blue blink while searching, green when online.
  using namespace StatusLed;
  assert(state(false, false, false, true, false) == Net::Off);
  assert(state(true, false, false, true, false) == Net::Searching);
  assert(state(true, false, true, true, false) == Net::SetupAp);
  assert(state(true, true, true, true, false) == Net::NoInternet); // Joined, cloud not synced yet.
  assert(state(true, true, false, true, true) == Net::Online);
  assert(state(true, true, false, false, false) == Net::Online);   // No cloud: Wi-Fi is the best proof.
  Rgb off, blue, green;
  blue.b = LEVEL;
  green.g = LEVEL;
  assert(color(Net::Searching, 100) == blue && color(Net::Searching, 300) == off); // Blinks.
  assert(color(Net::Online, 0) == green && color(Net::Online, 777) == green);       // Steady.
  assert(color(Net::NoInternet, 500) == green && color(Net::NoInternet, 1500) == off);
  assert(color(Net::Off, 0) == off && color(Net::SetupAp, 100).r == LEVEL && color(Net::SetupAp, 100).b == LEVEL);
  puts("PASS: network status LED colours and blinking");
  puts("PASS: Firebase JSON reading and shared settings validation (incl. inactivity limit)");
}
