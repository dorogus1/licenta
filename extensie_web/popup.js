import flatpickr from "flatpickr";
import "flatpickr/dist/flatpickr.min.css";

// --- Firebase Auth ---
import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut, sendPasswordResetEmail } from "firebase/auth";
import { getDatabase, ref, set, onDisconnect, onValue, push, serverTimestamp, remove } from "firebase/database";
import { app, auth } from './auth/login.js';

// DEBUG: Log Extension ID
console.log("Current Extension ID:", chrome.runtime.id);

// DEBUG: Catch global errors
window.addEventListener('error', (event) => {
    console.error("Global Error:", event.error);
    // alert("Global Error: " + (event.error ? event.error.message : event.message));
});

// --- AUTH OVERLAY LOGIC ---
const authOverlay = document.getElementById('authOverlay');
// ... (rest of the file remains similar, I will insert the initDevices function and call it)

// --- Firebase Modular Auth Setup ---
// app and auth are imported from login.js
const db = getDatabase(app);

// Attempt to force WebSockets to avoid CSP errors in Popup
function forceWebSockets() {
    try {
        // @ts-ignore
        const internalRepo = db._repo || (db.INTERNAL && db.INTERNAL.repo);
        if (internalRepo && internalRepo.connection) {
            internalRepo.connection.forceWebSockets();
            console.log('[popup] Forced WebSockets via internal API');
            return true;
        }
    } catch (e) {
        console.warn('[popup] Failed to force WebSockets:', e);
    }
    return false;
}

if (!forceWebSockets()) {
    const fwInterval = setInterval(() => {
        if (forceWebSockets()) {
            clearInterval(fwInterval);
        }
    }, 100);
    // Stop trying after 5 seconds
    setTimeout(() => clearInterval(fwInterval), 5000);
}

let currentUser = null; // Store logged in user for timer sync
let deviceListenerActive = false;
let currentDeviceListenerUnsub = null;

