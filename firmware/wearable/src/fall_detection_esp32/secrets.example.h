#pragma once
// Copy this file to secrets.h (same folder) and fill it in. secrets.h is
// git-ignored; never commit real passwords or tokens. Leave a channel's
// values empty to disable it. Without secrets.h, Wi-Fi stays off.

// 2.4 GHz Wi-Fi (ESP32-S3 does not support 5 GHz). Only the first default:
// up to 3 networks are then set on the device's web page (kept in NVS). May
// be left empty: the device then opens the setup hotspot "BaoNga-Setup-XXXX".
#define WIFI_SSID "TenWiFi"
#define WIFI_PASSWORD "MatKhauWiFi"
// 1 (default): setup hotspot when no saved network can be joined; its
// password is WEB_PASSWORD when that has 8+ characters, otherwise it is open.
#define WIFI_SETUP_AP 1

// Telegram: create a bot with @BotFather -> token. Send the bot any message,
// then open https://api.telegram.org/bot<TOKEN>/getUpdates and copy
// "chat":{"id":...}. Several chats/groups: comma separated.
// TELEGRAM_CHAT_IDS / ALERT_EMAIL_TO are only the first defaults: recipients
// and on/off switches can be changed later on the device's web page.
#define TELEGRAM_BOT_TOKEN "123456789:ABCdefGhIJKlmNoPQRstuVWxyz"
#define TELEGRAM_CHAT_IDS "123456789"

// Gmail: the sending account needs 2-Step Verification and an App Password
// (Google Account -> Security -> App passwords), NOT the normal password.
// Several recipients: comma separated.
#define GMAIL_ADDRESS "thietbi.baonga@gmail.com"
#define GMAIL_APP_PASSWORD "abcdefghijklmnop"
#define ALERT_EMAIL_TO "nguoithan@gmail.com"

// Shown in every message.
#define DEVICE_NAME "May bao nga - Ong Ba"

// Web page: http://<WEB_HOSTNAME>.local (or the IP printed on Serial).
// Recommended: set a password (user "admin"); empty = anyone on the Wi-Fi
// can change where alerts are sent.
#define WEB_HOSTNAME "baonga"
#define WEB_PASSWORD "doimatkhau"

// Remote access from any network (Firebase; see README "Truy cap tu xa").
// Leave FIREBASE_API_KEY empty to keep the device LAN-only.
// API key: Project settings -> General -> Web API Key.
// DB URL: Realtime Database -> Data (top of the page), without a trailing "/".
// Device account: a separate Email/Password user created for this device only.
#define FIREBASE_API_KEY "AIzaSy..."
#define FIREBASE_DB_URL "https://ten-project-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_DEVICE_EMAIL "thietbi01@baonga.app"
#define FIREBASE_DEVICE_PASSWORD "mat-khau-dai-ngau-nhien"
#define CLOUD_DEVICE_ID "baonga-01" // Same as deviceId in cloud/public/config.js
