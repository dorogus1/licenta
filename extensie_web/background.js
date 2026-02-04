import { initializeApp } from "firebase/app";
import { getAuth, onAuthStateChanged } from "firebase/auth";
import { getDatabase, ref, set, onDisconnect, onValue, serverTimestamp } from "firebase/database";

const firebaseConfig = {
  apiKey: "AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY",
  databaseURL: "https://focus-shild-default-rtdb.europe-west1.firebasedatabase.app"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getDatabase(app);

console.log('[background] Firebase initialized successfully');

// --- PRESENCE LOGIC ---
let presenceUnsub = null;
let devicesUnsub = null;
let sessionUnsub = null; // New listener for session
let currentUserId = null;

function setupPresence(user) {
    if (!user) return;
    if (presenceUnsub && currentUserId === user.uid) return; 
    
    currentUserId = user.uid;
    
    chrome.storage.local.get(['focus_deviceId'], (data) => {
        let deviceId = data.focus_deviceId;
        if (!deviceId) {
            deviceId = 'ext_' + Math.random().toString(36).substr(2, 9);
            chrome.storage.local.set({ focus_deviceId: deviceId });
        }
        
        console.log('[background] Setting up presence for device:', deviceId);

        const deviceRef = ref(db, `users/${user.uid}/devices/${deviceId}`);
        const connectedRef = ref(db, '.info/connected');

        try {
            // 1. Manage Online Presence
            presenceUnsub = onValue(connectedRef, (snap) => {
                if (snap.val() === true) {
                    console.log('[background] Connected to Realtime Database. Setting online.');
                    set(deviceRef, {
                        name: 'Browser Extension',
                        type: 'extension',
                        last_seen: serverTimestamp(),
                        state: 'online',
                        platform: 'Chrome Extension'
                    }).catch(err => console.error('[background] Error setting presence:', err));

                    onDisconnect(deviceRef).update({
                        state: 'offline',
                        last_seen: serverTimestamp()
                    }).catch(err => console.error('[background] Error setting onDisconnect:', err));
                }
            });
            
            // 2. Sync Devices List to Storage (Storage Bridge)
            const devicesListRef = ref(db, `users/${user.uid}/devices`);
            devicesUnsub = onValue(devicesListRef, (snapshot) => {
                const devices = snapshot.val();
                console.log('[background] Syncing devices to storage:', devices);
                chrome.storage.local.set({ cachedDevices: devices || {} });
            });

            // 3. Sync Focus Session to Storage (Storage Bridge)
            const sessionRef = ref(db, `users/${user.uid}/focus_session`);
            sessionUnsub = onValue(sessionRef, (snapshot) => {
                const session = snapshot.val();
                console.log('[background] Syncing session to storage:', session);
                chrome.storage.local.set({ cachedSession: session || null });
            });

        } catch (err) {
            console.error('[background] Error setting up listeners:', err);
        }
    });
}

// Handle messages from Popup to update Firebase
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.type === 'UPDATE_SESSION') {
        // Wait for auth to settle to avoid race conditions on SW wakeup
        const processUpdate = async () => {
             let user = auth.currentUser;
             if (!user) {
                 // specific check: wait once for auth state
                 user = await new Promise(resolve => {
                     const unsub = onAuthStateChanged(auth, u => {
                         unsub();
                         resolve(u);
                     });
                 });
             }

             if (!user) {
                console.warn('[background] Cannot update session: No user logged in.');
                return;
             }

             const sessionRef = ref(db, `users/${user.uid}/focus_session`);
             console.log('[background] Updating session in Firebase:', request.data);
            
             // Add metadata
             const data = {
                ...request.data,
                updatedBy: 'extension',
                lastUpdatedAt: serverTimestamp()
             };

             try {
                await set(sessionRef, data);
                console.log('[background] Session updated successfully.');
             } catch (err) {
                console.error('[background] Session update failed:', err);
             }
        };

        processUpdate();
        return true; // Indicates async work
    }
});

onAuthStateChanged(auth, (user) => {
    if (user) {
        console.log('[background] User logged in:', user.email);
        setupPresence(user);
    } else {
        console.log('[background] User logged out.');
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
        // Clear cache on logout
        chrome.storage.local.remove(['cachedDevices', 'cachedSession']);
    }
});


// --- BLOCKING LOGIC (Existing) ---
const sitesToBlock = ["facebook.com", "instagram.com", "youtube.com", "tiktok.com"];

// Creăm regulile de blocare
const rules = sitesToBlock.map((site, index) => ({
  id: index + 1,
  priority: 1,
  action: { type: "block" },
  condition: { urlFilter: site, resourceTypes: ["main_frame"] }
}));