// --- PRESENCE & DEVICES LOGIC ---
function initDevices(user) {
    if (!user) return;
    if (deviceListenerActive && currentUser && currentUser.uid === user.uid) {
        console.log('[popup] Devices listener already active for this user.');
        return;
    }
    
    deviceListenerActive = true;
    console.log('[popup] Initializing devices for user:', user.uid);
    
    // 1. Generate a device ID for this extension instance
    let deviceId = localStorage.getItem('focus_deviceId');
    if (!deviceId) {
        deviceId = 'ext_' + Math.random().toString(36).substr(2, 9);
        localStorage.setItem('focus_deviceId', deviceId);
    }

    const deviceRef = ref(db, `users/${user.uid}/devices/${deviceId}`);
    const connectedRef = ref(db, '.info/connected');

    // 2. Manage own presence
    onValue(connectedRef, (snap) => {
        if (snap.val() === true) {
            console.log('[popup] Connected to Firebase Realtime DB');
            // We're connected (or reconnected)!
            set(deviceRef, {
                name: 'Browser Extension',
                type: 'extension',
                last_seen: serverTimestamp(),
                state: 'online',
                platform: navigator.platform
            });

            // When I disconnect, remove this device or mark offline
            onDisconnect(deviceRef).update({
                state: 'offline',
                last_seen: serverTimestamp()
            });
        }
    });

    // 3. Listen for other devices (Read from Storage Bridge)
    const devicesContainer = document.getElementById('devicesDetails');
    let latestDevicesData = null; // Store data for periodic refresh

    function updateDevicesUI(devices) {
        if (!devicesContainer) return;
        latestDevicesData = devices; // Update cache
        renderDevicesList();
    }
    
    function renderDevicesList() {
        if (!devicesContainer) return;
        const devices = latestDevicesData;
        devicesContainer.innerHTML = ''; // clear

        if (!devices || Object.keys(devices).length === 0) {
            devicesContainer.textContent = 'No active devices.';
            return;
        }

        const ul = document.createElement('ul');
        ul.style.listStyle = 'none';
        ul.style.padding = '0';

        Object.keys(devices).forEach((key) => {
            const dev = devices[key];
            const isMe = key === deviceId;
            
            // Debug logic
            const now = Date.now();
            const seen = dev.last_seen || 0;
            const diff = now - seen;
            const isExplicitlyOffline = dev.state === 'offline';
            // Online if NOT explicitly offline AND seen within 90s
            const isOnline = !isExplicitlyOffline && (diff < 90000);

            const li = document.createElement('li');
            li.style.padding = '10px';
            li.style.borderBottom = '1px solid #333';
            li.style.display = 'flex';
            li.style.justifyContent = 'space-between';
            li.style.alignItems = 'center';

            const icon = dev.type === 'extension' ? '🌐' : (dev.type === 'windows' ? '💻' : '📱');
            
            li.innerHTML = `
                <div>
                    <strong style="color:white; font-size:14px;">${icon} ${dev.name || 'Unknown Device'} ${isMe ? '(You)' : ''}</strong>
                    <div style="font-size:12px; color: #aaa;">${dev.platform || 'Unknown OS'}</div>
                </div>
                <div style="font-size:12px; color: ${isOnline ? '#03DAC6' : '#666'};">
                    ${isOnline ? '● Online' : '○ Offline'}
                </div>
            `;
            ul.appendChild(li);
        });
        devicesContainer.appendChild(ul);
    }

    // Refresh UI every 5 seconds to update 'Online' status based on time diff
    setInterval(() => {
        if (latestDevicesData) {
            renderDevicesList();
        }
    }, 5000);

    // Load initial from storage
    chrome.storage.local.get(['cachedDevices'], (data) => {
        if (data.cachedDevices) {
            updateDevicesUI(data.cachedDevices);
        }
    });

    // 4. SYNC TIMER SESSION (Storage Bridge)
    function handleSessionUpdate(session) {
        if (session && session.isActive && session.endTime) {
            const now = Date.now();
            const remaining = Math.floor((session.endTime - now) / 1000);
            
            if (remaining > 0) {
                // Sync if not running OR if time skew is significant (>2s)
                if (!timerRunning || Math.abs(timeLeft - remaining) > 2) {
                    timeLeft = remaining;
                    updateTimerDisplay();
                    if (!timerRunning) {
                        startTimer(true, true); // restoring=true, fromSync=true
                    }
                }
            } else {
                stopTimer(true); // fromSync=true
            }
        } else if (session && !session.isActive) {
            if (timerRunning) {
                stopTimer(true); // fromSync=true
            }
        }
    }
    
    // Initial load for session
    chrome.storage.local.get(['cachedSession'], (data) => {
        if (data.cachedSession) {
            handleSessionUpdate(data.cachedSession);
        }
    });

    // Listen for storage changes
    chrome.storage.onChanged.addListener((changes, area) => {
        if (area === 'local') {
            if (changes.cachedDevices) {
                console.log('[popup] Cached devices updated:', changes.cachedDevices.newValue);
                updateDevicesUI(changes.cachedDevices.newValue);
            }
            if (changes.cachedSession) {
                const session = changes.cachedSession.newValue;
                console.log('[popup] Cached session updated:', session);
                handleSessionUpdate(session);
            }
            // Listen for Timer/Focus updates from Background (e.g. Calendar trigger)
            if (changes.timerTimeLeft || changes.timerRunning || changes.timerLastUpdate) {
                chrome.storage.local.get(['timerTimeLeft', 'timerRunning', 'timerLastUpdate'], (data) => {
                    // Update local state
                    if (data.timerRunning && data.timerLastUpdate) {
                        const now = Date.now();
                        const elapsed = Math.floor((now - data.timerLastUpdate) / 1000);
                        timeLeft = Math.max(0, data.timerTimeLeft - elapsed);
                        
                        if (!timerRunning) {
                             startTimer(true, true); // restoring=true, fromSync=true to avoid double sync
                        }
                    } else {
                        timeLeft = data.timerTimeLeft || (25*60);
                        if (timerRunning) {
                            stopTimer(true); // fromSync=true
                        }
                    }
                    updateTimerDisplay();
                });
            }
        }
    });
}

