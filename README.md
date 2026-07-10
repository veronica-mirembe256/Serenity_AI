# 🌿 Serenity — AI-Powered Recovery Companion

> A full-stack, AI-powered recovery support platform for people navigating addiction and mental health challenges. Serenity combines daily journaling, multi-agent AI analysis, personalised insights, progress tracking, and proactive crisis escalation into a single, privacy-first web application.

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Tech Stack](#tech-stack)
5. [Project Structure](#project-structure)
6. [Database Schema](#database-schema)
7. [AI Pipeline](#ai-pipeline)
8. [API Reference](#api-reference)
9. [Environment Variables](#environment-variables)
10. [Getting Started](#getting-started)
11. [Running with Docker](#running-with-docker)
12. [Frontend Setup](#frontend-setup)
13. [Email System](#email-system)
14. [Inactivity & Escalation System](#inactivity--escalation-system)
15. [Security & Privacy](#security--privacy)
16. [Prompt Templates](#prompt-templates)
17. [Deployment Notes](#deployment-notes)
18. [Known Limitations](#known-limitations)
19. [Disclaimer](#disclaimer)

---

## Overview

Serenity is built for people in recovery from addiction, mental health conditions, or both. Users journal daily, and a multi-agent LangGraph pipeline analyses each entry for emotion, behavioural patterns, and relapse risk. The system responds with personalised recommendations, tracks progress over time, and proactively escalates to emergency contacts or therapists when risk is high or a user has been inactive for too long.

The backend is a FastAPI application backed by Supabase (PostgreSQL + Auth) and ChromaDB for vector-based journal memory. The frontend is a Flutter Web application styled as a professional SaaS dashboard.

---

## Features

### User Account & Onboarding
- Registration with full name (last name used as display name), email, password, optional emergency contact email, and optional therapist/support email
- Supabase Auth handles JWT issuance; backend validates tokens server-side via service role key
- Three-step onboarding flow after registration:
  - Step 1 — Recovery type: addiction, mental health, or both
  - Step 2 — Active challenges: urges, anxiety, loneliness, stress, medication fatigue, stigma
  - Step 3 — Personal goals + emergency contact email + therapist email (can be updated here even if provided at registration)
- Onboarding completion flag stored in secure local storage; users are not shown onboarding again

### Daily Journaling
- Free-text journal entries with optional mood score (1–10 scale)
- Minimum 10 characters enforced on both frontend and backend
- Entries stored in Supabase (`journal_entries` table) and simultaneously embedded into ChromaDB for semantic retrieval
- Character count displayed in real time; entry locked after submission until user starts a new one

### AI Analysis Pipeline (LangGraph)
Each journal submission triggers a four-agent pipeline:

**Agent 1 — Orchestrator**
Retrieves the 5 most semantically similar past journal entries from ChromaDB using cosine similarity. These form the RAG (Retrieval-Augmented Generation) context for the reflection agent.

**Agent 2 — Reflection Agent**
Analyses the current entry against past entries using the `reflection.j2` prompt. Returns:
- Detected emotion (specific, e.g. "grief-tinged anxiety")
- Pattern insight (recurring themes, triggers, trajectories)
- Relapse risk level: `low`, `moderate`, or `high`
- Relapse risk reasoning
- Medication fatigue flag
- Stigma detection flag

**Agent 3 — Support Agent**
Uses reflection findings to generate a personalised response via the `support.j2` prompt:
- 2–3 concrete recommendations
- 1–2 alternative suggestions
- Encouragement message
- Medication support message (if fatigue flagged)
- Stigma reassurance message (if stigma detected)

**Agent 4 — Risk & Escalation**
Normalises risk level, flags high-risk entries for escalation, and logs reasoning. The pipeline result is returned to the frontend and stored in the `ai_insights` table.

If relapse risk is `high`, the Flutter frontend automatically redirects the user to the Crisis page.

### Dashboard
- Personalised daily message generated from user profile, streak, recovery type, and challenges
- Four stat cards: current streak, total entries, average mood (7-day), latest risk level
- Latest AI insight preview with emotion, pattern, and top recommendation
- Quick journal prompts panel
- All data auto-refreshes immediately after a journal entry is submitted (no manual refresh needed)

### Insights
- Full history of all AI insights, paginated
- Master-detail layout: list on left, full detail panel on right
- Each insight shows: date, detected emotion, pattern insight, risk badge, encouragement, numbered recommendations
- Colour-coded risk indicators (green/amber/red)

### Progress Tracking
- Current streak and longest streak displayed in a hero banner
- Total journal entries, best streak, average mood, latest risk level as stat cards
- Weekly mood chart (line chart via fl_chart) showing 7-day mood trend
- Weekly entry bar chart showing last 4 weeks of journaling frequency
- Badge/achievement system: first entry, 7-day streak, 30-day streak, 90-day streak, 365-day streak
- Streak logic: consecutive daily journaling increments streak; gap of 2+ days resets to 1

### Crisis Page
- Accessible from sidebar and top bar at all times (no authentication required for routing)
- Animated breathing guide (expand/contract circle with phase labels: breathe in, hold, breathe out)
- One-tap emergency alert button: sends an email to the user's registered emergency contact via Gmail SMTP
- Crisis hotline card (Call 999)
- Direct link to journal/AI chat for immediate support
- Motivational anchor chips

### Settings
- Privacy & notification consent toggles:
  - Email reminders (inactivity reminders)
  - Therapist escalation (consent for therapist to be notified on high-risk or prolonged inactivity)
  - Anonymous analytics
- Consent saved to `user_consents` table in Supabase
- About section: version, backend stack, AI model
- Sign out button

### Inactivity Detection & Escalation
- Background scan triggered via `POST /admin/inactivity-scan` (protected by `X-Admin-Key` header)
- Intended to be called by a cron job or external scheduler
- **1+ day inactive** → sends gentle reminder email to the user (if email reminders consented)
- **7+ days inactive** → sends escalation email to therapist (if `therapist_escalation` consented and `therapist_email` set) and/or rehab contact (if `rehab_escalation` consented and `rehab_contact_email` set)
- All notifications logged to `notification_log` table with status (sent/failed)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Flutter Web Frontend                │
│  (GoRouter + Riverpod + Dio + flutter_secure_storage)│
└───────────────────────┬─────────────────────────────┘
                        │ HTTPS / REST
┌───────────────────────▼─────────────────────────────┐
│              FastAPI Backend (Python)                │
│                                                      │
│  Routes: /auth  /journal  /user  /stats             │
│          /daily-message  /admin  /consent            │
│          /onboarding                                 │
│                                                      │
│  Services:                                           │
│  ├── journal_service      (entry + AI orchestration) │
│  ├── progress_service     (stats + badges)           │
│  ├── daily_message_service(personalised greeting)    │
│  ├── email_service        (SMTP via aiosmtplib)      │
│  └── inactivity_service   (background scan)          │
│                                                      │
│  AI Pipeline (LangGraph):                            │
│  Orchestrator → Reflection → Support → RiskEscalation│
└───────┬──────────────────────┬───────────────────────┘
        │                      │
┌───────▼──────┐     ┌────────▼────────┐
│   Supabase   │     │    ChromaDB     │
│              │     │                 │
│ PostgreSQL   │     │ Journal entry   │
│ Auth (JWT)   │     │ embeddings      │
│ RLS policies │     │ (cosine sim.)   │
└──────────────┘     └─────────────────┘
```

---

## Tech Stack

### Backend
| Component | Technology |
|---|---|
| Framework | FastAPI 0.111 |
| Server | Uvicorn |
| Auth | Supabase Auth (JWT) validated via httpx |
| Database | Supabase (PostgreSQL) |
| Vector DB | ChromaDB 0.5.3 (HTTP client) |
| AI Orchestration | LangGraph 0.1.19 |
| LLM | OpenAI GPT-4o |
| Embeddings | OpenAI text-embedding-3-small |
| Email | aiosmtplib (async SMTP) |
| Templating | Jinja2 (prompts + email bodies) |
| Settings | pydantic-settings |
| Logging | Structured JSON logging (custom formatter) |
| DNS | dnspython (Windows DNS patch for dev) |

### Frontend
| Component | Technology |
|---|---|
| Framework | Flutter Web |
| State Management | Riverpod 2.5 |
| Routing | GoRouter 14 |
| HTTP Client | Dio 5.4 |
| Secure Storage | flutter_secure_storage 9 |
| Charts | fl_chart 0.68 |
| Fonts | Google Fonts (Fraunces + DM Sans) |
| Animations | flutter_animate |

### Infrastructure
| Component | Technology |
|---|---|
| Database & Auth | Supabase (hosted) |
| Vector Store | ChromaDB (Docker container) |
| Containerisation | Docker + Docker Compose |
| Web App | Flutter Web (PWA-ready) |

---

## Project Structure

```
mmaria-AE.CAP.1.1/
│
├── backend/
│   └── app/
│       ├── main.py                    # FastAPI entry point, middleware, routers
│       ├── config.py                  # Centralised settings (pydantic-settings)
│       ├── dns_patch.py               # Windows DNS fix (Google DNS via dnspython)
│       │
│       ├── routes/
│       │   ├── auth.py                # POST /auth/register, /auth/login
│       │   ├── journal.py             # POST /journal, GET /journal/insights
│       │   ├── user.py                # POST /user/preferences, /user/emergency-alert
│       │   ├── progress.py            # GET /stats, /daily-message
│       │   ├── admin.py               # POST /admin/inactivity-scan
│       │   ├── onboarding.py          # POST /onboarding
│       │   └── consent.py             # POST /consent
│       │
│       ├── services/
│       │   ├── journal_service.py     # Entry save + AI pipeline + streak logic
│       │   ├── progress_service.py    # Stats, badges, weekly summary
│       │   ├── daily_message_service.py # Personalised daily greeting
│       │   ├── email_service.py       # Reminder + escalation emails
│       │   └── inactivity_service.py  # Background inactivity scan
│       │
│       ├── agents/
│       │   └── workflow.py            # LangGraph pipeline (4 agents)
│       │
│       ├── db/
│       │   ├── supabase_client.py     # Supabase client factory (service_role/anon)
│       │   └── chroma_client.py       # ChromaDB upsert + semantic retrieval
│       │
│       ├── utils/
│       │   ├── auth.py                # JWT validation via Supabase /auth/v1/user
│       │   ├── models.py              # All Pydantic request/response schemas
│       │   └── prompt_loader.py       # Jinja2 template renderer
│       │
│       ├── prompts/
│       │   ├── reflection.j2          # Reflection Agent prompt
│       │   ├── support.j2             # Support Agent prompt
│       │   ├── daily_message.j2       # Daily greeting prompt
│       │   ├── email_reminder.j2      # Inactivity reminder email (HTML)
│       │   └── email_escalation.j2    # Therapist escalation email (HTML)
│       │
│       └── logging_config/
│           └── logger.py              # Structured JSON logger
│
├── frontend/
│   └── lib/
│       ├── main.dart                  # App entry point (ProviderScope, routing)
│       │
│       ├── core/
│       │   ├── theme/app_theme.dart   # AppColors, AppSpacing, AppTheme
│       │   ├── constants/app_constants.dart # baseUrl, storage keys, risk levels
│       │   └── errors/app_exceptions.dart   # AppException hierarchy
│       │
│       ├── router/
│       │   └── app_router.dart        # GoRouter config + auth redirect logic
│       │
│       ├── state/
│       │   └── providers.dart         # Riverpod providers (auth, journal, stats, insights)
│       │
│       ├── models/
│       │   └── app_models.dart        # Dart model classes (AuthResponse, JournalResponse, etc.)
│       │
│       ├── services/
│       │   ├── api_client.dart        # Dio HTTP client + auth interceptor
│       │   └── secure_storage_service.dart # flutter_secure_storage wrapper
│       │
│       ├── shared/
│       │   ├── layout/dashboard_shell.dart  # Sidebar + topbar shell
│       │   └── widgets/web_widgets.dart     # WCard, WTile, StatCard, RiskBadge, WMoodPicker, WShimmer
│       │
│       └── features/
│           ├── auth/presentation/
│           │   ├── login_page.dart
│           │   └── register_page.dart
│           ├── onboarding/presentation/onboarding_page.dart
│           ├── dashboard/presentation/dashboard_page.dart
│           ├── journal/presentation/journal_page.dart
│           ├── insights/presentation/insights_page.dart
│           ├── progress/presentation/progress_page.dart
│           ├── crisis/presentation/crisis_page.dart
│           └── settings/presentation/settings_page.dart
│
├── schema.sql                         # Full Supabase PostgreSQL schema
├── requirements.txt                   # Python dependencies
├── Dockerfile                         # Backend Docker image
├── docker-compose.yml                 # API + ChromaDB services
└── .env.example                       # Environment variable template
```

---

## Database Schema

All tables live in Supabase (PostgreSQL). Row Level Security (RLS) is enabled on every user-facing table — users can only ever read or write their own rows.

### `user_profiles`
| Column | Type | Notes |
|---|---|---|
| `id` | UUID | References `auth.users(id)` |
| `display_name` | TEXT | Last name from registration |
| `recovery_type` | ENUM | `addiction`, `mental_health`, `both` |
| `goals` | TEXT[] | Free-form goal strings from onboarding |
| `challenges` | ENUM[] | Selected challenge tags |
| `therapist_email` | TEXT | Escalation contact |
| `rehab_contact_email` | TEXT | Escalation contact |
| `emergency_contact_email` | TEXT | Crisis alert target |
| `timezone` | TEXT | User's timezone string |
| `created_at` | TIMESTAMPTZ | Auto |
| `updated_at` | TIMESTAMPTZ | Auto-updated via trigger |

### `user_consents`
| Column | Type | Notes |
|---|---|---|
| `user_id` | UUID | FK → user_profiles |
| `email_reminders` | BOOLEAN | Inactivity reminder emails |
| `therapist_escalation` | BOOLEAN | Notify therapist on high risk |
| `rehab_escalation` | BOOLEAN | Notify rehab contact |
| `data_analytics` | BOOLEAN | Anonymous analytics consent |

### `journal_entries`
| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Also used as ChromaDB document ID |
| `user_id` | UUID | FK → user_profiles |
| `text` | TEXT | Raw journal content |
| `mood_score` | SMALLINT | 1–10 |
| `chroma_id` | TEXT | ChromaDB reference |
| `created_at` | TIMESTAMPTZ | Auto |

### `ai_insights`
| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | FK → user_profiles |
| `journal_entry_id` | UUID | FK → journal_entries |
| `detected_emotion` | TEXT | From Reflection Agent |
| `pattern_insight` | TEXT | From Reflection Agent |
| `recommendations` | TEXT[] | From Support Agent |
| `alternative_suggestions` | TEXT[] | From Support Agent |
| `encouragement` | TEXT | From Support Agent |
| `relapse_risk_level` | TEXT | `low`, `moderate`, `high` |
| `raw_response` | JSONB | Full LLM response for auditing |

### `user_progress`
| Column | Type | Notes |
|---|---|---|
| `user_id` | UUID | Unique FK → user_profiles |
| `current_streak` | INT | Consecutive journaling days |
| `longest_streak` | INT | All-time best streak |
| `total_entries` | INT | Lifetime entry count |
| `last_entry_date` | DATE | Used for streak calculation |
| `sobriety_start_date` | DATE | Optional, user-set |

### `user_badges`
| Column | Type | Notes |
|---|---|---|
| `user_id` | UUID | FK → user_profiles |
| `badge` | ENUM | `first_entry`, `streak_7`, `streak_30`, `streak_90`, `streak_365`, `milestone_custom` |
| `label` | TEXT | Display label |
| `awarded_at` | TIMESTAMPTZ | Auto |

### `notification_log`
Audit trail for every reminder and escalation email sent or failed. Columns: `user_id`, `type`, `recipient_email`, `subject`, `status`, `error_message`, `sent_at`.

### `user_consents`
Tracks opt-in consent for all automated communications. All flags default to `FALSE` — nothing is sent without explicit user consent.

---

## AI Pipeline

The pipeline is built with LangGraph and runs synchronously within the journal submission request. All agents are wrapped in try/except — a failed LLM call returns safe defaults and never crashes the entry submission.

```
Journal Submission
       │
       ▼
┌─────────────────┐
│   Orchestrator  │  Fetches 5 similar past entries from ChromaDB (RAG)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Reflection    │  GPT-4o + reflection.j2
│     Agent       │  → emotion, pattern, risk level, flags
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Support      │  GPT-4o + support.j2
│     Agent       │  → recommendations, encouragement, medication/stigma responses
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Risk Escalation │  Normalises risk, sets escalation_required flag
│     Agent       │
└────────┬────────┘
         │
         ▼
  Result returned to journal_service
  → saved to ai_insights table
  → streak updated
  → returned to frontend
```

**Model:** `gpt-4o` for reflection and support agents
**Embeddings:** `text-embedding-3-small` for ChromaDB upsert and retrieval
**Temperature:** 0.3 for reflection (analytical), 0.5 for support (warmer)

---

## API Reference

All endpoints except `/auth/*` and `/health` require a Bearer token in the `Authorization` header.

### Auth
| Method | Endpoint | Description |
|---|---|---|
| POST | `/auth/register` | Create account. Body: `email`, `password`, `display_name`, `therapist_email?`, `emergency_contact_email?` |
| POST | `/auth/login` | Sign in. Body: `email`, `password`. Returns `access_token`, `user_id` |

### Journal
| Method | Endpoint | Description |
|---|---|---|
| POST | `/journal` | Submit entry. Body: `text` (min 10 chars), `mood_score?` (1–10). Returns full AI analysis |
| GET | `/journal/insights` | Paginated insight history. Query: `limit`, `offset` |

### User
| Method | Endpoint | Description |
|---|---|---|
| POST | `/user/preferences` | Save onboarding preferences. Body: `recovery_type`, `challenges`, `goals`, `emergency_contact_email?`, `therapist_email?`, `timezone?` |
| POST | `/user/emergency-alert` | Send immediate email to emergency contact via Gmail SMTP |

### Progress
| Method | Endpoint | Description |
|---|---|---|
| GET | `/stats` | Returns streak, total entries, weekly summary, latest risk level, badges |
| GET | `/daily-message` | Returns personalised daily greeting based on profile + progress |

### Consent
| Method | Endpoint | Description |
|---|---|---|
| POST | `/consent` | Save notification preferences. Body: `email_reminders`, `therapist_escalation`, `rehab_escalation`, `data_analytics` |

### Admin
| Method | Endpoint | Description |
|---|---|---|
| POST | `/admin/inactivity-scan` | Trigger inactivity scan. Requires header: `X-Admin-Key: <SECRET_KEY>` |

### System
| Method | Endpoint | Description |
|---|---|---|
| GET | `/health` | Returns `{"status": "healthy", "app": "Serenity", "env": "..."}` |

### Interactive Docs
- Swagger UI: `http://localhost:8080/docs`
- ReDoc: `http://localhost:8080/redoc`

---

## Environment Variables

Copy `.env.example` to `.env` and fill in all values before running.

```dotenv
# APPLICATION
APP_NAME=Serenity
APP_ENV=production          # or development
SECRET_KEY=                 # Used for admin endpoint protection
DEBUG=false

# SUPABASE
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=          # Public anon key
SUPABASE_SERVICE_ROLE_KEY=  # Service role key (backend only — never expose to frontend)

# OPENAI
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o
OPENAI_EMBEDDING_MODEL=text-embedding-3-small

# CHROMADB
CHROMA_HOST=localhost        # Use 'chromadb' when running via Docker Compose
CHROMA_PORT=8000
CHROMA_COLLECTION_JOURNAL=journal_entries

# EMAIL (Gmail SMTP)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=               # Gmail App Password (not your account password)
EMAIL_FROM_NAME=Serenity
EMAIL_FROM_ADDRESS=no-reply@serenity.app

# INACTIVITY THRESHOLDS
INACTIVITY_REMINDER_DAYS=1   # Days before gentle reminder is sent
INACTIVITY_ESCALATION_DAYS=7 # Days before therapist escalation is triggered
```

> **Gmail App Password:** Go to your Google Account → Security → 2-Step Verification → App Passwords. Generate a password for "Mail". Use that as `SMTP_PASSWORD`.

---

## Getting Started

### Prerequisites
- Python 3.11+
- Flutter 3.19+ (with web support enabled)
- Docker Desktop (for ChromaDB)
- A Supabase project (free tier works)
- An OpenAI API key

### Backend Setup

```bash
# Clone the repo
git clone <your-repo-url>
cd mmaria-AE.CAP.1.1/backend

# Create and activate virtual environment
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy and fill in environment variables
cp ../.env.example .env
# Edit .env with your keys

# Run the API
python -m app.main
# OR
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

### Database Setup

Run `schema.sql` in your Supabase project's SQL editor. This creates all tables, enums, indexes, RLS policies, and triggers.

```bash
# In Supabase dashboard → SQL Editor → paste contents of schema.sql → Run
```

### ChromaDB (standalone)

```bash
docker run -p 8000:8000 chromadb/chroma:latest
```

---

## Running with Docker

Docker Compose starts both the FastAPI backend and ChromaDB together with hot-reload enabled.

```bash
# From the project root
docker-compose up --build
```

This starts:
- `api` on `http://localhost:8080`
- `chromadb` on `http://localhost:8000`

The `api` service waits for ChromaDB to pass its health check before starting.

```yaml
# docker-compose.yml summary
services:
  api:
    build: .
    ports: ["8080:8080"]
    env_file: .env
    environment:
      CHROMA_HOST: chromadb   # Points to the chromadb service, not localhost
    depends_on:
      chromadb:
        condition: service_healthy

  chromadb:
    image: chromadb/chroma:latest
    ports: ["8000:8000"]
    volumes:
      - chroma_data:/chroma/chroma
```

> **Note:** When running via Docker Compose, set `CHROMA_HOST=chromadb` in your `.env` (not `localhost`). The compose file overrides this automatically via the `environment` block.

---

## Frontend Setup

```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Run on Chrome (web)
flutter run -d chrome

# Build for production
flutter build web --release
```

### Configuration

The backend URL is set in `lib/core/constants/app_constants.dart`:

```dart
class AppConstants {
  static const String baseUrl = 'http://localhost:8080';
  // Change to your production URL before deploying
}
```

### Flutter Dependencies
| Package | Version | Purpose |
|---|---|---|
| `flutter_riverpod` | ^2.5.1 | State management |
| `dio` | ^5.4.3 | HTTP client with interceptors |
| `go_router` | ^14.2.0 | Declarative routing with auth redirect |
| `flutter_secure_storage` | ^9.0.0 | JWT + user ID storage (IndexedDB on web) |
| `fl_chart` | ^0.68.0 | Line and bar charts |
| `google_fonts` | ^6.2.1 | Fraunces (headings) + DM Sans (body) |
| `flutter_animate` | ^4.5.0 | Animations |
| `intl` | ^0.19.0 | Date formatting |
| `supabase_flutter` | ^2.12.4 | Supabase client (used for session access in journal page) |

### Routing & Auth

GoRouter manages all navigation. Auth state is bridged to GoRouter via a `ChangeNotifier` that listens to the Riverpod `authProvider`. Redirect rules:

- Unauthenticated users accessing any protected route → `/login`
- Authenticated users accessing `/login` or `/register` → `/dashboard`
- `/onboarding` and `/crisis` are public (no auth required)
- `/splash` is a neutral loading screen that immediately redirects based on auth state

### Secure Storage

Tokens and user IDs are stored using `flutter_secure_storage` with a named IndexedDB vault (`serenity_vault`) on web. The `ApiClient` Dio interceptor automatically attaches the Bearer token to every non-auth request. If no token is found, the request is rejected with an `UnauthorizedException` which triggers logout.

---

## Email System

All emails are sent via Gmail SMTP using `aiosmtplib` (async). Two email types are supported:

### Inactivity Reminder (`email_reminder.j2`)
Sent to the **user** after `INACTIVITY_REMINDER_DAYS` days of no journaling. Styled HTML email with a CTA button linking to `/journal`. Includes streak information if streak > 0. Only sent if `email_reminders` consent is `TRUE`.

### Escalation Alert (`email_escalation.j2`)
Sent to the **therapist or rehab contact** after `INACTIVITY_ESCALATION_DAYS` days of inactivity. Styled HTML email with risk level badge, days inactive, and a recommendation to check in. Only sent if the relevant consent flag is `TRUE` and the target email is set on the user's profile.

### Crisis Emergency Alert
Triggered manually by the user tapping "Send Alert Now" on the Crisis page. Sent immediately to `emergency_contact_email` via Gmail SMTP. Plain text + HTML body. Does not require consent flag — it is always user-initiated.

All emails use the Gmail App Password set in `SMTP_PASSWORD`. The sender address is `EMAIL_FROM_ADDRESS` with display name `EMAIL_FROM_NAME`.

---

## Inactivity & Escalation System

The inactivity scan is a background process that should be triggered on a schedule (daily is recommended).

### How to Trigger

```bash
curl -X POST http://localhost:8080/admin/inactivity-scan \
  -H "X-Admin-Key: your-SECRET_KEY-value"
```

Or set up a cron job / GitHub Actions scheduled workflow to call this endpoint daily.

### Scan Logic

For each user:
1. Load last journal entry date from `user_progress`
2. Calculate `days_inactive = today - last_entry_date`
3. If `days_inactive >= INACTIVITY_REMINDER_DAYS`:
   - Load consent flags
   - If `email_reminders = true` → send reminder email to user's auth email
4. If `days_inactive >= INACTIVITY_ESCALATION_DAYS`:
   - If `therapist_escalation = true` and `therapist_email` set → send escalation email
   - If `rehab_escalation = true` and `rehab_contact_email` set → send escalation email
5. Log all send attempts to `notification_log`

Users who have never journaled are skipped.

---

## Security & Privacy

- **JWT Validation:** All protected endpoints validate tokens against Supabase's `/auth/v1/user` endpoint using the service role key. Expired or invalid tokens return 401.
- **Service Role Key:** Used only server-side. Never sent to the frontend. Frontend uses only the anon key (via Supabase Flutter SDK for session access).
- **Row Level Security:** All Supabase tables have RLS enabled. Users can only access their own rows, enforced at the database level regardless of backend logic.
- **Consent Gating:** No escalation email is ever sent without explicit user consent. All consent flags default to `FALSE`.
- **Emergency Alert:** The `POST /user/emergency-alert` endpoint only works if the user has set an `emergency_contact_email`. Returns 400 with a clear message if not set.
- **ChromaDB:** Journal embeddings are filtered by `user_id` metadata on every query — users only retrieve their own semantic history.
- **Admin Endpoint:** `/admin/inactivity-scan` is protected by a secret key header. In production, this endpoint should not be publicly exposed.
- **Passwords:** Never stored by the backend. Supabase Auth handles all password hashing and storage.

---

## Prompt Templates

All LLM prompts are stored as Jinja2 templates in `backend/app/prompts/`. No prompt strings are hardcoded in Python. The `render_prompt()` utility renders any template with passed variables, using `StrictUndefined` so missing variables fail loudly during development.

| Template | Agent | Purpose |
|---|---|---|
| `reflection.j2` | Reflection Agent | Analyse journal entry for emotion, patterns, risk level, flags |
| `support.j2` | Support Agent | Generate recommendations, encouragement, medication/stigma responses |
| `daily_message.j2` | daily_message_service | Personalised daily greeting (not currently used — service generates message directly) |
| `email_reminder.j2` | email_service | HTML inactivity reminder email to user |
| `email_escalation.j2` | email_service | HTML escalation alert email to therapist/rehab contact |

---

## Deployment Notes

### Backend
- Set `DEBUG=false` and `APP_ENV=production` in `.env`
- Use a production WSGI server: `uvicorn app.main:app --host 0.0.0.0 --port 8080 --workers 4`
- Use a reverse proxy (nginx or Caddy) in front of uvicorn
- Host ChromaDB on a persistent volume; do not use ephemeral storage
- Protect `/admin/inactivity-scan` behind a firewall or internal network; only expose it to your scheduler

### Frontend
```bash
flutter build web --release
# Output is in build/web/ — deploy to any static host (Vercel, Netlify, Firebase Hosting, etc.)
```

Update `AppConstants.baseUrl` to your production backend URL before building.

### Supabase
- Enable email confirmation if desired (currently auto-login after register handles sessions without email confirmation)
- Configure SMTP in Supabase dashboard if you want Supabase to send its own auth emails
- RLS policies are already defined in `schema.sql`

---

## Known Limitations

- The `daily_message_service.py` generates messages using rule-based logic rather than calling the `daily_message.j2` LLM prompt. The template exists but the service builds the message directly from profile data. To enable LLM-generated daily messages, wire `render_prompt("daily_message.j2", ...)` into the service and call the OpenAI API.
- The weekly mood chart on the Progress page uses simulated offset data around the actual average mood. Real per-day mood data would require a daily aggregation query.
- The weekly bar chart shows hardcoded placeholder values for weeks 1–3; only the current week is real.
- ChromaDB requires a running server. If ChromaDB is unavailable, journal entry saving continues (the Chroma upsert step is non-fatal) but RAG context will be empty for those entries.
- The `GET /daily-message` endpoint generates a new message on every call and does not cache. This is intentional for personalisation but uses no LLM call currently.
- Flutter web does not support true background processing. The inactivity scan must be triggered externally.

---

## Disclaimer

Serenity is a support tool and is **not a medical device**. It does not replace professional mental health treatment, addiction counselling, or medical advice. In a crisis, users should contact emergency services or a qualified professional immediately.

---

*Built with care for people on their recovery journey. 