function updateBlockRules() {
    chrome.storage.local.get(['focusActive', 'blockedSites', 'blockedApps'], (data) => {
        if (data.focusActive && (data.blockedSites || data.blockedApps)) {
            // Blocare doar pe blockedSites și blockedApps
            const allBlocked = [
                ...(data.blockedSites || []),
                ...(data.blockedApps || [])
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
            console.log('[background] Updating block rules with:', rules);
            chrome.declarativeNetRequest.getDynamicRules(oldRules => {
                const oldIds = oldRules.map(r => r.id);
                chrome.declarativeNetRequest.updateDynamicRules({
                    removeRuleIds: oldIds,
                    addRules: rules
                }, () => {
                    // After rules are updated, immediately redirect any already-open tabs that match blocked sites
                    chrome.tabs.query({}, (tabs) => {
                        tabs.forEach(tab => {
                            try {
                                const tabUrl = tab.url || '';
                                if (!tabUrl) return;
                                const lower = tabUrl.toLowerCase();
                                for (const s of allBlocked) {
                                    if (!s) continue;
                                    // simple contains match for domain or host
                                    if (lower.includes(s.toLowerCase())) {
                                        chrome.tabs.update(tab.id, { url: chrome.runtime.getURL('blocked.html') });
                                        break;
                                    }
                                }
                            } catch (err) {
                                // ignore tabs we can't access
                            }
                        });
                    });
                });
            });
        } else {
            chrome.declarativeNetRequest.getDynamicRules(oldRules => {
                const oldIds = oldRules.map(r => r.id);
                chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: oldIds });
            });
        }
    });
}

chrome.storage.onChanged.addListener(() => {
    updateBlockRules();
});

// Setează regulile la inițializare (la pornirea extensiei)
chrome.runtime.onInstalled.addListener(() => {
    updateBlockRules();
});

// Fallback: Check tabs manually on update to ensure blocking works immediately
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
    if (changeInfo.status === 'loading' && tab.url) {
        chrome.storage.local.get(['focusActive', 'blockedSites', 'blockedApps'], (data) => {
            if (data.focusActive) {
                const allBlocked = [
                    ...(data.blockedSites || []),
                    ...(data.blockedApps || [])
                ].filter((v, i, arr) => arr.indexOf(v) === i && v && v.trim() !== "");

                const url = tab.url.toLowerCase();
                // Check if URL contains any blocked domain
                const isBlocked = allBlocked.some(site => {
                    // Remove protocol and www for cleaner check, though simple includes works too
                    return url.includes(site.toLowerCase());
                });

                if (isBlocked) {
                    console.log(`[background] Manual fallback blocking: ${tab.url}`);
                    chrome.tabs.update(tabId, { url: chrome.runtime.getURL('blocked.html') });
                }
            }
        });
    }
});

// --- GOOGLE CALENDAR INTEGRATION ---

// 1. Set up alarm for periodic checks (every 1 minute for accuracy)
chrome.alarms.create("checkCalendar", { periodInMinutes: 1 });

chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === "checkCalendar") {
        checkCalendarEvents();
    }
});

async function checkCalendarEvents() {
    try {
        // Get OAuth token silently
        const token = await new Promise((resolve, reject) => {
            chrome.identity.getAuthToken({ interactive: false }, (token) => {
                if (chrome.runtime.lastError || !token) {
                    reject(chrome.runtime.lastError);
                } else {
                    resolve(token);
                }
            });
        });

        const now = new Date();
        const nextMinute = new Date(now.getTime() + 60000); 

        const timeMin = now.toISOString();
        const timeMax = nextMinute.toISOString();

        const response = await fetch(
            `https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${timeMin}&timeMax=${timeMax}&singleEvents=true&orderBy=startTime`,
            {
                headers: {
                    'Authorization': `Bearer ${token}`,
                    'Content-Type': 'application/json'
                }
            }
        );

        if (!response.ok) {
            console.warn('[calendar] Fetch failed:', response.status);
            return;
        }

        const data = await response.json();
        const events = data.items || [];

        if (events.length > 0) {
            const currentEvent = events[0];
            const eventId = currentEvent.id;
            
            // Check if this is a new event we haven't handled yet
            chrome.storage.local.get(['lastEventId', 'focusActive'], (storage) => {
                if (storage.lastEventId !== eventId) {
                    console.log('[calendar] New active event found:', currentEvent.summary);

                    const endStr = currentEvent.end.dateTime || currentEvent.end.date;
                    // If it's an all-day event (date only), this logic might need tweaking, 
                    // but usually 'busy' events have times.
                    if (!endStr) return;

                    const endTime = new Date(endStr).getTime();
                    const nowTime = Date.now();
                    const remainingSeconds = Math.floor((endTime - nowTime) / 1000);

                    if (remainingSeconds > 0) {
                        console.log(`[calendar] Starting timer for ${remainingSeconds}s based on event duration.`);
                        
                        chrome.storage.local.set({
                            focusActive: true,
                            timerRunning: true,
                            timerTimeLeft: remainingSeconds,
                            timerLastUpdate: Date.now(),
                            lastEventId: eventId
                        });

                        chrome.notifications.create({
                            type: 'basic',
                            iconUrl: 'icon.png',
                            title: 'Focus Mode Activated',
                            message: `Event started: ${currentEvent.summary}\nTimer set to ${Math.floor(remainingSeconds/60)}m.`
                        });
                    }
                }
            });
        } else {
             // Clear lastEventId so if the same event happens again (unlikely) or just cleanup
             chrome.storage.local.set({ lastEventId: null });
        }

    } catch (err) {
        // console.log('[calendar] Check skipped or failed:', err);
    }
}