import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth.dart';
import '../dates.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../services/firestore_service.dart';
import '../theme.dart';

enum _WeekFilter { roster, all, notComing, noAnswer }

/// The office enters its weekly list here. First the week's duty roster —
/// who is working that week — then who on it will NOT eat on which days;
/// the rest of the roster is marked as coming. Answers are saved exactly
/// as if the employee had given them, so the restaurant's meal plan and
/// the reports pick them up.
class WeeklyPlanScreen extends StatefulWidget {
  const WeeklyPlanScreen({super.key});

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  final _service = FirestoreService();
  final _search = TextEditingController();

  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  _WeekFilter _filter = _WeekFilter.roster;

  late DateTime _weekStart;
  late Stream<Map<String, Attendance>> _answers;
  late Stream<Set<String>?> _roster;

  /// The roster being ticked, while editing it; null otherwise.
  Set<String>? _draft;

  @override
  void initState() {
    super.initState();
    // On a weekend the week being planned is the coming one.
    final t = today();
    _setWeek(_mondayOf(t.weekday >= DateTime.saturday ? nextServiceDay(t) : t));
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  List<DateTime> get _days => [
        for (var i = 0; i < 5; i++)
          DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i),
      ];

  void _setWeek(DateTime monday) {
    _weekStart = monday;
    _draft = null;
    final days = _days;
    _answers =
        _service.streamAttendanceRange(dateKey(days.first), dateKey(days.last));
    _roster = _service.streamWeekRoster(dateKey(monday));
  }

  Future<void> _copyLastWeek() async {
    final last =
        DateTime(_weekStart.year, _weekStart.month, _weekStart.day - 7);
    final ids = await _service.fetchWeekRoster(dateKey(last));
    if (!mounted) return;
    if (ids == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No roster was set for last week.')));
      return;
    }
    final active = _employees.map((e) => e.id).toSet();
    setState(() => _draft = ids.intersection(active));
  }