// --- AUTH STATE ---
onAuthStateChanged(auth, user => {
    currentUser = user;
    const accountActionsPublic = document.getElementById('accountActionsPublic');
    // The auth/login.js module handles the overlay and window.Auth.currentUser
    
    // Update the Account Page UI
    if (user) {
        initDevices(user); // <--- CALL HERE
        if (accountDetails) accountDetails.textContent = 'Logged in as:';
        if (accountActions) accountActions.style.display = '';
        if (accountActionsPublic) accountActionsPublic.style.display = 'none';
        if (accountEmail) accountEmail.textContent = user.email;
        if (accountMsg) {
            accountMsg.textContent = '';
            accountMsg.className = 'auth-error';
        }
    } else {
        if (currentDeviceListenerUnsub) {
            currentDeviceListenerUnsub();
            currentDeviceListenerUnsub = null;
        }
        deviceListenerActive = false;
        currentUser = null;
        
        if (accountDetails) accountDetails.textContent = 'Not logged in.';
        if (accountActions) accountActions.style.display = 'none';
        if (accountActionsPublic) accountActionsPublic.style.display = '';
        if (accountEmail) accountEmail.textContent = '';
        if (accountMsg) {
            accountMsg.textContent = '';
            accountMsg.className = 'auth-error';
        }
    }
});

// --- LOGIN, REGISTER, RESET, LOGOUT HANDLERS ---
// These are handled by the imported 'auth/login.js' module which attaches listeners to the elements.

// ...existing code...
// --- Apps (Blocked URLs) logic ---
const appUrlInput = document.getElementById('appUrlInput');
const addAppBtn = document.getElementById('addAppBtn');
const appsList = document.getElementById('appsList');

// Load saved apps on open and manage empty state
const appsEmpty = document.getElementById('appsEmpty');
function refreshEmptyState() {
    const has = appsList.children.length > 0;
    if (appsEmpty) appsEmpty.style.display = has ? 'none' : 'block';
}

chrome.storage.local.get(['blockedApps'], (data) => {
    const apps = data.blockedApps || [];
    apps.forEach(app => addAppToUI(app));
    refreshEmptyState();
});

// Add app on click or Enter
addAppBtn && addAppBtn.addEventListener('click', () => {
    let raw = appUrlInput.value.trim().toLowerCase();
    // sanitize: remove protocol, path, and leading www., and trim trailing dots
    raw = raw.replace(/^https?:\/\//, '').replace(/\/.*$/, '').replace(/^www\./, '').replace(/\.+$/, '');
    if (!raw) return;

    // helper: detect IPv4
    const isIPv4 = (s) => /^\d{1,3}(?:\.\d{1,3}){3}$/.test(s);

    let url = raw;
    const hasDot = raw.includes('.');

    // If user typed a domain (contains a dot) or an IPv4 or localhost, keep as-is
    if (hasDot || raw === 'localhost' || isIPv4(raw)) {
        url = raw;
    } else {
        // Fallback: append .com only when there's no dot
        url = `${raw}.com`;
    }

    // final cleanup
    url = url.replace(/\.+$/, '');

    if (url) {
        chrome.storage.local.get(['blockedApps'], (data) => {
            const apps = data.blockedApps || [];
            if (!apps.includes(url)) {
                apps.push(url);
                chrome.storage.local.set({ blockedApps: apps }, () => {
                    addAppToUI(url);
                    appUrlInput.value = '';
                    refreshEmptyState();
                });
            }
        });
    }
});
if (appUrlInput) {
    appUrlInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            addAppBtn && addAppBtn.click();
        }
    });
}

function addAppToUI(url) {
    const li = document.createElement('li');
    li.className = 'app-item';

    const favicon = document.createElement('img');
    favicon.className = 'app-favicon';
    // Use Google favicon service (fast) — fallback handled by browser
    favicon.src = `https://www.google.com/s2/favicons?domain=${encodeURIComponent(url)}&sz=64`;
    favicon.alt = '';

    const span = document.createElement('span');
    span.textContent = url;
    span.className = 'app-url';

    const delBtn = document.createElement('button');
    delBtn.className = 'delete-btn';
    delBtn.innerHTML = '<svg viewBox="0 0 24 24" width="14" height="14" xmlns="http://www.w3.org/2000/svg"><path d="M6 6 L18 18 M6 18 L18 6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
    delBtn.addEventListener('click', () => {
        removeApp(url, li);
    });

    li.appendChild(favicon);
    li.appendChild(span);
    li.appendChild(delBtn);
    appsList.appendChild(li);
    refreshEmptyState();
}

