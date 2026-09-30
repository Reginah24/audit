# Government meal check-in

A tablet app for the till: a cashier or the employee themself searches a
name, taps it, confirms, and it's logged. Built for staff turnover — no
login screen, one button, self-explanatory.

## What's included

```
lib/
  main.dart                    entry point, initializes Firebase
  models/
    employee.dart               employee record
    check_in.dart                one logged meal
  services/
    firestore_service.dart      all reads/writes to Firestore
  screens/
    home_screen.dart            search, tap-to-confirm, count, undo strip
pubspec.yaml
```

## Setup

1. Create a Firebase project at console.firebase.google.com if you don't
   have one for this yet.

2. From the project root, run your usual FlutterFire setup:
   ```
   flutter pub get
   dart pub global run flutterfire_cli:flutterfire configure
   ```
   This generates `lib/firebase_options.dart`, which `main.dart` expects —
   it isn't included here since it's tied to your specific Firebase project.

3. In the Firebase console, create two collections:
   - `employees` — one document per government staff member, with fields
     `name` (string) and `department` (string). Load these from the
     roster the government office gives you. For 50–200 people, the
     fastest way is the Firebase console's "Import JSON" on the
     collection, or add them one by one for a first test batch.
   - `checkins` — leave this empty; the app creates documents here as
     people check in.

4. Set Firestore security rules so only your app can write (adjust once
   you add authentication if you want it — for now, during setup, you
   can test with rules that allow read/write, then lock down before
   going live):
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /employees/{id} { allow read: if true; allow write: if false; }
       match /checkins/{id} { allow read, write: if true; }
     }
   }
   ```

5. Run it on the tablet:
   ```
   flutter run
   ```

## How it works

- **Home screen** shows today's running count and a search box, open by
  default so the first tap is typing a name.
- **Tap a name** → confirm dialog → logged. If that person already has a
  check-in today, it says so instead of logging a second one.
- **Recent strip** at the bottom shows the last 5 check-ins with an ✕ to
  undo a wrong tap — any cashier can fix a mistake without needing you.
- Everything is in Firestore, so you can check today's count from your
  phone anytime, whether you're at the restaurant or not.

## Not built yet — next step

The month-end export (pulling a date range grouped by employee for your
invoice) has its data-fetching method already written in
`firestore_service.dart` (`fetchCheckInsForRange`), but no screen wired
up to it yet. When you're ready, that's the natural next screen to add —
happy to help build it when you get there.