  Future<void> _saveRoster() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _busy = true);
    try {
      await _service.setWeekRoster(dateKey(_weekStart), draft);
      if (mounted) setState(() => _draft = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save the roster: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Answers the office entered for people who aren't on this week's
  /// roster (e.g. from marking everyone, before the roster existed).
  /// The employee's own answers and the restaurant's are never touched.
  Future<void> _clearOffRoster(List<String> docIds) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear answers for people not on the roster?'),
        content: Text('${docIds.length} answers this week were entered by the '
            'office for people who are not on this week\'s roster. They will '
            'be cleared, so those people are no longer expected to eat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear them')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _service.clearAttendanceMany(docIds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not clear: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _load() async {
    try {
      final employees = await _service.fetchEmployees();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the roster: $e';
        });
      }
    }
  }

  Future<void> _save(
      List<({Employee employee, String date, bool coming})> answers) async {
    if (answers.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _service.setAttendanceMany(answers, 'office');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clear(Employee employee, String date) async {
    setState(() => _busy = true);
    try {
      await _service.clearAttendance(employee.id, date);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not clear: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Everyone on this week's roster without an answer for a day is marked
  /// as coming that day. Answers already given (yes or no) are left alone,
  /// and nobody off the roster is touched.
  Future<void> _fillRestAsComing(
      Map<String, Attendance> answers, Set<String> roster) async {
    final missing = [
      for (final e in _employees.where((e) => roster.contains(e.id)))
        for (final d in _days)
          if (!answers.containsKey('${dateKey(d)}_${e.id}'))
            (employee: e, date: dateKey(d), coming: true),
    ];
    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Everyone on the roster already has an answer for this week.')));
      return;
    }
    final people = missing.map((a) => a.employee.id).toSet().length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark the rest of the roster as coming?'),
        content: Text('$people people on this week\'s roster have days with '
            'no answer. Those days will be set to "coming". People you '
            'marked as not coming, and people not on the roster, stay as '
            'they are.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mark as coming')),
        ],
      ),
    );
    if (confirmed == true) await _save(missing);
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (staffRoleForEmail(email) != StaffRole.audit) {
      return Scaffold(
        appBar: AppBar(title: const Text('WEEKLY LIST')),
        body: const Center(child: Text('This page is for audit-office users.')),
      );
    }

    return Scaffold(
      backgroundColor: GiColors.paper,
      appBar: AppBar(title: const Text('WEEKLY LIST')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: StreamBuilder<Set<String>?>(
            stream: _roster,
            builder: (context, rosterSnap) =>
                StreamBuilder<Map<String, Attendance>>(
              stream: _answers,
              builder: (context, snapshot) {
                final error = snapshot.error ?? rosterSnap.error;
                if (error != null) {
                  return Center(
                      child: Text('Could not load answers: $error',
                          style: const TextStyle(color: GiColors.red)));
                }
                return _buildBody(snapshot.data ?? const {}, rosterSnap.data);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, Attendance> answers, Set<String>? roster) {
    final days = _days;
    final keys = days.map(dateKey).toList();
    final draft = _draft;
    bool? answer(Employee e, String date) => answers['${date}_${e.id}']?.coming;
    bool onRoster(Employee e) => roster == null || roster.contains(e.id);

    final query = _search.text.trim().toLowerCase();
    final shown = _employees.where((e) {
      if (query.isNotEmpty &&
          !e.name.toLowerCase().contains(query) &&
          !e.department.toLowerCase().contains(query)) {
        return false;
      }
      if (draft != null) return true;
      return switch (_filter) {
        _WeekFilter.roster => onRoster(e),
        _WeekFilter.all => true,
        _WeekFilter.notComing => keys.any((d) => answer(e, d) == false),
        _WeekFilter.noAnswer =>
          onRoster(e) && keys.any((d) => answer(e, d) == null),
      };
    }).toList();

    final onRosterCount = _employees.where(onRoster).length;
    final notComing =
        _employees.where((e) => keys.any((d) => answer(e, d) == false)).length;
    final noAnswer = _employees
        .where((e) => onRoster(e) && keys.any((d) => answer(e, d) == null))
        .length;

    // Office answers for people off the roster — including anyone since
    // removed from the list — left over from marking everyone.
    final offRoster = roster == null
        ? const <String>[]
        : [
            for (final entry in answers.entries)
              if (entry.value.setBy == 'office' &&
                  !roster.contains(entry.value.employeeId))
                entry.key,
          ];

    Widget chip(_WeekFilter f, String text) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(text),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: GiColors.primary),
                tooltip: 'Previous week',
                onPressed: () => setState(() => _setWeek(DateTime(
                    _weekStart.year, _weekStart.month, _weekStart.day - 7))),
              ),
              Expanded(
                child: Text(
                    'Week of ${DateFormat('d MMM').format(days.first)} – '
                    '${DateFormat('d MMM yyyy').format(days.last)}',
                    textAlign: TextAlign.center,
                    style: giHeading(size: 19)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: GiColors.primary),
                tooltip: 'Next week',
                onPressed: () => setState(() => _setWeek(DateTime(
                    _weekStart.year, _weekStart.month, _weekStart.day + 7))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _rosterBanner(roster, offRoster),
          const SizedBox(height: 10),
          if (draft == null) ...[
            // Expected meals per day — what the kitchen will cook for.
            Row(
              children: [
                for (final d in keys)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: GiColors.card,
                        border: Border.all(color: GiColors.line),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                              '${answers.values.where((a) => a.date == d && a.coming).length}',
                              style:
                                  giHeading(size: 22, color: GiColors.green)),
                          Text(DateFormat('EEE').format(parseDateKey(d)),
                              style: giBody(size: 12, color: GiColors.muted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Coming each day',
                textAlign: TextAlign.center,
                style: giBody(size: 12, color: GiColors.muted)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _search,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search name or department'),
          ),
          const SizedBox(height: 8),
          if (draft == null) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (roster != null)
                  chip(_WeekFilter.roster, 'On roster ($onRosterCount)'),
                chip(_WeekFilter.all, 'Everyone (${_employees.length})'),
                chip(_WeekFilter.notComing, 'Not coming ($notComing)'),
                chip(_WeekFilter.noAnswer, 'No answer ($noAnswer)'),
              ]),
            ),
            const SizedBox(height: 8),
            Text(
                'Tap a day to switch between coming and not coming. '
                'Press and hold a day to clear it.',
                style: giBody(size: 13, color: GiColors.muted)),
            const SizedBox(height: 8),
          ],
          if (_error != null)
            Text(_error!, style: const TextStyle(color: GiColors.red)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? Center(
                        child: Text('Nobody in this list',
                            style: giBody(color: GiColors.muted)))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) => draft != null
                            ? _rosterTick(shown[index], draft)
                            : _personRow(shown[index], days, answer,
                                onRoster: onRoster(shown[index])),
                      ),
          ),
          const SizedBox(height: 8),
          if (draft == null)
            FilledButton.icon(
              onPressed: _busy || _loading || roster == null
                  ? null
                  : () => _fillRestAsComing(answers, roster),
              icon: const Icon(Icons.done_all),
              label: Text(roster == null
                  ? 'Set this week\'s roster first'
                  : 'Mark the rest of the roster as coming'),
            ),
        ],
      ),
    );
  }

  /// What the roster for this week is, and the buttons to set or fix it.
  Widget _rosterBanner(Set<String>? roster, List<String> offRoster) {
    final draft = _draft;
    Widget box(Color bg, List<Widget> children) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: GiColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
        );

    if (draft != null) {
      return box(GiColors.greenBg, [
        Text('Tick everyone on this week\'s roster (${draft.length} ticked)',
            style: giBody(size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: _busy ? null : _copyLastWeek,
              child: const Text('Copy last week')),
          OutlinedButton(
              onPressed: _busy ? null : () => setState(() => _draft = {}),
              child: const Text('Untick all')),
          TextButton(
              onPressed: _busy ? null : () => setState(() => _draft = null),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _busy ? null : _saveRoster,
              child: const Text('Save roster')),
        ]),
      ]);
    }

    if (roster == null) {
      return box(GiColors.accentBg, [
        Text('No roster set for this week',
            style: giBody(size: 15, weight: FontWeight.w600)),
        Text(
            'Tick the people on this week\'s roster first. Only they are '
            'marked as coming.',
            style: giBody(size: 13, color: GiColors.muted)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
              onPressed:
                  _busy || _loading ? null : () => setState(() => _draft = {}),
              child: const Text('Set this week\'s roster')),
        ),
      ]);
    }

    return box(GiColors.card, [
      Row(children: [
        Expanded(
          child: Text('This week\'s roster: ${roster.length} people',
              style: giBody(size: 15, weight: FontWeight.w600)),
        ),
        TextButton(
            onPressed: _busy || _loading
                ? null
                : () => setState(() => _draft = {...roster}),
            child: const Text('Edit roster')),
      ]),
      if (offRoster.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
            '${offRoster.length} answers this week are for people not on the '
            'roster.',
            style: giBody(size: 13, color: GiColors.accent)),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
              onPressed: _busy ? null : () => _clearOffRoster(offRoster),
              child: const Text('Clear them')),
        ),
      ],
    ]);
  }

  Widget _rosterTick(Employee e, Set<String> draft) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: CheckboxListTile(
        value: draft.contains(e.id),
        title: Text(e.name, style: giBody(size: 16, weight: FontWeight.w600)),
        subtitle: e.department.isEmpty ? null : Text(e.department),
        onChanged: (v) => setState(() {
          if (v == true) {
            draft.add(e.id);
          } else {
            draft.remove(e.id);
          }
        }),
      ),
    );
  }

  Widget _personRow(
      Employee e, List<DateTime> days, bool? Function(Employee, String) answer,
      {required bool onRoster}) {
    final keys = days.map(dateKey).toList();
    final awayAllWeek = keys.every((d) => answer(e, d) == false);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name,
                          style: giBody(size: 16, weight: FontWeight.w600)),
                      if (e.department.isNotEmpty)
                        Text(e.department,
                            style: giBody(size: 13, color: GiColors.muted)),
                      if (!onRoster)
                        Text('Not on this week\'s roster',
                            style: giBody(size: 13, color: GiColors.accent)),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor:
                          awayAllWeek ? GiColors.primary : GiColors.accent),
                  onPressed: _busy
                      ? null
                      : () => _save([
                            for (final d in keys)
                              (employee: e, date: d, coming: awayAllWeek),
                          ]),
                  child:
                      Text(awayAllWeek ? 'Coming all week' : 'Not this week'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _DayToggle(
                        day: DateFormat('EEE').format(days[i]),
                        coming: answer(e, keys[i]),
                        onTap: _busy
                            ? null
                            : () => _save([
                                  (
                                    employee: e,
                                    date: keys[i],
                                    coming: answer(e, keys[i]) != true,
                                  ),
                                ]),
                        onLongPress: _busy || answer(e, keys[i]) == null
                            ? null
                            : () => _clear(e, keys[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One day's answer: a tick for coming, a cross for not coming, a dash for
/// no answer — the icon carries the meaning, never colour alone.
class _DayToggle extends StatelessWidget {
  final String day;
  final bool? coming;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DayToggle({
    required this.day,
    required this.coming,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, fg, bg, label) = switch (coming) {
      true => (Icons.check, GiColors.green, GiColors.greenBg, 'coming'),
      false => (Icons.close, GiColors.red, GiColors.redBg, 'not coming'),
      null => (Icons.remove, GiColors.muted, GiColors.card, 'no answer'),
    };
    return Semantics(
      button: true,
      label: '$day, $label',
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: coming == null ? GiColors.line : fg),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(day, style: giBody(size: 12, color: GiColors.muted)),
                Icon(icon, size: 20, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