function removeApp(url, element) {
    chrome.storage.local.get(['blockedApps'], (data) => {
        const apps = data.blockedApps || [];
        const newApps = apps.filter(a => a !== url);
        chrome.storage.local.set({ blockedApps: newApps }, () => {
            element.remove();
            refreshEmptyState();
        });
    });
}
// --- Block logic: block apps when timer is running ---
function isBlockedApp(url) {
    return new Promise((resolve) => {
        chrome.storage.local.get(['blockedApps'], (data) => {
            const apps = data.blockedApps || [];
            resolve(apps.some(app => url.includes(app)));
        });
    });
}

// Optionally, you can use this function in your background.js to block requests when timer is running
// --- Modernized popup.js for new UI ---

let timeLeft = 25 * 60;
let timerInterval;
let timerRunning = false;

// Restore timer state from storage
chrome.storage.local.get(['timerTimeLeft', 'timerRunning', 'timerLastUpdate'], (data) => {
    if (typeof data.timerTimeLeft === 'number') {
        // If running, calculate elapsed time
        if (data.timerRunning && data.timerLastUpdate) {
            const now = Date.now();
            const elapsed = Math.floor((now - data.timerLastUpdate) / 1000);
            timeLeft = Math.max(0, data.timerTimeLeft - elapsed);
            if (timeLeft > 0) {
                startTimer(true); // true = restoring
            } else {
                stopTimer();
            }
        } else {
            timeLeft = data.timerTimeLeft;
            updateTimerDisplay();
        }
    }
});


const timerDisplay = document.getElementById('timerDisplay');
const playPauseBtn = document.getElementById('playPauseBtn');
const minusBtn = document.getElementById('minusBtn');
const plusBtn = document.getElementById('plusBtn');
const resetBtn = document.getElementById('resetBtn');

// --- NAVIGATION LOGIC ---
const navTimer = document.getElementById('navTimer'); // Was navMain
const navCalendar = document.getElementById('navCalendar'); // New
const navAccount = document.getElementById('navAccount');
const navApps = document.getElementById('navApps');
const navDevices = document.getElementById('navDevices');

const timerPage = document.getElementById('timerPage'); // Was mainPage (but now specific div)
const calendarPage = document.getElementById('calendarPage'); // New
const accountPage = document.getElementById('accountPage');
const appsPage = document.getElementById('appsPage');
const devicesPage = document.getElementById('devicesPage');

const navBtns = [navTimer, navCalendar, navApps, navDevices, navAccount].filter(Boolean);
const pages = [timerPage, calendarPage, appsPage, devicesPage, accountPage].filter(Boolean);

function showPage(pageEl) {
    pages.forEach(p => p.classList.remove('active'));
    if (pageEl) pageEl.classList.add('active');
    
    // Update nav selection
    navBtns.forEach(btn => btn.classList.remove('selected'));
    
    // Find corresponding button
    if (pageEl === timerPage) navTimer?.classList.add('selected');
    if (pageEl === calendarPage) navCalendar?.classList.add('selected');
    if (pageEl === appsPage) navApps?.classList.add('selected');
    if (pageEl === devicesPage) navDevices?.classList.add('selected');
    if (pageEl === accountPage) navAccount?.classList.add('selected');
}

if (navTimer) navTimer.addEventListener('click', () => showPage(timerPage));
if (navCalendar) navCalendar.addEventListener('click', () => { showPage(calendarPage); loadEventsForDate(); });
if (navApps) navApps.addEventListener('click', () => showPage(appsPage));
if (navDevices) navDevices.addEventListener('click', () => showPage(devicesPage));
if (navAccount) navAccount.addEventListener('click', () => showPage(accountPage));

// Default Page
showPage(timerPage);



// ... (rest of imports)

// ... (keep existing code until Calendar Logic)

// --- CALENDAR LOGIC (Fetch & Add) ---
const calendarList = document.getElementById('calendarList');
const btnRefreshCalendar = document.getElementById('btnRefreshCalendar');
const btnAddEvent = document.getElementById('btnAddEvent');
const calEventTitle = document.getElementById('calEventTitle');
// New Inputs (Text type now handled by flatpickr)
const calEventDate = document.getElementById('calEventDate');
const calEventStartTime = document.getElementById('calEventStartTime');
const calEventEndTime = document.getElementById('calEventEndTime');

