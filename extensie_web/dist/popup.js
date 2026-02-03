import { i as initializeApp, g as getAuth, o as onAuthStateChanged, s as signInWithEmailAndPassword, G as GoogleAuthProvider, a as signInWithCredential, c as createUserWithEmailAndPassword, b as sendPasswordResetEmail, d as signOut, e as getDatabase, r as ref, f as onValue, h as set, j as serverTimestamp, k as onDisconnect } from "./assets/index.esm-BlxZGF7M.js";
(function polyfill() {
  const relList = document.createElement("link").relList;
  if (relList && relList.supports && relList.supports("modulepreload")) return;
  for (const link of document.querySelectorAll('link[rel="modulepreload"]')) processPreload(link);
  new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type !== "childList") continue;
      for (const node of mutation.addedNodes) if (node.tagName === "LINK" && node.rel === "modulepreload") processPreload(node);
    }
  }).observe(document, {
    childList: true,
    subtree: true
  });
  function getFetchOpts(link) {
    const fetchOpts = {};
    if (link.integrity) fetchOpts.integrity = link.integrity;
    if (link.referrerPolicy) fetchOpts.referrerPolicy = link.referrerPolicy;
    if (link.crossOrigin === "use-credentials") fetchOpts.credentials = "include";
    else if (link.crossOrigin === "anonymous") fetchOpts.credentials = "omit";
    else fetchOpts.credentials = "same-origin";
    return fetchOpts;
  }
  function processPreload(link) {
    if (link.ep) return;
    link.ep = true;
    const fetchOpts = getFetchOpts(link);
    fetch(link.href, fetchOpts);
  }
})();
const firebaseConfig = {
  apiKey: "AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY",
  databaseURL: "https://focus-shild-default-rtdb.europe-west1.firebasedatabase.app"
  // other config keys can go here if needed
};
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
async function mountAuth() {
  console.log("[auth] mountAuth start");
  if (document.getElementById("authOverlay")) {
    console.log("[auth] authOverlay already present; skipping");
    return;
  }
  const container = document.getElementById("authContainer");
  const mountTarget = container || document.body;
  try {
    console.log("[auth] fetching auth/login.html using chrome.runtime.getURL");
    const url = typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.getURL ? chrome.runtime.getURL("auth/login.html") : "auth/login.html";
    console.log("[auth] fetch url:", url);
    const res = await fetch(url);
    console.log("[auth] fetch response:", res.status, res.ok);
    if (!res.ok) throw new Error(`Could not load auth HTML (status ${res.status})`);
    const html = await res.text();
    if (!document.getElementById("authStylesLink")) {
      const link = document.createElement("link");
      link.id = "authStylesLink";
      link.rel = "stylesheet";
      const cssUrl = typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.getURL ? chrome.runtime.getURL("auth.css") : "auth.css";
      link.href = cssUrl;
      document.head.appendChild(link);
    }
    const wrapper = document.createElement("div");
    wrapper.innerHTML = html.trim();
    const overlay = wrapper.firstElementChild;
    if (!overlay) throw new Error("Auth HTML had no root element");
    overlay.style.display = "none";
    mountTarget.appendChild(overlay);
    console.log("[auth] authOverlay appended to", mountTarget.id || "body");
  } catch (err) {
    console.error("[auth] Failed to load auth UI:", err);
    return;
  }
  const authOverlay = document.getElementById("authOverlay");
  const tabLogin = document.getElementById("tabLogin");
  const tabRegister = document.getElementById("tabRegister");
  const loginForm = document.getElementById("loginForm");
  const registerForm = document.getElementById("registerForm");
  const loginError = document.getElementById("loginError");
  const registerError = document.getElementById("registerError");
  const emailInput = document.getElementById("emailInput");
  const passwordInput = document.getElementById("passwordInput");
  const regEmailInput = document.getElementById("regEmailInput");
  const regPasswordInput = document.getElementById("regPasswordInput");
  const regPasswordRepeat = document.getElementById("regPasswordRepeat");
  const googleLoginBtn = document.getElementById("googleLoginBtn");
  console.log("[auth] elements:", {
    haveRegisterForm: !!registerForm,
    haveRegEmail: !!regEmailInput,
    haveRegPw: !!regPasswordInput,
    haveRegPwRepeat: !!regPasswordRepeat
  });
  if (registerForm) {
    const regBtn = registerForm.querySelector('button[type="submit"]');
    if (regBtn) {
      regBtn.addEventListener("click", () => console.log("[auth] register button clicked"));
      console.log("[auth] attached click listener to register button");
    } else {
      console.log("[auth] register button not found");
    }
  }
  let accountDetails2 = document.getElementById("accountDetails");
  if (!accountDetails2) {
    accountDetails2 = document.createElement("div");
    accountDetails2.id = "accountDetails";
    accountDetails2.style.width = "100%";
    accountDetails2.style.textAlign = "center";
    accountDetails2.style.marginTop = "12px";
    authOverlay && authOverlay.querySelector(".auth-card") && authOverlay.querySelector(".auth-card").appendChild(accountDetails2);
  }
  const accountActions2 = document.getElementById("accountActions");
  const accountEmail2 = document.getElementById("accountEmail");
  const resetPasswordBtn = document.getElementById("resetPasswordBtn");
  const logoutBtn = document.getElementById("logoutBtn");
  const accountMsg2 = document.getElementById("accountMsg");
  if (window.Auth && Array.isArray(window.Auth._queuedShows) && window.Auth._queuedShows.length) {
    console.log("[auth] processing queued shows:", window.Auth._queuedShows);
    window.Auth._queuedShows.forEach((tab) => showAuthOverlay(true, tab));
    window.Auth._queuedShows = [];
  }
  function showAuthOverlay(show, tab = "login") {
    console.log(`[auth] showAuthOverlay called -> show=${show}, tab=${tab}`);
    if (!authOverlay) {
      console.warn("[auth] showAuthOverlay: authOverlay is null");
      return;
    }
    if (show) {
      authOverlay.style.display = "flex";
      authOverlay.setAttribute("aria-hidden", "false");
      authOverlay.style.pointerEvents = "auto";
      if (tab === "login") {
        tabLogin.classList.add("selected");
        tabRegister.classList.remove("selected");
        loginForm.style.display = "";
        registerForm.style.display = "none";
        loginError.textContent = "";
        registerError.textContent = "";
      } else {
        tabLogin.classList.remove("selected");
        tabRegister.classList.add("selected");
        loginForm.style.display = "none";
        registerForm.style.display = "";
        loginError.textContent = "";
        registerError.textContent = "";
      }
      setTimeout(() => {
        if (tab === "login") emailInput && emailInput.focus();
        else regEmailInput && regEmailInput.focus();
      }, 100);
    } else {
      authOverlay.style.display = "none";
      authOverlay.setAttribute("aria-hidden", "true");
      authOverlay.style.pointerEvents = "none";
      loginError.textContent = "";
      registerError.textContent = "";
    }
  }
  tabLogin && tabLogin.addEventListener("click", () => showAuthOverlay(true, "login"));
  tabRegister && tabRegister.addEventListener("click", () => showAuthOverlay(true, "register"));
  window.Auth = window.Auth || { currentUser: null, _queuedShows: [] };
  window.Auth.show = (tab = "login") => {
    console.log(`[auth] window.Auth.show called -> ${tab}`);
    const overlay = document.getElementById("authOverlay");
    if (overlay && typeof overlay.style !== "undefined") {
      console.log("[auth] overlay present — calling showAuthOverlay");
      showAuthOverlay(true, tab);
    } else {
      window.Auth._queuedShows.push(tab);
      console.log("[auth] overlay not present — queued show request");
    }
  };
  window.Auth.currentUser = null;
  onAuthStateChanged(auth, (user) => {
    window.Auth.currentUser = user;
    if (user) {
      showAuthOverlay(false);
      setTimeout(() => {
        if (authOverlay) {
          authOverlay.style.display = "none";
          authOverlay.setAttribute("aria-hidden", "true");
          authOverlay.style.pointerEvents = "none";
        }
      }, 100);
      if (accountDetails2) accountDetails2.textContent = "Logged in as:";
      if (accountActions2) accountActions2.style.display = "";
      if (accountEmail2) accountEmail2.textContent = user.email;
      if (accountMsg2) {
        accountMsg2.textContent = "";
        accountMsg2.className = "auth-error";
      }
    } else {
      if (accountDetails2) accountDetails2.textContent = "Not logged in.";
      if (accountActions2) accountActions2.style.display = "none";
      if (accountEmail2) accountEmail2.textContent = "";
      if (accountMsg2) {
        accountMsg2.textContent = "";
        accountMsg2.className = "auth-error";
      }
    }
  });
  loginForm && loginForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!loginError) return;
    loginError.textContent = "";
    loginError.className = "auth-error";
    try {
      await signInWithEmailAndPassword(auth, emailInput.value, passwordInput.value);
      loginError.textContent = "";
    } catch (err) {
      loginError.textContent = err.message;
      loginError.className = "auth-error";
    }
  });
  googleLoginBtn && googleLoginBtn.addEventListener("click", () => {
    loginError.textContent = "Contacting Google...";
    chrome.identity.getAuthToken({ interactive: true }, async (token) => {
      if (chrome.runtime.lastError || !token) {
        console.error(chrome.runtime.lastError);
        loginError.textContent = "Google Sign-In cancelled or failed.";
        return;
      }
      loginError.textContent = "Signing in to Focus Shield...";
      console.log("[auth] Google token obtained, attempt Firebase sign-in");
      try {
        const credential = GoogleAuthProvider.credential(null, token);
        const userCredential = await signInWithCredential(auth, credential);
        console.log("[auth] Firebase sign-in success:", userCredential.user.email);
      } catch (err) {
        console.error("[auth] Firebase sign-in error:", err.code, err.message);
        if (err.code === "auth/account-exists-with-different-credential") {
          loginError.textContent = "An account already exists with this email but different login method.";
        } else {
          loginError.textContent = "Error: " + err.message;
        }
      }
    });
  });
  registerForm && registerForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    console.log("[auth] register submit fired", {
      email: regEmailInput?.value?.slice(0, 3) + "...",
      pwLength: regPasswordInput?.value?.length
    });
    if (!registerError) return;
    registerError.textContent = "";
    registerError.className = "auth-error";
    if (regPasswordInput.value !== regPasswordRepeat.value) {
      registerError.textContent = "Passwords do not match.";
      return;
    }
    if (regPasswordInput.value.length < 6) {
      registerError.textContent = "Password must be at least 6 characters.";
      return;
    }
    try {
      await createUserWithEmailAndPassword(auth, regEmailInput.value, regPasswordInput.value);
      registerError.textContent = "Account created! You are now logged in.";
      registerError.className = "auth-success";
      setTimeout(() => showAuthOverlay(false), 800);
    } catch (err) {
      console.error("[auth] createUser failed", err);
      registerError.textContent = err.message || "Registration failed";
      registerError.className = "auth-error";
    }
  });
  if (!window.Auth._delegatedRegisterAttached) {
    window.Auth._delegatedRegisterAttached = true;
    document.addEventListener("submit", async (e) => {
      const form = e.target;
      if (!form || form.id !== "registerForm") return;
      e.preventDefault();
      console.log("[auth] delegated register submit fired", {
        email: regEmailInput?.value?.slice(0, 3) + "...",
        pwLength: regPasswordInput?.value?.length
      });
      if (!registerError) return;
      registerError.textContent = "";
      registerError.className = "auth-error";
      if (regPasswordInput.value !== regPasswordRepeat.value) {
        registerError.textContent = "Passwords do not match.";
        return;
      }
      if (regPasswordInput.value.length < 6) {
        registerError.textContent = "Password must be at least 6 characters.";
        return;
      }
      try {
        await createUserWithEmailAndPassword(auth, regEmailInput.value, regPasswordInput.value);
        registerError.textContent = "Account created! You are now logged in.";
        registerError.className = "auth-success";
        setTimeout(() => showAuthOverlay(false), 800);
      } catch (err) {
        console.error("[auth] delegated createUser failed", err);
        registerError.textContent = err.message || "Registration failed";
        registerError.className = "auth-error";
      }
    }, true);
    console.log("[auth] delegated submit listener attached");
  }
  resetPasswordBtn && resetPasswordBtn.addEventListener("click", async () => {
    if (accountMsg2) {
      accountMsg2.textContent = "";
      accountMsg2.className = "auth-error";
    }
    const user = auth.currentUser;
    if (user && user.email) {
      try {
        await sendPasswordResetEmail(auth, user.email);
        if (accountMsg2) {
          accountMsg2.textContent = "Password reset email sent!";
          accountMsg2.className = "auth-success";
        }
      } catch (err) {
        if (accountMsg2) {
          accountMsg2.textContent = err.message;
          accountMsg2.className = "auth-error";
        }
      }
    }
  });
  logoutBtn && logoutBtn.addEventListener("click", async () => {
    await signOut(auth);
  });
}
window.mountAuth = mountAuth;
mountAuth();
console.log("Current Extension ID:", chrome.runtime.id);
window.addEventListener("error", (event) => {
  console.error("Global Error:", event.error);
});
document.getElementById("authOverlay");
const db = getDatabase(app);
function forceWebSockets() {
  try {
    const internalRepo = db._repo || db.INTERNAL && db.INTERNAL.repo;
    if (internalRepo && internalRepo.connection) {
      internalRepo.connection.forceWebSockets();
      console.log("[popup] Forced WebSockets via internal API");
      return true;
    }
  } catch (e) {
    console.warn("[popup] Failed to force WebSockets:", e);
  }
  return false;
}
if (!forceWebSockets()) {
  const fwInterval = setInterval(() => {
    if (forceWebSockets()) {
      clearInterval(fwInterval);
    }
  }, 100);
  setTimeout(() => clearInterval(fwInterval), 5e3);
}
let currentUser = null;
let deviceListenerActive = false;
function initDevices(user) {
  if (!user) return;
  if (deviceListenerActive && currentUser && currentUser.uid === user.uid) {
    console.log("[popup] Devices listener already active for this user.");
    return;
  }
  deviceListenerActive = true;
  console.log("[popup] Initializing devices for user:", user.uid);
  let deviceId = localStorage.getItem("focus_deviceId");
  if (!deviceId) {
    deviceId = "ext_" + Math.random().toString(36).substr(2, 9);
    localStorage.setItem("focus_deviceId", deviceId);
  }
  const deviceRef = ref(db, `users/${user.uid}/devices/${deviceId}`);
  const connectedRef = ref(db, ".info/connected");
  onValue(connectedRef, (snap) => {
    if (snap.val() === true) {
      console.log("[popup] Connected to Firebase Realtime DB");
      set(deviceRef, {
        name: "Browser Extension",
        type: "extension",
        last_seen: serverTimestamp(),
        state: "online",
        platform: navigator.platform
      });
      onDisconnect(deviceRef).update({
        state: "offline",
        last_seen: serverTimestamp()
      });
    }
  });
  const devicesContainer = document.getElementById("devicesDetails");
  let latestDevicesData = null;
  function updateDevicesUI(devices) {
    if (!devicesContainer) return;
    latestDevicesData = devices;
    renderDevicesList();
  }
  function renderDevicesList() {
    if (!devicesContainer) return;
    const devices = latestDevicesData;
    devicesContainer.innerHTML = "";
    if (!devices || Object.keys(devices).length === 0) {
      devicesContainer.textContent = "No active devices.";
      return;
    }
    const ul = document.createElement("ul");
    ul.style.listStyle = "none";
    ul.style.padding = "0";
    Object.keys(devices).forEach((key) => {
      const dev = devices[key];
      const isMe = key === deviceId;
      const now = Date.now();
      const seen = dev.last_seen || 0;
      const diff = now - seen;
      const isExplicitlyOffline = dev.state === "offline";
      const isOnline = !isExplicitlyOffline && diff < 9e4;
      const li = document.createElement("li");
      li.style.padding = "10px";
      li.style.borderBottom = "1px solid #333";
      li.style.display = "flex";
      li.style.justifyContent = "space-between";
      li.style.alignItems = "center";
      const icon = dev.type === "extension" ? "🌐" : dev.type === "windows" ? "💻" : "📱";
      li.innerHTML = `
                <div>
                    <strong style="color:white; font-size:14px;">${icon} ${dev.name || "Unknown Device"} ${isMe ? "(You)" : ""}</strong>
                    <div style="font-size:12px; color: #aaa;">${dev.platform || "Unknown OS"}</div>
                </div>
                <div style="font-size:12px; color: ${isOnline ? "#03DAC6" : "#666"};">
                    ${isOnline ? "● Online" : "○ Offline"}
                </div>
            `;
      ul.appendChild(li);
    });
    devicesContainer.appendChild(ul);
  }
  setInterval(() => {
    if (latestDevicesData) {
      renderDevicesList();
    }
  }, 5e3);
  chrome.storage.local.get(["cachedDevices"], (data) => {
    if (data.cachedDevices) {
      updateDevicesUI(data.cachedDevices);
    }
  });
  function handleSessionUpdate(session) {
    if (session && session.isActive && session.endTime) {
      const now = Date.now();
      const remaining = Math.floor((session.endTime - now) / 1e3);
      if (remaining > 0) {
        if (!timerRunning || Math.abs(timeLeft - remaining) > 2) {
          timeLeft = remaining;
          updateTimerDisplay();
          if (!timerRunning) {
            startTimer(true, true);
          }
        }
      } else {
        stopTimer(true);
      }
    } else if (session && !session.isActive) {
      if (timerRunning) {
        stopTimer(true);
      }
    }
  }
  chrome.storage.local.get(["cachedSession"], (data) => {
    if (data.cachedSession) {
      handleSessionUpdate(data.cachedSession);
    }
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local") {
      if (changes.cachedDevices) {
        console.log("[popup] Cached devices updated:", changes.cachedDevices.newValue);
        updateDevicesUI(changes.cachedDevices.newValue);
      }
      if (changes.cachedSession) {
        const session = changes.cachedSession.newValue;
        console.log("[popup] Cached session updated:", session);
        handleSessionUpdate(session);
      }
    }
  });
}
onAuthStateChanged(auth, (user) => {
  currentUser = user;
  const accountActionsPublic = document.getElementById("accountActionsPublic");
  if (user) {
    initDevices(user);
    if (accountDetails) accountDetails.textContent = "Logged in as:";
    if (accountActions) accountActions.style.display = "";
    if (accountActionsPublic) accountActionsPublic.style.display = "none";
    if (accountEmail) accountEmail.textContent = user.email;
    if (accountMsg) {
      accountMsg.textContent = "";
      accountMsg.className = "auth-error";
    }
  } else {
    deviceListenerActive = false;
    currentUser = null;
    if (accountDetails) accountDetails.textContent = "Not logged in.";
    if (accountActions) accountActions.style.display = "none";
    if (accountActionsPublic) accountActionsPublic.style.display = "";
    if (accountEmail) accountEmail.textContent = "";
    if (accountMsg) {
      accountMsg.textContent = "";
      accountMsg.className = "auth-error";
    }
  }
});
const appUrlInput = document.getElementById("appUrlInput");
const addAppBtn = document.getElementById("addAppBtn");
const appsList = document.getElementById("appsList");
const appsEmpty = document.getElementById("appsEmpty");
function refreshEmptyState() {
  const has = appsList.children.length > 0;
  if (appsEmpty) appsEmpty.style.display = has ? "none" : "block";
}
chrome.storage.local.get(["blockedApps"], (data) => {
  const apps = data.blockedApps || [];
  apps.forEach((app2) => addAppToUI(app2));
  refreshEmptyState();
});
addAppBtn && addAppBtn.addEventListener("click", () => {
  let raw = appUrlInput.value.trim().toLowerCase();
  raw = raw.replace(/^https?:\/\//, "").replace(/\/.*$/, "").replace(/^www\./, "").replace(/\.+$/, "");
  if (!raw) return;
  const isIPv4 = (s) => /^\d{1,3}(?:\.\d{1,3}){3}$/.test(s);
  let url = raw;
  const hasDot = raw.includes(".");
  if (hasDot || raw === "localhost" || isIPv4(raw)) {
    url = raw;
  } else {
    url = `${raw}.com`;
  }
  url = url.replace(/\.+$/, "");
  if (url) {
    chrome.storage.local.get(["blockedApps"], (data) => {
      const apps = data.blockedApps || [];
      if (!apps.includes(url)) {
        apps.push(url);
        chrome.storage.local.set({ blockedApps: apps }, () => {
          addAppToUI(url);
          appUrlInput.value = "";
          refreshEmptyState();
        });
      }
    });
  }
});
if (appUrlInput) {
  appUrlInput.addEventListener("keypress", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      addAppBtn && addAppBtn.click();
    }
  });
}
function addAppToUI(url) {
  const li = document.createElement("li");
  li.className = "app-item";
  const favicon = document.createElement("img");
  favicon.className = "app-favicon";
  favicon.src = `https://www.google.com/s2/favicons?domain=${encodeURIComponent(url)}&sz=64`;
  favicon.alt = "";
  const span = document.createElement("span");
  span.textContent = url;
  span.className = "app-url";
  const delBtn = document.createElement("button");
  delBtn.className = "delete-btn";
  delBtn.innerHTML = '<svg viewBox="0 0 24 24" width="14" height="14" xmlns="http://www.w3.org/2000/svg"><path d="M6 6 L18 18 M6 18 L18 6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
  delBtn.addEventListener("click", () => {
    removeApp(url, li);
  });
  li.appendChild(favicon);
  li.appendChild(span);
  li.appendChild(delBtn);
  appsList.appendChild(li);
  refreshEmptyState();
}
function removeApp(url, element) {
  chrome.storage.local.get(["blockedApps"], (data) => {
    const apps = data.blockedApps || [];
    const newApps = apps.filter((a) => a !== url);
    chrome.storage.local.set({ blockedApps: newApps }, () => {
      element.remove();
      refreshEmptyState();
    });
  });
}
let timeLeft = 25 * 60;
let timerInterval;
let timerRunning = false;
chrome.storage.local.get(["timerTimeLeft", "timerRunning", "timerLastUpdate"], (data) => {
  if (typeof data.timerTimeLeft === "number") {
    if (data.timerRunning && data.timerLastUpdate) {
      const now = Date.now();
      const elapsed = Math.floor((now - data.timerLastUpdate) / 1e3);
      timeLeft = Math.max(0, data.timerTimeLeft - elapsed);
      if (timeLeft > 0) {
        startTimer(true);
      } else {
        stopTimer();
      }
    } else {
      timeLeft = data.timerTimeLeft;
      updateTimerDisplay();
    }
  }
});
const timerDisplay = document.getElementById("timerDisplay");
const playPauseBtn = document.getElementById("playPauseBtn");
const minusBtn = document.getElementById("minusBtn");
const plusBtn = document.getElementById("plusBtn");
const resetBtn = document.getElementById("resetBtn");
const navTimer = document.getElementById("navTimer");
const navCalendar = document.getElementById("navCalendar");
const navAccount = document.getElementById("navAccount");
const navApps = document.getElementById("navApps");
const navDevices = document.getElementById("navDevices");
const timerPage = document.getElementById("timerPage");
const calendarPage = document.getElementById("calendarPage");
const accountPage = document.getElementById("accountPage");
const appsPage = document.getElementById("appsPage");
const devicesPage = document.getElementById("devicesPage");
const navBtns = [navTimer, navCalendar, navApps, navDevices, navAccount].filter(Boolean);
const pages = [timerPage, calendarPage, appsPage, devicesPage, accountPage].filter(Boolean);
function showPage(pageEl) {
  pages.forEach((p) => p.classList.remove("active"));
  if (pageEl) pageEl.classList.add("active");
  navBtns.forEach((btn) => btn.classList.remove("selected"));
  if (pageEl === timerPage) navTimer?.classList.add("selected");
  if (pageEl === calendarPage) navCalendar?.classList.add("selected");
  if (pageEl === appsPage) navApps?.classList.add("selected");
  if (pageEl === devicesPage) navDevices?.classList.add("selected");
  if (pageEl === accountPage) navAccount?.classList.add("selected");
}
if (navTimer) navTimer.addEventListener("click", () => showPage(timerPage));
if (navCalendar) navCalendar.addEventListener("click", () => {
  showPage(calendarPage);
  loadUpcomingEvents();
});
if (navApps) navApps.addEventListener("click", () => showPage(appsPage));
if (navDevices) navDevices.addEventListener("click", () => showPage(devicesPage));
if (navAccount) navAccount.addEventListener("click", () => showPage(accountPage));
showPage(timerPage);
const calendarList = document.getElementById("calendarList");
const btnRefreshCalendar = document.getElementById("btnRefreshCalendar");
const btnAddEvent = document.getElementById("btnAddEvent");
const calEventTitle = document.getElementById("calEventTitle");
const calEventStart = document.getElementById("calEventStart");
const calEventEnd = document.getElementById("calEventEnd");
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
async function loadUpcomingEvents() {
  if (!calendarList) return;
  calendarList.innerHTML = '<li style="text-align:center; color:#888;">Checking calendar...</li>';
  const token = await getCalendarToken();
  if (!token) {
    calendarList.innerHTML = '<li style="text-align:center;">Please connect Calendar in Account settings first.</li>';
    return;
  }
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const url = `https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${now}&maxResults=10&singleEvents=true&orderBy=startTime`;
  try {
    const res = await fetch(url, { headers: { "Authorization": `Bearer ${token}` } });
    if (!res.ok) {
      let errMsg = `Status: ${res.status}`;
      try {
        const errData = await res.json();
        if (errData.error && errData.error.message) {
          errMsg += ` - ${errData.error.message}`;
        } else {
          errMsg += ` - ${JSON.stringify(errData)}`;
        }
      } catch (e) {
        const text = await res.text();
        if (text) errMsg += ` - ${text}`;
      }
      throw new Error(errMsg);
    }
    const data = await res.json();
    calendarList.innerHTML = "";
    if (!data.items || data.items.length === 0) {
      calendarList.innerHTML = '<li style="text-align:center;">No upcoming events found.</li>';
      return;
    }
    data.items.forEach((evt) => {
      const start = evt.start.dateTime || evt.start.date;
      const dateObj = new Date(start);
      const timeStr = dateObj.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
      const dayStr = dateObj.toLocaleDateString([], { month: "short", day: "numeric" });
      const li = document.createElement("li");
      li.innerHTML = `
                <div style="flex:1">
                    <div style="font-weight:600; font-size:14px;">${evt.summary || "(No Title)"}</div>
                    <div style="font-size:12px; color:#666;">${dayStr} • ${timeStr}</div>
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
  const startVal = calEventStart.value;
  const endVal = calEventEnd.value;
  if (!title || !startVal || !endVal) {
    alert("Please fill in all fields");
    return;
  }
  const token = await getCalendarToken();
  if (!token) {
    alert("Please connect Calendar in Account settings first.");
    return;
  }
  const startDate = new Date(startVal);
  const endDate = new Date(endVal);
  const event = {
    "summary": title,
    "start": {
      "dateTime": startDate.toISOString()
    },
    "end": {
      "dateTime": endDate.toISOString()
    }
  };
  btnAddEvent.textContent = "Adding...";
  btnAddEvent.disabled = true;
  try {
    const res = await fetch("https://www.googleapis.com/calendar/v3/calendars/primary/events", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(event)
    });
    if (res.ok) {
      calEventTitle.value = "";
      loadUpcomingEvents();
      chrome.alarms.create("checkCalendar", { when: Date.now() + 1e3 });
    } else {
      alert("Failed to add event.");
    }
  } catch (e) {
    console.error(e);
    alert("Error adding event.");
  } finally {
    btnAddEvent.textContent = "+ Add Session";
    btnAddEvent.disabled = false;
  }
}
if (btnRefreshCalendar) btnRefreshCalendar.addEventListener("click", loadUpcomingEvents);
if (btnAddEvent) btnAddEvent.addEventListener("click", addCalendarEvent);
const openLoginBtn = document.getElementById("openLoginBtn");
if (openLoginBtn) {
  openLoginBtn.addEventListener("click", () => {
    if (window.Auth && window.Auth.show) {
      window.Auth.show("login");
    }
  });
}
const openRegisterBtn = document.getElementById("openRegisterBtn");
if (openRegisterBtn) {
  openRegisterBtn.addEventListener("click", () => {
    if (window.Auth && window.Auth.show) {
      window.Auth.show("register");
    }
  });
}
const btnConnectCalendar = document.getElementById("btnConnectCalendar");
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
  updateCalendarButtonState();
  btnConnectCalendar.addEventListener("click", () => {
    btnConnectCalendar.textContent = "Connecting...";
    chrome.identity.getAuthToken({ interactive: true }, (token) => {
      if (chrome.runtime.lastError || !token) {
        console.error(chrome.runtime.lastError);
        btnConnectCalendar.textContent = "Connection Failed. Try again.";
        setTimeout(() => {
          btnConnectCalendar.textContent = "Connect Google Calendar";
        }, 2e3);
      } else {
        console.log("Calendar token obtained:", token);
        updateCalendarButtonState();
        chrome.alarms.create("checkCalendar", { when: Date.now() + 1e3 });
      }
    });
  });
}
function updateTimerDisplay() {
  const mins = Math.floor(timeLeft / 60);
  const secs = timeLeft % 60;
  timerDisplay.textContent = `${mins}:${secs < 10 ? "0" : ""}${secs}`;
  chrome.storage.local.set({ timerTimeLeft: timeLeft });
}
function syncToFirebase(active) {
  if (!currentUser) return;
  let data;
  if (active) {
    const endTime = Date.now() + timeLeft * 1e3;
    data = {
      isActive: true,
      endTime
    };
  } else {
    data = {
      isActive: false,
      endTime: null
    };
  }
  chrome.runtime.sendMessage({ type: "UPDATE_SESSION", data });
}
function startTimer(restoring = false, fromSync = false) {
  if (timerInterval) clearInterval(timerInterval);
  timerInterval = setInterval(() => {
    if (timeLeft > 0) {
      timeLeft--;
      updateTimerDisplay();
      chrome.storage.local.set({ timerTimeLeft: timeLeft, timerRunning: true, timerLastUpdate: Date.now(), focusActive: true });
    } else {
      stopTimer();
    }
  }, 1e3);
  timerRunning = true;
  playPauseBtn.innerHTML = "&#10073;&#10073;";
  if (!restoring) {
    chrome.storage.local.set({ timerRunning: true, timerLastUpdate: Date.now(), focusActive: true });
    if (!fromSync) syncToFirebase(true);
  }
}
function stopTimer(fromSync = false) {
  clearInterval(timerInterval);
  timerRunning = false;
  playPauseBtn.innerHTML = "&#9654;";
  chrome.storage.local.set({ timerRunning: false, focusActive: false });
  if (!fromSync) syncToFirebase(false);
}
if (playPauseBtn) {
  playPauseBtn.addEventListener("click", () => {
    if (timerRunning) {
      stopTimer();
    } else {
      startTimer();
    }
  });
}
if (minusBtn) {
  minusBtn.addEventListener("click", () => {
    timeLeft = Math.max(60, timeLeft - 5 * 60);
    updateTimerDisplay();
    chrome.storage.local.set({ timerTimeLeft: timeLeft });
  });
}
if (plusBtn) {
  plusBtn.addEventListener("click", () => {
    timeLeft = Math.min(60 * 60, timeLeft + 5 * 60);
    updateTimerDisplay();
    chrome.storage.local.set({ timerTimeLeft: timeLeft });
  });
}
if (resetBtn) {
  resetBtn.addEventListener("click", () => {
    stopTimer();
    timeLeft = 25 * 60;
    updateTimerDisplay();
    chrome.storage.local.set({ timerTimeLeft: timeLeft });
  });
}
updateTimerDisplay();
