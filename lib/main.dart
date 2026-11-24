import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        LicenseEntryWithLineBreaks,
        LicenseRegistry,
        defaultTargetPlatform,
        kIsWeb,
        mapEquals;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException, rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'pet/pet_game.dart';
import 'pet/pet_platform.dart';
import 'pet/pet_sprite.dart';
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

class _PetRoomState extends State<PetRoom> with TickerProviderStateMixin {
  static const _home = Offset(.51, .82);
  static const _park = Offset(.52, .59);
  static const _parkEntrance = Offset(.23, .72);
  static const _parkBench = Offset(.57, .66);
  static const _cleanDuration = Duration(seconds: 3);
  static const _layoutChannel = MethodChannel('donglgewi/layout');
  final _picker = ImagePicker();
  final _message = TextEditingController();
  final _messageFocus = FocusNode();
  final _composerKey = GlobalKey();
  final _blink = ValueNotifier(false);
  late final AnimationController _idle;
  late final AnimationController _sweep;
  late final AnimationController _patEffect;
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
  bool _cleaning = false;
  bool _greeting = false;
  bool _voiceLoading = false;
  bool _canReplay = false;
  bool _chatOpen = false;
  bool _sending = false;
  bool _longReply = false;
  int _chatRequest = 0;
  DateTime? _firstPat;
  int _patCount = 0;
  double? _download;
  String _bubble = '안녕! 우리 방에 온 걸 환영해.';
  String _playReward = '';
  String _storageError = '';
  bool _systemToolbar = false;
  Map<String, bool>? _sentToolbarActions;