// Flatpickr Instances
let fpDate, fpStart, fpEnd;

function initPickers() {
    if (!calEventDate) return;

    fpDate = flatpickr(calEventDate, {
        dateFormat: "Y-m-d",
        defaultDate: new Date(),
        disableMobile: true, // Force custom UI
        static: true, // Position relative to wrapper
        monthSelectorType: 'static',
        altInput: true,
        altFormat: "F j, Y", // "February 4, 2026"
    });

    fpStart = flatpickr(calEventStartTime, {
        enableTime: true,
        noCalendar: true,
        dateFormat: "H:i",
        time_24hr: true,
        disableMobile: true,
        static: true
    });

    fpEnd = flatpickr(calEventEndTime, {
        enableTime: true,
        noCalendar: true,
        dateFormat: "H:i",
        time_24hr: true,
        disableMobile: true,
        static: true
    });
}

// Call init
initPickers();

// Date Navigation Elements
const prevDayBtn = document.getElementById('prevDayBtn');
const nextDayBtn = document.getElementById('nextDayBtn');
const currentDateDisplay = document.getElementById('currentDateDisplay');

let selectedDate = new Date();

function updateDateDisplay() {
    if (!currentDateDisplay) return;
    const options = { day: 'numeric', month: 'short', year: 'numeric' };
    currentDateDisplay.textContent = selectedDate.toLocaleDateString('en-GB', options);
    
    // Sync Flatpickr
    if (fpDate) {
        fpDate.setDate(selectedDate);
    }
}

function changeDate(offset) {
    selectedDate.setDate(selectedDate.getDate() + offset);
    updateDateDisplay();
    loadEventsForDate();
}

if (prevDayBtn) prevDayBtn.addEventListener('click', () => changeDate(-1));
if (nextDayBtn) nextDayBtn.addEventListener('click', () => changeDate(1));

async function getCalendarToken() {
    return new Promise((resolve) => {
        chrome.identity.getAuthToken({ interactive: false }, (token) => {
            if (chrome.runtime.lastError || !token) {
                resolve(null);
            } else {
                resolve(token);
            }
        });
    });
}

async function loadEventsForDate() {
    if (!calendarList) return;
    updateDateDisplay();
    
    calendarList.innerHTML = '<li style="text-align:center; color:#888;">Checking calendar...</li>';
    
    const token = await getCalendarToken();
    if (!token) {
        calendarList.innerHTML = '<li style="text-align:center;">Please connect Calendar in Account settings first.</li>';
        return;
    }

    // Calculate start and end of selectedDate
    const startOfDay = new Date(selectedDate);
    startOfDay.setHours(0, 0, 0, 0);
    
    const endOfDay = new Date(selectedDate);
    endOfDay.setHours(23, 59, 59, 999);

    const timeMin = startOfDay.toISOString();
    const timeMax = endOfDay.toISOString();

    const url = `https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${timeMin}&timeMax=${timeMax}&singleEvents=true&orderBy=startTime`;

    try {
        const res = await fetch(url, { headers: { 'Authorization': `Bearer ${token}` } });
        
        if (!res.ok) {
            // Try to parse the error text
            let errMsg = `Status: ${res.status}`;
            try {
                const errData = await res.json();
                if (errData.error && errData.error.message) {
                    errMsg += ` - ${errData.error.message}`;
                } else {
                    errMsg += ` - ${JSON.stringify(errData)}`;
                }
            } catch (e) {
                // If not JSON, try text
                const text = await res.text();
                if (text) errMsg += ` - ${text}`;
            }
            throw new Error(errMsg);
        }

        const data = await res.json();
        
        calendarList.innerHTML = '';
        if (!data.items || data.items.length === 0) {
            calendarList.innerHTML = '<li style="text-align:center;">No events for this day.</li>';
            return;
        }

        data.items.forEach(evt => {
            const start = evt.start.dateTime || evt.start.date;
            const dateObj = new Date(start);
            const timeStr = dateObj.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit', hour12: false});

            const li = document.createElement('li');
            li.innerHTML = `
                <div class="event-time-badge">${timeStr}</div>
                <div class="event-info">
                    <span class="event-title">${evt.summary || '(No Title)'}</span>
                </div>
            `;
            calendarList.appendChild(li);
        });

    } catch (err) {
        console.error("Calendar fetch error:", err);
        calendarList.innerHTML = `<li style="color:red; font-size:12px;">Error: ${err.message}</li>`;
    }
}

