s

# Descriere Livrabile Proiect

## 1. Adresa Repository

**Link Repository:** [github.com/dorogus1/licenta](https://github.com/dorogus1/licenta)

## 2. Pasi de compilare

### Client Mobile & Desktop (Flutter)

- Locatie: `focus_app/`
- Prerechizite: Flutter SDK, toolchain Android/Windows corespunzator
- Instalare pachete:

  ```bash
  flutter pub get
  ```
- Build Android (APK):

  ```bash
  flutter build apk
  ```
- Build Windows (EXE):

  ```bash
  flutter build windows
  ```

  (Pentru instalator MSIX se ruleaza aditional: `flutter pub run msix:create`)

### Extensie Browser (Chrome/Chromium)

- Locatie: `extensie_web/`
- Prerechizite: Node.js / npm
- Instalare dependinte:

  ```bash
  npm install
  ```
- Compilare proiect (Vite):

  ```bash
  npx vite build
  ```

  (Artefactele rezultate vor fi generate in folderul `dist/`)

## 3. Pasi de instalare si lansare

### Android

- **Debug / Dev:** Se conecteaza un device/emulator (ADB activ) si se ruleaza `flutter run` din `focus_app/`.
- **Standalone / Release:** Se instaleaza direct fisierul `focus_app.apk` aflat in root-ul proiectului (necesita activarea permisiunii pentru surse necunoscute pe device).

### Windows

- **Debug / Dev:** Se ruleaza `flutter run -d windows` din root-ul aplicatiei Flutter.
- **Standalone / Release:** O versiune precompilata a aplicatiei se regaseste in directorul `focus_app_windows/`. Aceasta poate fi lansata ruland executabilul din interiorul folderului fara extra dependinte.

### Extensie Browser

1. Se acceseaza `chrome://extensions/` din browser si se activeaza flag-ul **Developer mode**.
2. Se foloseste optiunea **Load unpacked** si se selecteaza directorul `extensie_web/dist/`.
