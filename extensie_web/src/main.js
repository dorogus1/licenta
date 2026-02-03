import { initializeApp } from "firebase/app";
import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut, sendPasswordResetEmail } from "firebase/auth";

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

// Navigation
const navMain = document.getElementById('navMain');
const navAccount = document.getElementById('navAccount');
const navApps = document.getElementById('navApps');
const navDevices = document.getElementById('navDevices');
const mainPage = document.getElementById('mainPage');
const accountPage = document.getElementById('accountPage');
const appsPage = document.getElementById('appsPage');
const devicesPage = document.getElementById('devicesPage');
const navBtns = [navMain, navAccount, navApps, navDevices];
const pages = [mainPage, accountPage, appsPage, devicesPage];

function showPage(idx) {
    pages.forEach((p, i) => { if (p) p.classList.toggle('active', i === idx); });
    navBtns.forEach((b, i) => { if (b) b.classList.toggle('selected', i === idx); });
}
if (navMain) navMain.addEventListener('click', () => showPage(0));
if (navAccount) navAccount.addEventListener('click', () => {
    if (window.Auth && !window.Auth.currentUser) {
        window.Auth.show('login');
        return;
    }
    showPage(1);
});
if (navApps) navApps.addEventListener('click', () => showPage(2));
if (navDevices) navDevices.addEventListener('click', () => showPage(3));
showPage(0);

// Open register from Account page when not logged in
const openRegisterBtn = document.getElementById('openRegisterBtn');
if (openRegisterBtn) {
    openRegisterBtn.addEventListener('click', () => {
        if (window.Auth) {
            window.Auth.show('register');
        } else {
            // fallback: ensure account page triggers overlay; setTimeout in case Auth loads shortly
            setTimeout(() => window.Auth && window.Auth.show('register'), 200);
        }
    });
}

// Timer logic
function updateTimerDisplay() {
    const mins = Math.floor(timeLeft / 60);
    const secs = timeLeft % 60;
    timerDisplay.textContent = `${mins}:${secs < 10 ? '0' : ''}${secs}`;
    chrome.storage.local.set({ timerTimeLeft: timeLeft });
}
function startTimer(restoring = false) {
    if (timerInterval) clearInterval(timerInterval);
    timerInterval = setInterval(() => {
        if (timeLeft > 0) {
            timeLeft--;
            updateTimerDisplay();
            chrome.storage.local.set({ timerTimeLeft: timeLeft, timerRunning: true, timerLastUpdate: Date.now(), focusActive: true });
        } else {
            stopTimer();
        }
    }, 1000);
    timerRunning = true;
    playPauseBtn.innerHTML = '&#10073;&#10073;'; // Pause icon
    if (!restoring) {
        chrome.storage.local.set({ timerRunning: true, timerLastUpdate: Date.now(), focusActive: true });
    }
}
function stopTimer() {
    clearInterval(timerInterval);
    timerRunning = false;
    playPauseBtn.innerHTML = '&#9654;'; // Play icon
    chrome.storage.local.set({ timerRunning: false, focusActive: false });
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