async function addCalendarEvent() {
    const title = calEventTitle.value;
    const dateVal = calEventDate.value; // Flatpickr updates the hidden input value to YYYY-MM-DD
    const startVal = calEventStartTime.value; // HH:MM
    const endVal = calEventEndTime.value; // HH:MM

    if (!title || !dateVal || !startVal || !endVal) {
        alert("Please fill in all fields (Title, Date, Start & End Time)");
        return;
    }

    const token = await getCalendarToken();
    if (!token) {
        alert("Please connect Calendar in Account settings first.");
        return;
    }

    // Construct ISO strings
    const startDateTime = new Date(`${dateVal}T${startVal}`);
    const endDateTime = new Date(`${dateVal}T${endVal}`);

    if (endDateTime <= startDateTime) {
         alert("End time must be after Start time.");
         return;
    }

    const event = {
        'summary': title,
        'start': {
            'dateTime': startDateTime.toISOString(),
        },
        'end': {
            'dateTime': endDateTime.toISOString(),
        }
    };

    btnAddEvent.textContent = "Adding...";
    btnAddEvent.disabled = true;

    try {
        const res = await fetch('https://www.googleapis.com/calendar/v3/calendars/primary/events', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(event)
        });

        if (res.ok) {
            // Success
            calEventTitle.value = '';
            // Clear times
            if(fpStart) fpStart.clear();
            if(fpEnd) fpEnd.clear();
            
            // Refresh list
            loadEventsForDate();
            chrome.alarms.create("checkCalendar", { when: Date.now() + 1000 });
        } else {
            alert("Failed to add event.");
        }
    } catch (e) {
        console.error(e);
        alert("Error adding event.");
    } finally {
        btnAddEvent.textContent = "+ Schedule Session";
        btnAddEvent.disabled = false;
    }
}



// --- Auth UI Handling ---
const openLoginBtn = document.getElementById('openLoginBtn');
if (openLoginBtn) {
    openLoginBtn.addEventListener('click', () => {
        if (window.Auth && window.Auth.show) {
            window.Auth.show('login');
        }
    });
}

const openRegisterBtn = document.getElementById('openRegisterBtn');
if (openRegisterBtn) {
    openRegisterBtn.addEventListener('click', () => {
        if (window.Auth && window.Auth.show) {
            window.Auth.show('register');
        }
    });
}

// --- CALENDAR UI HANDLING ---
const btnConnectCalendar = document.getElementById('btnConnectCalendar');

function updateCalendarButtonState() {
    if (!btnConnectCalendar) return;
    chrome.identity.getAuthToken({ interactive: false }, (token) => {
        if (!chrome.runtime.lastError && token) {
            btnConnectCalendar.textContent = "Calendar Connected ✓";
            btnConnectCalendar.disabled = true;
            btnConnectCalendar.style.backgroundColor = "#4caf50";
            btnConnectCalendar.style.borderColor = "#4caf50";
        }
    });
}

if (btnConnectCalendar) {
    updateCalendarButtonState(); // Check on load

    btnConnectCalendar.addEventListener('click', () => {
        btnConnectCalendar.textContent = "Connecting...";
        chrome.identity.getAuthToken({ interactive: true }, (token) => {
            if (chrome.runtime.lastError || !token) {
                console.error(chrome.runtime.lastError);
                btnConnectCalendar.textContent = "Connection Failed. Try again.";
                setTimeout(() => {
                    btnConnectCalendar.textContent = "Connect Google Calendar";
                }, 2000);
            } else {
                console.log("Calendar token obtained:", token);
                updateCalendarButtonState();
                
                // Trigger an immediate check
                chrome.alarms.create("checkCalendar", { when: Date.now() + 1000 });
            }
        });
    });
}

