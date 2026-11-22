import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(const KamApp());

const _red = Color(0xFFFF1744);
const _bg = Color(0xFF080808);
const _card = Color(0xFF161616);
const _rulesKey = 'kam_rules_v2';
const _dayKey = 'kam_last_day_v2';
const graceMinutes = 15; // sabit mola. Uzatma yok.

const _mottos = [
  'Disiplin, canın istemediğinde de yapmaktır.',
  'Motivasyon gelip geçer. Disiplin kalır.',
  'Bugünün rahatı, yarının pişmanlığıdır.',
  'Ekran seni izlerken hayat akıp gidiyor.',
  'Söz verdin. Şimdi tutma zamanı.',
  'Kolay olan seni küçültür, zor olan büyütür.',
  'Bahane üretme. Şınav çek.',
  'Kendine verdiğin sözü bozma. İlk güvenin orada başlar.',
  'Küçük zaferler, büyük karakter yapar.',
  'Sınır koyan özgürdür. Sınırsız olan esirdir.',
];

String _today() => DateTime.now().toIso8601String().substring(0, 10);

String _fmtMin(int m) {
  if (m < 60) return '$m dk';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h sa' : '$h sa $r dk';
}

class KamApp extends StatelessWidget {
  const KamApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kam Odaklanma',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _red,
            brightness: Brightness.dark,
            surface: _card,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        home: const HomeScreen(),
      );
}

// ───────────────────────── MODEL & DEPO ─────────────────────────

class LimitRule {
  final String id;
  String appName;
  int limitMinutes; // günlük sınır
  int pushups; // 0 = yok
  int plankSeconds; // 0 = yok
  int readMinutes; // 0 = yok
  int pendingLimit; // 0 = yok, yarın geçerli
  bool pendingDelete; // yarın silinir
  int doneToday;
  String doneDay;

