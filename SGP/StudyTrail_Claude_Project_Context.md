# StudyTrail — Project Context for Claude Project Knowledge

*Use this as the "Project Knowledge" / custom instructions for a Claude Project dedicated to this SGP. It summarizes every decision made so far so new chats don't lose context.*

---

## 1. Project Summary

**Name:** StudyTrail (working name — alternatives considered: Prepzy, Syllabo, PathWise, ExamPilot)

**One-liner:** An AI-powered educational planning platform — a personal AI assistant for exam preparation that ingests exam dates, syllabi, notes, PDFs, and YouTube videos/playlists to generate study roadmaps, schedule sessions, send reminders, and enable content Q&A.

**Type:** SGP (Student Group Project), B.E. Computer Science Engineering, CSPIT, Charusat University.

**Student:** Yash, Enrollment ID D25CS118, Batch B-2.

**Problem it solves:** Students preparing for school/college/competitive exams struggle to plan an effective, personalised study schedule. Exam dates, syllabi, and study material (notes, PDFs, YouTube lectures) are scattered, and manually working out what to study, when, and for how long is time-consuming and error-prone — leading to last-minute cramming, missed topics, and stress.

---

## 2. Core Concept / User Flow

1. User uploads exam/test date with syllabus (typed, PDF, or scanned photo via OCR).
2. AI schedules a study plan on a calendar automatically.
3. User uploads study material: notes, PDFs, YouTube videos/playlists.
4. AI generates a proper roadmap and day-wise schedule.
5. Daily reminders keep the user on track.
6. User can ask AI about specific parts of a YouTube video, or get auto-generated notes/flashcards from it.
7. Roadmap adapts automatically if a session is missed or a topic is marked difficult.

---

## 3. Users

- **Student (primary user)** — uploads material, receives roadmap, gets reminders, asks doubts, takes quizzes.
- **Parent / Guardian (optional)** — read-only access to roadmap/progress dashboard, shared progress summaries.
- **Future stakeholder** — educator/admin view for institutions tracking cohort-level exam readiness.

---

## 4. Full Feature List