// Timer logic
function updateTimerDisplay(save = true) {
    const mins = Math.floor(timeLeft / 60);
    const secs = timeLeft % 60;
    timerDisplay.textContent = `${mins}:${secs < 10 ? '0' : ''}${secs}`;
    if (save) {
        chrome.storage.local.set({ timerTimeLeft: timeLeft });
    }
}

function syncToFirebase(active) {
    if (!currentUser) return;
    
    let data;
    if (active) {
        const endTime = Date.now() + (timeLeft * 1000);
        data = {
            isActive: true,
            endTime: endTime
        };
    } else {
        data = {
            isActive: false,
            endTime: null
        };
    }
    
    // Delegate to background script to ensure update happens even if popup closes
    chrome.runtime.sendMessage({ type: 'UPDATE_SESSION', data: data });
}

function startTimer(restoring = false, fromSync = false) {
    if (timerInterval) clearInterval(timerInterval);
    timerInterval = setInterval(() => {
        // Just update UI every second based on timeLeft
        // The background script is the source of truth for timeLeft now, 
        // but for smooth UI we can decrement locally or wait for storage events.
        // Let's decrement locally for smoothness.
        if (timeLeft > 0) {
            timeLeft--;
            updateTimerDisplay(false); // don't save to storage here, background does it
        } else {
            stopTimer(true);
        }
    }, 1000);
    timerRunning = true;
    playPauseBtn.innerHTML = '&#10073;&#10073;'; // Pause icon
    
    if (!restoring && !fromSync) {
        // This is a manual start from popup
        syncToFirebase(true);
    }
}
function stopTimer(fromSync = false) {
    if (timerInterval) clearInterval(timerInterval);
    timerInterval = null;
    timerRunning = false;
    playPauseBtn.innerHTML = '&#9654;'; // Play icon
    
    if (!fromSync) {
        // This is a manual stop from popup
        syncToFirebase(false);
    }
}
    
if (playPauseBtn) {
    playPauseBtn.addEventListener('click', () => {
        if (timerRunning) {
            stopTimer();
        } else {
            startTimer();
        }
    });
}
if (minusBtn) {
    minusBtn.addEventListener('click', () => {
        timeLeft = Math.max(60, timeLeft - 5 * 60);
        updateTimerDisplay();
        chrome.storage.local.set({ timerTimeLeft: timeLeft });
    });
}
if (plusBtn) {
    plusBtn.addEventListener('click', () => {
        timeLeft = Math.min(60 * 60, timeLeft + 5 * 60);
        updateTimerDisplay();
        chrome.storage.local.set({ timerTimeLeft: timeLeft });
    });
}
if (resetBtn) {
    resetBtn.addEventListener('click', () => {
        stopTimer();
        timeLeft = 25 * 60;
        updateTimerDisplay();
        chrome.storage.local.set({ timerTimeLeft: timeLeft });
    });
}
updateTimerDisplay();

// --- DARK MODE LOGIC ---
const themeToggleBtn = document.getElementById('themeToggleBtn');
const themeToggleBtnPublic = document.getElementById('themeToggleBtnPublic');

function applyTheme(isDark) {
    if (isDark) {
        document.body.classList.add('dark-mode');
        if (themeToggleBtn) themeToggleBtn.textContent = "Switch to Light Mode";
        if (themeToggleBtnPublic) themeToggleBtnPublic.textContent = "Switch to Light Mode";
    } else {
        document.body.classList.remove('dark-mode');
        if (themeToggleBtn) themeToggleBtn.textContent = "Switch to Dark Mode";
        if (themeToggleBtnPublic) themeToggleBtnPublic.textContent = "Switch to Dark Mode";
    }
}

// Load preference
chrome.storage.local.get(['darkMode'], (data) => {
    applyTheme(!!data.darkMode);
});

function toggleTheme() {
    const isDark = document.body.classList.contains('dark-mode');
    const newState = !isDark;
    applyTheme(newState);
    chrome.storage.local.set({ darkMode: newState });
}

if (themeToggleBtn) themeToggleBtn.addEventListener('click', toggleTheme);
if (themeToggleBtnPublic) themeToggleBtnPublic.addEventListener('click', toggleTheme);