  LimitRule({
    required this.id,
    required this.appName,
    required this.limitMinutes,
    required this.pushups,
    required this.plankSeconds,
    required this.readMinutes,
    this.pendingLimit = 0,
    this.pendingDelete = false,
    this.doneToday = 0,
    this.doneDay = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'appName': appName,
        'limitMinutes': limitMinutes,
        'pushups': pushups,
        'plankSeconds': plankSeconds,
        'readMinutes': readMinutes,
        'pendingLimit': pendingLimit,
        'pendingDelete': pendingDelete,
        'doneToday': doneToday,
        'doneDay': doneDay,
      };

  factory LimitRule.fromJson(Map<String, dynamic> j) => LimitRule(
        id: j['id'] as String,
        appName: j['appName'] as String,
        limitMinutes: j['limitMinutes'] as int? ?? 60,
        pushups: j['pushups'] as int? ?? 0,
        plankSeconds: j['plankSeconds'] as int? ?? 0,
        readMinutes: j['readMinutes'] as int? ?? 0,
        pendingLimit: j['pendingLimit'] as int? ?? 0,
        pendingDelete: j['pendingDelete'] as bool? ?? false,
        doneToday: j['doneToday'] as int? ?? 0,
        doneDay: j['doneDay'] as String? ?? '',
      );

  String get tasksText => [
        if (pushups > 0) '$pushups şınav',
        if (plankSeconds > 0) '$plankSeconds sn plank',
        if (readMinutes > 0) '$readMinutes dk kitap',
      ].join(' + ');
}

class RuleStore {
  static const _s = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static Future<List<LimitRule>> load() async {
    final t = await _s.read(key: _rulesKey);
    if (t == null) return [];
    try {
      return (jsonDecode(t) as List<dynamic>)
          .map((e) => LimitRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<LimitRule> r) =>
      _s.write(key: _rulesKey, value: jsonEncode(r.map((e) => e.toJson()).toList()));

  static Future<String?> lastDay() => _s.read(key: _dayKey);
  static Future<void> setLastDay(String d) => _s.write(key: _dayKey, value: d);
}

// ───────────────────── iOS EKRAN SÜRESİ KÖPRÜSÜ ─────────────────────

class RuleStatus {
  final bool locked;
  final int graceUntil; // ms
  const RuleStatus(this.locked, this.graceUntil);
  bool get inGrace => !locked && DateTime.now().millisecondsSinceEpoch < graceUntil;
}

class ScreenTimeBridge {
  static const _ch = MethodChannel('kam/screentime');

  static Future<bool> requestAuthorization() async {
    try {
      return await _ch.invokeMethod<bool>('requestAuthorization') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> pickApps(String id) async {
    try {
      return await _ch.invokeMethod<bool>('pickApps', {'ruleId': id}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startLimit(String id, int minutes) async {
    try { await _ch.invokeMethod('startLimit', {'ruleId': id, 'minutes': minutes}); } catch (_) {}
  }

  static Future<void> unshield(String id) async {
    try { await _ch.invokeMethod('unshield', {'ruleId': id}); } catch (_) {}
  }

  static Future<void> removeRule(String id) async {
    try { await _ch.invokeMethod('removeRule', {'ruleId': id}); } catch (_) {}
  }

  static Future<RuleStatus> status(String id) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status', {'ruleId': id});
      return RuleStatus(m?['locked'] == true, (m?['graceUntil'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return const RuleStatus(false, 0);
    }
  }
}

// ───────────────────────── ANA EKRAN ─────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<LimitRule> _rules = [];
  final Map<String, RuleStatus> _status = {};
  bool _loading = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _rollover().then((_) => _refresh());
  }

  Future<void> _init() async {
    _rules = await RuleStore.load();
    await _rollover();
    await _refresh();
    if (mounted) setState(() => _loading = false);
  }

  /// Yeni güne geçildiyse bekleyen değişiklikleri (limit artışı, silme) uygular.
  Future<void> _rollover() async {
    final today = _today();
    if (await RuleStore.lastDay() == today) return;
    final removed = <LimitRule>[];
    for (final r in _rules) {
      if (r.pendingDelete) {
        removed.add(r);
        await ScreenTimeBridge.removeRule(r.id);
      } else if (r.pendingLimit > 0) {
        r.limitMinutes = r.pendingLimit;
        r.pendingLimit = 0;
        await ScreenTimeBridge.startLimit(r.id, r.limitMinutes);
      }
    }
    _rules.removeWhere(removed.contains);
    await RuleStore.setLastDay(today);
    await RuleStore.save(_rules);
  }

  Future<void> _refresh() async {
    for (final r in _rules) {
      _status[r.id] = await ScreenTimeBridge.status(r.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    await RuleStore.save(_rules);
    if (mounted) setState(() {});
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── Yeni sınır ──
  Future<void> _addRule() async {
    final name = TextEditingController();
    final hours = TextEditingController(text: '1');
    final mins = TextEditingController(text: '0');
    final push = TextEditingController(text: '20');
    final plank = TextEditingController(text: '0');
    final read = TextEditingController(text: '15');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Yeni sınır'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad (örn. Sosyal medya)')),
            const SizedBox(height: 14),
            const Align(alignment: Alignment.centerLeft, child: Text('GÜNLÜK SINIR', style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 1.2))),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Saat'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: mins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dakika'))),
            ]),
            const SizedBox(height: 14),
            const Align(alignment: Alignment.centerLeft, child: Text('KİLİT AÇMA GÖREVLERİ (0 = yok)', style: TextStyle(fontSize: 11, color: Colors.white54, letterSpacing: 1.2))),
            const SizedBox(height: 6),
            TextField(controller: push, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Şınav sayısı')),
            const SizedBox(height: 10),
            TextField(controller: plank, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Plank (saniye)')),
            const SizedBox(height: 10),
            TextField(controller: read, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kitap okuma (dakika)')),
            const SizedBox(height: 12),
            const Text('Dikkat: limit artırma ve silme ancak ertesi gün geçerli olur. Süre uzatma yoktur.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    final n = name.text.trim();
    final limit = (int.tryParse(hours.text) ?? 0) * 60 + (int.tryParse(mins.text) ?? 0);
    final p = int.tryParse(push.text) ?? 0;
    final pl = int.tryParse(plank.text) ?? 0;
    final rd = int.tryParse(read.text) ?? 0;
    for (final c in [name, hours, mins, push, plank, read]) { c.dispose(); }
    if (ok != true) return;
    if (n.isEmpty) return _toast('Bir ad yaz.');
    if (limit < 1) return _toast('Günlük sınır en az 1 dakika olmalı.');
    if (p <= 0 && pl <= 0 && rd <= 0) return _toast('En az bir görev seç. Görevsiz kilit olmaz.');

    if (!await ScreenTimeBridge.requestAuthorization()) {
      return _toast('Ekran Süresi izni verilmedi. Ayarlar > Ekran Süresi bölümünden izin ver.');
    }
    final rule = LimitRule(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      appName: n, limitMinutes: limit, pushups: p, plankSeconds: pl, readMinutes: rd,
    );
    if (!await ScreenTimeBridge.pickApps(rule.id)) {
      return _toast('Uygulama seçilmedi, sınır oluşturulmadı.');
    }
    await ScreenTimeBridge.startLimit(rule.id, limit);
    _rules.add(rule);
    await _save();
    await _refresh();
  }

  // ── Limit değiştir (yarın) ──
  Future<void> _editLimit(LimitRule r) async {
    final h = TextEditingController(text: '${r.limitMinutes ~/ 60}');
    final m = TextEditingController(text: '${r.limitMinutes % 60}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text('${r.appName} limiti'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Saat'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: m, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dakika'))),
          ]),
          const SizedBox(height: 12),
          const Text('Yeni limit bugün değil, yarın başlar.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yarına planla'),
          ),
        ],
      ),
    );
    final v = (int.tryParse(h.text) ?? 0) * 60 + (int.tryParse(m.text) ?? 0);
    h.dispose(); m.dispose();
    if (ok != true || v < 1) return;
    r.pendingLimit = v == r.limitMinutes ? 0 : v;
    await _save();
    _toast(r.pendingLimit == 0 ? 'Değişiklik yok.' : 'Yarın başlayacak: ${_fmtMin(v)}');
  }

