/* ==========================================================================
 * device_secrets.example.h
 * --------------------------------------------------------------------------
 * MAU. Chep file nay thanh "device_secrets.h" roi dien khoa that vao.
 * File device_secrets.h da duoc them vao .gitignore - KHONG BAO GIO commit no.
 *
 * DUNG DE LAM GI:
 *   Khoa rieng cua tung thiet bi duoc sinh ra tu MASTER_KEY va dia chi MAC:
 *       device_key = HMAC-SHA256(MASTER_KEY, mac_6_byte)
 *   App dien thoai lay device_key bang cach quet ma QR dan tren vo may, nen
 *   MASTER_KEY KHONG BAO GIO nam trong app. Server relay tren Vercel giu
 *   MASTER_KEY trong bien moi truong de tinh lai khoa khi can.
 *
 * HAI CACH NAP KHOA - CHON MOT:
 *
 *   A. NAP SAN QUA SERIAL (khuyen nghi cho ban phat hanh)
 *      Build KHONG dinh nghia DEVICE_MASTER_KEY. Firmware doc khoa tu NVS.
 *      Cong cu nap khoa tren may tinh sinh khoa roi gui xuong qua Serial mot lan duy
 *      nhat luc nap. Uu diem: MASTER_KEY khong nam trong firmware, ke nao do
 *      duoc flash cua MOT may cung khong gia mao duoc cac may khac.
 *
 *   B. BIEN DICH KEM MASTER_KEY (tien khi lam demo, KEM AN TOAN HON)
 *      Dinh nghia DEVICE_MASTER_KEY ben duoi. Firmware tu suy ra khoa rieng
 *      luc khoi dong lan dau roi luu vao NVS.
 *      RUI RO: ai doc duoc flash cua mot may la co MASTER_KEY, tu do gia mao
 *      duoc MOI thiet bi trong ca lo hang. Chi dung khi lam do an/thu nghiem.
 *
 * SINH MASTER_KEY (32 byte ngau nhien, chay tren may tinh):
 *     python -c "import secrets;print(secrets.token_hex(32))"
 * ========================================================================== */

#ifndef DEVICE_SECRETS_H
#define DEVICE_SECRETS_H

// Chuoi HEX 64 ky tu = 32 byte. Bo comment dong duoi neu chon cach B.
// #define DEVICE_MASTER_KEY "0000000000000000000000000000000000000000000000000000000000000000"

// Tien to ma thiet bi, in tren vo may. Mac dinh "CBC" (device_identity.h);
// chi bo comment neu muon dat tien to khac.
// #define DEVICE_ID_PREFIX "CBC"

// ---- Mang Wi-Fi (chi 2.4GHz) ----
#define WIFI_SSID "DIEN_TEN_WIFI_VAO_DAY"
#define WIFI_PASSWORD "DIEN_MAT_KHAU_VAO_DAY"

// ---- Bot Telegram (xem huong dan lay token/chat id trong telegram_alert.h) ----
#define TELEGRAM_BOT_TOKEN "DIEN_TOKEN_BOT_VAO_DAY"
#define TELEGRAM_CHAT_ID "DIEN_CHAT_ID_VAO_DAY"

#endif // DEVICE_SECRETS_H
