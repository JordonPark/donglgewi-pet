import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        LicenseEntryWithLineBreaks,
        LicenseRegistry,
        defaultTargetPlatform,
        kIsWeb;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException, rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'pet/pet_game.dart';
import 'pet/pet_platform.dart';
import 'pet/pet_voice.dart';
import 'photo_analysis.dart';

const forest = Color(0xff214e3b);
const ink = Color(0xff26382e);
const paper = Color(0xfffffaf1);
const mint = Color(0xffe2ebda);

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans KR',
    ], await rootBundle.loadString('assets/pet/NotoSansKR-OFL.txt'));
  });
  runApp(const PetApp());
}

class PetApp extends StatelessWidget {
  const PetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '동글귀 · 로컬 펫',
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'PetNotoSansKR',
      colorScheme: ColorScheme.fromSeed(seedColor: forest, surface: paper),
      scaffoldBackgroundColor: paper,
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'PetNotoSansKR',
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    home: const PetRoom(),
  );
}

class PetRoom extends StatefulWidget {
  const PetRoom({super.key});

  @override
  State<PetRoom> createState() => _PetRoomState();
}

class _PetRoomState extends State<PetRoom> with SingleTickerProviderStateMixin {
  static const _home = Offset(.51, .82);
  static const _park = Offset(.52, .59);
  static const _layoutChannel = MethodChannel('donglgewi/layout');
  final _picker = ImagePicker();
  final _message = TextEditingController();
  final _messageFocus = FocusNode();
  final _composerKey = GlobalKey();
  late final AnimationController _idle;
  late PetGame _game;
  PetVoice? _voice;
  Timer? _timer;
  Future<void> _writes = Future.value();
  Offset _position = _home;
  Offset? _discPosition;
  Duration _moveDuration = const Duration(milliseconds: 220);
  bool _facingLeft = false;
  bool _ready = false;
  bool _busy = false;
  bool _greeting = false;
  bool _voiceLoading = false;
  bool _canReplay = false;
  bool _chatOpen = false;
  bool _sending = false;
  bool _longReply = false;
  int _chatRequest = 0;
  double? _download;
  String _bubble = '안녕! 우리 방에 온 걸 환영해.';
  String _storageError = '';
  String? _toolbarSide;