### Smarter Planning & Scheduling
- Adaptive re-scheduling (auto-shift roadmap on missed sessions/weak topics)
- Topic weightage detection (prioritize high-yield topics from syllabus/past papers)
- Energy-aware scheduling (study slots based on user's productive times)
- Exam countdown with stress check-ins
- Auto-detect exam type (school/college/competitive) and adjust roadmap style

### Content Intelligence
- YouTube timestamp Q&A (jump to exact moment, transcript-grounded answers)
- Auto-generated flashcards (spaced repetition / SM-2 algorithm)
- Mind-map generation from notes
- Auto quiz generation with performance tracking feeding back into roadmap
- Handwritten doubt solver (photo → OCR → step-by-step solution)
- Summarize PDF in 5 bullet points (one-click)
- Import syllabus from a photo (OCR)

### Engagement & Accountability
- Streaks, XP, badges, gamification
- Study buddy / group rooms for peers on the same exam
- Study streak calendar (GitHub-style)
- Leaderboard among friends
- Share roadmap as image/PDF

### Personalization & Insight
- Progress analytics dashboard (completion %, weak/strong topics, time spent)
- "Explain like I'm confused" mode (switches explanation style on repeated doubts)
- Previous-year question pattern analysis
- Difficulty self-rating (easy/medium/hard) feeding into rescheduling

### Practical Integrations
- Google Calendar / Outlook sync
- Offline-first mode for reminders/downloaded notes
- Export roadmap/notes to Notion/PDF
- Search across all notes/PDFs
- Bookmark/star important notes or video timestamps

### Simple / Quick-Win Additions
- Dark mode
- Pomodoro timer with auto time-logging
- "Today's Focus" home widget
- Syllabus progress bar per subject
- Quick-add task
- Daily motivational quote
- "Time saved by AI" stat
- Reminder snooze

### Multilingual & Accessibility
- Multilingual doubt-solving (Hindi/Gujarati, etc.)
- Text-to-speech for notes (Web Speech API)
- Adjustable font size

---

## 5. How the Quiz & Flashcard Generator Works

1. Source content (notes/PDF text or video transcript) is chunked into manageable sections.
2. A prompt is sent to the Gemini API asking it to generate questions (MCQ/short-answer) and flashcards in **strict JSON format** from that chunk.
3. Backend parses the JSON and stores it (MongoDB) linked to the topic/subject.
4. Quiz results are logged per topic and fed back into the roadmap engine to reprioritize weak areas.
5. Flashcards use a self-implemented **SM-2 spaced-repetition algorithm** to schedule reviews.

This is prompt engineering, not model training — no ML training is involved in this feature.

---

## 6. How AI Is Implemented (Important — No LLM Training Involved)

**Key principle:** The project does NOT train an LLM from scratch. It uses a pretrained model (Google Gemini) via API, made "smart" through prompting, retrieval, and light logic — the same approach used by most real production AI products.

| Feature | Technique | Needs training? |
|---|---|---|
| Roadmap generation | Prompt engineering (structured JSON output) | No |
| Adaptive rescheduling | Rule-based logic + prompt engineering | No |
| Quiz/flashcard generation | Prompt engineering | No |
| Video/notes Q&A | RAG (Retrieval-Augmented Generation) | No (uses pretrained embeddings) |
| Topic-weightage prediction | Small custom scikit-learn classifier | Yes — small-scale, optional |

### RAG pipeline (the one real "AI technique" beyond prompting)
1. Chunk transcripts/notes into ~300–500 word pieces.
2. Convert each chunk to a vector embedding via the **Gemini Embeddings API**.
3. Store embeddings in **MongoDB Atlas Vector Search**.
4. On a user question, embed the question, retrieve the most similar chunks via vector similarity search.
5. Feed only those relevant chunks + the question to Gemini for a grounded answer.

### The one actually-trained component (optional, for extra credit)
**Topic-weightage predictor** — predicts likely exam topics from historical question papers.
- **Where trained:** Google Colab (free GPU/CPU) or Kaggle Notebooks — no paid compute needed.
- **Data:** Self-labeled spreadsheet of past questions → topic → frequency (100–300 examples is enough).
- **Tools:** `pandas` (data), `scikit-learn` (`TfidfVectorizer` + `LogisticRegression`/`RandomForestClassifier`), `joblib` (export as `.pkl`).
- **Workflow:** Load labeled CSV → TF-IDF vectorize → train classifier → evaluate (`accuracy_score`, `classification_report`) → export `.pkl`.
- **Usage in app:** Either (a) wrap in a small FastAPI microservice the Node backend calls, or (b) simpler — run offline in Colab once, generate topic-weightage scores for the demo syllabus, and feed those scores into the roadmap prompt as context. Recommended: option (b) for SGP scope — avoids a second live service.
- **Do NOT:** fine-tune or train the LLM itself — not needed and not feasible on free tiers.

---

## 7. Technology Stack (100% Free / Student-Tier)

| Layer | Technology | Notes |
|---|---|---|
| Frontend (cross-platform) | **Flutter** | Single codebase: Android, iOS, Web, Desktop |
| Backend | **Node.js + Express** | REST API, auth, scheduling, roadmap CRUD |
| Hosting (backend) | **Render** (free tier) | Alt: Railway / Azure for Students ($100 credit) |
| Database | **MongoDB Atlas** (free M0 tier) | Supports Vector Search on free tier (manual index setup via Atlas UI on M0) |
| Vector Search | **MongoDB Atlas Vector Search** | RAG for notes/video Q&A |
| Cache / Reminder Queue | **node-cron** | Simple, in-process — sufficient at SGP scale |
| AI / LLM | **Google Gemini API** (free tier) | Roadmap generation, quizzes, doubt-solving, summaries |
| Embeddings | **Gemini Embeddings API** | Powers RAG pipeline |
| Backup AI | **Groq API** (free tier) | Fast inference, open models |
| YouTube Data | **YouTube Data API v3** | 10,000 units/day free |
| Video Transcripts | **youtube-transcript-api** | Free, no key required |
| Transcription (no captions) | **faster-whisper / whisper.cpp** | Free, self-hosted alternative to paid Whisper API |
| PDF Parsing | **PyMuPDF / pdf-parse** | Extract syllabus/notes text |
| OCR | **Tesseract.js** | Free; weak on handwriting — best for typed/printed text |
| Auth | **Firebase Authentication** | Free, no billing required |
| Push Notifications | **Firebase Cloud Messaging** | Free, no billing required |
| File Storage | **Cloudinary** (NOT Firebase Storage) | ⚠️ Firebase Storage now requires a Blaze (billing) plan as of Feb 2026, even for free-tier usage — use Cloudinary instead |
| Scheduler | **node-cron** | Daily reminder jobs |
| Charts/Analytics UI | **fl_chart** (Flutter) | Progress dashboard |
| Calendar UI | **table_calendar** (Flutter) | Drag-drop rescheduling |
| Spaced Repetition | **Custom SM-2 algorithm** | Self-implemented — good evaluation talking point |

**Flutter packages:** `provider`/`riverpod`, `table_calendar`, `fl_chart`, `flutter_local_notifications`, `http`/`dio`, `flutter_tts`, `file_picker`, `youtube_player_flutter`

**Node packages:** `express`, `mongoose`, `@google/generative-ai`, `firebase-admin`, `node-cron`, `pdf-parse`, `multer`, `axios`, `jsonwebtoken`

---

## 8. Known Gaps / Risks & Fixes (Verified)

1. **Firebase Storage requires billing (Blaze plan) since Feb 2026** — even for free-tier usage, a card must be linked. **Fix:** Use Cloudinary for all file storage instead; keep Firebase only for Auth + FCM (still genuinely free).
2. **MongoDB Atlas M0 (free tier) Vector Search** — works, but search index setup must currently be done manually via the Atlas UI on shared M0 clusters (not fully programmatic). Not a blocker, just a one-time manual step.
3. **Gemini free-tier rate limits** — fine for solo dev, but add retry/error handling in case of concurrent demo usage.
4. **Render free tier cold starts** — backend sleeps after ~15 min idle, takes 30–50s to wake. **Fix:** ping the server every 10 min with a free cron pinger (e.g., cron-job.org) before demos.
5. **No input validation/security middleware** — consider adding `express-rate-limit`, `helmet`, basic schema validation for robustness.
6. **No offline storage in Flutter yet** — add `Hive` or `sqflite` if implementing the offline-first notes feature.
7. **Two-backend complexity (Node + Python microservice)** — recommended to skip the separate Python FastAPI microservice for SGP scope; do PDF/OCR extraction directly in Node (`pdf-parse`, `tesseract.js` both have Node versions) to reduce moving parts.
8. **Tesseract OCR accuracy on handwriting** — built for typed/printed text; set expectations accordingly for the "handwritten doubt solver" demo, or scope it to printed pages only.

---

## 9. Recommended Architecture Split

- **Flutter app** — dashboard, calendar, chat interface, notes viewer (single codebase for all platforms)
- **Node.js/Express backend** — main API, auth, scheduling, reminders, roadmap CRUD, PDF/OCR handling
- **MongoDB Atlas** — primary data store + vector search for Q&A
- **Firebase** — auth, push notifications only (not storage)
- **Cloudinary** — file storage
- *(Optional, not recommended for SGP scope)* Python FastAPI microservice — only if separating out heavy OCR/ML work

---

## 10. Build Order (Recommended Sequence)

1. Firebase project setup (Auth + FCM)
2. MongoDB Atlas free cluster + enable Vector Search
3. Backend skeleton — auth routes + DB connection
4. Gemini integration — roadmap generation with a test syllabus
5. Flutter app shell — login → home → connect to backend auth
6. Upload flow — syllabus/PDF upload → roadmap on calendar
7. RAG pipeline — YouTube transcript → embeddings → Q&A chat screen
8. Quiz/flashcard generation — notes → Gemini → quiz screen
9. Reminders — node-cron + FCM push notifications
10. Polish — dark mode, streaks, dashboard, Pomodoro timer

---

## 11. Deliverables Already Produced in This Project

- A features + tech stack reference PDF
- A filled Project Proposal Word document (Problem Definition, Product Overview, Proposed Solution, Expected Outcome & Future Plan, Challenges, References) styled to match a provided reference template (blue Word theme, Members/Roll Number table, Technology Stack table)
- Two architecture diagrams: (1) high-level input → AI core → output flow, (2) detailed view showing the AI core's four internal modules (roadmap builder, scheduler, quiz/flashcard generator, video Q&A engine) mapped to their outputs

---

## 12. Open Decisions

- **Final project name** not locked in — currently using "StudyTrail" in documents; other options considered: Prepzy, Syllabo, PathWise, ExamPilot, ScholarAI.
- **Team members** — only Yash (D25CS118) is on record; add teammates' names/roll numbers if this is a group submission.
