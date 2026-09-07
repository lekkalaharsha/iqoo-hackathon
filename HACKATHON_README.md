> Historical plan/context: consult PROJECT.md for current verification.
> Offline, accessibility, latency, and device claims below are not current
> acceptance evidence. Follow AGENTS.md safety rules for all new work.

# Logic Legends - iQOO Hackathon 2026 Chennai

## 🎯 Project Overview
**Phone-first AI Assistant** with on-device LLM (Gemma 2B), GPS context, web browsing, **voice activation**, and full accessibility for blind/visually impaired users. Built for iQOO 15 Snapdragon NPU.

## 🏆 Hackathon Track
**Smart Living (Track #5)** - AI-powered solutions for everyday convenience

---

## 🚀 Key Features for Judges

### 1. **On-Device LLM** (15% phone usage score)
- Gemma 2B running on Snapdragon NPU via `tflite_flutter`
- Zero cloud dependency for core features
- Falls back to cloud Gemini if model not bundled

### 2. **🎙️ Voice Assistant & Wake Word** (NEW - Creative Phone Use)
- **"Hey Assistant"** wake word activation (configurable)
- **Shake-to-activate** for accessibility (accelerometer)
- 25+ voice commands across all features
- **Full Tamil + English** voice support
- Continuous listening mode for hands-free operation

### 3. **🌐 Web Browsing / Real-World Info** (NEW)
- DuckDuckGo HTML scraping (no API key needed)
- Auto-detects when real-time info needed (weather, prices, news, nutrition)
- Specialized searches: food nutrition, documents, local places, current events
- Injects live web context into AI prompts with source citations

### 4. **GPS-Enhanced AI Prompts** (Creative phone use)
- Sub-10m accuracy overlay on camera (green/yellow/orange/red)
- Reverse geocoding for address context
- Location automatically injected into every AI prompt
- Live GPS bottom sheet with coordinates, altitude, speed, heading

### 5. **♿ Full Accessibility for Blind Users** (NEW - High Impact)
- **Voice-only navigation** - all features via voice commands
- **TalkBack/VoiceOver compatible** - semantic labels, live regions
- **High contrast mode** toggle
- **Large text** (1.5x) toggle
- **Screen reader announcements** for all state changes
- **Shake gesture** for wake word toggle
- **Vibration feedback** for all interactions

### 6. **Offline-First Architecture** (Real-world utility)
- Response caching with 7-day TTL, 50-entry LRU
- Pre-loaded test images for demo
- Works 100% offline after first run
- Offline banner + cached response badges

### 7. **Tamil Localization** (Local relevance)
- Full UI in Tamil/English (80+ strings)
- AI prompts in Tamil
- Voice output in Tamil (TTS with `ta-IN` locale)
- Runtime language switch

### 8. **Office Kit Ready** (10% score)
- Pre-built release APK for Red Light install
- Config-driven prompts (no recompile needed)
- Debug overlay for live metrics

---

## 📱 Demo Flow (2 minutes)

```
1. Open app → Camera loads with GPS accuracy badge (green = ≤10m)
2. Say "Hey Assistant" → Voice assistant activates
3. Say "Take photo" → Captures image in current mode
4. Say "Describe scene" → AI describes with GPS context
5. Say "Switch to food mode" → Changes to food labels
6. Say "Identify food" → Captures + analyzes nutrition/allergens
7. Say "Read text" → OCR mode for documents/signs
8. Say "Where am I" → Announces address + GPS coordinates
9. Say "Search weather Chennai" → Live web search + AI summary
10. Switch to Tamil → Full UI + voice in Tamil
11. Disconnect WiFi → Still works with cached responses
12. Shake phone → Toggles wake word listening
13. Double-tap → Debug overlay (FPS, GPS, cache, network, model)
14. Enable High Contrast + Large Text → Full accessibility demo
```

---

## 🎙️ Voice Commands Reference

| Category | Commands (EN) | Commands (TA) |
|----------|---------------|---------------|
| **Capture** | "Take photo", "Snap picture", "Capture image" | "புகைப்படம் எடு", "திரைப்படம் பிடி" |
| **Describe** | "Describe scene", "What do you see", "What's around" | "சூழலை விவரி", "இங்கு என்ன உள்ளது" |
| **Food** | "Identify food", "What's this food", "Nutrition info" | "உணவு அடையாளம்", "நீர்ப்பு தகவல்" |
| **Text** | "Read text", "Scan text", "Extract writing" | "எழுத்து வாசி", "உரை அம்மா" |
| **Document** | "Analyze document", "Read document", "Summarize paper" | "ஆவணம் பகுப்பாய்வு", "கத்து வாசி" |
| **Location** | "Where am I", "My location", "Address" | "எங்கே இருக்கிறேன்", "என் இடம்" |
| **Navigation** | "Navigate to [place]", "Directions to [place]" | "திசை [இடம்]", "मार்க் [இடம்]" |
| **Web Search** | "Search [topic]", "Look up [topic]", "Latest news", "Weather" | "தேடு [விஷயம்]", "செய்தி", "வானிலை" |
| **Response** | "Read last response", "Repeat answer", "Say again" | "கடைசி பதில் வாசி", "மறுபடியும் சொல்" |
| **Modes** | "Switch to explore/food/text/document" | "மோடு மாற்று ஆராய்வு/உணவு/உரை/ஆவணம்" |
| **Features** | "Enable GPS/TTS/Vibration/Browsing/Offline" | "GPS/பேச்சு/நடை/உலாவல்/ஆஃப்லைன் இயக்கு" |
| **Settings** | "Open settings", "Show menu" | "அமைப்பு திற", "மெனู காட்டு" |
| **Help** | "Help", "What can you do", "Commands" | "உதவி", "நீங்கள் என்ன செய்யலாம்" |
| **Emergency** | "Emergency", "Help me", "SOS", "Danger" | "அவசரம்", "உதவி", "SOS" |

---

## 🔧 Build for Event

```bash
# 1. Get dependencies
flutter pub get

# 2. Generate JSON serialization code
flutter pub run build_runner build --delete-conflicting-outputs

# 3. Build release APK (for Office Kit install during Red Light)
flutter build apk --release --target-platform android-arm64

# 4. APK location: build/app/outputs/flutter-apk/app-release.apk
```

---

## 📦 Office Kit Workflow (Red Light)

| Green Light (Laptop) | Red Light (Phone Only) |
|---------------------|------------------------|
| `flutter build apk --release` | Test camera + GPS + AI + Voice |
| Drag APK → Office Kit → Install | Voice commands for all features |
| Push test images to phone | Demo rehearsal (hands-free) |
| Configure prompts via `assets/config/prompts.json` | Record demo video |
| Edit `app_config.json` for feature flags | Toggle accessibility modes |

---

## 📁 Key Files for Hackathon

```
assets/
├── config/
│   ├── app_config.json       # Feature flags, model config, GPS thresholds, accessibility
│   └── prompts.json          # AI prompts per mode (EN/TA)
├── l10n/
│   ├── en.json               # English strings (100+)
│   └── ta.json               # Tamil strings (100+)
└── models/
    └── gemma-2b-it-q4.tflite # On-device model (add before event)

lib/
├── services/
│   ├── ai_service.dart               # Unified on-device + cloud AI + web browsing
│   ├── browsing_service.dart         # NEW: DuckDuckGo scraping + page extraction
│   ├── config_service.dart           # Loads app_config.json + prompts.json
│   ├── localization_service.dart     # EN/TA with SharedPreferences
│   ├── on_device_llm_service.dart    # TFLite Gemma 2B inference
│   ├── offline_cache_service.dart    # Response caching
│   ├── gps_service.dart              # High-accuracy GPS + geocoding
│   └── voice_assistant_service.dart  # NEW: Wake word, commands, TTS, shake
├── widgets/
│   └── debug_overlay.dart            # Double-tap: FPS, GPS, cache, network, model
└── screens/
    ├── homepage.dart                 # Camera + GPS + Voice + Accessibility
    ├── chatscreen.dart               # DashChat + AI + cache + TTS + Voice
    └── settings_screen.dart          # All feature toggles + accessibility
```

---

## ⚙️ Configuration (No Recompile - Edit via Office Kit)

### `assets/config/app_config.json`
```json
{
  "features": {
    "on_device_llm": true,
    "offline_mode": true,
    "tamil_support": true,
    "gps_enabled": true,
    "tts_enabled": true,
    "vibration_feedback": true,
    "web_browsing": true
  },
  "gps": {
    "accuracy_threshold_high": 10,
    "accuracy_threshold_medium": 50
  }
}
```

### `assets/config/prompts.json`
```json
{
  "modes": {
    "explore": {
      "en": "Describe this image in detail. What do you see?",
      "ta": "இதை விவரமாக விவரிக்கவும். நீங்கள் என்ன দেখுகிறீர்கள்?"
    },
    "food": {
      "en": "Identify this food item. List ingredients, allergens, and nutritional info.",
      "ta": "இந்த உணவு பொருளை அடையாளம் காணுங்கள். கூறுகள், ஆலர்ஜிகள், ஊட்டச்சத்து தகவல்களை பட்டியலிடுங்கள்."
    },
    "text": {
      "en": "Extract and read all text from this image. Preserve formatting.",
      "ta": "இதிலிருந்து அனைத்து உரையையும் விசイして 読み取り、 வடிவமைப்பைப் பாதுகாத்து வைக்கவும்."
    },
    "document": {
      "en": "Analyze this document. Summarize key information, dates, amounts, and action items.",
      "ta": "இந்த ஆவணத்து�்த முக்கிய தகவல்கள், தேதிகள், தொகைகள், செயல் items まとめ してください。"
    }
  },
  "location_context": {
    "en": "Location context: {address} (GPS: {lat}, {lon}, accuracy: {accuracy}m)",
    "ta": "இடம் சூழல்: {address} (GPS: {lat}, {lon}, துல்லியம்: {accuracy}m)"
  }
}
```

---

## 🎪 Pre-Event Checklist

- [ ] Add Gemma 2B TFLite model to `assets/models/gemma-2b-it-q4.tflite`
- [ ] Add test images to `assets/images/` (food, document, text, scene)
- [ ] Set Gemini API key in `lib/screens/constapi.dart`
- [ ] Build release APK and test on iQOO 15
- [ ] Install Office Kit on laptop, practice mirror + install + remote control
- [ ] **Test Voice Assistant**: Wake word, all 25+ commands, Tamil + English
- [ ] **Test Accessibility**: TalkBack, High Contrast, Large Text, Shake gesture
- [ ] **Test Web Browsing**: Search, nutrition, weather, local places
- [ ] Prepare 3 Tamil demo phrases for voice
- [ ] Pack: laptop, charger, power bank (20k mAh), USB-C cable

---

## 🏁 Judging Criteria Mapping

| Criteria (Weight) | How We Score |
|-------------------|--------------|
| **End Product Quality (30%)** | Camera+GPS+AI+Voice+Web working, polished UI, zero crashes, 4 modes |
| **Novelty & Impact (20%)** | GPS-injected prompts, offline-first, Tamil, **voice assistant for blind**, **web browsing**, accessibility |
| **Creative Phone Use (15%)** | Camera, GPS, NPU, **accelerometer (shake)**, **microphone (wake word)**, TTS, vibration, **web scraping** |
| **Technical Depth (15%)** | TFLite inference, config-driven, cache, localization, **voice command parsing**, **HTML scraping**, semantic accessibility |
| **Office Kit Usage (10%)** | APK install, remote control, file transfer, config edits logged |
| **Demo & Presentation (10%)** | 2-min flow, **voice-only demo**, Tamil demo, offline demo, accessibility demo |

---

## 🆘 Emergency Fallbacks

| Failure | Fallback |
|---------|----------|
| Model not loading | Cloud Gemini API (auto) |
| GPS denied | Manual location input |
| Camera crash | Pre-loaded test images |
| Network down | Cached responses |
| TTS not working | Visual only |
| Voice recognition fails | Touch fallback + visual commands |
| Wake word not detected | Shake gesture + manual button |

---

## ♿ Accessibility Compliance

| Feature | Implementation |
|---------|----------------|
| **Screen Reader** | Semantic labels, live regions, headers, hints |
| **Voice Control** | 25+ commands, wake word, continuous listening |
| **High Contrast** | System-level toggle, Material 3 support |
| **Large Text** | 1.5x scale factor, dynamic text scaling |
| **Vibration** | Haptic feedback for all actions |
| **Shake Gesture** | Accelerometer-based wake word toggle |
| **TTS** | `ta-IN` / `en-IN` locales, interruptible |
| **Focus Management** | Logical tab order, visible focus indicators |

---

## 📞 Contact
Built for iQOO Hackathon 2026 Chennai  
Track: Smart Living  
**Innovation**: Voice-first AI for blind users + Real-time web browsing + On-device LLM
