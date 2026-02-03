import { i as initializeApp, g as getAuth, e as getDatabase, o as onAuthStateChanged, r as ref, h as set, f as onValue, j as serverTimestamp, k as onDisconnect } from "./assets/index.esm-BlxZGF7M.js";
const firebaseConfig = {
  apiKey: "AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY",
  databaseURL: "https://focus-shild-default-rtdb.europe-west1.firebasedatabase.app"
};
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getDatabase(app);
console.log("[background] Firebase initialized successfully");
let presenceUnsub = null;
let devicesUnsub = null;
let sessionUnsub = null;
let currentUserId = null;
function setupPresence(user) {
  if (!user) return;
  if (presenceUnsub && currentUserId === user.uid) return;
  currentUserId = user.uid;
  chrome.storage.local.get(["focus_deviceId"], (data) => {
    let deviceId = data.focus_deviceId;
    if (!deviceId) {
      deviceId = "ext_" + Math.random().toString(36).substr(2, 9);
      chrome.storage.local.set({ focus_deviceId: deviceId });
    }
    console.log("[background] Setting up presence for device:", deviceId);
    const deviceRef = ref(db, `users/${user.uid}/devices/${deviceId}`);
    const connectedRef = ref(db, ".info/connected");
    try {
      presenceUnsub = onValue(connectedRef, (snap) => {
        if (snap.val() === true) {
          console.log("[background] Connected to Realtime Database. Setting online.");
          set(deviceRef, {
            name: "Browser Extension",
            type: "extension",
            last_seen: serverTimestamp(),
            state: "online",
            platform: "Chrome Extension"
          }).catch((err) => console.error("[background] Error setting presence:", err));
          onDisconnect(deviceRef).update({
            state: "offline",
            last_seen: serverTimestamp()
          }).catch((err) => console.error("[background] Error setting onDisconnect:", err));
        }
      });
      const devicesListRef = ref(db, `users/${user.uid}/devices`);
      devicesUnsub = onValue(devicesListRef, (snapshot) => {
        const devices = snapshot.val();
        console.log("[background] Syncing devices to storage:", devices);
        chrome.storage.local.set({ cachedDevices: devices || {} });
      });
      const sessionRef = ref(db, `users/${user.uid}/focus_session`);
      sessionUnsub = onValue(sessionRef, (snapshot) => {
        const session = snapshot.val();
        console.log("[background] Syncing session to storage:", session);
        chrome.storage.local.set({ cachedSession: session || null });
      });
    } catch (err) {
      console.error("[background] Error setting up listeners:", err);
    }
  });
}
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.type === "UPDATE_SESSION") {
    const processUpdate = async () => {
      let user = auth.currentUser;
      if (!user) {
        user = await new Promise((resolve) => {
          const unsub = onAuthStateChanged(auth, (u) => {
            unsub();
            resolve(u);
          });
        });
      }
      if (!user) {
        console.warn("[background] Cannot update session: No user logged in.");
        return;
      }
      const sessionRef = ref(db, `users/${user.uid}/focus_session`);
      console.log("[background] Updating session in Firebase:", request.data);
      const data = {
        ...request.data,
        updatedBy: "extension",
        lastUpdatedAt: serverTimestamp()
      };
      try {
        await set(sessionRef, data);
        console.log("[background] Session updated successfully.");
      } catch (err) {
        console.error("[background] Session update failed:", err);
      }
    };
    processUpdate();
    return true;
  }
});
onAuthStateChanged(auth, (user) => {
  if (user) {
    console.log("[background] User logged in:", user.email);
    setupPresence(user);
  } else {
    console.log("[background] User logged out.");
    if (presenceUnsub) {
      presenceUnsub();
      presenceUnsub = null;
    }
    if (devicesUnsub) {
      devicesUnsub();
      devicesUnsub = null;
    }
    if (sessionUnsub) {
      sessionUnsub();
      sessionUnsub = null;
    }
    currentUserId = null;
    chrome.storage.local.remove(["cachedDevices", "cachedSession"]);
  }
});
function updateBlockRules() {
  chrome.storage.local.get(["focusActive", "blockedSites", "blockedApps"], (data) => {
    if (data.focusActive && (data.blockedSites || data.blockedApps)) {
      const allBlocked = [
        ...data.blockedSites || [],
        ...data.blockedApps || []
      ].filter((v, i, arr) => arr.indexOf(v) === i && v && v.trim() !== "");
      const rules = allBlocked.map((site, index) => ({
        id: index + 1,
        priority: 1,
        action: {
          type: "redirect",
          redirect: { extensionPath: "/blocked.html" }
        },
        condition: {
          // Matches domain and subdomains (e.g. ||youtube.com matches http://youtube.com, https://www.youtube.com/...)
          urlFilter: `||${site}`,
          resourceTypes: ["main_frame"]
        }
      }));
      console.log("[background] Updating block rules with:", rules);
      chrome.declarativeNetRequest.getDynamicRules((oldRules) => {
        const oldIds = oldRules.map((r) => r.id);
        chrome.declarativeNetRequest.updateDynamicRules({
          removeRuleIds: oldIds,
          addRules: rules
        }, () => {
          chrome.tabs.query({}, (tabs) => {
            tabs.forEach((tab) => {
              try {
                const tabUrl = tab.url || "";
                if (!tabUrl) return;
                const lower = tabUrl.toLowerCase();
                for (const s of allBlocked) {
                  if (!s) continue;
                  if (lower.includes(s.toLowerCase())) {
                    chrome.tabs.update(tab.id, { url: chrome.runtime.getURL("blocked.html") });
                    break;
                  }
                }
              } catch (err) {
              }
            });
          });
        });
      });
    } else {
      chrome.declarativeNetRequest.getDynamicRules((oldRules) => {
        const oldIds = oldRules.map((r) => r.id);
        chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: oldIds });
      });
    }
  });
}
chrome.storage.onChanged.addListener(() => {
  updateBlockRules();
});
chrome.runtime.onInstalled.addListener(() => {
  updateBlockRules();
});
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "loading" && tab.url) {
    chrome.storage.local.get(["focusActive", "blockedSites", "blockedApps"], (data) => {
      if (data.focusActive) {
        const allBlocked = [
          ...data.blockedSites || [],
          ...data.blockedApps || []
        ].filter((v, i, arr) => arr.indexOf(v) === i && v && v.trim() !== "");
        const url = tab.url.toLowerCase();
        const isBlocked = allBlocked.some((site) => {
          return url.includes(site.toLowerCase());
        });
        if (isBlocked) {
          console.log(`[background] Manual fallback blocking: ${tab.url}`);
          chrome.tabs.update(tabId, { url: chrome.runtime.getURL("blocked.html") });
        }
      }
    });
  }
});
chrome.alarms.create("checkCalendar", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "checkCalendar") {
    checkCalendarEvents();
  }
});
async function checkCalendarEvents() {
  try {
    const token = await new Promise((resolve, reject) => {
      chrome.identity.getAuthToken({ interactive: false }, (token2) => {
        if (chrome.runtime.lastError || !token2) {
          reject(chrome.runtime.lastError);
        } else {
          resolve(token2);
        }
      });
    });
    const now = /* @__PURE__ */ new Date();
    const nextMinute = new Date(now.getTime() + 6e4);
    const timeMin = now.toISOString();
    const timeMax = nextMinute.toISOString();
    const response = await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${timeMin}&timeMax=${timeMax}&singleEvents=true&orderBy=startTime`,
      {
        headers: {
          "Authorization": `Bearer ${token}`,
          "Content-Type": "application/json"
        }
      }
    );
    if (!response.ok) {
      console.warn("[calendar] Fetch failed:", response.status);
      return;
    }
    const data = await response.json();
    const events = data.items || [];
    if (events.length > 0) {
      const currentEvent = events[0];
      console.log("[calendar] Active event found:", currentEvent.summary);
      chrome.storage.local.get(["focusActive"], (res) => {
        if (!res.focusActive) {
          console.log("[calendar] Enabling Focus Mode due to calendar event.");
          chrome.storage.local.set({ focusActive: true });
          chrome.notifications.create({
            type: "basic",
            iconUrl: "icon.png",
            title: "Focus Mode Activated",
            message: `Scheduled session: ${currentEvent.summary}`
          });
        }
      });
    } else {
      console.log("[calendar] No active events.");
    }
  } catch (err) {
  }
}
