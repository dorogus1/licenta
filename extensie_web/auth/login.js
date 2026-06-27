import { initializeApp } from "firebase/app";
import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut, sendPasswordResetEmail, GoogleAuthProvider, signInWithCredential } from "firebase/auth";

const firebaseConfig = {
  apiKey: "AIzaSyDiUH04OAUwJk8vdDbqFrQuH-F7ybWBUiY",
  databaseURL: "https://focus-shild-default-rtdb.europe-west1.firebasedatabase.app"
  // other config keys can go here if needed
};

// Initialize Firebase app used by the auth component
export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app); // Also export auth directly logic

export async function mountAuth() {
  console.log('[auth] mountAuth start');
  // Avoid mounting multiple times
  if (document.getElementById('authOverlay')) {
    console.log('[auth] authOverlay already present; skipping');
    return;
  }

  const container = document.getElementById('authContainer');
  const mountTarget = container || document.body;

  // Load markup and append to the chosen mount target
  try {
    console.log('[auth] fetching auth/login.html using chrome.runtime.getURL');
    const url = (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getURL) ? chrome.runtime.getURL('auth/login.html') : 'auth/login.html';
    console.log('[auth] fetch url:', url);
    const res = await fetch(url);
    console.log('[auth] fetch response:', res.status, res.ok);
    if (!res.ok) throw new Error(`Could not load auth HTML (status ${res.status})`);
    const html = await res.text();

    // Ensure the shared CSS file from extension is loaded so UI matches the main page
    if (!document.getElementById('authStylesLink')) {
      const link = document.createElement('link');
      link.id = 'authStylesLink';
      link.rel = 'stylesheet';
      const cssUrl = (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getURL) ? chrome.runtime.getURL('auth.css') : 'auth.css';
      link.href = cssUrl;
      document.head.appendChild(link);
    }

    const wrapper = document.createElement('div');
    wrapper.innerHTML = html.trim();
    const overlay = wrapper.firstElementChild;
    if (!overlay) throw new Error('Auth HTML had no root element');
    // hide overlay initially so it only shows when requested
    overlay.style.display = 'none';
    mountTarget.appendChild(overlay);
    console.log('[auth] authOverlay appended to', mountTarget.id || 'body');
  } catch (err) {
    console.error('[auth] Failed to load auth UI:', err);
    return;
  }

  // Query elements inside the mounted auth UI (from the document root)
  const authOverlay = document.getElementById('authOverlay');
  const tabLogin = document.getElementById('tabLogin');
  const tabRegister = document.getElementById('tabRegister');
  const loginForm = document.getElementById('loginForm');
  const registerForm = document.getElementById('registerForm');
  const loginError = document.getElementById('loginError');
  const registerError = document.getElementById('registerError');
  const emailInput = document.getElementById('emailInput');
  const passwordInput = document.getElementById('passwordInput');
  const regEmailInput = document.getElementById('regEmailInput');
  const regPasswordInput = document.getElementById('regPasswordInput');
  const regPasswordRepeat = document.getElementById('regPasswordRepeat');
  const googleLoginBtn = document.getElementById('googleLoginBtn');

  // Debug: log elements availability
  console.log('[auth] elements:', {
    haveRegisterForm: !!registerForm,
    haveRegEmail: !!regEmailInput,
    haveRegPw: !!regPasswordInput,
    haveRegPwRepeat: !!regPasswordRepeat
  });

  // Attach a click log to the create account button for debugging
  if (registerForm) {
    const regBtn = registerForm.querySelector('button[type="submit"]');
    if (regBtn) {
      regBtn.addEventListener('click', () => console.log('[auth] register button clicked'));
      console.log('[auth] attached click listener to register button');
    } else {
      console.log('[auth] register button not found');
    }
  }
  let accountDetails = document.getElementById('accountDetails');
  if (!accountDetails) {
    accountDetails = document.createElement('div');
    accountDetails.id = 'accountDetails';
    accountDetails.style.width = '100%';
    accountDetails.style.textAlign = 'center';
    accountDetails.style.marginTop = '12px';
    authOverlay && authOverlay.querySelector('.auth-card') && authOverlay.querySelector('.auth-card').appendChild(accountDetails);
  }
  const accountActions = document.getElementById('accountActions');
  const accountEmail = document.getElementById('accountEmail');
  const resetPasswordBtn = document.getElementById('resetPasswordBtn');
  const logoutBtn = document.getElementById('logoutBtn');
  const accountMsg = document.getElementById('accountMsg');

  // Process any queued show() requests that happened before mount completed
  if (window.Auth && Array.isArray(window.Auth._queuedShows) && window.Auth._queuedShows.length) {
    console.log('[auth] processing queued shows:', window.Auth._queuedShows);
    window.Auth._queuedShows.forEach(tab => showAuthOverlay(true, tab));
    window.Auth._queuedShows = [];
  }

  function showAuthOverlay(show, tab = 'login') {
    console.log(`[auth] showAuthOverlay called -> show=${show}, tab=${tab}`);
    if (!authOverlay) { console.warn('[auth] showAuthOverlay: authOverlay is null'); return; }
    if (show) {
      authOverlay.style.display = 'flex';
      authOverlay.setAttribute('aria-hidden', 'false');
      authOverlay.style.pointerEvents = 'auto';
      if (tab === 'login') {
        tabLogin.classList.add('selected');
        tabRegister.classList.remove('selected');
        loginForm.style.display = '';
        registerForm.style.display = 'none';
        loginError.textContent = '';
        registerError.textContent = '';
      } else {
        tabLogin.classList.remove('selected');
        tabRegister.classList.add('selected');
        loginForm.style.display = 'none';
        registerForm.style.display = '';
        loginError.textContent = '';
        registerError.textContent = '';
      }
      setTimeout(() => {
        if (tab === 'login') emailInput && emailInput.focus();
        else regEmailInput && regEmailInput.focus();
      }, 100);
    } else {
      authOverlay.style.display = 'none';
      authOverlay.setAttribute('aria-hidden', 'true');
      authOverlay.style.pointerEvents = 'none';
      loginError.textContent = '';
      registerError.textContent = '';
    }
  }

  tabLogin && tabLogin.addEventListener('click', () => showAuthOverlay(true, 'login'));
  tabRegister && tabRegister.addEventListener('click', () => showAuthOverlay(true, 'register'));

  // Expose a tiny global API so other modules (popup) can check auth state / open overlay
  window.Auth = window.Auth || { currentUser: null, _queuedShows: [] };
  // If called before mount, queue requests
  window.Auth.show = (tab = 'login') => {
    console.log(`[auth] window.Auth.show called -> ${tab}`);
    // If mounted already, call directly
    const overlay = document.getElementById('authOverlay');
    if (overlay && typeof overlay.style !== 'undefined') {
      console.log('[auth] overlay present — calling showAuthOverlay');
      // actual show is implemented later with showAuthOverlay
      showAuthOverlay(true, tab);
    } else {
      // queue show until mounted
      window.Auth._queuedShows.push(tab);
      console.log('[auth] overlay not present — queued show request');
    }
  };
  window.Auth.currentUser = null;

  // Auth state handling
  onAuthStateChanged(auth, user => {
    window.Auth.currentUser = user;
    if (user) {
      showAuthOverlay(false);
      setTimeout(() => {
        if (authOverlay) {
          authOverlay.style.display = 'none';
          authOverlay.setAttribute('aria-hidden', 'true');
          authOverlay.style.pointerEvents = 'none';
        }
      }, 100);
      if (accountDetails) accountDetails.textContent = 'Logged in as:';
      if (accountActions) accountActions.style.display = '';
      if (accountEmail) accountEmail.textContent = user.email;
      if (accountMsg) {
        accountMsg.textContent = '';
        accountMsg.className = 'auth-error';
      }
    } else {
      // keep overlay closed by default — show on demand when user navigates to Account
      if (accountDetails) accountDetails.textContent = 'Not logged in.';
      if (accountActions) accountActions.style.display = 'none';
      if (accountEmail) accountEmail.textContent = '';
      if (accountMsg) {
        accountMsg.textContent = '';
        accountMsg.className = 'auth-error';
      }
    }
  });

  // --- LOGIN ---
  loginForm && loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!loginError) return;
    loginError.textContent = '';
    loginError.className = 'auth-error';
    try {
      await signInWithEmailAndPassword(auth, emailInput.value, passwordInput.value);
      loginError.textContent = '';
    } catch (err) {
      loginError.textContent = err.message;
      loginError.className = 'auth-error';
    }
  });

  // --- GOOGLE LOGIN ---
  googleLoginBtn && googleLoginBtn.addEventListener('click', () => {
      loginError.textContent = 'Contacting Google...';
      
      const clientId = '1024855875521-8ajkijhu9qoo37o03aifarf7739soem7.apps.googleusercontent.com';
      const redirectUri = chrome.identity.getRedirectURL();
      const scopes = [
          'https://www.googleapis.com/auth/calendar',
          'https://www.googleapis.com/auth/userinfo.email',
          'https://www.googleapis.com/auth/userinfo.profile'
      ].join(' ');
      
      const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?` +
          `client_id=${clientId}` +
          `&response_type=token` +
          `&redirect_uri=${encodeURIComponent(redirectUri)}` +
          `&scope=${encodeURIComponent(scopes)}`;

      chrome.identity.launchWebAuthFlow({
          url: authUrl,
          interactive: true
      }, async (responseUrl) => {
          if (chrome.runtime.lastError || !responseUrl) {
              console.error('[auth] launchWebAuthFlow error:', chrome.runtime.lastError);
              loginError.textContent = 'Google Sign-In cancelled or failed.';
              return;
          }

          loginError.textContent = 'Signing in to Focus Shield...';
          console.log('[auth] Google token obtained via launchWebAuthFlow, attempt Firebase sign-in');
          
          try {
              const url = new URL(responseUrl);
              const params = new URLSearchParams(url.hash.substring(1));
              const token = params.get('access_token');
              const expiresIn = parseInt(params.get('expires_in') || '3600', 10);

              if (!token) {
                  throw new Error('Access token not found in Google response.');
              }

              // Store token in local storage for fallback/calendar use
              const expiryTime = Date.now() + (expiresIn * 1000);
              await new Promise((resolve) => {
                  chrome.storage.local.set({
                      google_access_token: token,
                      google_token_expiry: expiryTime
                  }, resolve);
              });

              const credential = GoogleAuthProvider.credential(null, token);
              const userCredential = await signInWithCredential(auth, credential);
              console.log('[auth] Firebase sign-in success:', userCredential.user.email);
          } catch (err) {
              console.error('[auth] Firebase sign-in error:', err.code, err.message);
              if (err.code === 'auth/account-exists-with-different-credential') {
                  loginError.textContent = 'An account already exists with this email but different login method.';
              } else {
                  loginError.textContent = 'Error: ' + err.message;
              }
          }
      });
  });

  // --- REGISTER ---
  registerForm && registerForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    console.log('[auth] register submit fired', {
      email: regEmailInput?.value?.slice(0,3) + '...',
      pwLength: regPasswordInput?.value?.length
    });
    if (!registerError) return;
    registerError.textContent = '';
    registerError.className = 'auth-error';
    if (regPasswordInput.value !== regPasswordRepeat.value) {
      registerError.textContent = "Passwords do not match.";
      return;
    }
    // simple client-side validation
    if (regPasswordInput.value.length < 6) {
      registerError.textContent = 'Password must be at least 6 characters.';
      return;
    }
    try {
      await createUserWithEmailAndPassword(auth, regEmailInput.value, regPasswordInput.value);
      registerError.textContent = 'Account created! You are now logged in.';
      registerError.className = 'auth-success';
      setTimeout(() => showAuthOverlay(false), 800);
    } catch (err) {
      console.error('[auth] createUser failed', err);
      registerError.textContent = err.message || 'Registration failed';
      registerError.className = 'auth-error';
    }
  });

  // Delegated fallback: capture submit events on document in case form handlers aren't attached
  if (!window.Auth._delegatedRegisterAttached) {
    window.Auth._delegatedRegisterAttached = true;
    document.addEventListener('submit', async (e) => {
      const form = e.target;
      if (!form || form.id !== 'registerForm') return;
      e.preventDefault();
      console.log('[auth] delegated register submit fired', {
        email: regEmailInput?.value?.slice(0,3) + '...',
        pwLength: regPasswordInput?.value?.length
      });
      if (!registerError) return;
      registerError.textContent = '';
      registerError.className = 'auth-error';
      if (regPasswordInput.value !== regPasswordRepeat.value) {
        registerError.textContent = "Passwords do not match.";
        return;
      }
      if (regPasswordInput.value.length < 6) {
        registerError.textContent = 'Password must be at least 6 characters.';
        return;
      }
      try {
        await createUserWithEmailAndPassword(auth, regEmailInput.value, regPasswordInput.value);
        registerError.textContent = 'Account created! You are now logged in.';
        registerError.className = 'auth-success';
        setTimeout(() => showAuthOverlay(false), 800);
      } catch (err) {
        console.error('[auth] delegated createUser failed', err);
        registerError.textContent = err.message || 'Registration failed';
        registerError.className = 'auth-error';
      }
    }, true);
    console.log('[auth] delegated submit listener attached');
  }

  // --- RESET PASSWORD ---
  resetPasswordBtn && resetPasswordBtn.addEventListener('click', async () => {
    if (accountMsg) {
      accountMsg.textContent = '';
      accountMsg.className = 'auth-error';
    }
    const user = auth.currentUser;
    if (user && user.email) {
      try {
        await sendPasswordResetEmail(auth, user.email);
        if (accountMsg) {
          accountMsg.textContent = 'Password reset email sent!';
          accountMsg.className = 'auth-success';
        }
      } catch (err) {
        if (accountMsg) {
          accountMsg.textContent = err.message;
          accountMsg.className = 'auth-error';
        }
      }
    }
  });

  // --- LOGOUT ---
  logoutBtn && logoutBtn.addEventListener('click', async () => {
    await signOut(auth);
  });
}

// Make mountAuth available globally and as default export so bundlers don't tree-shake it away
window.mountAuth = mountAuth;
export default mountAuth;

// Mount right away
mountAuth();