  bool get _usesIosLayout =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _idle
      ..addListener(() => _blink.value = _idle.value > .975)
      ..repeat(reverse: true);
    _sweep = AnimationController(vsync: this, duration: _cleanDuration);
    _patEffect = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
      value: 1,
    );
    if (_usesIosLayout) {
      _layoutChannel.setMethodCallHandler((call) async {
        if (call.method == 'roomToolbarVisibleChanged') {
          _setSystemToolbar(call.arguments);
        } else if (call.method == 'roomToolbarAction') {
          _handleToolbarAction(call.arguments);
        }
      });
      unawaited(_readSystemToolbar());
    }
    unawaited(_restore());
  }

  Future<void> _readSystemToolbar() async {
    try {
      _setSystemToolbar(
        await _layoutChannel.invokeMethod<bool>('roomToolbarVisible'),
      );
    } on MissingPluginException {
      // Existing TestFlight builds keep the regular Flutter controls.
    } on PlatformException {
      // The regular layout is available if the platform cannot supply a bar.
    }
  }

  void _setSystemToolbar(Object? value) {
    final visible = value == true;
    if (mounted && _systemToolbar != visible) {
      setState(() => _systemToolbar = visible);
    }
  }

  Map<String, bool> _toolbarActions() {
    final available =
        (ModalRoute.isCurrentOf(context) ?? true) && !_busy && !_chatOpen;
    return {
      'talk': available && _game.alive,
      'bag': available && _game.alive,
      'album': available,
      'settings': available,
    };
  }

  void _handleToolbarAction(Object? action) {
    if (!mounted || !_ready || action is! String) return;
    if (_toolbarActions()[action] != true) return;
    final VoidCallback? run = switch (action) {
      'talk' => _openChat,
      'bag' => _bag,
      'album' => _album,
      'settings' => _settings,
      _ => null,
    };
    run?.call();
  }

  void _syncToolbarActions() {
    if (!_usesIosLayout) return;
    final actions = _toolbarActions();
    if (mapEquals(_sentToolbarActions, actions)) return;
    _sentToolbarActions = actions;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(_sentToolbarActions, actions)) return;
      try {
        await _layoutChannel.invokeMethod<void>('roomToolbarActions', actions);
      } on MissingPluginException {
        // Existing builds have no native bar to update.
      } on PlatformException {
        // Flutter controls continue to use the current game state.
      }
    });
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
      } else {
        _bubble = '안녕! ${_game.kind.label}야.';
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
    _blink.dispose();
    _sweep.dispose();
    _patEffect.dispose();
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
    final oldEnergy = _game.energy;
    _game.advance(_game.now());
    if (!_game.alive) {
      if (wasAlive) _save();
      _cancelChatReply();
      setState(() => _bubble = '${_game.death}으로 ${_game.kind.label}와 헤어졌어요.');
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
        oldFullness != _game.fullness ||
        oldEnergy != _game.energy) {
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
      '캐릭터': _game.kind.label,
      '성향': _game.personality.traits,
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

  Future<void> _clean() async {
    if (_busy || _game.inPark) return;
    _refresh(greet: false);
    if (!_game.alive || _game.waste == 0) return;
    final game = _game;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _cleaning = true;
    });
    _sweep.forward(from: 0);
    await Future<void>.delayed(_cleanDuration);
    if (!mounted) return;
    _refresh(greet: false);
    final cleaned = game == _game && game.clean();
    setState(() {
      _busy = false;
      _cleaning = false;
      if (cleaned) _bubble = '이제 발 디딜 곳이 생겼다!';
    });
    if (cleaned) _save();
    _refresh();
  }

  Future<void> _throw({bool left = false}) async {
    _refresh(greet: false);
    if (_busy || !_game.canPlay(PetPlay.disc)) return;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _canReplay = false;
      _playReward = '';
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
    final reward = _game.play();
    setState(() {
      _discPosition = null;
      _busy = false;
      _canReplay = reward != null && _game.disc;
      if (reward != null) {
        _bubble = reward.discBroke ? '잡았다! 이 원반은 이제 다 썼어.' : '잡았다! 한 번 더 던져볼까?';
        _playReward =
            '${_rewardLabel(reward)} · ${reward.discBroke ? '원반 소진' : '내구도 −1'}';
      }
    });
    _save();
    _refresh();
  }

  Future<void> _chooseThrow() async {
    _refresh(greet: false);
    if (_busy || !_game.canPlay(PetPlay.disc)) return;
    if (_game.level < 4 || _game.inPark) return _throw();
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
    _refresh(greet: false);
    if (!_game.alive) return;
    final now = DateTime.now();
    if (_firstPat == null ||
        now.difference(_firstPat!) >= const Duration(seconds: 8)) {
      _firstPat = now;
      _patCount = 0;
    }
    _patCount++;
    final response = !_game.healthy
        ? '지금은 불편해. 먼저 돌봐줘.'
        : _game.mood < 4
        ? '지금은 기분이 안 좋아. 조금만 쉬고 싶어.'
        : _patCount >= 4
        ? '너무 많이 만지면 싫어. 잠깐 쉬게 해줘.'
        : null;
    if (response != null) {
      _patEffect.value = 1;
      final annoyed = _patCount == 4 && _game.healthy && _game.mood >= 4;
      setState(() {
        _cancelChatReply();
        if (annoyed) _game.moodChange(-1);
        _bubble = response;
      });
      if (annoyed) _save();
      return;
    }
    _game.mark(PetActivity.bond);
    setState(() {
      _cancelChatReply();
      _facingLeft = !_facingLeft;
      _bubble = '헤헤, 좋아!';
    });
    _patEffect.forward(from: 0);
    _save();
  }

  Future<void> _changeLocation() async {
    if (_busy || !_game.alive) return;
    final toPark = !_game.inPark;
    if (toPark && !_game.healthy) {
      _notice('산책 전에 펫을 돌봐주세요.');
      return;
    }
    setState(() {
      _cancelChatReply();
      _game.inPark = toPark;
      _canReplay = false;
      _position = toPark ? _parkEntrance : _home;
      _bubble = toPark ? '오늘은 벤치까지 걸어가 볼까?' : '우리 집에 돌아왔어.';
      _busy = toPark;
    });
    if (toPark) {
      await _walkParkPath();
      return;
    }
    _save();
    _refresh();
  }

  Future<void> _walkParkPath({bool training = false}) async {
    await _animateTo(const Offset(.39, .65), 370);
    await _animateTo(_park, 440);
    if (!mounted) return;
    _game.advance(_game.now());
    final reward = training ? _game.play(PetPlay.walk) : null;
    if (!training) _game.walk();
    setState(() {
      _busy = false;
      if (reward != null) _playReward = _rewardLabel(reward);
    });
    _save();
    _refresh();
  }

  Future<void> _walkInPark() async {
    if (_busy || !_game.inPark) return;
    _refresh(greet: false);
    if (!_game.canPlay(PetPlay.walk)) return;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _playReward = '';
      _bubble = '벤치까지 한 바퀴 걷자!';
    });
    await _animateTo(_parkEntrance, 420);
    if (mounted) await _walkParkPath(training: true);
  }

  Future<void> _restInPark() async {
    if (_busy || !_game.inPark || !_game.alive) return;
    _refresh(greet: false);
    if (!_game.alive) return;
    final recovering = _game.canRecoverAtBench;
    setState(() {
      _cancelChatReply();
      _busy = true;
      if (_game.healthy) _bubble = '벤치 옆에서 잠깐 쉬자.';
    });
    await _animateTo(_parkBench, 430);
    if (recovering && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 2500));
    }
    if (!mounted) return;
    _refresh(greet: false);
    final restored = _game.recoverAtBench();
    setState(() {
      _busy = false;
      if (restored > 0) {
        _playReward =
            '체력 +${_game.energyPercent(restored).toStringAsFixed(1)}%';
        if (_game.healthy) _bubble = '잠깐 쉬니까 힘이 나!';
      }
    });
    if (restored > 0) _save();
    _refresh();
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<T?> _sheet<T>(String title, List<Widget> children) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
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

  Future<void> _bag({bool fresh = false, PetDisc? foundDisc}) async {
    if (!_game.alive) return;
    final action = await _sheet<String>('가방', [
      if (fresh && _game.memories.isNotEmpty)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.auto_awesome, color: forest),
          title: Text(_game.memories.last.title),
          subtitle: const Text('새 추억을 저장했어요.'),
        ),
      if (foundDisc != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.trip_origin, color: forest),
          title: const Text('사진에서 원반을 찾았어요'),
          subtitle: Text('내구도 ${foundDisc.remaining}/${foundDisc.maximum}'),
        ),
      for (final (icon, title, detail) in [
        (Icons.apple, '사과 ×${_game.apples}', '방의 먹이기에서 줄 수 있어요.'),
        (Icons.rice_bowl, '기본 먹이 ×${_game.pantry}', '매일 보충돼요.'),
        (
          Icons.trip_origin,
          '원반 ×${_game.discs.length}',
          _game.disc
              ? '내구도 ${_game.discs.take(4).map((item) => '${item.remaining}/${item.maximum}').join(' · ')}${_game.discs.length > 4 ? ' 외 ${_game.discs.length - 4}개' : ''}'
              : '사진 속에서 찾아보세요.',
        ),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: mint,
            foregroundColor: forest,
            child: Icon(icon),
          ),
          title: Text(title),
          subtitle: Text(detail),
        ),
      const Divider(),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, 'import'),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('아이템 얻기'),
      ),
    ]);
    if (mounted && action == 'import') await _import();
  }

  Future<void> _feeding() async {
    if (_busy || !_game.alive || _game.inPark) return;
    if (_game.apples == 0) return _feed(false);
    if (_game.pantry == 0) return _feed(true);
    final action = await _sheet<String>('먹이 고르기', [
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
    ]);
    if (mounted && action != null) await _feed(action == 'apple');
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
      useSafeArea: true,
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
    final foundDisc = _game.addFinds(title, apple: apple, frisbee: disc);
    setState(() => _bubble = '가방에 담았어. 같이 써보자!');
    _save();
    await _bag(fresh: title.isNotEmpty, foundDisc: foundDisc);
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

  Widget _composer({bool inRail = false}) => Material(
    key: _composerKey,
    color: paper,
    borderRadius: inRail ? BorderRadius.circular(20) : BorderRadius.zero,
    child: TextFieldTapRegion(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, inRail ? 12 : 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text('체력 $_energyLabel')),
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
                    onTapOutside: (_) => _messageFocus.unfocus(),
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
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
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
    for (final kind in PetKind.values)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(width: 44, height: 38, child: PetSprite(kind: kind)),
        title: Text(kind.label),
        subtitle: Text(
          _game.kind == kind
              ? '지금 키우는 중'
              : _game.raisedKinds.contains(kind)
              ? '키워봤어요'
              : '새 펫으로 선택할 수 있어요',
        ),
      ),
  ]);

  String _petTime(Duration time) {
    final minutes = math.max(0, time.inMinutes);
    return [
      if (minutes >= 1440) '${minutes ~/ 1440}일',
      if (minutes >= 60) '${minutes ~/ 60 % 24}시간',
      '${minutes % 60}분',
    ].join(' ');
  }

  Future<void> _petInfo() async {
    _refresh(greet: false);
    final game = _game;
    final time = game.nextStageAt?.difference(game.at);
    final affectionNeeded = math.max(0, game.nextAffection - game.affection);
    await _sheet<void>('${game.kind.label} 펫 정보', [
      Text(
        '${game.stage} · Lv. ${game.level}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text('함께한 시간 ${_petTime(game.at.difference(game.born))}'),
      if (time != null) ...[
        const SizedBox(height: 8),
        Text('다음 성장 · ${game.level < 3 ? '꼬마' : '성체'}'),
        Text(
          affectionNeeded > 0
              ? '애정도 ${game.affection}/${game.nextAffection}'
              : '애정도 ${game.affection} · 기준 충족',
        ),
        if (affectionNeeded > 0) Text('애정도 $affectionNeeded 더 필요해요.'),
        if (time > Duration.zero)
          Text('성장까지 약 ${_petTime(time + const Duration(seconds: 59))}'),
        if (game.alive && !game.healthy) const Text('건강이 회복되면 성장할 수 있어요.'),
      ] else
        const Text('성체까지 자랐어요.'),
      const Divider(),
      Text(
        '성격 · ${game.personality.code}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final trait in game.personality.traits) Chip(label: Text(trait)),
        ],
      ),
      Text(game.personality.active ? '좋아하는 활동 · 원반 놀이' : '좋아하는 활동 · 벤치에서 쉬기'),
      const Divider(),
      Text('능력치', style: Theme.of(context).textTheme.titleMedium),
      for (final (label, value) in [
        ('기분', game.mood),
        ('자신감', game.confidence),
        ('민첩', game.agility),
        ('호기심', game.curiosity),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          trailing: Text('$value/10'),
        ),
      Text('체력 $_energyLabel'),
      if (game.nextRecovery case final recovery?)
        Text(
          '다음 자동 회복 약 ${_petTime(recovery.difference(game.at) + const Duration(seconds: 59))}',
        ),
    ]);
  }

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
      OutlinedButton(
        onPressed: () => Navigator.pop(context, 'newPet'),
        child: const Text('펫 초기화'),
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
    if (choice == 'newPet') {
      await _chooseNewPet();
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
      _replacePet(
        PetGame(demo, kind: _game.kind)
          ..timeOffsetMs = demo.difference(now).inMilliseconds
          ..demoClock = true,
        '안녕! 가방에서 소풍 장면을 골라보자.',
      );
      return;
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

  Future<void> _chooseNewPet() async {
    final kind = await _sheet<PetKind>('새 펫 고르기', [
      for (final candidate in PetKind.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(
            width: 50,
            height: 38,
            child: PetSprite(kind: candidate),
          ),
          title: Text(candidate.label),
          subtitle: Text(candidate.description),
          onTap: () => Navigator.pop(context, candidate),
        ),
    ]);
    if (!mounted || kind == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${kind.label}로 다시 시작할까요?'),
        content: const Text('현재 펫의 성장, 가방, 추억을 초기화합니다. 키워본 캐릭터는 도감에 남아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초기화하고 시작'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _replacePet(PetGame(DateTime.now(), kind: kind), '안녕! ${kind.label}야.');
  }

  void _replacePet(PetGame next, String greeting) {
    next.raisedKinds.addAll(_game.raisedKinds);
    setState(() {
      _cancelChatReply();
      _message.clear();
      _messageFocus.unfocus();
      _chatOpen = false;
      _game = next;
      _position = _home;
      _discPosition = null;
      _canReplay = false;
      _facingLeft = false;
      _playReward = '';
      _firstPat = null;
      _patCount = 0;
      _patEffect.value = 1;
      _bubble = greeting;
    });
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
      '${_game.energyPercent(_game.energy).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _syncToolbarActions();
    final keyboardOpen =
        _chatOpen && MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          key: const ValueKey('room-safe-margin'),
          padding: EdgeInsets.only(bottom: keyboardOpen ? 0 : 20),
          child: LayoutBuilder(
            builder: (context, space) {
              if (space.maxWidth >= 620) return _wideRoom(space, keyboardOpen);
              return _compactRoom(keyboardOpen);
            },
          ),
        ),
      ),
    );
  }

  Widget _compactRoom(bool keyboardOpen) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 610),
      child: Column(
        children: [
          Expanded(child: _compactScene(keyboardOpen)),
          if (_chatOpen && _game.alive) _composer(),
        ],
      ),
    ),
  );

  Widget _compactScene(bool keyboardOpen) => LayoutBuilder(
    builder: (context, space) {
      final roomy =
          !keyboardOpen &&
          space.maxHeight >= 560 &&
          MediaQuery.textScalerOf(context).scale(14) <= 18 &&
          _storageError.isEmpty &&
          _download == null;
      final padding = EdgeInsets.fromLTRB(16, keyboardOpen ? 4 : 16, 16, 14);
      final status = [
        const SizedBox(height: 12),
        _status(),
        const SizedBox(height: 12),
        _actions(showTalk: !_systemToolbar),
        if (!_systemToolbar) _shortcuts(),
        ..._messages(),
      ];
      if (roomy) {
        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _identity(),
              const SizedBox(height: 12),
              Expanded(child: _scene(immersive: true)),
              if (!_game.alive) Text(_bubble),
              ...status,
            ],
          ),
        );
      }
      return ListView(
        key: ValueKey(keyboardOpen),
        padding: padding,
        children: [
          if (!keyboardOpen) ...[_identity(), const SizedBox(height: 12)],
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
          if (!keyboardOpen) ...status,
        ],
      );
    },
  );

  Widget _wideRoom(BoxConstraints space, bool keyboardOpen) {
    final controlWidth = (space.maxWidth * .36).clamp(236.0, 324.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, keyboardOpen ? 8 : 16, 16, 12),
      child: Row(
        key: const ValueKey('wide-room'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        textDirection: TextDirection.ltr,
        children: [
          Expanded(child: _scene(immersive: true)),
          const SizedBox(width: 16),
          SizedBox(
            key: const ValueKey('room-controls'),
            width: controlWidth,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, rail) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: rail.maxHeight),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _controlCard(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _identity(),
                                  const SizedBox(height: 16),
                                  _status(),
                                  if (!keyboardOpen) ...[
                                    const SizedBox(height: 10),
                                    const Divider(height: 1),
                                    _shortcuts(vertical: true),
                                  ],
                                  if (!_game.alive) Text(_bubble),
                                  ..._messages(),
                                ],
                              ),
                            ),
                            if (!keyboardOpen)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _controlCard(_actions()),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_chatOpen && _game.alive) _composer(inRail: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlCard(Widget child) => Container(
    decoration: BoxDecoration(
      color: const Color(0xfff7f2e9),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xffe8e0d1)),
    ),
    padding: const EdgeInsets.all(13),
    child: child,
  );

  Widget _identity() => LayoutBuilder(
    builder: (context, space) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _game.kind.label,
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
      final details = Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          health,
          TextButton(
            onPressed: _busy ? null : _petInfo,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('펫 정보'),
          ),
        ],
      );
      if (space.maxWidth < 270 ||
          MediaQuery.textScalerOf(context).scale(14) > 19) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 2), details],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: 8),
          Flexible(child: details),
        ],
      );
    },
  );

  Widget _status() => LayoutBuilder(
    builder: (context, space) {
      final stats = [
        _stat(
          '포만감',
          '${_game.fullness}/${_game.maxFullness}',
          urgent: _game.fullness == 0,
        ),
        _stat(
          '애정도',
          _game.affection >= _game.nextAffection
              ? '${_game.affection}'
              : '${_game.affection}/${_game.nextAffection}',
        ),
        _stat('배변', '${_game.waste}/3', urgent: _game.waste >= 3),
      ];
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xffefe9dd),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child:
              space.maxWidth < 186 ||
                  MediaQuery.textScalerOf(context).scale(13) > 18
              ? Wrap(spacing: 14, runSpacing: 6, children: stats)
              : Row(
                  children: [for (final stat in stats) Expanded(child: stat)],
                ),
        ),
      );
    },
  );

  Widget _stat(String label, String value, {bool urgent = false}) => Semantics(
    label: '$label $value',
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: urgent ? const Color(0xff9c3e22) : ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );

  String _rewardLabel(PetPlayResult reward) => [
    '체력 −${reward.energyPercent.toStringAsFixed(1)}%',
    for (final gain in reward.gains.entries) '${gain.key} +${gain.value}',
  ].join(' · ');

  String _playHint(PetPlay activity) {
    if (activity == PetPlay.disc && !_game.disc) return '가방에 원반이 필요해요.';
    if (!_game.healthy) return '먹이기나 청소가 필요해요.';
    final cost = _game.energyPercent(activity.cost).toStringAsFixed(1);
    return _game.energy < activity.cost ? '체력이 $cost% 필요해요.' : '체력 −$cost%';
  }

  Widget _actions({bool showTalk = true}) {
    if (_chatOpen) return const SizedBox.shrink();
    final ready = _game.alive && !_busy;
    final buttons = <(IconData, String, VoidCallback?, String?)>[
      if (!_game.inPark) ...[
        (
          Icons.rice_bowl,
          '먹이기',
          ready && _game.fullness < _game.maxFullness ? _feeding : null,
          null,
        ),
        (
          Icons.cleaning_services_outlined,
          '청소하기',
          ready && _game.waste > 0 ? _clean : null,
          null,
        ),
      ],
      (
        Icons.trip_origin,
        _canReplay ? '한 번 더 던지기' : '원반 던지기',
        ready && _game.canPlay(PetPlay.disc) ? _chooseThrow : null,
        _playHint(PetPlay.disc),
      ),
      if (_game.inPark) ...[
        (
          Icons.park_outlined,
          '산책하기',
          ready && _game.canPlay(PetPlay.walk) ? _walkInPark : null,
          _playHint(PetPlay.walk),
        ),
        (
          Icons.favorite_border,
          '벤치에서 쉬기',
          ready ? _restInPark : null,
          _game.canRecoverAtBench ? '벤치에서 쉬고 체력을 회복해요.' : null,
        ),
      ],
      if (showTalk)
        (Icons.chat_bubble_outline, '말 걸기', ready ? _openChat : null, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '체력 $_energyLabel',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '체력',
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
        if (_playReward.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _playReward,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, space) {
            final pair =
                space.maxWidth >= 270 &&
                MediaQuery.textScalerOf(context).scale(14) <= 19;
            final width = pair ? (space.maxWidth - 8) / 2 : space.maxWidth;
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (icon, label, press, hint) in buttons)
                  SizedBox(
                    width: width,
                    child: Tooltip(
                      message: hint ?? label,
                      excludeFromSemantics: hint == null,
                      child: FilledButton.tonalIcon(
                        onPressed: press,
                        icon: Icon(icon, size: 17),
                        label: Text(label, textAlign: TextAlign.center),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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

  List<(IconData, String, VoidCallback)> get _menuActions => [
    (Icons.inventory_2_outlined, '가방', _bag),
    (Icons.collections_outlined, '앨범·도감', _album),
    (Icons.settings_outlined, '설정', _settings),
  ];

  Widget _iconLabel(IconData icon, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center),
    ],
  );

  Widget _shortcuts({bool vertical = false}) {
    final buttons = _menuActions.map(
      (item) => TextButton(
        onPressed: _busy ? null : item.$3,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(0, 48),
        ),
        child: vertical
            ? Row(
                children: [
                  Icon(item.$1, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item.$2)),
                  const ExcludeSemantics(child: Text('›')),
                ],
              )
            : _iconLabel(item.$1, item.$2),
      ),
    );
    return vertical
        ? Column(children: buttons.toList())
        : Row(
            children: [for (final button in buttons) Expanded(child: button)],
          );
  }

  Widget _scene({bool immersive = false}) {
    final surface = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final headerHeight = immersive && height >= 210 ? 48.0 : 0.0;
        final worldWidth = immersive
            ? math.min(width, (height - headerHeight) * 1.5)
            : width;
        final worldHeight = immersive ? worldWidth / 1.5 : height;
        final worldX = (width - worldWidth) / 2;
        final worldY = headerHeight + (height - headerHeight - worldHeight) / 2;
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
                  key: const ValueKey('room-artwork'),
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
                    left: worldX + worldWidth * (.64 + .065 * index) - 15,
                    top: worldY + worldHeight * (.84 - .04 * index) - 12,
                    width: 48,
                    height: 48,
                    child: Semantics(
                      key: ValueKey('room-waste-$index'),
                      container: true,
                      label: '배변 치우기',
                      button: true,
                      enabled: _game.alive && !_busy,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _game.alive && !_busy ? _clean : null,
                        child: const Center(
                          child: ExcludeSemantics(
                            child: Text('💩', style: TextStyle(fontSize: 17)),
                          ),
                        ),
                      ),
                    ),
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
                      container: true,
                      button: true,
                      label: '${_game.kind.label} 톡 누르기',
                      child: GestureDetector(
                        key: const ValueKey('pet-touch-target'),
                        behavior: HitTestBehavior.opaque,
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
                              child: ValueListenableBuilder<bool>(
                                valueListenable: _blink,
                                builder: (context, blinking, _) => PetSprite(
                                  kind: _game.kind,
                                  blink: !_busy && blinking,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_game.alive)
                  Positioned(
                    left: petX - size * .72,
                    top: petTop + size * .06,
                    width: size * 1.44,
                    height: size * .72,
                    child: _patHearts(),
                  ),
                if (_game.alive && (_sending || _bubble.isNotEmpty))
                  _speechBubble(width, height, petX, petTop, size),
                if (_cleaning && _game.alive)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: IgnorePointer(
                      child: Center(child: _cleanProgress()),
                    ),
                  ),
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

  Widget _patHearts() => IgnorePointer(
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _patEffect,
        builder: (context, _) {
          final progress = _patEffect.value;
          if (progress >= 1) return const SizedBox.shrink();
          return Opacity(
            opacity: 1 - Curves.easeIn.transform(progress),
            child: Transform.translate(
              offset: Offset(0, -23 * progress),
              child: const Stack(
                key: ValueKey('pet-pat-hearts'),
                children: [
                  Align(
                    alignment: Alignment(-.92, -.1),
                    child: Icon(
                      Icons.favorite,
                      color: Color(0xffd76a75),
                      size: 15,
                    ),
                  ),
                  Align(
                    alignment: Alignment(.90, -.7),
                    child: Icon(
                      Icons.favorite,
                      color: Color(0xffe57378),
                      size: 18,
                    ),
                  ),
                  Align(
                    alignment: Alignment(.99, .14),
                    child: Icon(
                      Icons.favorite,
                      color: Color(0xffe58f89),
                      size: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _cleanProgress() => Semantics(
    liveRegion: true,
    child: AnimatedBuilder(
      animation: _sweep,
      builder: (context, label) => Material(
        color: paper,
        elevation: 1,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: math.sin(_sweep.value * math.pi * 8) * .28,
                    child: const Icon(
                      Icons.cleaning_services_outlined,
                      color: forest,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 6),
                  label!,
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 78,
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: _sweep.value,
                    minHeight: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: const Text('청소 중'),
    ),
  );

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
    final preview = Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: Text(
        _sending ? '…' : _bubble,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, height: 1.23),
      ),
    );
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
              child: _sending
                  ? preview
                  : Tooltip(
                      message: '대사 전체 보기',
                      child: InkWell(
                        onTap: () => _sheet<void>('${_game.kind.label}의 말', [
                          SelectableText(_bubble),
                        ]),
                        child: preview,
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
