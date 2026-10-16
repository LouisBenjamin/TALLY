# Tally

A free expense-splitting app, like Splitwise. Built with Flutter and Supabase, runs on the web and Android from one codebase.

I built it as a portfolio project to learn Flutter and Dart.

## Features

- **Sign in with an email code.** No passwords.
- **Groups.** Create a group, invite people with a 10-character code or a join link, add a group photo.
- **Guests.** Add someone who doesn't have an account. They work like any other member.
- **Expenses.** Split equally, by exact amounts, or by percentages. Edit or delete anytime.
- **Balances.** See who owes whom, with a suggested minimal set of payments to settle up.
- **Recurring expenses.** Rent, subscriptions, etc. get added automatically (daily, weekly, monthly).
- **Categories and tags.** Manage them from the Labels tab.
- **Insights.** Spending per category for last week, month to date, or year to date.
- **Bank statement import.** Load a CSV from your bank, pick the shared transactions, and turn them into expenses. Importing the same statement twice won't create duplicates.
- **Live updates.** When someone in the group adds an expense, everyone sees it right away.

## Tech stack

| What | Used |
|---|---|
| App | Flutter / Dart |
| State | Riverpod |
| Routing | go_router |
| Backend | Supabase (Postgres, Auth, Realtime, Storage) |
| Money | `package:decimal` |
| Hosting | Cloudflare Pages (web), GitHub Releases (Android APK) |

## How it's organized

```
lib/
  core/        Shared stuff: router, theme, money helpers, Supabase client
  features/    One folder per feature (auth, groups, expenses, balances, ...)
  models/      Dart classes that mirror the database tables
supabase/
  migrations/  SQL files that build the database, run in order
test/          Unit and widget tests
docs/          Longer write-ups on specific features
```

Each feature folder is split the same way:

- `ui/` screens and widgets
- `providers/` Riverpod state
- `data/` the code that talks to Supabase
- `logic/` plain Dart functions (split math, debt simplification), easy to test

## A few notes on how it works

**There's no custom backend.** The app talks straight to Supabase. Security is handled in the database with Row Level Security: you can only read or change data for groups you're a member of. Things that need extra checks (joining by code, editing an expense, importing) go through Postgres functions.

**Money is never a `double`.** Amounts are `numeric(12,2)` in Postgres and `Decimal` in Dart, and are sent as strings so no precision is lost. When a split doesn't divide evenly (like $10 three ways), the leftover cent goes to one person so the total always adds up.

**Guests are just members without an account.** Expenses and balances point to `group_members` instead of users, so a guest is a member row with a name and no user id. No special cases needed in the code.

**Bank statements stay on your device.** The CSV is read in the app and never uploaded. Only the final expenses are saved, plus a hash of each transaction's reference number to detect duplicates. More detail in [`docs/statement-import.md`](docs/statement-import.md).

**Settling up uses a simple greedy approach.** Match the person who owes the most with the person who's owed the most, repeat. A group of `n` people needs at most `n - 1` payments.

## Running it locally

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) and a free [Supabase](https://supabase.com) project.

1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Set up the database: run each file in `supabase/migrations/` in order in the Supabase SQL Editor (or use `supabase db push`).
3. In Supabase, go to **Auth > URL Configuration** and add `http://localhost:3000` as a redirect URL.
4. Run the app:
   ```bash
   flutter run -d chrome --web-port 3000 \
     --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
     --dart-define=REDIRECT_URL=http://localhost:3000
   ```

You can copy `.env.example` to `.env.local` to keep your keys handy (don't commit it).

Two Supabase settings to check: the **Email OTP Length** must match `_codeLength` in `login_screen.dart`, and **Realtime** must be enabled for live updates.

## Tests

```bash
flutter test
```

Covers the money math, split logic, debt simplification, CSV import parsing, and smoke tests for the screens.

## CI/CD

GitHub Actions runs three workflows:

- `test.yml` runs `flutter analyze` and `flutter test` on every push and PR.
- `deploy-web.yml` builds the web app and deploys it to Cloudflare Pages on pushes to `main`.
- `build-apk.yml` builds an Android APK on `v*` tags and attaches it to the GitHub release.

Secrets needed: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `REDIRECT_URL`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

## Not done yet

- Push notifications (setup notes in [`docs/push-notifications.md`](docs/push-notifications.md))
- Multiple currencies (everything is CAD for now)
- Removing members and transferring group ownership
- Importing PDF statements
