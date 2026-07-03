# Focus Shield Sync

Focus Shield Sync este un ecosistem complex de productivitate conceput pentru a te ajuta sa iti mentii concentrarea minimizand distragerile digitale. Este compus dintr-o aplicatie cross-platform pentru mobil/desktop si o extensie de browser, ambele sincronizate prin cloud pentru a se asigura ca regulile tale de concentrare se aplica peste tot.

## Ghid de Instalare

### Android (APK)
Pentru a instala aplicatia pe dispozitivul tau Android:
1. Descarca fisierul `app-release.apk` din acest folder.
2. Transfera-l pe telefon (sau descarca-l direct pe dispozitiv).
3. Deschide fisierul pe telefon. Daca sistemul te intreaba, permite "Instalarea din surse necunoscute" (Unknown Sources) din setarile browserului sau managerului de fisiere.
4. Apasa pe **Install** si apoi deschide aplicatia.

### Windows (Desktop)
Aplicatia de Windows poate fi rulata direct din sursa sau instalata ca pachet nativ:

**Varianta Instalabila (Recomandat):**
1. Navigheaza in `focus_app`.
2. Ruleaza comanda pentru a genera pachetul MSIX:
   ```bash
   flutter pub run msix:create
   ```
3. Instaleaza fisierul generat (il vei gasi in `focus_app/build/windows/x64/runner/Release`).

**Varianta de Dezvoltare:**
1. Navigheaza in `focus_app`.
2. Ruleaza comanda:
   ```bash
   flutter run -d windows
   ```

## Structura Proiectului

Repository-ul este organizat in doua componente principale:

* **`focus_app/`**: O aplicatie bazata pe Flutter pentru Mobil (Android/iOS) si Desktop (Windows). Aceasta aplicatie ruleaza in fundal pentru a monitoriza si bloca aplicatiile care te distrag in functie de programul tau.
* **`extensie_web/`**: O extensie de browser Chrome (Manifest V3) care blocheaza site-urile care te distrag si se integreaza cu Google Calendar pentru a automatiza sesiunile de concentrare.

## Functionalitati

### Aplicatie Mobila & Desktop (`focus_app`)

* **Blocarea Aplicatiilor:** Previne accesul la aplicatiile specificate care distrag atentia.
* **Serviciu in Fundal:** Ruleaza silentios in fundal pentru a impune regulile fara a tine aplicatia deschisa.
* **Statistici de Utilizare:** Urmareste utilizarea aplicatiilor pentru a te ajuta sa iti intelegi obiceiurile.
* **Cross-Platform:** Construita cu Flutter pentru Android, iOS si Windows.
* **Integrare in Sistem:** Foloseste API-uri native pentru permisiuni, ferestre suprapuse si monitorizarea proceselor.

### Extensie de Browser (`extensie_web`)

* **Blocarea Site-urilor:** Foloseste API-ul `declarativeNetRequest` pentru a bloca accesul la URL-urile care te distrag.
* **Sincronizare Calendar:** Se integreaza cu Google Calendar pentru a activa automat "Modul Concentrare" in timpul evenimentelor programate.
* **Pagini de Blocare Personalizate:** Afiseaza o pagina motivationala sau informativa atunci cand un site este blocat.
* **Integrare Firebase:** Sincronizeaza setarile si datele cu aplicatia mobila.

## Tehnologii Folosite

* **Frontend (Aplicatie):** [Flutter](https://flutter.dev/) (Dart)
* **Frontend (Extensie):** JavaScript, HTML, CSS, [Vite](https://vitejs.dev/)
* **Backend / Sincronizare:** [Firebase](https://firebase.google.com/) (Realtime Database, Auth)
* **Autentificare:** Google OAuth2, Firebase Auth

## Cum sa Incepi

### Cerinte preliminare

* [Flutter SDK](https://docs.flutter.dev/get-started/install) instalat.
* [Node.js](https://nodejs.org/) si npm instalate.
* Un proiect Firebase configurat (cu `google-services.json` pentru aplicatie si configurare web pentru extensie).

### 1. Setarea Aplicatiei Flutter

1. Navigheaza in directorul aplicatiei:
   ```bash
   cd focus_app
   ```
2. Instaleaza dependintele:
   ```bash
   flutter pub get
   ```
3. Ruleaza aplicatia:
   ```bash
   # Pentru Android/iOS
   flutter run

   # Pentru Windows
   flutter run -d windows
   ```

### 2. Setarea Extensiei de Browser

1. Navigheaza in directorul extensiei:

   ```bash
   cd extensie_web
   ```
2. Instaleaza dependintele:

   ```bash
   npm install
   ```
3. Construieste extensia:

   ```bash
   npx vite build
   ```
   *Aceasta va genera un folder `dist`.*
4. Incarca in Chrome:

   * Deschide Chrome si mergi la `chrome://extensions/`.
   * Activeaza **Developer mode** (Modul Dezvoltator) (dreapta sus).
   * Da click pe **Load unpacked** (Incarca extensia neimpachetata).
   * Selecteaza folderul `dist` creat la pasul anterior.
