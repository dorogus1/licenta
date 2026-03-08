# Focus Shield Sync

Focus Shield Sync is a comprehensive productivity ecosystem designed to help you maintain focus by minimizing digital distractions. It consists of a cross-platform mobile/desktop application and a browser extension, both synchronized via the cloud to ensure your focus rules apply everywhere.

## 🚀 Ghid de Instalare (Installation Guide)

### 📱 Android (APK)
Pentru a instala aplicația pe dispozitivul tău Android:
1. Descarcă fișierul `app-release.apk` din acest folder.
2. Transferă-l pe telefon (sau descarcă-l direct pe dispozitiv).
3. Deschide fișierul pe telefon. Dacă sistemul te întreabă, permite "Instalarea din surse necunoscute" (Unknown Sources) din setările browserului sau managerului de fișiere.
4. Apasă pe **Install** și apoi deschide aplicația.

### 💻 Windows (Desktop)
Aplicația de Windows poate fi rulată direct din sursă sau instalată ca pachet nativ:

**Varianta Instalabilă (Recomandat):**
1. Navighează în `focus_app`.
2. Rulează comanda pentru a genera pachetul MSIX:
   ```bash
   flutter pub run msix:create
   ```
3. Instalează fișierul generat (îl vei găsi în `focus_app/build/windows/x64/runner/Release`).

**Varianta de Dezvoltare:**
1. Navighează în `focus_app`.
2. Rulează comanda:
   ```bash
   flutter run -d windows
   ```

## 📂 Project Structure

The repository is organized into two main components:

* **`focus_app/`**: A Flutter-based application for Mobile (Android/iOS) and Desktop (Windows). This app runs in the background to monitor and block distracting applications based on your schedule.
* **`extensie_web/`**: A Chrome Browser Extension (Manifest V3) that blocks distracting websites and integrates with your Google Calendar to automate focus sessions.

## ✨ Features

### 📱 Mobile & Desktop App (`focus_app`)

* **App Blocking:** Prevents access to specified distracting applications.
* **Background Service:** Runs silently in the background to enforce rules without keeping the app open.
* **Usage Statistics:** Tracks your app usage to help you understand your habits.
* **Cross-Platform:** Built with Flutter for Android, iOS, and Windows.
* **System Integration:** Uses native APIs for permissions, overlay windows, and process monitoring.

### 🌐 Browser Extension (`extensie_web`)

* **Website Blocking:** Uses the `declarativeNetRequest` API to block access to distracting URLs.
* **Calendar Sync:** Integrates with Google Calendar to automatically enable "Focus Mode" during scheduled events.
* **Custom Block Pages:** Displays a motivational or informative page when a site is blocked.
* **Firebase Integration:** Syncs settings and data with the mobile app.

## 🛠️ Tech Stack

* **Frontend (App):** [Flutter](https://flutter.dev/) (Dart)
* **Frontend (Extension):** JavaScript, HTML, CSS, [Vite](https://vitejs.dev/)
* **Backend / Sync:** [Firebase](https://firebase.google.com/) (Realtime Database, Auth)
* **Authentication:** Google OAuth2, Firebase Auth

## 🚀 Getting Started

### Prerequisites

* [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
* [Node.js](https://nodejs.org/) and npm installed.
* A Firebase project configured (with `google-services.json` for the app and web config for the extension).

### 1️⃣ Setting up the Flutter App

1. Navigate to the app directory:
   ```bash
   cd focus_app
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   # For Android/iOS
   flutter run

   # For Windows
   flutter run -d windows
   ```

### 2️⃣ Setting up the Browser Extension

1. Navigate to the extension directory:

   ```bash
   cd extensie_web
   ```
2. Install dependencies:

   ```bash
   npm install
   ```
3. Build the extension:

   ```bash
   npx vite build
   ```
   *This will generate a `dist` folder.*
4. Load into Chrome:

   * Open Chrome and go to `chrome://extensions/`.
   * Enable **Developer mode** (top right).
   * Click **Load unpacked**.
   * Select the `dist` folder created in the previous step.
