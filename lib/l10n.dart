import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

/// English / Kinyarwanda for the screens customers see. Text is written in
/// English in the code and looked up here, so a missing translation simply
/// shows the English.
enum Lang { en, rw }

final language = ValueNotifier<Lang>(Lang.en);

const _prefKey = 'language';

/// Restores the language chosen last time on this phone or tablet.
Future<void> loadLanguage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefKey) == 'rw') language.value = Lang.rw;
  } catch (_) {
    // Private browsing or blocked storage: start in English.
  }
}

Future<void> setLanguage(Lang lang) async {
  language.value = lang;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, lang.name);
  } catch (_) {}
}

/// The text in the chosen language. `{name}`-style blanks are filled from
/// [args]: tr('Welcome, {name}.', {'name': n}).
String tr(String english, [Map<String, String> args = const {}]) {
  var text = language.value == Lang.rw ? (_rw[english] ?? english) : english;
  args.forEach((k, v) => text = text.replaceAll('{$k}', v));
  return text;
}

const _rwDays = [
  'Kuwa mbere',
  'Kuwa kabiri',
  'Kuwa gatatu',
  'Kuwa kane',
  'Kuwa gatanu',
  'Kuwa gatandatu',
  'Ku cyumweru',
];
const _rwMonths = [
  'Mutarama',
  'Gashyantare',
  'Werurwe',
  'Mata',
  'Gicurasi',
  'Kamena',
  'Nyakanga',
  'Kanama',
  'Nzeri',
  'Ukwakira',
  'Ugushyingo',
  'Ukuboza',
];

/// "Wednesday 28 October" / "Kuwa gatatu 28 Ukwakira".
String dayAndDate(DateTime d) => language.value == Lang.rw
    ? '${_rwDays[d.weekday - 1]} ${d.day} ${_rwMonths[d.month - 1]}'
    : DateFormat('EEEE d MMMM').format(d);

/// "Wednesday, 28 October 2026" / "Kuwa gatatu, 28 Ukwakira 2026".
String fullDate(DateTime d) => language.value == Lang.rw
    ? '${_rwDays[d.weekday - 1]}, ${d.day} ${_rwMonths[d.month - 1]} ${d.year}'
    : DateFormat('EEEE, d MMMM yyyy').format(d);

/// "October 2026" / "Ukwakira 2026".
String monthAndYear(DateTime d) => language.value == Lang.rw
    ? '${_rwMonths[d.month - 1]} ${d.year}'
    : DateFormat('MMMM yyyy').format(d);

/// Clock time; Kinyarwanda uses the 24-hour clock ("saa 12:30").
String clockTime(DateTime d) => language.value == Lang.rw
    ? DateFormat('HH:mm').format(d)
    : DateFormat('h:mm a').format(d);

/// The EN / RW switch, for an app bar.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Lang>(
      valueListenable: language,
      builder: (context, lang, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SegmentedButton<Lang>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            selectedBackgroundColor: GiColors.primary,
            selectedForegroundColor: Colors.white,
          ),
          segments: const [
            ButtonSegment(
                value: Lang.en, label: Text('EN'), tooltip: 'English'),
            ButtonSegment(
                value: Lang.rw, label: Text('RW'), tooltip: 'Kinyarwanda'),
          ],
          selected: {lang},
          onSelectionChanged: (s) => setLanguage(s.first),
        ),
      ),
    );
  }
}

