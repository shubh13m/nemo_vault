# Nemo Vault

**Secure your data in the crushing depths of the abyss.**

Nemo Vault is a high-security privacy application built with **Flutter** for Android and Windows. It utilizes a **zero-knowledge architecture**, ensuring user privacy through local-only encryption.

## 🛠 Technical Stack

* **Framework:** Flutter (Android & Windows)
* **Encryption:** AES-GCM (Authenticated Encryption)
* **Key Derivation:** SHA-256 (User Passphrase to 32-byte key)
* **Storage:** FlutterSecureStorage (Hardware-backed Keystore/Keychain)
* **Concurrency:** Background Isolates for non-blocking encryption

---

## 🗺 Roadmap & Release Tracking

### 🌊 Phase 1: The Foundation (Major Release v1.0.0)
*Focus: Establishing functional security and the "Submarine Hatch".*

* **[x] v1.0.0.0: User-Defined Passphrase (SHA-256)**
* *Details:* Replaces static keys with dynamic user input. The passphrase is hashed via SHA-256 to create a unique 32-byte key.

* **[x] v1.1.0.0: Auto-Lock on Background**
* *Details:* Monitors app lifecycle; if the app is minimized or the screen turns off, the vault "seals" (clears the key from memory) immediately.

* **[ ] v1.2.0.0: Security "Destruct" Timer**
* *Details:* Implements an exponential backoff for incorrect attempts. After X failed tries, the app locks for a set duration to prevent brute-force attacks.

### 🚢 Phase 2: The Core Workflow (Major Release v2.0.0)
*Focus: The "Decompression Chamber" and file handling.*

* **[ ] v2.1.0.0: Interactive Staging Area**
* *Details:* A "Cargo Bay" UI where users drag or pick files. Features a multi-pick grid with **Red [X]** icons to remove files before they are committed to the abyss.

* **[ ] v2.2.0.0: "VAULT LOCK" Bulk Action**
* *Details:* The heavy-lifting engine. Processes all staged files through Background Isolates to encrypt them simultaneously without freezing the UI.

* **[ ] v2.3.0.0: "Clean Sweep" Logic**
* *Details:* A safety-first deletion protocol. Only deletes the original unencrypted files from the device storage *after* the encryption process is verified as successful.

* **[ ] v2.4.0.0: Separate Archive Panel**
* *Details:* The "Gallery of Secrets." A secure viewing area where encrypted files are temporarily decrypted into memory for viewing.

### ☁️ Phase 3: Portability & Cloud (Major Release v3.0.0)
*Focus: Ensuring data survival across the "Deep Sea".*

* **[ ] v3.1.0.0: Google Drive Integration**
* *Details:* Syncs encrypted `.nemo` blobs to a hidden app-data folder on Google Drive, allowing for secure off-device backups.

* **[ ] v3.2.0.0: Universal Decryptor & Cloud Import**
* *Details:* Allows users to pull files from the cloud onto a new device. As long as they have their secret phrase, they can "resurface" their data anywhere.

### 📊 Phase 4: Intelligence & Insights (Major Release v4.0.0)
*Focus: Data visualization and vault health.*

* **[ ] v4.1.0.0: Dashboard Stats**
* *Details:* Displays a sonar-style dashboard showing total file count, total size of the "Abyss," and a calculated "Security Score" based on passphrase strength.

* **[ ] v4.2.0.0: Passphrase "Hint" System**
* *Details:* A user-defined hint (not the password itself) to help recall complex phrases without compromising the zero-knowledge integrity.

* **[ ] v4.3.0.0: Automatic File Categorization**
* *Details:* Uses file signatures to automatically sort imports into Photos, Documents, and Videos within the Archive Panel.

### 🎭 Phase 5: Elite Stealth & Cosmetics (Major Release v5.0.0)
*Focus: The "Ghost Submarine" aesthetic and panic features.*

* **[ ] v5.1.0.0: "Decoy Vault" (Panic Feature)**
* *Details:* Entering a specific "Panic PIN" opens a dummy vault filled with harmless "Filmy Fool" content to mislead unauthorized users.

* **[ ] v5.2.0.0: Stealth Icon**
* *Details:* An Android/Windows feature to change the app's launcher icon and name to something mundane, like a "Calculator" or "Weather" app.

* **[ ] v5.3.0.0: "Deep Sea" Theme Customization**
* *Details:* Aesthetic toggle between "Shallow" (standard dark mode) and "Abyss" (true OLED black) to save battery and enhance immersion.
