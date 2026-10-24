# Giraphe Meal App

Staff meal check-in for the **Office of the Auditor General**, run by the
Giraphe restaurant. It replaces the paper list the office used to send:

- employees say the day before whether they will eat, so the kitchen knows
  how many meals to prepare;
- at lunch they scan a meal pass (printed card or phone) at the restaurant
  tablet, or the cashier finds their name;
- the office gets a daily and monthly report of who ate and who did not,
  with every correction and every added person shown.

Built for staff aged 50–60: large text, large buttons, few words, no
emojis, and nothing to install from an app store.

- **Live app:** https://giraphe-govt-checkin.web.app
- **Firebase project:** `giraphe-govt-checkin`
- **Restaurant account:** `anthonyregina48@gmail.com`
- **Office account:** `audit@gmail.com`

(The two accounts are listed at the top of `firestore.rules`; that list,
not the app, decides who can sign in to the restaurant and report pages.)

---

## 1. The three parts of the app

The first screen shows today's date and three choices.

### 1.1 Restaurant counter (tablet, restaurant account)

Sign in once with the restaurant account; the tablet stays signed in.
Four tabs:

**Check in**
- **Scan meal pass** opens the camera and keeps it on, like a supermarket
  scanner. The person holds up their printed card or their phone.
- On a good scan the tablet shows **CHECK-IN CONFIRMED** with the name,
  department and time, then asks *"Will you eat here [next working day]?"*
  with two large buttons, **Yes, I will eat** / **No, I will not**. It
  closes by itself after 15 seconds so the queue keeps moving.
- **No pass? Search by name:** the cashier types any part of the name and
  taps it, then confirms. Same result as a scan.
- **Not on the list? Add "…":** appears under the search (see *Add a
  person* below).

**Today**
- Cards for *Meals served*, *Confirmed* and *Confirmed, not yet arrived*.
- The list of who has eaten, with time and how (scanned pass / tapped at
  till). Anyone eating without having said yes is marked *not booked*.
- The **✕** next to a name removes a meal recorded by mistake. The cashier
  must choose a reason (*Wrong person was recorded* or *Recorded by
  mistake - did not eat*). The meal is not deleted silently: a permanent
  correction is saved and shown on the office report.

**Plan** (the kitchen plan)
- **Meals to prepare** for the next working day (Friday rolls over to
  Monday), with how many declined and how many have not answered.
- A Yes / No switch next to every name, for what the office tells the
  restaurant (leave, travel, meetings). Tapping the selected answer again
  clears it. Arrows move to other days.

**Alerts**
- Every refused second meal on the same day: who, when, and whether it was
  a scan or a tap.

**Buttons at the top**
- **Add a person** (person icon) — see below.
- **Meal passes** (QR icon) — print everyone's passes, or tap **Lost** next
  to a name to cancel their pass and print a new one.
- **Load employee roster** (upload icon) — loads `lib/employee_roster.dart`.
- **Sign out.**

**Add a person** — for someone missing from the office's list
- Full name and department. Existing departments are one-tap buttons;
  typing "finance" joins the existing "Finance" instead of creating a new
  spelling.
- A name already on the list is refused (capitals, spaces and accents are
  ignored when comparing).
- Afterwards: **Record meal now** (serves them straight away) and **Print
  meal pass**.
- The database stamps **who added them and when**. Every report lists them
  under *People added at the restaurant counter*.

### 1.2 My meals (employee's own phone)

1. **Find your name** — type any part of it, in any capitals ("PRINCESS"
   finds "Princess Uwase"). If several people match, the app shows *Which
   one are you?* with name and department.
2. **PIN** — the first time, choose 4 numbers; after that, enter them.
3. The phone remembers the person; next time it opens straight to their
   page.

Three tabs at the bottom:
- **Home** — greeting, *"Will you eat here [next working day]?"* with Yes /
  No, today's status (*Meal taken at …* or *Not yet checked in*) and meals
  this month.
- **Pass** — the person's QR meal pass, to hold up to the tablet, with the
  live check-in status (*Awaiting scan* / *Checked in at …*).
- **Profile** — name, department, this month's meal history, sign out.

Employees **cannot record a meal from their phone.** Meals are only
recorded by the restaurant account at the counter.

### 1.3 Reports (office or restaurant account)