// Translations. Please have a Kinyarwanda speaker read these over; they
// can be corrected here without touching the screens.
const _rw = <String, String>{
  // Sign-in
  'STAFF MEAL SERVICE': 'SERIVISI Y\'AMAFUNGURO Y\'ABAKOZI',
  'Sign in': 'Injira',
  'Customer': 'Umukiriya',
  'Restaurant': 'Resitora',
  'Audit': 'Ubugenzuzi',
  'Returning customer: use your name and PIN. First time here? Create your PIN below.':
      'Niba usanzwe uyikoresha: koresha izina ryawe na PIN. Ni ubwa mbere? Kora PIN yawe hepfo.',
  'Open My Meals': 'Fungura Amafunguro Yanjye',
  'First time? Create customer PIN': 'Ni ubwa mbere? Kora PIN yawe',

  // My meals
  'MY MEALS': 'AMAFUNGURO YANJYE',
  'MEAL PASS': 'IKARITA Y\'IFUNGURO',
  'MY PROFILE': 'UMWIRONDORO WANJYE',
  'Change role': 'Hindura uruhare',
  'Home': 'Ahabanza',
  'Pass': 'Ikarita',
  'Profile': 'Umwirondoro',
  'STEP 1 OF 2': 'INTAMBWE YA 1 KURI 2',
  'STEP 2 OF 2': 'INTAMBWE YA 2 KURI 2',
  'Find your name': 'Shaka izina ryawe',
  'Type your name. Capital letters do not matter.':
      'Andika izina ryawe. Inyuguti nkuru cyangwa nto ntacyo bitwaye.',
  'Your name': 'Izina ryawe',
  'Continue': 'Komeza',
  'Name not found. Check the spelling and try again, or ask at the restaurant.':
      'Izina ntiribonetse. Reba uko waryanditse wongere ugerageze, cyangwa ubaze kuri resitora.',
  'Many people match. Please type more of your name.':
      'Abantu benshi bafite iryo zina. Andika izina ryawe ryuzuye.',
  'No connection. Please try again.': 'Nta murandasi. Ongera ugerageze.',
  'WHICH ONE ARE YOU?': 'NI NDE MURI ABA?',
  'Create your PIN': 'Kora PIN yawe',
  'Enter your PIN': 'Andika PIN yawe',
  'Welcome, {name}. Choose 4 numbers and remember them. Do not share your PIN with anyone.':
      'Murakaza neza, {name}. Hitamo imibare 4 kandi uyibuke. Ntugire uwo uha PIN yawe.',
  '{name}, enter your 4-number PIN.': '{name}, andika PIN yawe y\'imibare 4.',
  'Save PIN and continue': 'Bika PIN ukomeze',
  'Not you? Go back': 'Si wowe? Subira inyuma',
  'Forgotten your PIN? The restaurant manager can reset it.':
      'Wibagiwe PIN yawe? Umuyobozi wa resitora arayigufasha.',
  'The PIN is 4 numbers': 'PIN igizwe n\'imibare 4',
  'This name already has a PIN. Enter that PIN.':
      'Iri zina risanzwe rifite PIN. Andika iyo PIN.',
  'Wrong PIN. Please try again.': 'PIN si yo. Ongera ugerageze.',
  'Something went wrong: {error}': 'Habaye ikibazo: {error}',
  'Good morning': 'Mwaramutse',
  'Good afternoon': 'Mwiriwe',
  'Good evening': 'Mwiriwe',
  "TODAY'S STATUS": 'UYU MUNSI',
  'Meal taken at {time}': 'Wafashe ifunguro saa {time}',
  'Not yet checked in': 'Ntiwari wafata ifunguro',
  'Meals this month': 'Amafunguro y\'uku kwezi',
  'Meal plan  |  next five working days':
      'Gahunda y\'amafunguro  |  iminsi 5 y\'akazi ikurikira',
  'Your plan has been submitted and is locked.':
      'Gahunda yawe yoherejwe, ntishobora guhinduka.',
  'Tick the days you will eat here, then submit. Days you have already submitted cannot be changed.':
      'Hitamo iminsi uzafatira ifunguro hano, hanyuma wohereze. Iminsi wamaze kohereza ntishobora guhinduka.',
  'Submitted': 'Byoherejwe',
  'Entered by the office. You can change it.':
      'Byashyizweho n\'ibiro. Ushobora kubihindura.',
  'Entered by the restaurant. You can change it.':
      'Byashyizweho na resitora. Ushobora kubihindura.',
  'Submit meal plan': 'Ohereza gahunda',
  'Could not submit the plan: {error}':
      'Ntibyashobotse kohereza gahunda: {error}',
  'Your pass has not been issued yet.': 'Ikarita yawe ntiratangwa.',
  'Please ask at the restaurant counter.': 'Baza kuri resitora.',
  'Scan on arrival': 'Yerekane ugeze',
  'Hold this screen, or your printed pass, to the counter camera.':
      'Erekana iyi ecran cyangwa ikarita yawe yacapwe imbere ya kamera ya resitora.',
  'CHECK-IN STATUS': 'UKO BIHAGAZE',
  'Checked in at {time}': 'Wanditswe saa {time}',
  'Awaiting scan': 'Ntiwari wasikanwa',
  'Ate on {n} of {total} days': 'Wafashe ifunguro iminsi {n} kuri {total}',
  'No working days yet this month.': 'Nta minsi y\'akazi irashira uku kwezi.',
  'Ate (signed paper list)': 'Wafashe (wasinye ku rupapuro)',
  'Ate at {time}': 'Wafashe saa {time}',
  'Did not eat': 'Ntiwafashe',
  'said coming': 'wavuze ko uzaza',
  'said not coming': 'wavuze ko utazaza',
  'no answer': 'nta gisubizo',
  'Sign out': 'Sohoka',
  'Could not load your record: {error}':
      'Ntibyashobotse kubona amakuru yawe: {error}',

  // Counter (seen by the customer)
  'SCAN MEAL PASS': 'SIKANA IKARITA',
  'Hold your meal pass in front of the camera':
      'Erekana ikarita yawe imbere ya kamera',
  'Ready': 'Byiteguye',
  'One moment…': 'Akanya gato…',
  'That is not a meal pass': 'Iyo si ikarita y\'ifunguro',
  'This pass is no longer valid. Please ask at the counter.':
      'Iyi karita ntigikora. Baza kuri resitora.',
  'Pass not recognised. Please ask at the counter.':
      'Ikarita ntimenyekanye. Baza kuri resitora.',
  'CHECK-IN CONFIRMED': 'IFUNGURO RYANDITSWE',
  'ALREADY RECORDED TODAY': 'WAMAZE KWANDIKWA UYU MUNSI',
  'A second meal on the same day is not permitted.':
      'Ntibyemewe gufata ifunguro kabiri ku munsi umwe.',
  'Close': 'Funga',

  // Reports
  'REPORTS': 'RAPORO',
  'One day': 'Umunsi umwe',
  'Whole month': 'Ukwezi kose',
  'Print / save PDF': 'Capisha / Bika PDF',
  'Send / share': 'Ohereza / Sangiza',
  'Who is coming this week': 'Abaza muri iki cyumweru',
  'Manage office roster': 'Genzura urutonde rw’ibiro',
  'RESTAURANT COUNTER': 'AHO BAFATIRA AMAFUNGURO',
  'Reports': 'Raporo',
  'Meal passes': 'Amakarita y’amafunguro',
  'Check in': 'Kwandikwa',
  'Today': 'Uyu munsi',
  'Meal plan': 'Gahunda y’amafunguro',
  'Alerts': 'Imenyesha',
  'Total who ate': 'Abafashe amafunguro uyu munsi',
  'Not on the list, but came': 'Abatari kuri list baje',
  'Not to come, but came': 'Abatarikuza baje',
  'Guests': 'Abashitsi',
  'Staff': 'Abakozi',
  'None': 'Nta n’umwe',
};