  bool get _usesIosLayout =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    if (_usesIosLayout) {
      _layoutChannel.setMethodCallHandler((call) async {
        if (call.method == 'toolbarSideChanged') {
          _setToolbarSide(call.arguments);
        }
      });
      unawaited(_readToolbarSide());
    }
    unawaited(_restore());
  }

  Future<void> _readToolbarSide() async {
    try {
      _setToolbarSide(await _layoutChannel.invokeMethod<String>('toolbarSide'));
    } on MissingPluginException {
      // Older preview builds can lay out the game without the native hint.
    } on PlatformException {
      // SafeArea and window constraints still govern the layout.
    }
  }

  void _setToolbarSide(Object? side) {
    final position = switch (side) {
      'left' => 'left',
      'right' => 'right',
      _ => null,
    };
    if (mounted && _toolbarSide != position) {
      setState(() => _toolbarSide = position);
    }
  }

  Future<void> _restore() async {
    try {
      final snapshot = await readPetSnapshot();
      _game = snapshot == null
          ? PetGame(DateTime.now())
          : PetGame.decode(snapshot);
    } catch (_) {
      _game = PetGame(DateTime.now());
      _storageError = '저장 기록을 읽을 수 없어요.';
    }
    _game.advance(_game.now());
    if (!mounted) return;
    _position = _game.inPark ? _park : _home;
    setState(() {
      _ready = true;
      _voiceLoading = petNativeModelAvailable;
      if (_game.healthy &&
          _game.greetingDay == petDay(_game.at) &&
          _game.greeting.isNotEmpty) {
        _bubble = _game.greeting;
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _refresh();
    if (_voiceLoading) unawaited(_loadVoice());
  }

  Future<void> _loadVoice() async {
    try {
      final voice = await openPetVoice();
      if (!mounted) {
        await voice?.dispose();
        return;
      }
      setState(() => _voice = voice);
    } catch (_) {
      // The room remains playable while the local model is unavailable.
    } finally {
      if (mounted) {
        setState(() => _voiceLoading = false);
        _refresh();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_usesIosLayout) _layoutChannel.setMethodCallHandler(null);
    _idle.dispose();
    _message.dispose();
    _messageFocus.dispose();
    final voice = _voice;
    voice?.cancel();
    if (voice != null) unawaited(voice.dispose());
    super.dispose();
  }

  void _save() {
    final snapshot = _game.encode();
    _writes = _writes.then((_) => savePetSnapshot(snapshot)).catchError((
      Object error,
    ) {
      if (mounted && _storageError.isEmpty) {
        setState(() => _storageError = '이 기기에 저장하지 못했어요.');
      }
    });
  }

  void _refresh({bool greet = true}) {
    if (!mounted || !_ready) return;
    final wasAlive = _game.alive;
    final oldWaste = _game.waste;
    final oldLevel = _game.level;
    final oldFullness = _game.fullness;
    _game.advance(_game.now());
    if (!_game.alive) {
      if (wasAlive) _save();
      _cancelChatReply();
      setState(() => _bubble = '${_game.death}으로 동글귀를 떠나보냈어요.');
      return;
    }
    if (!_game.healthy) {
      final key =
          '${_game.hungerDeadline}:${_game.waste >= 3 ? _game.hygieneDeadline : null}';
      if (_game.lastWarning != key) {
        _cancelChatReply();
        _game.lastWarning = key;
        _bubble = _game.hungerDeadline != null && _game.waste >= 3
            ? '배고프고 바닥도 더러워. 돌봐줄래?'
            : _game.hungerDeadline != null
            ? '배가 꼬르륵해. 먹이 하나 줄래?'
            : '바닥을 조금 치워줄래?';
        _save();
      }
    } else {
      _game.lastWarning = '';
    }
    if (oldWaste != _game.waste ||
        oldLevel != _game.level ||
        oldFullness != _game.fullness) {
      _save();
    }
    setState(() {});
    if (greet && _game.healthy && !_busy && !_voiceLoading) unawaited(_greet());
  }

  Future<void> _greet() async {
    if (_greeting || _sending || _busy || !_game.healthy) return;
    final game = _game;
    final day = petDay(game.at);
    if (game.greetingDay == day) return;
    final memory = game.nextMemory;
    if (memory == null) return;
    _greeting = true;
    final distance = petDayDifference(game.at, memory.at);
    final time = distance == 1 ? '어제' : '$distance일 전에';
    final ending = game.disc ? '오늘도 원반으로 놀까?' : '오늘은 뭐 하고 놀까?';
    final reply = await _reply(
      '추억: ${memory.title}. 저장 시점: $time.',
      '이 추억을 먼저 꺼내고 하고 싶은 놀이를 한마디로 이야기해.',
      48,
    );
    _greeting = false;
    if (!mounted ||
        _sending ||
        game != _game ||
        !game.healthy ||
        petDay(game.at) != day) {
      return;
    }
    // Keep the actual title in the greeting even if a small model omits it.
    final line =
        reply != null &&
            reply.text.contains(memory.title) &&
            reply.text.contains(time)
        ? reply.text
        : '$time 남긴 ‘${memory.title}’ 기억나? $ending';
    game.greetingDay = day;
    game.greeting = line;
    game.lastMemory = memory.at.toIso8601String();
    setState(() => _bubble = line);
    _save();
  }

  Future<({String text, int tokens})?> _reply(
    String note,
    String question,
    int limit,
  ) async {
    final voice = _voice;
    if (voice == null || limit < 12) return null;
    final state = jsonEncode({
      '건강': _game.healthLabel,
      '기분': _game.moodLabel,
      '포만감': '${_game.fullness}/${_game.maxFullness}',
      '장소': _game.inPark ? '공원' : '집',
      '원반을 가지고 있음': _game.disc,
      '참고': note,
    });
    try {
      final reply = await voice
          .reply(state, question, limit)
          .timeout(const Duration(seconds: 7));
      return reply != null && reply.text.isNotEmpty && reply.tokens <= limit
          ? reply
          : null;
    } catch (_) {
      voice.cancel();
      return null;
    }
  }

  Future<void> _animateTo(Offset next, [int milliseconds = 230]) async {
    if (!mounted) return;
    setState(() {
      if ((next.dx - _position.dx).abs() > .02) {
        _facingLeft = next.dx < _position.dx;
      }
      _moveDuration = Duration(milliseconds: milliseconds);
      _position = next;
    });
    await Future<void>.delayed(_moveDuration);
  }

  Future<void> _feed(bool apple) async {
    _refresh();
    if (_busy || !_game.feed(apple: apple)) {
      _notice(
        _game.fullness >= _game.maxFullness ? '지금은 배가 불러요.' : '지금은 먹일 수 없어요.',
      );
      return;
    }
    setState(() {
      _cancelChatReply();
      _busy = true;
      _bubble = apple ? '아삭! 사과 맛있어.' : '냠냠. 이제 좀 든든해!';
    });
    _save();
    await _animateTo(const Offset(.31, .80), 450);
    await _animateTo(const Offset(.31, .77), 220);
    await _animateTo(const Offset(.31, .80), 250);
    if (!mounted) return;
    setState(() => _busy = false);
    _refresh();
  }

  void _clean() {
    _refresh();
    if (_busy || !_game.clean()) return;
    setState(() {
      _cancelChatReply();
      _bubble = '이제 발 디딜 곳이 생겼다!';
    });
    _save();
    _refresh();
  }

  Future<void> _throw({bool left = false}) async {
    _refresh();
    if (_busy || !_game.healthy || !_game.disc) {
      _notice(!_game.disc ? '가방에 원반이 필요해요.' : '먼저 동글귀를 돌봐주세요.');
      return;
    }
    setState(() {
      _cancelChatReply();
      _busy = true;
      _canReplay = false;
      _bubble = '내가 받아올게!';
    });
    final anchor = _game.inPark ? _park : _home;
    final landing = _game.inPark
        ? const Offset(.81, .64)
        : left
        ? const Offset(.40, .61)
        : const Offset(.79, .63);
    await _animateTo(anchor);
    if (!mounted) return;
    setState(() => _discPosition = landing);
    final outward = _game.inPark
        ? [const Offset(.64, .69), landing]
        : left
        ? [const Offset(.43, .76), landing]
        : [const Offset(.72, .81), landing];
    for (final point in outward) {
      await _animateTo(point, 280);
      if (!mounted || !_game.healthy) break;
    }
    if (!mounted) return;
    if (_game.healthy) {
      await _animateTo(Offset(landing.dx, landing.dy - .055), 180);
      if (!mounted) return;
      setState(() => _discPosition = null);
      await _animateTo(landing, 170);
      if (!_game.inPark && !left) await _animateTo(const Offset(.60, .63), 330);
      await _animateTo(anchor, 440);
    }
    if (!mounted) return;
    _game.advance(_game.now());
    _game.play();
    setState(() {
      _discPosition = null;
      _busy = false;
      _canReplay = _game.healthy;
      if (_canReplay) _bubble = '잡았다! 한 번 더 던져볼까?';
    });
    _save();
    _refresh();
  }

  Future<void> _chooseThrow() async {
    if (_game.level < 4 || _game.inPark || !_game.healthy) return _throw();
    final left = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('어디에 던질까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('왼쪽'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('오른쪽'),
          ),
        ],
      ),
    );
    if (left != null && mounted) await _throw(left: left);
  }

  void _tapPet() {
    if (!_game.alive || _busy) return;
    _game.mark(PetActivity.bond);
    setState(() => _facingLeft = !_facingLeft);
    _save();
  }

  Future<void> _changeLocation() async {
    if (_busy || !_game.alive) return;
    final toPark = !_game.inPark;
    if (toPark && !_game.healthy) {
      _notice('산책 전에 동글귀를 돌봐주세요.');
      return;
    }
    setState(() {
      _cancelChatReply();
      _game.inPark = toPark;
      _canReplay = false;
      _position = toPark ? const Offset(.23, .72) : _home;
      _bubble = toPark ? '오늘은 벤치까지 걸어가 볼까?' : '우리 집에 돌아왔어.';
      _busy = toPark;
    });
    if (toPark) {
      await _animateTo(const Offset(.39, .65), 370);
      await _animateTo(_park, 440);
      if (!mounted) return;
      _game.walk();
      setState(() => _busy = false);
    }
    _save();
    _refresh();
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<T?> _sheet<T>(String title, List<Widget> children) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: paper,
        builder: (context) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      );

  Widget _actionRow(
    IconData icon,
    String title,
    String subtitle,
    String button,
    VoidCallback? onPressed,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: mint,
      foregroundColor: forest,
      child: Icon(icon),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    trailing: FilledButton.tonal(onPressed: onPressed, child: Text(button)),
  );

  Future<void> _bag({bool fresh = false}) async {
    if (!_game.alive) return;
    final action = await _sheet<String>('가방', [
      if (fresh && _game.memories.isNotEmpty)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.auto_awesome, color: forest),
          title: Text(_game.memories.last.title),
          subtitle: const Text('새 추억을 저장했어요.'),
        ),
      _actionRow(
        Icons.apple,
        '사과 ×${_game.apples}',
        '사진에서 얻은 먹거리',
        '먹이기',
        _game.apples > 0 && !_game.inPark
            ? () => Navigator.pop(context, 'apple')
            : null,
      ),
      _actionRow(
        Icons.rice_bowl,
        '기본 먹이 ×${_game.pantry}',
        '매일 보충되는 먹이',
        '먹이기',
        !_game.inPark &&
                (_game.pantry > 0 || (_game.apples == 0 && _game.fullness == 0))
            ? () => Navigator.pop(context, 'feed')
            : null,
      ),
      _actionRow(
        Icons.trip_origin,
        '원반',
        _game.disc ? '여러 번 놀 수 있어요.' : '사진에서 찾아보세요.',
        '던지기',
        _game.disc ? () => Navigator.pop(context, 'throw') : null,
      ),
      const Divider(),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, 'import'),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('아이템 얻기'),
      ),
    ]);
    if (!mounted) return;
    switch (action) {
      case 'apple':
        await _feed(true);
      case 'feed':
        await _feed(false);
      case 'throw':
        await _chooseThrow();
      case 'import':
        await _import();
    }
  }

  Future<void> _care() async {
    if (_game.inPark) {
      _notice('먹이기와 청소는 집에서 할 수 있어요.');
      return;
    }
    if (!_game.alive) return;
    final action = await _sheet<String>('돌보기', [
      Text('포만감 ${_game.fullness}/${_game.maxFullness} · 배변 ${_game.waste}/3'),
      const SizedBox(height: 10),
      _actionRow(
        Icons.apple,
        '사과 ×${_game.apples}',
        '포만감 +1칸',
        '먹이기',
        _game.apples > 0 ? () => Navigator.pop(context, 'apple') : null,
      ),
      _actionRow(
        Icons.rice_bowl,
        '기본 먹이 ×${_game.pantry}',
        '포만감 +1칸',
        '먹이기',
        _game.pantry > 0 || (_game.apples == 0 && _game.fullness == 0)
            ? () => Navigator.pop(context, 'feed')
            : null,
      ),
      _actionRow(
        Icons.cleaning_services_outlined,
        '청소하기',
        '배변 ${_game.waste}개',
        '치우기',
        _game.waste > 0 ? () => Navigator.pop(context, 'clean') : null,
      ),
    ]);
    if (!mounted) return;
    if (action == 'apple' || action == 'feed') {
      await _feed(action == 'apple');
    } else if (action == 'clean') {
      _clean();
    }
  }

  Future<void> _import() async {
    final source = await _sheet<String>('아이템 얻기', [
      FilledButton.tonalIcon(
        onPressed: () => Navigator.pop(context, 'photo'),
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('사진 선택'),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, 'sample'),
        icon: const Icon(Icons.park_outlined),
        label: const Text('시연용 소풍 장면'),
      ),
    ]);
    if (!mounted || source == null) return;
    Uint8List? bytes;
    List<String> labels = [];
    final sample = source == 'sample';
    if (!sample) {
      try {
        if (petNativeModelAvailable) {
          final findings = await PhotoAnalysis().pickAndAnalyze();
          bytes = findings?.imageBytes;
          labels = findings?.labels ?? [];
        } else {
          final picked = await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1400,
          );
          bytes = await picked?.readAsBytes();
        }
      } catch (_) {
        if (mounted) _notice('사진을 열 수 없어요. 시연 장면으로 진행할 수 있어요.');
      }
      if (!mounted || bytes == null) return;
    }
    final picked = bytes;
    final memory = TextEditingController(text: sample ? '공원 소풍' : '');
    bool apple =
        sample || labels.any((label) => label.toLowerCase().contains('apple'));
    bool disc =
        sample ||
        labels.any((label) => label.toLowerCase().contains('frisbee'));
    bool confirmed = false;
    await showModalBottomSheet<void>(
      isScrollControlled: true,
      showDragHandle: true,
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              22,
              0,
              22,
              22 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '아이템 확인',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: sample
                      ? SizedBox(
                          height: 120,
                          child: Stack(
                            fit: StackFit.expand,
                            alignment: Alignment.center,
                            children: [
                              Image.asset(
                                'assets/pet/park.png',
                                fit: BoxFit.cover,
                              ),
                              const Center(
                                child: Text(
                                  '🍎  🟠',
                                  style: TextStyle(fontSize: 40),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Image.memory(
                          picked!,
                          height: 130,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Text('미리보기를 표시할 수 없어요.'),
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  sample
                      ? '시연용 장면에서 사과와 원반을 담을 수 있어요.'
                      : '사진에 있는 물건을 직접 확인해 골라주세요.',
                ),
                TextField(
                  controller: memory,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: '추억 제목'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('사과'),
                  value: apple,
                  onChanged: (v) => setModalState(() => apple = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('원반'),
                  value: disc,
                  onChanged: (v) => setModalState(() => disc = v ?? false),
                ),
                FilledButton(
                  onPressed: () {
                    confirmed = true;
                    Navigator.pop(context);
                  },
                  child: const Text('가방에 담기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final title = memory.text.trim();
    memory.dispose();
    if (!mounted || !confirmed) return;
    if (!apple && !disc && title.isEmpty) {
      _notice('담을 아이템이나 추억을 선택해주세요.');
      return;
    }
    _game.addFinds(title, apple: apple, frisbee: disc);
    setState(() => _bubble = '가방에 담았어. 같이 써보자!');
    _save();
    await _bag(fresh: title.isNotEmpty);
  }

  void _openChat() {
    setState(() => _chatOpen = true);
    _messageFocus.requestFocus();
  }

  void _cancelChatReply() {
    if (!_sending) return;
    _chatRequest++;
    _sending = false;
    _voice?.cancel();
  }

  void _closeChat() {
    _messageFocus.unfocus();
    setState(() {
      _cancelChatReply();
      _chatOpen = false;
    });
  }

  Future<void> _sendMessage() async {
    final question = _message.text.trim();
    if (question.isEmpty || _sending || _busy || !_game.alive) return;
    _refresh(greet: false);
    final game = _game;
    if (!game.alive) return;
    if (game.energy < 12) {
      setState(() => _bubble = '잠깐 쉬었다가 또 이야기하자.');
      return;
    }
    final memory = game.memories.isEmpty ? '' : game.memories.last.title;
    final heading = game.healthLabel;
    final request = ++_chatRequest;
    final usingModel = _voice != null;
    setState(() {
      _sending = true;
      _facingLeft = false;
    });
    final reply = await _reply(
      '최근 추억: $memory',
      question,
      math.min(_longReply ? 64 : 32, game.energy),
    );
    if (!mounted || request != _chatRequest || game != _game) return;
    _refresh(greet: false);
    if (request != _chatRequest || !game.alive) return;
    if (game.healthLabel != heading) {
      setState(() => _sending = false);
      return;
    }
    if (reply != null) {
      game.spend(reply.tokens);
      if (question.contains('잘했') || question.contains('고마워')) {
        game.moodChange(1);
      }
    } else if (!usingModel) {
      game.mark(PetActivity.bond);
    }
    if (reply != null || !usingModel) _message.clear();
    setState(() {
      _sending = false;
      _bubble = reply?.text ?? _fallbackReply(question, memory);
    });
    _save();
  }

  Widget _composer() => Material(
    key: _composerKey,
    color: paper,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('대화 체력 $_energyLabel')),
              if (_voice != null)
                Semantics(
                  toggled: _longReply,
                  child: TextButton(
                    onPressed: _sending
                        ? null
                        : () => setState(() => _longReply = !_longReply),
                    child: Text(_longReply ? '긴 답장 켜짐' : '긴 답장'),
                  ),
                ),
              IconButton(
                tooltip: '대화 닫기',
                onPressed: _closeChat,
                icon: const Text('×', style: TextStyle(fontSize: 24)),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _message,
                  focusNode: _messageFocus,
                  readOnly: _sending,
                  maxLength: 160,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => unawaited(_sendMessage()),
                  decoration: const InputDecoration(
                    hintText: '무슨 말을 걸까요?',
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sending || _busy || !_game.alive
                    ? null
                    : _sendMessage,
                child: const Text('보내기'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _fallbackReply(String question, String memory) {
    if (_game.fullness == 0) return '배가 꼬르륵해. 먼저 먹이 하나 줄래?';
    if (_game.waste >= 3) return '바닥을 치워주면 같이 놀 수 있어!';
    if (question.contains('원반') || question.contains('놀')) {
      return _game.disc ? '좋아! 가방에서 원반을 던져줘.' : '원반이 생기면 같이 놀자.';
    }
    if (memory.isNotEmpty &&
        (question.contains('기억') || question.contains('어제'))) {
      return '‘$memory’ 기억나. 같이한 일이 좋았어!';
    }
    return '응, 나 여기 있어. 네가 오니까 좋아.';
  }

  Future<void> _album() => _sheet<void>('앨범·도감', [
    if (_game.memories.isEmpty) const Text('사진이나 산책으로 첫 추억을 만들어보세요.'),
    for (final memory in _game.memories.reversed)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.photo_album_outlined),
        title: Text(memory.title),
        subtitle: Text('${memory.at.month}월 ${memory.at.day}일'),
      ),
    const Divider(),
    const ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.pets),
      title: Text('동글귀'),
      subtitle: Text('기본 캐릭터'),
    ),
  ]);

  Future<void> _settings() async {
    final choice = await _sheet<String>('설정', [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.memory),
        title: Text(_voice == null ? '기본 대사 모드' : 'Kanana 연결됨'),
        subtitle: Text(
          petNativeModelAvailable
              ? '기기에 내려받은 모델을 사용합니다.'
              : 'Chrome 시연에서는 내장된 기본 대사를 사용해요.',
        ),
      ),
      if (petNativeModelAvailable && _voice == null && _download == null)
        OutlinedButton(
          onPressed: () => Navigator.pop(context, 'download'),
          child: const Text('Kanana 모델 받기 · 약 1.52 GB'),
        ),
      const Divider(),
      const Text('시연 시계', style: TextStyle(fontWeight: FontWeight.bold)),
      const Text(
        '시연을 열어 첫날을 18시로 맞춘 뒤, 사과를 먹이고 원반으로 놀아주세요. 15시간과 24시간 시연은 각각 새로 시작하는 편이 정확해요.',
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => Navigator.pop(context, 'reset'),
        child: const Text('시연 새로 시작 · 첫날 18시'),
      ),
      if (_game.demoClock) ...[
        OutlinedButton(
          onPressed: () => Navigator.pop(context, '15'),
          child: const Text('15시간 뒤 재방문'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, '24'),
          child: const Text('24시간 뒤 재방문'),
        ),
      ],
    ]);
    if (!mounted || choice == null) return;
    if (choice == 'download') {
      unawaited(_downloadModel());
      return;
    }
    if (choice == 'reset') {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('새 시연을 시작할까요?'),
          content: const Text('이 프로토타입에서 만든 현재 펫 기록이 새로 시작됩니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('새로 시작'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final now = DateTime.now();
      final demo = DateTime(now.year, now.month, now.day, 18);
      setState(() {
        _cancelChatReply();
        _message.clear();
        _messageFocus.unfocus();
        _chatOpen = false;
        _game = PetGame(demo)
          ..timeOffsetMs = demo.difference(now).inMilliseconds
          ..demoClock = true;
        _position = _home;
        _discPosition = null;
        _canReplay = false;
        _bubble = '안녕! 가방에서 소풍 장면을 골라보자.';
      });
    } else {
      final target = _game.born.add(hour * int.parse(choice));
      if (!target.isAfter(_game.at)) {
        _notice('이미 이 시각을 지났어요. 시연을 새로 시작해주세요.');
        return;
      }
      _game.timeOffsetMs = target.difference(DateTime.now()).inMilliseconds;
      _canReplay = false;
      _refresh();
    }
    _save();
  }

  Future<void> _downloadModel() async {
    setState(() => _download = 0);
    try {
      await installPetModel((progress) {
        if (mounted) setState(() => _download = progress);
      });
      if (!mounted) return;
      await _loadVoice();
      if (mounted && _voice != null) _notice('로컬 모델을 연결했어요.');
    } catch (_) {
      if (mounted) _notice('모델을 받지 못했어요. 설정에서 이어받을 수 있어요.');
    } finally {
      if (mounted) setState(() => _download = null);
    }
  }

  String get _energyLabel =>
      '${(_game.energy * 100 / _game.maxEnergy).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final keyboardOpen =
        _chatOpen && MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, space) =>
              space.maxWidth >= 620 && space.maxHeight >= 340
              ? _wideRoom(space)
              : _compactRoom(keyboardOpen),
        ),
      ),
    );
  }

  Widget _compactRoom(bool keyboardOpen) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 610),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, space) {
                final roomy =
                    !keyboardOpen &&
                    space.maxHeight >= 560 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 18 &&
                    _storageError.isEmpty &&
                    _download == null;
                if (roomy) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _identity(),
                        const SizedBox(height: 12),
                        Expanded(child: _scene(immersive: true)),
                        if (!_game.alive) Text(_bubble),
                        const SizedBox(height: 12),
                        _status(),
                        const SizedBox(height: 12),
                        _actions(context),
                        ..._messages(),
                      ],
                    ),
                  );
                }
                return ListView(
                  key: ValueKey(keyboardOpen),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    keyboardOpen ? 4 : 16,
                    16,
                    14,
                  ),
                  children: [
                    if (!keyboardOpen) ...[
                      _identity(),
                      const SizedBox(height: 12),
                    ],
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: keyboardOpen
                              ? math.max(120, (space.maxHeight - 12) * 1.5)
                              : 610,
                        ),
                        child: _scene(),
                      ),
                    ),
                    if (!_game.alive)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_bubble),
                      ),
                    if (!keyboardOpen) ...[
                      const SizedBox(height: 12),
                      _status(),
                      const SizedBox(height: 12),
                      _actions(context),
                      ..._messages(),
                    ],
                  ],
                );
              },
            ),
          ),
          if (_chatOpen && _game.alive) _composer(),
        ],
      ),
    ),
  );

  Widget _wideRoom(BoxConstraints space) {
    final controlWidth = (space.maxWidth * .34).clamp(232.0, 320.0);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        key: const ValueKey('wide-room'),
        textDirection: _toolbarSide == 'left'
            ? TextDirection.rtl
            : TextDirection.ltr,
        children: [
          Expanded(child: _scene(immersive: true)),
          const SizedBox(width: 16),
          SizedBox(
            key: const ValueKey('room-controls'),
            width: controlWidth,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xfff3ede2),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(14),
                  children: [
                    _identity(),
                    const SizedBox(height: 12),
                    _status(),
                    const SizedBox(height: 12),
                    if (!_game.alive) Text(_bubble),
                    if (_chatOpen && _game.alive) _composer(),
                    _actions(context, stacked: true),
                    ..._messages(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identity() => LayoutBuilder(
    builder: (context, space) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '동글귀',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -.9,
            ),
          ),
          Text(
            '${_game.stage} · Lv. ${_game.level} · 기분 ${_game.moodLabel}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
      final health = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _game.healthy ? mint : const Color(0xffffdfcb),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          _game.healthLabel,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
      if (space.maxWidth < 270 ||
          MediaQuery.textScalerOf(context).scale(14) > 19) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 6), health],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: 8),
          Flexible(child: health),
        ],
      );
    },
  );

  Widget _status() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xffeee9df),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Wrap(
      spacing: 17,
      runSpacing: 4,
      children: [
        _stat('포만감', '${_game.fullness}/${_game.maxFullness}'),
        _stat('애정도', '${_game.affection}/${_game.nextAffection}'),
        _stat('배변', '${_game.waste}/3'),
      ],
    ),
  );

  Widget _stat(String label, String value) => Text.rich(
    TextSpan(
      text: '$label ',
      style: const TextStyle(fontSize: 13),
      children: [
        TextSpan(
          text: value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context, {bool stacked = false}) {
    final care = FilledButton.icon(
      onPressed: _busy || !_game.alive ? null : _care,
      icon: const Icon(Icons.favorite_border, size: 19),
      label: const Text('돌보기'),
    );
    final talk = FilledButton.tonalIcon(
      onPressed: _busy || !_game.alive || _chatOpen ? null : _openChat,
      icon: const Icon(Icons.chat_bubble_outline, size: 18),
      label: const Text('말 걸기'),
    );
    final vertical = stacked || MediaQuery.textScalerOf(context).scale(14) > 20;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_chatOpen) ...[
          Semantics(
            label: '대화 체력 $_energyLabel',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '대화 체력',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Text(
                    _energyLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: _game.energy / _game.maxEnergy,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (vertical) ...[
          care,
          const SizedBox(height: 6),
          talk,
        ] else
          Row(
            children: [
              Expanded(child: care),
              const SizedBox(width: 8),
              Expanded(child: talk),
            ],
          ),
        if (_canReplay && !_busy)
          OutlinedButton.icon(
            onPressed: _chooseThrow,
            icon: const Icon(Icons.replay),
            label: const Text('한 번 더 던지기'),
          ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.spaceBetween,
          children: [
            _shortcut(Icons.inventory_2_outlined, '가방', () => _bag()),
            _shortcut(Icons.collections_outlined, '앨범·도감', _album),
            _shortcut(Icons.settings_outlined, '설정', _settings),
          ],
        ),
      ],
    );
  }

  List<Widget> _messages() => [
    if (_storageError.isNotEmpty) Text(_storageError),
    if (_download case final double progress) ...[
      const SizedBox(height: 8),
      LinearProgressIndicator(value: progress),
      Text('모델 받는 중 ${(progress * 100).round()}%'),
    ],
    if (_game.demoClock) const Text('시연 시계 사용 중', textAlign: TextAlign.center),
  ];

  Widget _shortcut(IconData icon, String label, VoidCallback press) =>
      TextButton.icon(
        onPressed: _busy ? null : press,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      );

  Widget _scene({bool immersive = false}) {
    final surface = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final worldWidth = immersive
            ? math.min(width * 1.20, height * 1.5)
            : width;
        final worldHeight = immersive ? worldWidth / 1.5 : height;
        final worldX = (width - worldWidth) / 2;
        final worldY = (height - worldHeight) / 2;
        final size =
            worldWidth *
            (.20 +
                (_game.level >= 5
                    ? .04
                    : _game.level >= 3
                    ? .02
                    : 0));
        final disc = _discPosition;
        return TweenAnimationBuilder<Offset>(
          tween: Tween(end: _position),
          duration: _moveDuration,
          curve: Curves.easeInOut,
          builder: (context, position, _) {
            final petX = worldX + worldWidth * position.dx;
            final petTop = worldY + worldHeight * position.dy - size * .65;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (immersive)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xfff6ebdd),
                          const Color(0xfffcf1e6),
                          _game.inPark
                              ? const Color(0xffeaf0df)
                              : const Color(0xfff0e1cf),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: worldX,
                  top: worldY,
                  width: worldWidth,
                  height: worldHeight,
                  child: _scenery(immersive),
                ),
                for (
                  var index = 0;
                  index < _game.waste && !_game.inPark;
                  index++
                )
                  Positioned(
                    left: worldX + worldWidth * (.64 + .065 * index),
                    top: worldY + worldHeight * (.84 - .04 * index),
                    child: const Text('💩', style: TextStyle(fontSize: 17)),
                  ),
                if (disc != null)
                  Positioned(
                    left: worldX + worldWidth * (disc.dx - .026),
                    top: worldY + worldHeight * disc.dy - 10,
                    child: Transform.rotate(
                      angle: -.25,
                      child: Container(
                        width: worldWidth * .065,
                        height: worldWidth * .028,
                        decoration: BoxDecoration(
                          color: const Color(0xffffa12c),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xff994624),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_game.alive)
                  Positioned(
                    left: petX - size / 2,
                    top: petTop,
                    width: size,
                    height: size * .7,
                    child: Semantics(
                      button: true,
                      label: '동글귀 톡 누르기',
                      child: GestureDetector(
                        onTap: _tapPet,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              width: size * .62,
                              height: size * .13,
                              decoration: BoxDecoration(
                                color: const Color(0x443d2514),
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _idle,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(
                                  0,
                                  _busy ? 0 : -2.5 * _idle.value,
                                ),
                                child: Transform.flip(
                                  flipX: _facingLeft,
                                  child: child,
                                ),
                              ),
                              child: Image.asset(
                                'assets/pet/dongle.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.low,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_game.alive && (_sending || _bubble.isNotEmpty))
                  _speechBubble(width, height, petX, petTop, size),
                if (immersive)
                  Positioned(
                    top: 15,
                    left: 15,
                    child: Text(
                      _game.inPark ? '공원' : '우리 방',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Positioned(
                  right: 9,
                  top: 9,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy || !_game.alive ? null : _changeLocation,
                    icon: Icon(
                      _game.inPark ? Icons.home_outlined : Icons.park_outlined,
                      size: 17,
                    ),
                    label: Text(_game.inPark ? '집으로' : '공원 산책'),
                    style: FilledButton.styleFrom(
                      backgroundColor: paper.withValues(alpha: .94),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    return ClipRRect(
      key: const ValueKey('pet-stage'),
      borderRadius: BorderRadius.circular(20),
      child: immersive
          ? surface
          : AspectRatio(aspectRatio: 1.5, child: surface),
    );
  }

  Widget _scenery(bool immersive) {
    final picture = Image.asset(
      'assets/pet/${_game.inPark ? 'park' : 'room'}.png',
      fit: BoxFit.fill,
    );
    if (!immersive) return picture;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0, .07, .93, 1],
      ).createShader(bounds),
      child: picture,
    );
  }

  Widget _speechBubble(
    double width,
    double height,
    double petX,
    double petTop,
    double petSize,
  ) {
    const padding = 7.0;
    final beside = petTop < math.min(84, height * .48);
    final toLeft = beside && petX > width / 2;
    final side = petX + (toLeft ? -1 : 1) * (petSize / 2 - 4);
    final room = beside
        ? (toLeft ? side : width - side) - padding
        : width - 2 * padding;
    final bubbleWidth = math.min(_sending ? 56.0 : 228.0, math.max(48.0, room));
    final left =
        (beside ? side - (toLeft ? bubbleWidth : 0) : petX - bubbleWidth / 2)
            .clamp(padding, width - bubbleWidth - padding);
    final bubbleHeight = math.max(
      27.0,
      math.min(96.0, beside ? height * .48 : petTop - 12),
    );
    final tailX = ((petX - left) / bubbleWidth * 2 - 1).clamp(-.83, .83);
    final box = Material(
      color: paper,
      borderRadius: BorderRadius.circular(13),
      elevation: 2,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: bubbleHeight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey(_sending ? 'thinking' : _bubble),
                padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                child: Text(
                  _sending ? '…' : _bubble,
                  style: const TextStyle(fontSize: 14, height: 1.23),
                ),
              ),
            ),
            if (!_sending)
              Semantics(
                label: '말풍선 닫기',
                button: true,
                child: InkWell(
                  onTap: () => setState(() => _bubble = ''),
                  child: const SizedBox(
                    width: 30,
                    height: 34,
                    child: Center(
                      child: Text('×', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Positioned(
      left: left,
      width: bubbleWidth,
      top: beside
          ? (petTop + 5).clamp(
              padding,
              math.max(padding, height - bubbleHeight - padding),
            )
          : null,
      bottom: beside ? null : height - petTop + 1,
      child: Semantics(
        liveRegion: true,
        child: beside
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!toLeft)
                    const CustomPaint(
                      size: Size(8, 12),
                      painter: _BubbleTail(AxisDirection.left),
                    ),
                  Expanded(child: box),
                  if (toLeft)
                    const CustomPaint(
                      size: Size(8, 12),
                      painter: _BubbleTail(AxisDirection.right),
                    ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  box,
                  Align(
                    alignment: Alignment(tailX, 0),
                    child: const CustomPaint(
                      size: Size(12, 7),
                      painter: _BubbleTail(AxisDirection.down),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  const _BubbleTail(this.direction);

  final AxisDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final points = switch (direction) {
      AxisDirection.left => [Offset(w, 0), Offset(0, h / 2), Offset(w, h)],
      AxisDirection.right => [Offset.zero, Offset(w, h / 2), Offset(0, h)],
      _ => [Offset.zero, Offset(w / 2, h), Offset(w, 0)],
    };
    canvas.drawPath(Path()..addPolygon(points, true), Paint()..color = paper);
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) =>
      direction != oldDelegate.direction;
}