- **One day:** everyone on the list with *Said coming* (Yes / No / No
  answer), *Ate* (time and how), and notes *Said yes, did not eat* or *Ate
  without booking*. Filters: Everyone, Ate, Did not eat, Said yes - did not
  eat, Ate without booking. Summary boxes: Said they would eat, Ate, Did
  not eat, Said yes - did not eat, Ate without booking, Corrections.
- **Whole month:** meals eaten, days booked and booked-but-not-eaten per
  person, with totals.
- Both always include **People added at the restaurant counter** and
  **Corrections (meals removed by the restaurant)** with who, when and why.
- **Print / save PDF** and **Send / share** produce an A4 PDF headed
  *Office of the Auditor General*, with the same tables, those two
  sections, and signature lines for the restaurant and the office.

---

## 2. Meal passes

- Every person gets a pass automatically as soon as they are on the list.
  Printing is **optional**: someone with a smartphone uses the **Pass** tab.
  Print cards (8 per A4 page, cut on the dashed lines, laminate if
  possible) for people without a smartphone.
- A pass's QR code contains the person's ID and a **secret key** that only
  the restaurant account can read. Printing again gives the same passes.
- **Lost card or stolen phone:** *Meal passes* → **Lost** next to the name.
  The old pass stops working at once; the phone shows the new pass the
  next time it opens.
- **One meal per person per day.** A second scan is refused (*Already
  recorded today*) and logged under Alerts.
- When a scan is refused the tablet says why: *That is not a meal pass*,
  *This pass is no longer valid*, or *Pass not recognised*.

---

## 3. What is recorded (for audit)

All data is in Cloud Firestore in project `giraphe-govt-checkin`. Times
marked *server* are set by Google's server, not by the tablet or phone, and
cannot be changed by the app.

| Collection | One record per | Fields |
|---|---|---|
| `employees` | person on the list | name, department, addedBy, addedAt (server), source (`roster` = office list, `counter` = added at restaurant), pinSet |
| `badges` | person | key (the secret part of their pass) |
| `checkins` | meal eaten, id `<date>_<personId>` | employeeId, employeeName, department, date, timestamp (server), method (`scan` / `tap`), recordedBy |
| `voided_checkins` | meal removed by the restaurant | the original meal, voidedAt (server), voidedBy, reason |
| `attendance` | "will I eat that day?" answer, id `<date>_<personId>` | employeeId, employeeName, date, coming (true/false), setBy (`employee` / `staff`), updatedAt (server), updatedBy |
| `duplicate_attempts` | refused second meal | employeeId, employeeName, date, timestamp (server), source |

PINs are **not** stored in the database; Firebase Authentication holds
them. Older check-ins (before October 2026 changes) may have `self` as
method, from a phone button that has since been removed.

---

## 4. Security — who can do what

Enforced by `firestore.rules` on Google's servers, so it holds even if
someone copies or changes the app.

| | Not signed in | Employee (name + PIN) | Restaurant account | Office account |
|---|---|---|---|---|
| See names and departments | yes | yes | yes | yes |
| Record a meal | no | no | yes (server time, only once per person per day) | no |
| Edit a meal | no | no | no | no |
| Remove a meal | no | no | only with a permanent correction | no |
| Edit or delete a correction | no | no | no | no |
| Answer "will I eat?" | no | own answer only | anyone's | no |
| See meals | no | own only | all | all |
| Add a person | no | no | yes (stamped who + when) | no |
| Rename / delete a person | no | no | no | no |
| Read pass keys | no | own only | all | no |
| Reports and corrections | no | no | yes | yes |

- A wrong PIN several times in a row makes Firebase block further tries
  for a while.
- The rules were tested against **56 attack cases** in the Firebase
  emulator (not signed in, unlisted account, employee, restaurant,
  office), including backdating meals, faking who recorded or added
  something, silent deletion, and editing corrections. All 56 behaved as
  intended. Re-test after any change to `firestore.rules`.
- The app has **14 automated tests** (`flutter test`) for service days,
  pass codes, name matching and report numbers.

---

## 5. Setup and publishing

**Done already (October 2026):** Email/Password sign-in switched on,
rules published with the two accounts above, app published at the live
address.

**Load the staff list:** put everyone in `lib/employee_roster.dart`, then
publish (below) and press the upload icon on the tablet — or simply use
*Add a person* on the tablet. Names already on the list are skipped.

**Publish a change to the app:**
```
flutter build web
firebase deploy --only hosting
```
Everyone's app updates on its own.

**Publish a change to the security rules:**
```
firebase deploy --only firestore:rules
```

