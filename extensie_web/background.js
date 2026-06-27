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

// --- TIMER MANAGEMENT ---
// setInterval is unreliable in Manifest V3 Service Workers. 
// We use chrome.alarms for the end of the session and storage for state.

function startBackgroundTimer(durationSeconds) {
    const now = Date.now();
    const endTime = now + (durationSeconds * 1000);
    
    chrome.storage.local.set({ 
        timerRunning: true, 
        timerTimeLeft: durationSeconds, 
        timerLastUpdate: now,
        timerEndTime: endTime,
        focusActive: true 
    });

    // Create an alarm for when the timer should finish
    chrome.alarms.create("timerEnd", { when: endTime });
    console.log('[background] Alarm set for timer end in', durationSeconds, 's');
}

function stopBackgroundTimer() {
    chrome.alarms.clear("timerEnd");
    chrome.storage.local.set({ 
        timerRunning: false, 
        focusActive: false,
        timerEndTime: 0
    });
}

// Handle alarm for timer completion
chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === "timerEnd") {
        console.log('[background] Timer alarm fired.');
        stopBackgroundTimer();
        
        chrome.notifications.create({
            type: 'basic',
            iconUrl: 'icon.png',
            title: 'Focus Session Finished',
            message: 'Well done! Take a break.'
        });
        
        // Update Firebase if logged in
        if (currentUserId) {
            const sessionRef = ref(db, `users/${currentUserId}/focus_session`);
            set(sessionRef, {
                isActive: false,
                updatedBy: 'extension',
                lastUpdatedAt: serverTimestamp()
            });
        }
    } else if (alarm.name === "checkCalendar") {
        checkCalendarEvents();
    }
});

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
                
                if (session && session.lastUpdatedAt) {
                    const latency = Date.now() - session.lastUpdatedAt;
                    console.log(`[PERFORMANCE] Focus session sync latency: ${latency} ms (updated by ${session.updatedBy})`);
                }
                
                chrome.storage.local.get(['focus_deviceId'], (localData) => {
                    const myDeviceId = localData.focus_deviceId;
                    const updatedByMe = session && (session.updatedBy === 'extension' || session.updatedBy === myDeviceId || session.updatedBy === 'extension_calendar');

                    if (session && session.isActive) {
                        const now = Date.now();
                        const endTime = session.endTime || (now + 25 * 60 * 1000);
                        const remaining = Math.floor((endTime - now) / 1000);
                        
                        if (remaining > 0) {
                            // If it's not updated by me, we MUST sync our local timer to it
                            if (!updatedByMe) {
                                console.log('[background] Session started by other device. Syncing timer.');
                                startBackgroundTimer(remaining);
                            }
                        }
                    } else {
                        // If session is NOT active and NOT updated by me, stop local timer
                        if (!updatedByMe) {
                            console.log('[background] Session stopped by other device. Stopping timer.');
                            stopBackgroundTimer();
                        }
                    }

                    chrome.storage.local.set({ 
                        cachedSession: session || null,
                        focusActive: session ? (session.isActive || false) : false
                    });
                });
            });

            // 4. Sync Blocked Apps from Mobile (NEW)
            const blockedAppsRef = ref(db, `users/${user.uid}/blocked_apps`);
            onValue(blockedAppsRef, (snapshot) => {
                const packages = snapshot.val() || [];
                console.log('[background] Blocked apps from mobile:', packages);
                
                const appToSiteMap = {
                    'com.instagram.android': 'instagram.com',
                    'com.facebook.katana': 'facebook.com',
                    'com.facebook.orca': 'messenger.com',
                    'com.zhiliaoapp.musically': 'tiktok.com',
                    'com.google.android.youtube': 'youtube.com',
                    'com.twitter.android': 'twitter.com',
                    'com.twitter.android.x': 'x.com',
                    'com.whatsapp': 'web.whatsapp.com',
                    'com.snapchat.android': 'snapchat.com',
                    'com.reddit.frontpage': 'reddit.com',
                    'com.netflix.mediaclient': 'netflix.com',
                    'com.spotify.music': 'spotify.com',
                    'com.linkedin.android': 'linkedin.com',
                    'com.pinterest': 'pinterest.com',
                    'com.discord': 'discord.com',
                    'com.twitch.android': 'twitch.tv',
                    'com.amazon.mShop.android.shopping': 'amazon.com',
                    'com.amazon.mobile.shopping.anaconda': 'amazon.com',
                    'com.ebay.mobile': 'ebay.com',
                    'com.hbo.hbonow': 'max.com',
                    'com.disney.disneyplus': 'disneyplus.com'
                };

                const mappedSites = packages
                    .map(pkg => appToSiteMap[pkg])
                    .filter(site => site !== undefined);
                
                console.log('[background] Mapped blocked sites:', mappedSites);
                chrome.storage.local.set({ blockedApps: mappedSites });
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
                
                // Also update local background timer state immediately
                if (request.data.isActive) {
                    const now = Date.now();
                    const remaining = Math.floor(((request.data.endTime || (now + 25*60*1000)) - now) / 1000);
                    startBackgroundTimer(remaining);
                } else {
                    stopBackgroundTimer();
                }
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
                const t0 = performance.now();
                chrome.declarativeNetRequest.updateDynamicRules({
                    removeRuleIds: oldIds,
                    addRules: rules
                }, () => {
                    const t1 = performance.now();
                    console.log(`[PERFORMANCE] declarativeNetRequest updateDynamicRules took ${(t1 - t0).toFixed(2)} ms`);
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
                const t0 = performance.now();
                chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: oldIds }, () => {
                    const t1 = performance.now();
                    console.log(`[PERFORMANCE] declarativeNetRequest removeRules took ${(t1 - t0).toFixed(2)} ms`);
                });
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
        // Get OAuth token silently, checking storage first, then falling back to identity
        const token = await new Promise((resolve) => {
            chrome.storage.local.get(['google_access_token', 'google_token_expiry'], (result) => {
                const now = Date.now();
                if (result.google_access_token && result.google_token_expiry && now < result.google_token_expiry) {
                    resolve(result.google_access_token);
                } else {
                    chrome.identity.getAuthToken({ interactive: false }, (t) => {
                        if (chrome.runtime.lastError || !t) {
                            resolve(null);
                        } else {
                            resolve(t);
                        }
                    });
                }
            });
        });

        if (!token) {
            console.log("[background] No valid Google token found for calendar check.");
            return;
        }

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

                        // Sync to Firebase
                        if (currentUserId) {
                            const sessionRef = ref(db, `users/${currentUserId}/focus_session`);
                            set(sessionRef, {
                                isActive: true,
                                endTime: Date.now() + (remainingSeconds * 1000),
                                updatedBy: 'extension_calendar',
                                lastUpdatedAt: serverTimestamp(),
                                eventTitle: currentEvent.summary
                            });
                        }

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