  Future<void> _toggleDelete(LimitRule r) async {
    if (r.pendingDelete) {
      r.pendingDelete = false;
      await _save();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gerçekten bırakıyor musun?'),
        content: Text('${r.appName} sınırı bugün kalkmaz. Yarın silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yarın sil')),
        ],
      ),
    );
    if (ok == true) {
      r.pendingDelete = true;
      await _save();
    }
  }

  // ── Görevler ──
  Future<void> _doTasks(LimitRule r) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TaskScreen(rule: r)),
    );
    if (done != true) return;
    await ScreenTimeBridge.unshield(r.id);
    final today = _today();
    if (r.doneDay != today) { r.doneDay = today; r.doneToday = 0; }
    r.doneToday++;
    await _save();
    await _refresh();
    _toast('Hak ettin: $graceMinutes dk. Süre uzatma yok.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final today = _today();
    final lockedCount = _rules.where((r) => _status[r.id]?.locked == true).length;
    final doneCount = _rules.fold<int>(0, (a, r) => a + (r.doneDay == today ? r.doneToday : 0));
    final motto = _mottos[DateTime.now().difference(DateTime(DateTime.now().year)).inDays % _mottos.length];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _red,
        foregroundColor: Colors.white,
        onPressed: _addRule,
        icon: const Icon(Icons.add),
        label: const Text('SINIR EKLE'),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 100), children: [
          const Row(children: [
            Icon(Icons.local_fire_department_rounded, color: _red, size: 34),
            SizedBox(width: 10),
            Text('KAM', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 6)),
          ]),
          const Padding(
            padding: EdgeInsets.only(left: 44),
            child: Text('ODAKLANMA', style: TextStyle(color: Colors.white54, letterSpacing: 5, fontSize: 12)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF7A0020), Color(0xFF1C0910), _card],
              ),
              border: Border.all(color: _red.withOpacity(.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('BUGÜNÜN SÖZÜ', style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 2)),
              const SizedBox(height: 10),
              Text(motto, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _stat('$doneCount', 'bugün tamamlanan görev', Icons.fitness_center)),
            const SizedBox(width: 12),
            Expanded(child: _stat('$lockedCount', 'şu an kilitli', Icons.lock)),
          ]),
          const SizedBox(height: 22),
          const Text('SINIRLARIN', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 10),
          if (_rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Henüz sınır yok.\nBir sınır ekle, kilitlenecek uygulamaları seç ve kendi kurallarını koy.\nSözünü tutacak mısın?',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ),
          for (final r in _rules) _ruleCard(r),
        ]),
      ),
    );
  }

  Widget _stat(String big, String label, IconData icon) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(icon, color: _red),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(big, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ])),
        ]),
      );

  Widget _ruleCard(LimitRule r) {
    final st = _status[r.id] ?? const RuleStatus(false, 0);
    final Color color;
    final IconData icon;
    final String line;
    if (st.locked) {
      color = _red; icon = Icons.lock;
      line = 'Süren doldu. Bahane yok, görevleri yap.';
    } else if (st.inGrace) {
      color = Colors.orangeAccent; icon = Icons.hourglass_bottom;
      final left = ((st.graceUntil - DateTime.now().millisecondsSinceEpoch) / 60000).ceil();
      line = 'Mola: $left dk kaldı. Uzatma yok.';
    } else {
      color = Colors.greenAccent; icon = Icons.lock_open;
      line = 'Serbest. Süreni akıllı kullan.';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(r.appName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'limit') _editLimit(r);
              if (v == 'delete') _toggleDelete(r);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'limit', child: Text('Limiti değiştir (yarın)')),
              PopupMenuItem(value: 'delete', child: Text(r.pendingDelete ? 'Silmeyi iptal et' : 'Sil (yarın)')),
            ],
          ),
        ]),
        const SizedBox(height: 6),
        Text('Günlük sınır: ${_fmtMin(r.limitMinutes)}', style: const TextStyle(color: Colors.white70)),
        Text('Açma görevi: ${r.tasksText}', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 6),
        Text(line, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        if (r.pendingLimit > 0)
          Text('Yarın: limit ${_fmtMin(r.pendingLimit)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        if (r.pendingDelete)
          const Text('Yarın silinecek.', style: TextStyle(color: Colors.white38, fontSize: 12)),
        if (st.locked) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
              onPressed: () => _doTasks(r),
              child: const Text('GÖREVLERİ YAP', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ───────────────────────── GÖREV EKRANI ─────────────────────────

class TaskScreen extends StatefulWidget {
  final LimitRule rule;
  const TaskScreen({super.key, required this.rule});
  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  static const _minRepGap = Duration(milliseconds: 1500);

  // şınav
  int _reps = 0;
  DateTime? _lastRep;

  // plank
  int _plankHeld = 0;
  bool _holding = false;
  Timer? _plankTimer;

  // kitap
  DateTime? _readStart;
  Timer? _readTimer;
  Duration _readLeft = Duration.zero;
  final _summary = TextEditingController();

  LimitRule get r => widget.rule;
  bool get _pushDone => r.pushups == 0 || _reps >= r.pushups;
  bool get _plankDone => r.plankSeconds == 0 || _plankHeld >= r.plankSeconds;
  bool get _timeDone => _readStart != null && _readLeft == Duration.zero;
  bool get _readDone => r.readMinutes == 0 || (_timeDone && _summary.text.trim().length >= 60);

  @override
  void dispose() {
    _plankTimer?.cancel();
    _readTimer?.cancel();
    _summary.dispose();
    super.dispose();
  }

  void _rep() {
    final now = DateTime.now();
    if (_lastRep != null && now.difference(_lastRep!) < _minRepGap) {
      HapticFeedback.heavyImpact();
      return;
    }
    _lastRep = now;
    HapticFeedback.mediumImpact();
    setState(() => _reps++);
  }

  void _plankDown() {
    if (_plankDone) return;
    _holding = true;
    _plankTimer?.cancel();
    _plankTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_holding) { t.cancel(); return; }
      setState(() => _plankHeld++);
      HapticFeedback.selectionClick();
      if (_plankHeld >= r.plankSeconds) { t.cancel(); HapticFeedback.heavyImpact(); }
    });
    setState(() {});
  }

  void _plankUp() {
    _holding = false;
    _plankTimer?.cancel();
    if (_plankHeld < r.plankSeconds) setState(() => _plankHeld = 0); // bırakırsan sıfırlanır
  }

  void _startRead() {
    _readStart = DateTime.now();
    final end = _readStart!.add(Duration(minutes: r.readMinutes));
    _readLeft = end.difference(DateTime.now());
    _readTimer?.cancel();
    _readTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final rem = end.difference(DateTime.now());
      if (rem <= Duration.zero) {
        t.cancel();
        setState(() => _readLeft = Duration.zero);
      } else {
        setState(() => _readLeft = rem);
      }
    });
    setState(() {});
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Widget _section(IconData icon, String title, bool done, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: done ? Colors.greenAccent.withOpacity(.5) : Colors.transparent),
        ),
        child: Column(children: [
          Row(children: [
            Icon(done ? Icons.check_circle : icon, color: done ? Colors.greenAccent : _red),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final allDone = _pushDone && _plankDone && _readDone;
    return Scaffold(
      appBar: AppBar(title: Text('${r.appName} · Görevler'), backgroundColor: _bg),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(18), children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('Kolay yolu seçmedin. Şimdi hak ettiğin molayı kazan.',
                style: TextStyle(color: Colors.white70, fontSize: 15)),
          ),
          if (r.pushups > 0)
            _section(Icons.fitness_center, 'Şınav', _pushDone, [
              Text('$_reps / ${r.pushups}', style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 90,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                  onPressed: _pushDone ? null : _rep,
                  child: const Text('BURNUNU EKRANA DEĞDİR', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Telefonu yere koy. Her şınavda burnunla dokun. İki tekrar arası en az 1,5 sn.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          if (r.plankSeconds > 0)
            _section(Icons.accessibility_new, 'Plank', _plankDone, [
              Text('$_plankHeld / ${r.plankSeconds} sn', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Listener(
                onPointerDown: (_) => _plankDown(),
                onPointerUp: (_) => _plankUp(),
                onPointerCancel: (_) => _plankUp(),
                child: Container(
                  width: double.infinity, height: 90,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _plankDone ? Colors.green : (_holding ? const Color(0xFFB0102F) : _red),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_plankDone ? 'TAMAMLANDI' : 'BASILI TUT',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Planktayken burnunla veya elinle basılı tut. Bırakırsan süre sıfırlanır.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          if (r.readMinutes > 0)
            _section(Icons.menu_book, 'Kitap oku', _readDone, [
              Text(_readStart == null ? '${r.readMinutes}:00' : _fmt(_readLeft),
                  style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                  onPressed: _readStart == null ? _startRead : null,
                  child: Text(_readStart == null ? 'OKUMAYA BAŞLA' : (_timeDone ? 'SÜRE DOLDU' : 'OKUYORSUN...')),
                ),
              ),
              if (_timeDone) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _summary,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Ne okudun? Kendi cümlelerinle yaz (en az 60 karakter)',
                    helperText: '${_summary.text.trim().length} / 60',
                  ),
                ),
              ],
            ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: allDone ? () => Navigator.pop(context, true) : null,
              child: Text('KİLİDİ AÇ ($graceMinutes DK)', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}