**Change who can sign in:** edit the email lists at the top of
`firestore.rules`, create the account in Firebase console →
Authentication → Users, then publish the rules.

**Names on reports and passes:** `lib/admin_config.dart`
(`officeName`, `restaurantName`).

---

## 6. Getting people on the app

- It is a web app: people open the link and tap **Add to Home screen**
  (Android Chrome: ⋮ menu; iPhone Safari: Share button). It then shows as
  **Giraphe Meals** with a green **G** icon and opens full screen. It needs
  internet.
- **Staff poster:** `../Giraphe-staff-poster.pdf` (next to the project
  folder) — QR code to the app and the three setup steps. Print it for the
  office and the restaurant, or send the link on WhatsApp.
- **Restaurant tablet:** open the link in Chrome → Add to Home screen →
  sign in with the restaurant account → *Scan meal pass* → allow the
  camera. In Android settings set a long screen timeout and use app
  (screen) pinning so customers can't leave the app. Keep it charging.

---

## 7. Known limits and how to handle them

- **Someone using another person's pass.** The tablet shows the name in
  large letters on every scan; a pass works once per day; *Lost* cancels a
  pass at once. Photos on passes were considered and **not adopted** (too
  much setup). If a face is unfamiliar, ask for the staff ID.
- **Lost pass used before it is reported:** the finder could eat once as
  that person. When the real owner arrives, the tablet refuses them and
  the attempt appears under Alerts — replace the pass then.
- **Forgotten PIN, or someone set another person's PIN first:** Firebase
  console → Authentication → Users → delete the account whose email starts
  with the person's ID (the ID is the document name in the *employees*
  collection); then in Firestore → employees → that person, delete the
  `pinSet` field. They can then choose a new PIN.
- **No internet:** the tablet shows *Could not record*. Use the paper list
  until the connection is back.
- **Guests / visitors who are not staff:** not handled separately yet. Add
  them with *Add a person* (they appear on the report as added at the
  counter) or decide a rule with the office.
- **Web address** contains "govt-checkin" because a Firebase project ID
  cannot be renamed. A second address (e.g. `giraphe-meal-app.web.app`)
  can be added in the same project if wanted.

---

## 8. Change history

All in October 2026.

1. **Original app:** tap a name at the till, self-service page with a
   shared-passcode report.
2. **Booking, scanning and reports:** "Will you eat tomorrow?", QR meal
   passes and camera scanning, Today / Plan / Alerts tabs, daily and
   monthly reports with PDF export.
3. **Security:** shared passcodes replaced with real accounts; database
   rules added; employee PINs moved into Firebase Authentication; phone
   "I ate today" button removed (meals only at the counter); server time
   on every record; removals turned into permanent corrections; pass keys
   so a lost pass can be cancelled; roster loading made duplicate-safe.
4. **Design:** formal look (cream, white cards, deep green and terracotta,
   Public Sans typeface), employee app with Home / Pass / Profile tabs.
5. **Add a person** at the counter, stamped and shown on every report;
   reports no longer count someone as "did not eat" for days before they
   were added.
6. **Name search ignores capitals,** spacing, accents and word order;
   *Which one are you?* when names are shared.
7. **Passes issued automatically** so the phone Pass works without
   printing.
8. **Renamed** from govt_checkin to **Giraphe Meal App**; home-screen icon
   and name set; published at the live address; staff poster made.

---

## 9. Where things are in the code

```
firestore.rules                who may read/write what — the real security
lib/
  main.dart                    entry point, starts Firebase
  auth.dart                    restaurant/office sign-in, employee PINs
  admin_config.dart            office and restaurant names on reports/passes
  employee_roster.dart         the staff list to load
  dates.dart                   working days, pass codes
  text_match.dart              name matching (capitals, accents, order)
  theme.dart                   colours and typeface
  models/                      employee, meal, attendance
  services/
    firestore_service.dart     every read and write to the database
    report.dart                who ate / who didn't — used by screen and PDF
    pdf_service.dart           report and pass PDFs
  screens/
    landing_screen.dart        first screen, three choices
    home_screen.dart           restaurant counter: check in, today, plan, alerts
    scan_screen.dart           camera scanner
    badges_screen.dart         meal passes: print all, replace a lost one
    my_record_screen.dart      employee app: Home, Pass, Profile
    govt_report_screen.dart    reports
  widgets/                     shared pieces (sign-in, add person, check-in
                               confirmation, yes/no buttons, cards)
test/widget_test.dart          the 14 automated tests
```
