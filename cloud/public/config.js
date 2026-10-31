// Firebase console -> Project settings -> General -> Your apps -> Web app ->
// "SDK setup and configuration" -> Config. Paste the values below.
// These values are public by design (they identify the project); access is
// controlled by database.rules.json and the /access list, not by hiding them.
export const firebaseConfig = {
  apiKey: "AIzaSyCMpi-CSCgvlx8w1WlW1wPzMT3qV2eld5A",
  authDomain: "fall-detect-26023.firebaseapp.com",
  databaseURL: "https://fall-detect-26023-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "fall-detect-26023",
  appId: "1:481327911166:web:709e4165dec3a02d3dd5af",
};

// Must equal CLOUD_DEVICE_ID in the firmware's secrets.h.
// Another device can be opened with ?device=<id> in the address.
export const deviceId = "baonga-01";
