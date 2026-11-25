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

import 'pet/pet_ending_scene.dart';
import 'pet/pet_game.dart';
import 'pet/pet_platform.dart';
import 'pet/pet_sprite.dart';
import 'pet/pet_voice.dart';
import 'photo_analysis.dart';

const forest = Color(0xff214e3b);
const ink = Color(0xff26382e);
const paper = Color(0xfffffaf1);
const mint = Color(0xffe2ebda);

enum _DiscOffer { lesson, ready, remembered }

enum _FarDiscAim { preparing, ready }

typedef _SceneAction = ({
  Offset anchor,
  String label,
  IconData icon,
  Color color,
  VoidCallback? onPressed,
});

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans KR',
    ], await rootBundle.loadString('assets/pet/NotoSansKR-OFL.txt'));
  });
  runApp(const PetApp());
}

class PetApp extends StatelessWidget {
  const PetApp({super.key, this.voice});

  final PetVoice? voice;

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
    home: PetRoom(voice: voice),
  );
}

class PetRoom extends StatefulWidget {
  const PetRoom({super.key, this.voice});

  final PetVoice? voice;

  @override
  State<PetRoom> createState() => _PetRoomState();
}

class _PetRoomState extends State<PetRoom> with TickerProviderStateMixin {
  static const _home = Offset(.51, .82);
  static const _park = Offset(.52, .59);
  static const _parkEntrance = Offset(.23, .72);
  static const _parkBench = Offset(.57, .66);
  static const _parkGrove = Offset(.60, .40);
  static const _shortcutStone = Offset(.322, .602);
  static const _shortcutLookout = Offset(.23, .72);
  static const _shortcutEntrance = Offset(.30, .65);
  static const _pineconePositions = {
    PetRoomSpot.window: Offset(.63, .58),
    PetRoomSpot.rug: Offset(.37, .71),
  };
  static const _discPaths = {
    PetDiscLane.near: [_park, Offset(.64, .69), Offset(.81, .64)],
    PetDiscLane.far: [
      _park,
      Offset(.60, .73),
      Offset(.74, .70),
      Offset(.83, .62),
      Offset(.87, .51),
    ],
  };
  static const _window = Offset(.68, .65);
  static const _keepsakeSpot = Offset(.25, .70);
  static const _cleanDuration = Duration(seconds: 3);
  static const _layoutChannel = MethodChannel('donglgewi/layout');
  final _picker = ImagePicker();
  final _photoAnalysis = PhotoAnalysis();
  final _blink = ValueNotifier(false);
  late final AnimationController _idle;
  late final AnimationController _sweep;
  late final AnimationController _patEffect;
  late PetGame _game;
  PetVoice? _voice;
  Timer? _timer;
  Timer? _farDiscTimer;
  late final AppLifecycleListener _lifecycle;
  Future<void> _writes = Future.value();
  Offset _position = _home;
  Offset? _discPosition;
  _DiscOffer? _discOffer;
  bool? _throwLaneSelection;
  _FarDiscAim? _farDiscAim;
  bool _guidingShortcut = false;
  bool _roomOfferPending = false;
  PetRoomSpot? _roomOffer;
  bool _placingPinecone = false;
  double _hopLift = 0;
  Duration _hopDuration = const Duration(milliseconds: 150);
  bool _waitingPose = false;
  Duration _moveDuration = const Duration(milliseconds: 220);
  bool _facingLeft = false;
  bool _ready = false;
  bool _busy = false;
  bool _cleaning = false;
  bool _voiceLoading = false;
  bool _canReplay = false;
  bool _chatOpen = false;
  bool _feedbackOpen = false;
  bool _memoryGreeting = false;
  bool _searchOffer = false;
  bool _keepsakeOffer = false;
  bool _welcomeOffer = false;
  bool _careBeforeMemory = false;
  PetSearchSpot? _searchTarget;
  bool _teachingSearch = false;
  PetMemory? _talkMemory;
  String? _activityTopic;
  bool _sending = false;
  int _chatRequest = 0;
  DateTime? _firstPat;
  int _patCount = 0;
  double? _download;
  String _bubble = '안녕! 우리 방에 온 걸 환영해.';
  String _playReward = '';
  String _storageError = '';
  bool _systemToolbar = false;
  Map<String, bool>? _sentToolbarActions;
  final _speechAnchor = GlobalKey();
  bool _choicesWereVisible = false;

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
    _lifecycle = AppLifecycleListener(
      onResume: _refresh,
      onPause: () {
        if (_sending && mounted) setState(_cancelChatReply);
      },
    );
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
    final available = (ModalRoute.isCurrentOf(context) ?? true) && !_busy;
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
    var firstVisit = false;
    var readable = true;
    try {
      final snapshot = await readPetSnapshot();
      firstVisit = snapshot == null;
      _game = snapshot == null
          ? PetGame(DateTime.now())
          : PetGame.decode(snapshot);
    } catch (_) {
      _game = PetGame(DateTime.now());
      readable = false;
      _storageError = '저장 기록을 읽을 수 없어요.';
    }
    _game.advance(_game.now());
    if (!mounted) return;
    _position = _game.inPark ? _parkRest : _homeRest;
    setState(() {
      _ready = true;
      _roomOfferPending = !_game.inPark;
      _welcomeOffer = firstVisit;
      _voice = widget.voice;
      _voiceLoading = _voice == null && petNativeModelAvailable;
      if (_game.healthy &&
          _game.greetingDay == petDay(_game.at) &&
          _game.greeting.isNotEmpty) {
        _bubble = _game.greeting;
      } else {
        _bubble = firstVisit
            ? '안녕! 사진 속 물건으로 같이 놀아볼래?'
            : '안녕! ${_game.kind.label}야.';
      }
    });
    if (readable) _save();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _refresh();
    if (_voiceLoading) unawaited(_loadVoice());
    if (petNativeModelAvailable &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_recoverPhoto());
    }
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
    _lifecycle.dispose();
    _timer?.cancel();
    _farDiscTimer?.cancel();
    if (_usesIosLayout) _layoutChannel.setMethodCallHandler(null);
    _idle.dispose();
    _blink.dispose();
    _sweep.dispose();
    _patEffect.dispose();
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
      _clearPlayPrompt();
      if (wasAlive) _save();
      _cancelChatReply();
      setState(() => _bubble = '${_game.death}으로 ${_game.kind.label}와 헤어졌어요.');
      return;
    }
    if (!_game.healthy) {
      _clearPlayPrompt();
      _careBeforeMemory = _game.greetingDay != petDay(_game.at);
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
    if (greet &&
        !_busy &&
        !_sending &&
        !_hasPlayPrompt &&
        _game.healthy &&
        (ModalRoute.isCurrentOf(context) ?? true)) {
      _showGreeting();
      if (!_hasPlayPrompt) {
        if (_roomOfferPending) _showRoomOffer();
        if (!_game.shortcutGuided &&
            _game.canWalkRoute(PetParkRoute.shortcut)) {
          unawaited(_guideShortcut());
        }
      }
    }
    setState(() {});
  }

  bool get _hasPlayPrompt =>
      _chatOpen ||
      _discOffer != null ||
      _throwLaneSelection != null ||
      _placingPinecone ||
      _roomOffer != null ||
      _searchOffer ||
      _searchTarget != null ||
      _keepsakeOffer ||
      _welcomeOffer;

  void _showGreeting() {
    final day = petDay(_game.at);
    final memory = _game.greetingDay == day ? null : _game.nextMemory;
    final remembersWait = _game.recallWait();
    final remembersSearch = _game.recallSearch();
    if (!remembersWait && !remembersSearch && memory == null) return;

    final recalled = remembersWait ? _game.waitMemory ?? memory : memory;
    _talkMemory = recalled;
    if (remembersWait) {
      _position = _parkRest;
      _waitingPose = true;
      _discOffer = _DiscOffer.remembered;
      final title = _game.waitOrigin ?? memory?.title;
      _bubble =
          recalled?.discLane != null && recalled!.discId == _game.waitDiscId
          ? '${_photoMemoryLine(recalled)} 그때 배운 대로 기다릴게.'
          : title == null
          ? '그때 배운 대로 기다릴게.'
          : '‘$title’ 기억나? 그때 배운 대로 기다릴게.';
    } else if (remembersSearch) {
      _bubble = '그때 배운 대로 찾아볼게!';
      if (_game.canFindPinecone) {
        _searchTarget = _game.searchSpot;
        final target = petParkSearchPositions[_searchTarget]!;
        _facingLeft = target.dx < _position.dx;
        _bubble = '그때 배운 대로 찾아볼게! ${_searchTarget!.hint}';
      } else {
        _chatOpen = true;
      }
    } else if (memory != null) {
      final days = petDayDifference(_game.at, memory.at);
      final when = days == 1 ? '어제' : '$days일 전에';
      final line = memory.discLane == null
          ? '$when 남긴 ‘${memory.title}’ 기억나?'
          : _photoMemoryLine(memory);
      _bubble = _careBeforeMemory ? '이제 괜찮아. $line' : line;
      _chatOpen = true;
      _memoryGreeting = true;
    }
    if (memory != null) {
      _game.greetingDay = day;
      _game.greeting = _bubble;
      _game.lastMemory = (recalled ?? memory).key;
    }
    _careBeforeMemory = false;
    _save();
  }

  String _photoMemoryLine(PetMemory memory) {
    final days = petDayDifference(_game.at, memory.at);
    final when = days == 0
        ? '오늘'
        : days == 1
        ? '어제'
        : '$days일 전에';
    return '$when ‘${memory.title}’에서 가져온 원반을 공원 ${memory.discLane!.label}에 던졌지.';
  }

  void _showRoomOffer() {
    _roomOfferPending = false;
    final spot = _game.takeRoomOffer();
    if (spot == null) return;
    _roomOffer = spot;
    _facingLeft = _pineconePositions[spot]!.dx < _position.dx;
    _bubble = switch (spot) {
      PetRoomSpot.window => '별 보러 갈까?',
      PetRoomSpot.rug => '러그에서 같이 앉을래?',
    };
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
      '원반 놀이 장소': '공원에서만',
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

  Offset get _homeRest => switch (_game.pineconeSpot) {
    PetRoomSpot.window => const Offset(.68, .64),
    PetRoomSpot.rug => const Offset(.42, .76),
    null => _home,
  };

  Offset get _parkRest =>
      _game.parkRoute == PetParkRoute.shortcut ? _parkGrove : _park;

  Future<void> _hop(
    double lift,
    int milliseconds, {
    VoidCallback? onCatch,
  }) async {
    final duration = Duration(milliseconds: milliseconds);
    setState(() {
      _hopDuration = duration;
      _hopLift = lift;
    });
    await Future<void>.delayed(duration);
    if (!mounted) return;
    setState(() {
      _hopLift = 0;
      onCatch?.call();
    });
    await Future<void>.delayed(duration);
  }

  Future<void> _feed(bool apple, {required int portions}) async {
    _refresh(greet: false);
    if (_busy || _game.previewMeal(apple: apple, portions: portions) == null) {
      _notice(
        _game.fullness >= _game.maxFullness ? '지금은 배가 불러요.' : '지금은 먹일 수 없어요.',
      );
      return;
    }
    for (var i = 0; i < portions; i++) {
      _game.feed(apple: apple);
    }
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
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
      _clearPlayPrompt();
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

  void _clearPlayPrompt() {
    _discOffer = null;
    _throwLaneSelection = null;
    _farDiscTimer?.cancel();
    _farDiscTimer = null;
    _farDiscAim = null;
    _roomOffer = null;
    _placingPinecone = false;
    _waitingPose = false;
    _searchOffer = false;
    _keepsakeOffer = false;
    _welcomeOffer = false;
    _searchTarget = null;
    _teachingSearch = false;
    _chatOpen = false;
    _feedbackOpen = false;
    _memoryGreeting = false;
    _talkMemory = null;
    _activityTopic = null;
  }

  Future<void> _playPhotoDisc(int id, {bool resumeLesson = false}) async {
    _refresh(greet: false);
    final game = _game;
    if (_busy || !game.healthy || !game.discs.any((disc) => disc.id == id)) {
      return;
    }
    if (!game.inPark) await _changeLocation();
    if (!mounted || game != _game || !game.canPlay(PetPlay.disc)) return;
    if (!game.selectPhotoDisc(id)) return;
    _save();
    if (resumeLesson) {
      await _chooseThrow();
    } else {
      _offerThrow();
    }
  }

  void _offerThrow() {
    _refresh(greet: false);
    if (_busy || !_game.canPlay(PetPlay.disc)) return;
    if (!_game.canLearnLesson) {
      unawaited(_chooseThrow());
      return;
    }
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
      _discOffer = _DiscOffer.lesson;
      _bubble = '어떻게 던져 줄래?';
    });
  }

  void _practiceWait() {
    if (_busy ||
        _discOffer != _DiscOffer.lesson ||
        !_game.canPlay(PetPlay.disc)) {
      return;
    }
    setState(() {
      _discOffer = _DiscOffer.ready;
      _waitingPose = true;
      _bubble = '응, 여기서 기다릴게!';
    });
  }

  Future<void> _throw({
    PetDiscLane lane = PetDiscLane.near,
    bool teachWait = false,
  }) async {
    _refresh(greet: false);
    if (_busy || !_game.canThrowLane(lane)) return;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _clearPlayPrompt();
      _canReplay = false;
      _playReward = '';
      _bubble = '내가 받아올게!';
    });
    final path = _discPaths[lane]!;
    await _animateTo(path.first);
    if (!mounted) return;
    setState(() => _discPosition = path.last);
    for (final point in path.skip(1)) {
      await _animateTo(point, lane == PetDiscLane.far ? 230 : 260);
      if (!mounted || !_game.healthy) break;
    }
    if (!mounted) return;
    if (_game.healthy) {
      await _hop(
        lane == PetDiscLane.far ? .43 : .22,
        lane == PetDiscLane.far ? 200 : 155,
        onCatch: () => _discPosition = null,
      );
      for (final point in path.reversed.skip(1)) {
        if (!mounted || !_game.healthy) break;
        await _animateTo(point, 220);
      }
    }
    if (!mounted) return;
    _game.advance(_game.now());
    final reward = _game.play(PetPlay.disc, teachWait: teachWait, lane: lane);
    setState(() {
      _discPosition = null;
      _busy = false;
      _canReplay = reward != null && _game.disc;
      if (reward != null) {
        _bubble = teachWait
            ? '기다렸다가 잡았어! 다음에도 해볼게.'
            : reward.discBroke
            ? '잡았다! 이 원반은 이제 다 썼어.'
            : '잡았다! 한 번 더 던져볼까?';
        _playReward =
            '${_rewardLabel(reward)} · ${reward.discBroke ? '원반 소진' : '내구도 −1'}';
        _chatOpen = true;
        _feedbackOpen = true;
        _activityTopic = 'activity:disc';
      }
    });
    _save();
    _refresh();
  }

  Future<void> _chooseThrow({bool teachWait = false}) async {
    _refresh(greet: false);
    if (_busy || !_game.canPlay(PetPlay.disc)) return;
    if (_game.level < 4) return _throw(teachWait: teachWait);
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
      _throwLaneSelection = teachWait;
      _waitingPose = teachWait;
      _bubble = '어느 잔디 쪽으로 던져 줄래?';
    });
  }

  void _aimFarDisc() {
    _refresh(greet: false);
    if (_busy ||
        _throwLaneSelection == null ||
        _farDiscAim != null ||
        !_game.canThrowLane(PetDiscLane.far)) {
      return;
    }
    setState(() {
      _farDiscAim = _FarDiscAim.preparing;
      _waitingPose = true;
      _facingLeft = false;
      _bubble = '잠깐, 자세 잡을게.';
    });
    unawaited(_animateTo(_park, 360));
    _farDiscTimer = Timer(const Duration(milliseconds: 700), () {
      _farDiscTimer = null;
      _refresh(greet: false);
      if (_farDiscAim != _FarDiscAim.preparing ||
          !_game.canThrowLane(PetDiscLane.far)) {
        return;
      }
      setState(() {
        _farDiscAim = _FarDiscAim.ready;
        _bubble = '준비됐어! 지금 던져줘.';
      });
    });
  }

  void _tapPet() {
    if (!_game.alive || _busy) return;
    _refresh(greet: false);
    if (!_game.alive) return;
    _clearPlayPrompt();
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
      _roomOfferPending = !toPark;
      _game.parkRoute = PetParkRoute.bench;
      _clearPlayPrompt();
      _canReplay = false;
      _position = toPark ? _parkEntrance : _homeRest;
      _bubble = !toPark
          ? '우리 집에 돌아왔어.'
          : _game.level >= 3 && !_game.shortcutGuided
          ? '공원에 왔어!'
          : '오늘은 벤치까지 걸어가 볼까?';
      _busy = toPark;
    });
    if (toPark) {
      await _walkParkPath();
      return;
    }
    _save();
    _refresh();
  }

  Future<void> _guideShortcut() async {
    setState(() {
      _busy = true;
      _guidingShortcut = true;
    });
    await _animateTo(_shortcutLookout, 420);
    if (!mounted) return;
    setState(() => _facingLeft = false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _refresh(greet: false);
    final eligible = _game.canWalkRoute(PetParkRoute.shortcut);
    setState(() {
      _busy = false;
      _guidingShortcut = false;
      if (eligible) _game.shortcutGuided = true;
    });
    if (eligible) _save();
  }

  Future<void> _walkParkPath({
    bool training = false,
    PetParkRoute route = PetParkRoute.bench,
  }) async {
    if (route == PetParkRoute.shortcut) {
      await _animateTo(_shortcutEntrance, 340);
      if (!mounted) return;
      await Future.wait([
        _hop(.37, 160),
        _animateTo(const Offset(.39, .54), 320),
      ]);
      if (!mounted) return;
      await _animateTo(const Offset(.49, .46), 350);
      if (!mounted) return;
      await _animateTo(_parkGrove, 420);
    } else {
      await _animateTo(const Offset(.39, .65), 370);
      if (!mounted) return;
      await _animateTo(_park, 440);
    }
    if (!mounted) return;
    _game.advance(_game.now());
    final wasUnlocked = _game.searchUnlocked;
    final reward = training ? _game.play(PetPlay.walk, route: route) : null;
    setState(() {
      _busy = false;
      if (reward != null) {
        _playReward = _rewardLabel(reward);
        if (route == PetParkRoute.shortcut && _game.canFindPinecone) {
          _searchTarget = _game.searchSpot;
          _bubble = '돌을 넘으니 나무 뒤에 풀이 흔들려!';
        } else if (!wasUnlocked && _game.canFindPinecone) {
          _searchOffer = true;
          _bubble = '길가에 솔방울이 숨어 있나 봐.';
        }
      }
    });
    _save();
    _refresh();
  }

  Future<void> _walkInPark([PetParkRoute route = PetParkRoute.bench]) async {
    if (_busy || !_game.inPark) return;
    _refresh(greet: false);
    if (!_game.canWalkRoute(route)) return;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _playReward = '';
      _clearPlayPrompt();
      _bubble = route == PetParkRoute.shortcut
          ? '저 돌을 넘으면 나무 뒤로 갈 수 있어!'
          : '벤치까지 한 바퀴 걷자!';
    });
    if (route == PetParkRoute.bench) await _animateTo(_parkEntrance, 420);
    if (mounted) await _walkParkPath(training: true, route: route);
  }

  void _offerSearch() {
    _refresh(greet: false);
    if (_busy || !_game.canFindPinecone) return;
    if (!_game.canLearnLesson) {
      _beginSearch();
      return;
    }
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
      _searchOffer = true;
      _bubble = '어느 쪽을 살펴볼까?';
    });
  }

  void _beginSearch({bool teach = false}) {
    _refresh(greet: false);
    if (_busy || !_game.canFindPinecone) return;
    final target = _game.searchSpot;
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
      _teachingSearch = teach;
      _searchTarget = target;
      _facingLeft = petParkSearchPositions[target]!.dx < _position.dx;
      _bubble = target.hint;
    });
  }

  Future<void> _guessSearchSpot(PetSearchSpot spot) async {
    _refresh(greet: false);
    final target = _searchTarget;
    if (_busy || target == null || !_game.canFindPinecone) return;
    if (spot != target || !_game.findPinecone(spot, teach: _teachingSearch)) {
      setState(() {
        _bubble = target == _game.searchSpot
            ? '거긴 아닌 것 같아. ${target.hint}'
            : '새 흔적이 보여. ${_game.searchSpot.hint}';
        _searchTarget = _game.searchSpot;
      });
      return;
    }
    final taught = _teachingSearch;
    setState(() {
      _clearPlayPrompt();
      _busy = true;
      _bubble = taught ? '찾아냈어! 다음에도 내가 먼저 살펴볼게.' : '여기 솔방울이 있었어!';
      _playReward = '솔방울 발견';
    });
    _save();
    await _animateTo(petParkSearchPositions[spot]!, 440);
    if (!mounted) return;
    setState(() => _busy = false);
    _refresh();
  }

  Future<void> _findStar() async {
    if (_busy) return;
    _refresh(greet: false);
    final game = _game;
    if (!game.canFindStar) return;
    var written = '';
    final name = await _sheet<String>('창가의 별', [
      Icon(
        petStarIcons[game.starDays.length],
        color: const Color(0xff946427),
        size: 36,
      ),
      const SizedBox(height: 8),
      TextField(
        maxLength: 24,
        onChanged: (value) => written = value,
        decoration: InputDecoration(
          labelText: '별 이름',
          hintText: PetGame.starNames[game.starDays.length],
        ),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, written),
        child: const Text('별 앨범에 담기'),
      ),
    ]);
    if (!mounted || name == null || game != _game) return;
    _refresh(greet: false);
    final title = game.findStar(name: name);
    if (title == null) return;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _clearPlayPrompt();
      _bubble = '창가에서 ‘$title’을 찾았어!';
    });
    _save();
    await _animateTo(_window, 430);
    if (!mounted) return;
    setState(() => _busy = false);
    _refresh();
  }

  IconData _keepsakeIcon(PetEnding ending) => switch (ending) {
    PetEnding.lastDisc => Icons.trip_origin,
    PetEnding.pinecone => Icons.eco_outlined,
    PetEnding.stars => Icons.auto_awesome,
    PetEnding.window => Icons.pets_outlined,
  };

  Future<void> _inspectKeepsake() async {
    if (_busy || _game.inPark || !_game.healthy) return;
    final item = _game.keepsake;
    if (item == null) return;
    final active = _game.personality.active;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _clearPlayPrompt();
      _bubble = active
          ? '${item.ending.keepsake} 옆까지 같이 갈래?'
          : '${item.ending.keepsake} 옆에 잠깐 앉을래.';
    });
    final spot = _keepsakeSpot + const Offset(.09, .02);
    await _animateTo(spot, active ? 330 : 620);
    if (!mounted) return;
    if (active) {
      await _animateTo(spot - const Offset(0, .045), 145);
      await _animateTo(spot, 175);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _keepsakeOffer = _game.canUseKeepsakeAtHome;
    });
    _refresh(greet: false);
  }

  Future<void> _playKeepsakeAtHome() async {
    _refresh(greet: false);
    if (_busy || !_game.useKeepsakeAtHome()) return;
    final ending = _game.keepsake!.ending;
    setState(() {
      _clearPlayPrompt();
      _busy = true;
      _bubble = switch (ending) {
        PetEnding.lastDisc => '작은 원반을 러그까지 굴려볼게!',
        PetEnding.pinecone => '러그 옆에서 솔방울을 찾아볼게!',
        PetEnding.stars => '별 장식을 창가에 두면 반짝일까?',
        PetEnding.window => '작은 발자국을 따라가 볼게.',
      };
      if (ending == PetEnding.lastDisc) _discPosition = _keepsakeSpot;
    });
    _save();
    final destination = ending == PetEnding.stars
        ? _window
        : const Offset(.42, .76);
    await _animateTo(destination, 450);
    if (!mounted) return;
    setState(() {
      if (ending == PetEnding.lastDisc) {
        _discPosition = destination + const Offset(.06, 0);
      }
      _bubble = switch (ending) {
        PetEnding.lastDisc => '끝까지 굴렀어! · 민첩 연습',
        PetEnding.pinecone => '찾았어, 러그 옆에 있었네! · 탐색 연습',
        PetEnding.stars => '별빛이 방 안까지 들어왔어.',
        PetEnding.window => '이 자리에서 잠깐 쉬어갈래.',
      };
      _waitingPose = !_game.personality.active;
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _discPosition = null;
      _busy = false;
    });
    _refresh();
  }

  String _homeKeepsakeAction(PetEnding ending) => switch (ending) {
    PetEnding.lastDisc => '방에서 굴려 보기',
    PetEnding.pinecone => '러그 옆에서 찾아보기',
    PetEnding.stars => '창가에 별 장식 두기',
    PetEnding.window => '발자국 따라가기',
  };

  Future<void> _takeKeepsakeToPark() async {
    _refresh(greet: false);
    if (_busy || !_game.useKeepsake()) return;
    _save();
    await _changeLocation();
    if (!mounted || !_game.healthy || !_game.inPark) return;
    if (_game.keepsake?.ending == PetEnding.pinecone) {
      _offerSearch();
    } else {
      _offerThrow();
    }
  }

  Future<void> _showGrowthEnding() async {
    if (_busy) return;
    _refresh(greet: false);
    final game = _game;
    var ending = game.ending;
    if (ending == null) {
      final options = game.availableEndings;
      if (options.isEmpty) return;
      ending = await _sheet<PetEnding>('함께한 날의 엔딩', [
        for (final option in options)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_keepsakeIcon(option)),
            title: Text(option.title),
            subtitle: Text(_endingReason(game, option)),
            onTap: () => Navigator.pop(context, option),
          ),
      ]);
      if (!mounted || ending == null || game != _game) return;
      _refresh(greet: false);
      if (!game.finish(ending)) return;
      setState(() {});
      _save();
    }
    final scene = ending;
    final next = await _sheet<bool>(scene.title, [
      PetEndingScene(
        kind: game.kind,
        ending: scene,
        searchSpot: game.taughtSearchSpot,
      ),
      const SizedBox(height: 12),
      Text(scene.line),
      const SizedBox(height: 6),
      Text(_endingReason(game, scene)),
      if (game.waitOrigin case final title? when scene == PetEnding.lastDisc)
        Text('‘$title’에서 가져온 원반'),
      if (game.taughtSearchSpot case final spot?
          when scene == PetEnding.pinecone)
        Text('처음 찾았던 자리 · ${spot.label}'),
      if (scene == PetEnding.stars)
        Wrap(
          spacing: 6,
          children: [
            for (final name in game.starTitles) Chip(label: Text(name)),
          ],
        ),
      const SizedBox(height: 8),
      Text('다음 펫에게 남길 기념품 · ${scene.keepsake}'),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('계속 키우기'),
      ),
      OutlinedButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('새 펫 키우기'),
      ),
    ]);
    if (mounted && next == true && game == _game) await _chooseNewPet();
  }

  String _endingReason(PetGame game, PetEnding ending) {
    String day(DateTime time) => '${time.month}월 ${time.day}일';
    return switch (ending) {
      PetEnding.lastDisc
          when game.waitTaughtAt != null && game.waitRecalledAt != null =>
        '${day(game.waitTaughtAt!)}에 기다려를 가르쳤고, ${day(game.waitRecalledAt!)}에 펫이 먼저 기다렸어요.',
      PetEnding.lastDisc => '다음 날에도 스스로 기다렸던 공원',
      PetEnding.pinecone
          when game.searchTaughtAt != null && game.searchRecalledAt != null =>
        '${day(game.searchTaughtAt!)}에 찾아봐를 가르쳤고, ${day(game.searchRecalledAt!)}에 펫이 먼저 단서를 찾았어요.',
      PetEnding.pinecone => '다음 날에도 먼저 단서를 찾았던 공원',
      PetEnding.stars => '서로 다른 사흘에 창가의 별을 하나씩 이름 지어줬어요.',
      PetEnding.window => '${day(game.born)}부터 돌보고 놀며 성체가 됐어요.',
    };
  }

  Future<void> _showFarewell() async {
    final game = _game;
    if (game.alive) return;
    final album = await _sheet<bool>('마지막 인사', [
      PetFarewellScene(hunger: game.death == '굶주림'),
      const SizedBox(height: 10),
      Text('${game.death}으로 ${game.kind.label}와 헤어졌어요.'),
      if (game.memories.lastOrNull case final memory?)
        Text('함께 남긴 추억 · ${memory.title}'),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('남은 추억 보기'),
      ),
    ]);
    if (mounted && album == true && game == _game) await _album();
  }

  Future<void> _restInPark() async {
    if (_busy || !_game.inPark || !_game.alive) return;
    _refresh(greet: false);
    if (!_game.alive) return;
    final recovering = _game.canRecoverAtBench;
    setState(() {
      _cancelChatReply();
      _busy = true;
      _clearPlayPrompt();
      _game.parkRoute = PetParkRoute.bench;
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
    _save();
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

  Future<void> _bag({
    bool fresh = false,
    bool foundApple = false,
    PetDisc? foundDisc,
  }) async {
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
      if (foundApple && !_game.inPark && _game.fullness < _game.maxFullness)
        FilledButton.tonalIcon(
          onPressed: () => Navigator.pop(context, 'eatApple'),
          icon: const Icon(Icons.apple),
          label: const Text('지금 사과 주기'),
        ),
      if (foundDisc?.id != null && _game.healthy)
        FilledButton.tonalIcon(
          onPressed: () => Navigator.pop(context, 'playDisc'),
          icon: const Icon(Icons.trip_origin),
          label: Text(_game.inPark ? '이 원반으로 놀기' : '이 원반 들고 공원 가기'),
        ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: mint,
        leading: const Icon(Icons.add_photo_alternate_outlined, color: forest),
        title: const Text('아이템 얻기'),
        subtitle: const Text('사진에서 먹이와 물건을 찾아요.'),
        trailing: const Icon(Icons.chevron_right, color: forest),
        onTap: () => Navigator.pop(context, 'import'),
      ),
      const SizedBox(height: 8),
      for (final (icon, title, detail) in [
        (Icons.apple, '사과 ×${_game.apples}', '방의 먹이기에서 줄 수 있어요.'),
        (Icons.rice_bowl, '기본 먹이 ×${_game.pantry}', '매일 보충돼요.'),
        (
          Icons.trip_origin,
          '원반 ×${_game.discs.length}',
          _game.disc
              ? '공원에서 던질 수 있어요. · 내구도 ${_game.discs.take(4).map((item) => '${item.remaining}/${item.maximum}').join(' · ')}${_game.discs.length > 4 ? ' 외 ${_game.discs.length - 4}개' : ''}'
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
      if (_game.lastSearchAt != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.eco_outlined),
          title: const Text('솔방울'),
          subtitle: Text(
            _game.pineconeSpot == null
                ? '공원에서 찾았어요.'
                : '${_game.pineconeSpot!.label}에 놓아뒀어요.',
          ),
          trailing: _game.canPlacePinecone
              ? TextButton(
                  onPressed: () => Navigator.pop(context, 'placePinecone'),
                  child: Text(_game.pineconeSpot == null ? '방에 두기' : '자리 바꾸기'),
                )
              : null,
        ),
    ]);
    if (!mounted) return;
    if (action == 'import') await _import();
    if (action == 'eatApple') await _feed(true, portions: 1);
    if (action == 'playDisc' && foundDisc?.id != null) {
      await _playPhotoDisc(foundDisc!.id!);
    }
    if (action == 'placePinecone' && _game.canPlacePinecone) {
      setState(() {
        _clearPlayPrompt();
        _placingPinecone = true;
        _bubble = '솔방울을 어디에 둘까?';
      });
    }
  }

  Future<void> _placePinecone(PetRoomSpot spot) async {
    _refresh(greet: false);
    if (_busy || !_placingPinecone || !_game.placePinecone(spot)) return;
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
      _busy = true;
      _roomOfferPending = false;
      _bubble = '${spot.label}에서 솔방울을 보니 좋아!';
    });
    _save();
    await _animateTo(_homeRest, 420);
    if (mounted) setState(() => _busy = false);
  }

  String _mealTime(DateTime time) {
    final days = petDayDifference(time, _game.at);
    final day = days == 0
        ? '오늘'
        : days == 1
        ? '내일'
        : '$days일 뒤';
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$day $hours:$minutes';
  }

  Future<void> _feeding() async {
    if (_busy || !_game.alive || _game.inPark) return;
    _refresh(greet: false);
    final game = _game;
    final options = [
      for (final (apple, portions) in [
        (true, 1),
        (false, 1),
        (false, 2),
        (false, 3),
      ])
        if (game.previewMeal(apple: apple, portions: portions)
            case final preview?)
          (apple, portions, preview),
    ];
    if (options.isEmpty) return;
    if (_sending) setState(_cancelChatReply);
    final choice = await _sheet<({bool apple, int portions})>('먹이 고르기', [
      if (game.waste > 0) Text('현재 청소할 배변 ${game.waste}개'),
      for (final (apple, portions, preview) in options)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(apple ? Icons.apple : Icons.rice_bowl),
          title: Text('${apple ? '사과' : '기본 먹이'} $portions개'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '포만감 ${preview.fullness}칸 · 공복 ${_mealTime(preview.hungryAt)}',
              ),
              Text(
                '청소 전 예상 배변 ${preview.waste}/3'
                '${preview.nextWaste == null ? '' : ' · 다음 ${_mealTime(preview.nextWaste!)}'}',
              ),
              Text(
                '돌보지 않으면 ${_mealTime(preview.unattendedDeadline)} · ${preview.risk} 위험',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: preview.risk == '위생 악화'
                      ? const Color(0xff863b22)
                      : ink,
                ),
              ),
            ],
          ),
          onTap: () =>
              Navigator.pop(context, (apple: apple, portions: portions)),
        ),
    ]);
    if (mounted && choice != null && game == _game) {
      await _feed(choice.apple, portions: choice.portions);
    }
  }

  Future<void> _import() async {
    final source = await _sheet<String>('아이템 얻기', [
      if (_usesIosLayout ||
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android))
        FilledButton.tonalIcon(
          onPressed: () => Navigator.pop(context, 'camera'),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('사진 찍기'),
        ),
      FilledButton.tonalIcon(
        onPressed: () => Navigator.pop(context, 'photo'),
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('앨범에서 선택'),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, 'sample'),
        icon: const Icon(Icons.park_outlined),
        label: const Text('시연용 소풍 장면'),
      ),
    ]);
    if (!mounted || source == null) return;
    if (source == 'sample') {
      await _reviewPhoto(sample: true);
      return;
    }

    final imageSource = source == 'camera'
        ? ImageSource.camera
        : ImageSource.gallery;
    PhotoFindings? findings;
    try {
      if (petNativeModelAvailable) {
        findings = await _photoAnalysis.pickAndAnalyze(imageSource);
      } else {
        final picked = await _picker.pickImage(
          source: imageSource,
          maxWidth: 1400,
        );
        if (picked != null) {
          findings = (imageBytes: await picked.readAsBytes(), labels: const []);
        }
      }
    } catch (_) {
      if (mounted) {
        _notice(
          imageSource == ImageSource.camera
              ? '카메라를 열 수 없어요. 카메라 권한을 확인하거나 앨범에서 선택해 주세요.'
              : '사진을 열 수 없어요. 시연 장면으로 진행할 수 있어요.',
        );
      }
      return;
    }
    if (findings != null) {
      await _reviewPhoto(picked: findings.imageBytes, labels: findings.labels);
    }
  }

  Future<void> _recoverPhoto() async {
    PhotoFindings? findings;
    try {
      findings = await _photoAnalysis.recoverOnAndroid();
    } catch (_) {
      if (mounted) _notice('사진을 다시 가져올 수 없어요. 가방에서 다시 시도해 주세요.');
      return;
    }
    if (findings != null) {
      await _reviewPhoto(picked: findings.imageBytes, labels: findings.labels);
    }
  }

  Future<void> _reviewPhoto({
    Uint8List? picked,
    List<String> labels = const [],
    bool sample = false,
  }) async {
    if (!mounted || !_game.alive) return;
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
    if (!mounted || !_game.alive || !confirmed) return;
    if (!apple && !disc && title.isEmpty) {
      _notice('담을 아이템이나 추억을 선택해주세요.');
      return;
    }
    _refresh(greet: false);
    if (!_game.alive) return;
    final date = _game.at;
    final photoTitle = title.isNotEmpty
        ? title
        : '${date.month}월 ${date.day}일 사진';
    final foundDisc = _game.addFinds(photoTitle, apple: apple, frisbee: disc);
    setState(() {
      _clearPlayPrompt();
      _bubble = '가방에 담았어. 같이 써보자!';
    });
    _save();
    await _bag(fresh: true, foundApple: apple, foundDisc: foundDisc);
  }

  void _openChat() {
    if (_busy || !_game.alive) return;
    _refresh(greet: false);
    if (!_game.alive) return;
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
      _chatOpen = true;
      _talkMemory = _game.memories.lastOrNull;
      if (!_game.healthy) return;
      _facingLeft = false;
      _bubble = !_game.inPark
          ? '오늘은 뭐 하고 싶어?'
          : switch (_game.parkIdea) {
              PetParkIdea.disc => '원반을 받아보고 싶어!',
              PetParkIdea.search => '잔디에 뭐가 숨었을까?',
              PetParkIdea.walk => '저 길로 한 바퀴 걸어볼까?',
              PetParkIdea.rest => '벤치 옆에 같이 앉을래?',
            };
    });
  }

  void _cancelChatReply() {
    if (!_sending) return;
    _chatRequest++;
    _sending = false;
    _voice?.cancel();
  }

  List<(String, VoidCallback)> _talkChoices() {
    if (!_game.healthy) {
      return [
        _game.inPark
            ? ('집으로 가기', _changeLocation)
            : _game.waste >= 3
            ? ('바닥 치우기', _clean)
            : ('먹이 주기', _feeding),
        ('알겠어', _dismissBubble),
      ];
    }
    if (_feedbackOpen) {
      return [
        ('잘했어!', () => _respondToPet(PetTalk.encouragement)),
        ('조금 아쉬웠어', () => _respondToPet(PetTalk.concern)),
        ('다른 얘기 하자', () => setState(() => _feedbackOpen = false)),
      ];
    }
    final memory = _talkMemory;
    final topic = memory != null && petDayDifference(_game.at, memory.at) == 1
        ? '어제 뭐가 좋았어?'
        : memory != null
        ? '그때 기억나?'
        : '오늘 기분 어때?';
    final (String, VoidCallback) suggested =
        _memoryGreeting && memory?.discLane != null
        ? _game.hasMemoryDisc(memory!) && _game.energy >= PetPlay.disc.cost
              ? (
                  _game.inPark ? '같은 원반 던지기' : '같은 원반 들고 공원 가기',
                  () => _playPhotoDisc(memory.discId!),
                )
              : ('같이 쉬자', _game.inPark ? _restInPark : _sitTogether)
        : !_game.inPark
        ? _game.canFindStar
              ? ('창가로 가자', _findStar)
              : ('공원으로 가자', _changeLocation)
        : switch (_game.parkIdea) {
            PetParkIdea.disc => ('원반으로 놀자', _offerThrow),
            PetParkIdea.search => ('같이 찾아봐', _offerSearch),
            PetParkIdea.walk => ('한 바퀴 걷자', _walkInPark),
            PetParkIdea.rest => ('같이 쉬자', _restInPark),
          };
    return [
      suggested,
      (topic, _askPet),
      if (_memoryGreeting && suggested.$1 != '같이 쉬자')
        ('같이 쉬자', _game.inPark ? _restInPark : _sitTogether)
      else
        ('한마디 해줄게', () => setState(() => _feedbackOpen = true)),
    ];
  }

  String get _talkTopic {
    if (_activityTopic case final topic?) return topic;
    final memory = _talkMemory;
    if (memory == null) return _game.inPark ? 'park' : 'room';
    final title = memory.title.trim().toLowerCase();
    return 'memory:${petDay(memory.at)}:$title';
  }

  void _respondToPet(PetTalk choice) {
    if (_busy || !_chatOpen || !_feedbackOpen) return;
    _refresh(greet: false);
    if (!_game.healthy) return;
    final result = _game.replyTo(choice, _talkTopic);
    if (result == null) {
      _showTalkFatigue();
      return;
    }
    setState(() {
      _bubble = switch (choice) {
        _ when result.bored => '그 말은 이제 좀 지겨워. 다른 얘기 하자.',
        PetTalk.encouragement when result.repeated => '응, 아까 그 말 기억해.',
        PetTalk.encouragement =>
          _game.personality.active ? '헤헤, 다음에도 해볼래!' : '그렇게 말해주니 좋아.',
        PetTalk.concern when result.repeated => '또 들으니까 마음이 좀 무거워.',
        _ => '그랬구나. 다음엔 같이 해보자.',
      };
      _playReward = _statChangesLabel(result.energyPercent, result.changes);
    });
    _save();
  }

  void _showTalkFatigue() {
    setState(() {
      _bubble = '지금은 힘이 없어. 잠깐 쉬었다 얘기하자.';
      _playReward = '';
    });
  }

  void _lookOutWindow() {
    if (_game.canFindStar) {
      unawaited(_findStar());
    } else {
      _sitTogether('별이 반짝일 때까지 같이 보자.');
    }
  }

  void _sitTogether([String line = '응, 여기서 같이 있자.']) {
    if (_busy || !_game.healthy) return;
    setState(() {
      _clearPlayPrompt();
      _waitingPose = true;
      _bubble = line;
    });
    _game.mark(PetActivity.bond);
    _save();
  }

  String _speechKey(String line) =>
      line.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');

  Future<void> _askPet() async {
    if (_busy || _sending || !_chatOpen) return;
    _refresh(greet: false);
    final game = _game;
    if (!game.healthy) return;
    if (!game.canTalk) {
      _showTalkFatigue();
      return;
    }
    final memory = _talkMemory;
    final topic = _talkTopic;
    final heading = game.healthLabel;
    final request = ++_chatRequest;
    setState(() {
      _chatOpen = false;
      _sending = true;
      _facingLeft = false;
    });
    final photoPlay = memory?.discLane != null;
    final reply = photoPlay || game.willBeBored(PetTalk.question, topic)
        ? null
        : await _reply(
            memory == null ? '' : '사용자가 고른 실제 추억: ${memory.title}',
            memory == null
                ? '지금 기분과 눈에 보이는 것을 한마디로 이야기해.'
                : '사용자가 그때 뭐가 좋았는지 물었어. 실제 추억의 제목을 포함해 한마디로 답해.',
            math.min(memory == null ? 32 : 64, game.energy),
          );
    if (!mounted || request != _chatRequest || game != _game) return;
    _refresh(greet: false);
    if (request != _chatRequest ||
        !game.healthy ||
        game.healthLabel != heading) {
      if (request == _chatRequest) setState(() => _sending = false);
      return;
    }
    final recent = game.recentReplies;
    final generated =
        reply != null &&
        reply.tokens > 0 &&
        (memory == null || reply.text.contains(memory.title)) &&
        !recent.contains(_speechKey(reply.text));
    final fallback = memory == null
        ? [
            '네가 오니까 기분이 좋아.',
            '오늘 기분은 ${game.moodLabel}. 같이 뭐 하나 할래?',
            '응, 한동안 여기 있는 것도 좋아.',
          ]
        : photoPlay
        ? [
            '${_photoMemoryLine(memory)} 내가 받아왔어!',
            '‘${memory.title}’에서 가져온 원반을 공원 ${memory.discLane!.label}에서 잡았어.',
          ]
        : [
            '‘${memory.title}’ 기억나. 같이 있어서 좋았어.',
            '‘${memory.title}’ 얘기를 하니까 또 생각나네.',
            '응, ‘${memory.title}’는 앨범에도 남겨뒀어.',
          ];
    final result = game.replyTo(
      PetTalk.question,
      topic,
      shownTokens: generated ? reply.tokens : null,
    );
    if (result == null) {
      setState(() {
        _sending = false;
        _chatOpen = true;
      });
      _showTalkFatigue();
      return;
    }
    final line = result.bored
        ? '같은 얘기는 이제 좀 지겨워. 다른 게 궁금해.'
        : generated
        ? reply.text
        : fallback.firstWhere(
            (text) => !recent.contains(_speechKey(text)),
            orElse: () => fallback.first,
          );
    recent.add(_speechKey(line));
    if (recent.length > 6) recent.removeAt(0);
    setState(() {
      _sending = false;
      _bubble = line;
      _chatOpen = true;
      _memoryGreeting = false;
      _playReward = _statChangesLabel(result.energyPercent, result.changes);
    });
    _save();
  }

  void _dismissBubble() {
    setState(() {
      _cancelChatReply();
      _clearPlayPrompt();
      _bubble = '';
    });
  }

  Future<void> _album() => _sheet<void>('앨범·도감', [
    if (_game.keepsake case final item?)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(_keepsakeIcon(item.ending)),
        title: Text(item.ending.keepsake),
        subtitle: Text('${item.from.label} · ${item.ending.title}'),
      ),
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
              : kind == PetKind.star &&
                    _game.starDays.length == PetGame.starNames.length
              ? '창가에서 별 세 개를 모아 발견했어요'
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
      Text(
        game.personality.active
            ? '좋아하는 활동 · 원반 놀이'
            : game.personality.curious
            ? '좋아하는 활동 · 솔방울 찾기'
            : '좋아하는 활동 · 벤치에서 쉬기',
      ),
      if (game.level >= 2)
        Text('방 둘러보기 · ${game.pineconeSpot?.label ?? '솔방울 자리 고르기'}'),
      if (game.level >= 3) const Text('공원 · 나무 샛길이 열렸어요.'),
      if (game.level >= 4) const Text('원반 · 두 착지점을 고를 수 있어요.'),
      if (game.searchTaughtAt != null)
        Text(
          game.searchRecalledAt == null
              ? '배운 행동 · 찾아봐'
              : '배운 행동 · 공원에서 먼저 단서를 찾았어요',
        ),
      if (game.waitTaughtAt != null)
        Text(
          game.waitRecalledAt == null
              ? '배운 행동 · 기다려'
              : '배운 행동 · 공원에서 스스로 기다렸어요',
        ),
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
        '첫날 방에서 사과를 먹이고, 공원에서 원반을 던지기 전에 기다려를 골라보세요. 24시간 뒤에는 방에서 청소하고 먹이 두 개를 준 뒤 다시 공원으로 가세요. 48시간 뒤 돌봄을 마치면 성장 엔딩을 볼 수 있어요.',
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
        OutlinedButton(
          onPressed: () => Navigator.pop(context, '36'),
          child: const Text('36시간 뒤 · 원반 착지점'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, '48'),
          child: const Text('48시간 뒤 · 셋째 날'),
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
        content: const Text(
          '현재 펫의 성장, 가방, 추억을 초기화합니다. 키워본 캐릭터와 마지막 기념품은 새 펫에게도 남아요.',
        ),
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
    final item = _game.keepsake;
    final greeting = item == null
        ? '안녕! ${kind.label}야.'
        : '${item.ending.keepsake}가 있네. 같이 보러 갈래?';
    _replacePet(PetGame(DateTime.now(), kind: kind), greeting);
    if (_game.canUseKeepsakeAtHome) setState(() => _keepsakeOffer = true);
  }

  void _replacePet(PetGame next, String greeting) {
    next.raisedKinds.addAll(_game.raisedKinds);
    next.keepsake = _game.keepsake;
    setState(() {
      _cancelChatReply();
      _game = next;
      _roomOfferPending = false;
      _careBeforeMemory = false;
      _position = _home;
      _clearPlayPrompt();
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
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: SafeArea(
        child: AnimatedPadding(
          key: const ValueKey('room-safe-margin'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
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
      child: _compactScene(keyboardOpen),
    ),
  );

  Widget _compactScene(bool keyboardOpen) {
    const padding = EdgeInsets.fromLTRB(12, 12, 12, 10);
    if (keyboardOpen) {
      return Padding(padding: padding, child: _scene(bounded: true));
    }
    return Column(
      children: [
        if (_careNotice() case final notice?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(width: double.infinity, child: notice),
          ),
        Expanded(
          key: const ValueKey('compact-room-content'),
          child: LayoutBuilder(
            builder: (context, space) => SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, space.maxHeight - padding.vertical),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _identity(),
                    const SizedBox(height: 8),
                    _scene(dockChoices: _largeText || space.maxWidth < 320),
                    if (!_game.alive) Text(_bubble),
                    const SizedBox(height: 10),
                    _status(),
                    const SizedBox(height: 10),
                    _actions(showTalk: !_systemToolbar),
                    if (!_systemToolbar) _shortcuts(vertical: _largeText),
                    ..._messages(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool get _largeText => MediaQuery.textScalerOf(context).scale(14) > 19;

  Widget _wideRoom(BoxConstraints space, bool keyboardOpen) {
    final controlWidth = (space.maxWidth * .32).clamp(214.0, 304.0);
    final scene = !keyboardOpen && (_largeText || space.maxHeight < 300)
        ? SingleChildScrollView(child: _scene(dockChoices: true))
        : _scene(bounded: true);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1220),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            key: const ValueKey('wide-room'),
            textDirection: TextDirection.ltr,
            children: [
              Expanded(child: scene),
              const SizedBox(width: 14),
              SizedBox(
                key: const ValueKey('room-controls'),
                width: controlWidth,
                child: _controlCard(
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _identity(),
                        const SizedBox(height: 8),
                        _status(),
                        if (_careNotice() case final notice?) ...[
                          const SizedBox(height: 8),
                          notice,
                        ],
                        if (!_game.alive) Text(_bubble),
                        if (!keyboardOpen) ...[
                          const Divider(height: 20),
                          _actions(showTalk: !_systemToolbar),
                          if (!_systemToolbar) ...[
                            const Divider(height: 16),
                            _shortcuts(vertical: true),
                          ],
                        ],
                        ..._messages(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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

  Widget? _careNotice() {
    if (!_game.alive) return null;
    final risks = [
      if (_game.hungerDeadline case final deadline?)
        (title: '굶주림', deadline: deadline, feed: true),
      if (_game.waste >= 3 && _game.hygieneDeadline != null)
        (title: '위생 악화', deadline: _game.hygieneDeadline!, feed: false),
    ]..sort((first, second) => first.deadline.compareTo(second.deadline));
    if (risks.isEmpty) return null;
    final feedFirst = risks.first.feed;
    return DecoratedBox(
      key: const ValueKey('care-warning'),
      decoration: BoxDecoration(
        color: const Color(0xfffce4d5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final risk in risks)
              Text(
                '${risk.title} · ${_remainingCareTime(risk.deadline)}',
                style: const TextStyle(
                  color: Color(0xff743820),
                  fontWeight: FontWeight.w700,
                ),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : _game.inPark
                  ? _changeLocation
                  : feedFirst
                  ? _feeding
                  : _clean,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xff743820),
                backgroundColor: paper,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                _game.inPark
                    ? '집으로 이동'
                    : feedFirst
                    ? '먹이 주기'
                    : '바닥 치우기',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _remainingCareTime(DateTime deadline) {
    final remaining = deadline.difference(_game.at);
    if (remaining.inMinutes < 1) return '1분 미만 남음';
    return [
      if (remaining.inHours > 0) '${remaining.inHours}시간',
      if (remaining.inMinutes % 60 > 0) '${remaining.inMinutes % 60}분',
      '남음',
    ].join(' ');
  }

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
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: urgent ? const Color(0xff9c3e22) : ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );

  String _rewardLabel(PetPlayResult reward) {
    final summary = _statChangesLabel(reward.energyPercent, reward.gains);
    return reward.repeated ? '$summary · 오늘 능력치 보상 받음' : summary;
  }

  String _statChangesLabel(double energyPercent, Map<String, int> changes) => [
    '체력 −${energyPercent.toStringAsFixed(1)}%',
    for (final change in changes.entries)
      '${change.key} ${change.value > 0 ? '+' : '−'}${change.value.abs()}',
  ].join(' · ');

  String _playHint(PetPlay activity) {
    if (activity == PetPlay.disc && !_game.disc) return '가방에 원반이 필요해요.';
    if (!_game.healthy) return '먹이기나 청소가 필요해요.';
    final cost = _game.energyPercent(activity.cost).toStringAsFixed(1);
    return _game.energy < activity.cost ? '체력이 $cost% 필요해요.' : '체력 −$cost%';
  }

  Widget _actions({bool showTalk = true}) {
    if (!_game.alive) {
      return FilledButton.tonalIcon(
        onPressed: _showFarewell,
        icon: const Icon(Icons.photo_album_outlined),
        label: const Text('마지막 인사 보기'),
      );
    }
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
        (
          Icons.auto_awesome_outlined,
          '창가에서 별 보기',
          ready && _game.canFindStar ? _findStar : null,
          _game.starDays.length == PetGame.starNames.length
              ? '별 세 종류를 모두 찾았어요.'
              : _game.canFindStar
              ? null
              : '하루에 별 하나를 찾을 수 있어요.',
        ),
      ],
      if (_game.inPark) ...[
        (
          Icons.trip_origin,
          _canReplay ? '한 번 더 던지기' : '원반 던지기',
          ready && _game.canPlay(PetPlay.disc) ? _offerThrow : null,
          _playHint(PetPlay.disc),
        ),
        (
          Icons.park_outlined,
          '산책하기',
          ready && _game.canPlay(PetPlay.walk) ? _walkInPark : null,
          _playHint(PetPlay.walk),
        ),
        if (_game.searchUnlocked)
          (
            Icons.eco_outlined,
            '솔방울 찾기',
            ready && _game.canFindPinecone ? _offerSearch : null,
            _game.canFindPinecone ? null : '오늘 찾은 솔방울은 가방에 있어요.',
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
        if (_game.ending != null || _game.availableEndings.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _busy ? null : _showGrowthEnding,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text(_game.ending == null ? '성장 엔딩 보기' : '마지막 장면 다시 보기'),
          ),
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

  Widget _mapChip({
    required Rect world,
    required double viewWidth,
    required _SceneAction action,
  }) {
    final width = math.min(116.0, math.max(0.0, viewWidth - 14));
    return Positioned(
      left: (world.left + world.width * action.anchor.dx - width / 2).clamp(
        7.0,
        math.max(7.0, viewWidth - width - 7),
      ),
      top: world.top + world.height * action.anchor.dy - 24,
      width: width,
      child: ActionChip(
        avatar: Icon(action.icon, size: 16, color: action.color),
        backgroundColor: paper,
        label: Text(action.label, textAlign: TextAlign.center),
        onPressed: action.onPressed,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
    );
  }

  Widget _shortcutHotspot(Rect world) => Positioned(
    left: world.left + world.width * _shortcutStone.dx - 24,
    top: world.top + world.height * _shortcutStone.dy - 24,
    width: 48,
    height: 48,
    child: IconButton(
      key: const ValueKey('park-shortcut-stone'),
      tooltip: '낮은 돌 · 나무 샛길',
      alignment: const Alignment(0, -.65),
      padding: EdgeInsets.zero,
      onPressed: _guidingShortcut
          ? null
          : () => _walkInPark(PetParkRoute.shortcut),
      icon: AnimatedScale(
        scale: _guidingShortcut ? 1.25 : 1,
        duration: const Duration(milliseconds: 220),
        child: const Icon(
          Icons.auto_awesome,
          size: 18,
          color: Color(0xfffbd586),
          shadows: [Shadow(color: Color(0xff443116), blurRadius: 4)],
        ),
      ),
    ),
  );

  List<_SceneAction> _sceneActions() => [
    if (_searchTarget != null && _game.canFindPinecone)
      for (final spot in _game.reachableSearchSpots)
        (
          anchor: petParkSearchPositions[spot]!,
          label: spot.label,
          icon: Icons.search,
          color: forest,
          onPressed: () => _guessSearchSpot(spot),
        ),
    if (_placingPinecone && _game.canPlacePinecone)
      for (final spot in PetRoomSpot.values)
        (
          anchor: _pineconePositions[spot]!,
          label: spot.label,
          icon: _game.pineconeSpot == spot ? Icons.check : Icons.eco_outlined,
          color: forest,
          onPressed: _game.pineconeSpot == spot
              ? null
              : () => _placePinecone(spot),
        ),
    if (_throwLaneSelection case final teachWait?)
      for (final lane in PetDiscLane.values)
        (
          anchor: lane == PetDiscLane.near
              ? const Offset(.69, .79)
              : const Offset(.84, .42),
          label: lane == PetDiscLane.near
              ? lane.label
              : switch (_farDiscAim) {
                  null => lane.label,
                  _FarDiscAim.preparing => '준비 중…',
                  _FarDiscAim.ready => '지금 던지기',
                },
          icon: lane == PetDiscLane.far && _farDiscAim == _FarDiscAim.ready
              ? Icons.check_circle_outline
              : Icons.trip_origin,
          color: _DiscPathPainter.color(lane),
          onPressed: lane == PetDiscLane.near
              ? () => _throw(lane: lane, teachWait: teachWait)
              : switch (_farDiscAim) {
                  null => _aimFarDisc,
                  _FarDiscAim.preparing => null,
                  _FarDiscAim.ready => () => _throw(
                    lane: lane,
                    teachWait: teachWait,
                  ),
                },
        ),
  ];

  Widget _scene({bool bounded = false, bool dockChoices = false}) {
    final choices = _speechChoices();
    if (!_choicesWereVisible && choices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSpeech());
    }
    _choicesWereVisible = choices.isNotEmpty;
    final actions = _sceneActions();
    final park = _game.inPark;
    final art = AspectRatio(
      aspectRatio: park ? 1.43 : 1.24,
      child: _world(
        choices: choices,
        actions: dockChoices ? const [] : actions,
        dockChoices: dockChoices,
      ),
    );
    return ClipRRect(
      key: const ValueKey('pet-stage'),
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: park ? const Color(0xffedf0e1) : const Color(0xfff5e8d9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        park ? '공원' : '우리 방',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _busy || !_game.alive
                            ? null
                            : _changeLocation,
                        icon: Icon(
                          park ? Icons.home_outlined : Icons.park_outlined,
                          size: 17,
                        ),
                        label: Text(park ? '집으로' : '공원 산책'),
                        style: FilledButton.styleFrom(
                          backgroundColor: paper,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (dockChoices)
              AnimatedSize(
                alignment: Alignment.topCenter,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Padding(
                  key: _speechAnchor,
                  padding: choices.isEmpty
                      ? EdgeInsets.zero
                      : const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: _speechSwitcher(
                    choices.isEmpty
                        ? null
                        : _speechCard(choices, tail: Alignment.bottomCenter),
                  ),
                ),
              ),
            if (dockChoices && actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final action in actions)
                      TextButton.icon(
                        onPressed: action.onPressed,
                        icon: Icon(action.icon, color: action.color),
                        label: Text(action.label, textAlign: TextAlign.center),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                  ],
                ),
              ),
            if (bounded) Flexible(child: art) else art,
          ],
        ),
      ),
    );
  }

  Widget _world({
    required List<(String, VoidCallback)> choices,
    required List<_SceneAction> actions,
    required bool dockChoices,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final worldWidth = math.min(
        width * (_game.inPark ? 1.04 : 1.22),
        height * 1.5,
      );
      final worldHeight = worldWidth / 1.5;
      final worldX = (width - worldWidth) / 2;
      final worldY = (height - worldHeight) / 2;
      final world = Rect.fromLTWH(worldX, worldY, worldWidth, worldHeight);
      final size = math.max(
        69.0,
        worldWidth *
            (_game.level >= 5
                ? .29
                : _game.level >= 3
                ? .27
                : .24),
      );
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
              Positioned(
                key: const ValueKey('room-artwork'),
                left: worldX,
                top: worldY,
                width: worldWidth,
                height: worldHeight,
                child: _scenery(),
              ),
              for (var index = 0; index < _game.waste && !_game.inPark; index++)
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
              if (!_game.inPark && _game.starDays.contains(petDay(_game.at)))
                Positioned(
                  left: worldX + worldWidth * _window.dx,
                  top: worldY + worldHeight * (_window.dy - .23),
                  child: IgnorePointer(
                    child: Icon(
                      petStarIcons[_game.starDays.length - 1],
                      color: const Color(0xff946427),
                      size: 27,
                    ),
                  ),
                ),
              if (_game.pineconeSpot case final spot? when !_game.inPark)
                Positioned(
                  left: worldX + worldWidth * _pineconePositions[spot]!.dx - 12,
                  top: worldY + worldHeight * _pineconePositions[spot]!.dy - 13,
                  child: Semantics(
                    label: '솔방울 · ${spot.label}',
                    child: IgnorePointer(
                      child: Icon(
                        Icons.eco,
                        key: ValueKey('room-pinecone-${spot.name}'),
                        color: const Color(0xff785233),
                        size: 24,
                      ),
                    ),
                  ),
                ),
              if (_game.keepsake case final item? when !_game.inPark)
                Positioned(
                  left: worldX + worldWidth * _keepsakeSpot.dx - 24,
                  top: worldY + worldHeight * _keepsakeSpot.dy - 24,
                  child: IconButton(
                    key: const ValueKey('pet-keepsake'),
                    tooltip: '기념품 · ${item.ending.keepsake}',
                    onPressed: _game.healthy && !_busy
                        ? _inspectKeepsake
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: paper.withValues(alpha: .85),
                      foregroundColor: forest,
                    ),
                    icon: Icon(_keepsakeIcon(item.ending), size: 20),
                  ),
                ),
              if (_throwLaneSelection != null)
                Positioned.fromRect(
                  rect: world,
                  child: const IgnorePointer(
                    child: CustomPaint(
                      key: ValueKey('park-disc-routes'),
                      painter: _DiscPathPainter(_discPaths),
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
                                _busy || _waitingPose ? 0 : -2.5 * _idle.value,
                              ),
                              child: Transform.flip(
                                flipX: _facingLeft,
                                child: AnimatedSlide(
                                  key: const ValueKey('pet-hop'),
                                  offset: Offset(0, -_hopLift),
                                  duration: _hopDuration,
                                  curve: Curves.easeInOut,
                                  child: AnimatedScale(
                                    key: const ValueKey('pet-wait-pose'),
                                    scale: _waitingPose ? .91 : 1,
                                    duration: const Duration(milliseconds: 220),
                                    alignment: Alignment.bottomCenter,
                                    child: child,
                                  ),
                                ),
                              ),
                            ),
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _blink,
                              builder: (context, blinking, _) => PetSprite(
                                kind: _game.kind,
                                stage: _game.growthStage,
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
              _speechLayer(
                width: width,
                height: height,
                petX: petX,
                petTop: petTop,
                petSize: size,
                choices: choices,
                dockChoices: dockChoices,
                mapActive: actions.isNotEmpty,
              ),
              if (_game.canWalkRoute(PetParkRoute.shortcut) &&
                  (_guidingShortcut || (!_busy && !_hasPlayPrompt)))
                _shortcutHotspot(world),
              for (final action in actions)
                _mapChip(world: world, viewWidth: width, action: action),
              if (_cleaning && _game.alive)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(child: Center(child: _cleanProgress())),
                ),
            ],
          );
        },
      );
    },
  );

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

  Widget _scenery() {
    final picture = Image.asset(
      'assets/pet/${_game.inPark ? 'park' : 'room'}.png',
      fit: BoxFit.fill,
      excludeFromSemantics: true,
    );
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

  List<(String, VoidCallback)> _discChoices(_DiscOffer offer) {
    if (offer == _DiscOffer.remembered) {
      final memory = _talkMemory;
      return [
        if (memory != null &&
            memory.discId == _game.waitDiscId &&
            _game.hasMemoryDisc(memory) &&
            _game.canPlay(PetPlay.disc))
          ('던져줄게', () => _playPhotoDisc(memory.discId!, resumeLesson: true))
        else if (_game.waitOrigin == null && _game.canPlay(PetPlay.disc))
          ('던져줄게', _chooseThrow),
        if (memory != null)
          (
            '그때 어땠어?',
            () {
              setState(() {
                _discOffer = null;
                _waitingPose = false;
                _chatOpen = true;
                _memoryGreeting = true;
              });
              unawaited(_askPet());
            },
          ),
        ('같이 쉬자', _restInPark),
      ];
    }
    return [
      if (offer == _DiscOffer.lesson) ...[
        ('바로 던지기', _chooseThrow),
        ('기다려', _practiceWait),
      ] else ...[
        if (_game.canPlay(PetPlay.disc))
          ('던져줄게', () => _chooseThrow(teachWait: true))
        else
          ('다음에 놀자', _dismissBubble),
        ('같이 쉬자', _restInPark),
      ],
    ];
  }

  List<(String, VoidCallback)> _speechChoices() => switch (_discOffer) {
    final _DiscOffer offer => _discChoices(offer),
    null when _welcomeOffer => [
      (
        '가방 열기',
        () {
          _dismissBubble();
          unawaited(_bag());
        },
      ),
      ('나중에', _dismissBubble),
    ],
    null when _searchOffer => <(String, VoidCallback)>[
      ('같이 찾기', _beginSearch),
      if (_game.canLearnLesson) ('찾아봐', () => _beginSearch(teach: true)),
      ('다음에 찾자', _dismissBubble),
    ],
    null when _keepsakeOffer && _game.keepsake != null =>
      <(String, VoidCallback)>[
        if (_game.personality.active && _game.canUseKeepsake)
          ('공원으로 가져가기', _takeKeepsakeToPark),
        (_homeKeepsakeAction(_game.keepsake!.ending), _playKeepsakeAtHome),
        if (!_game.personality.active && _game.canUseKeepsake)
          ('공원으로 가져가기', _takeKeepsakeToPark),
        ('곁에 두기', _dismissBubble),
      ],
    null when _roomOffer == PetRoomSpot.window => <(String, VoidCallback)>[
      ('같이 보자', _lookOutWindow),
      ('다음에 보자', _dismissBubble),
    ],
    null when _roomOffer == PetRoomSpot.rug => <(String, VoidCallback)>[
      ('같이 앉자', () => _sitTogether('응, 러그가 포근해.')),
      ('다음에 앉자', _dismissBubble),
    ],
    null when _chatOpen => _talkChoices(),
    _ => const <(String, VoidCallback)>[],
  };

  void _revealSpeech() {
    if (!mounted || !_choicesWereVisible) return;
    final anchor = _speechAnchor.currentContext;
    final box = anchor?.findRenderObject();
    if (anchor == null || box is! RenderBox || !box.hasSize) return;
    final viewport = MediaQuery.of(anchor);
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final policy = top < viewport.padding.top
        ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
        : bottom > viewport.size.height - viewport.padding.bottom - 20
        ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
        : null;
    if (policy != null) {
      unawaited(
        Scrollable.ensureVisible(
          anchor,
          alignmentPolicy: policy,
          duration: viewport.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 210),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Widget _speechLayer({
    required double width,
    required double height,
    required double petX,
    required double petTop,
    required double petSize,
    required List<(String, VoidCallback)> choices,
    required bool dockChoices,
    required bool mapActive,
  }) {
    final visible =
        _game.alive &&
        (_sending || _bubble.isNotEmpty) &&
        (!dockChoices || choices.isEmpty);
    final bubbleWidth = math.min(width - 14, 352.0);
    final left = (petX - bubbleWidth / 2).clamp(7.0, width - bubbleWidth - 7);
    final cardWidth = choices.isEmpty
        ? math.min(bubbleWidth, 266.0)
        : bubbleWidth;
    final cardLeft = (petX - cardWidth / 2).clamp(
      left,
      left + bubbleWidth - cardWidth,
    );
    final tailX = ((petX - cardLeft) / cardWidth * 2 - 1).clamp(-.82, .82);
    final slack = bubbleWidth - cardWidth;
    final cardX = slack > 0 ? (cardLeft - left) * 2 / slack - 1 : 0.0;
    final petBottom = petTop + petSize * .7;
    final above = mapActive || petTop >= height - petBottom;
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _SpeechPlacement(
          left: left,
          width: bubbleWidth,
          petEdge: above ? petTop : petBottom,
          above: above,
        ),
        child: KeyedSubtree(
          key: dockChoices ? null : _speechAnchor,
          child: _speechSwitcher(
            visible
                ? Align(
                    key: ValueKey(
                      choices.isEmpty ? 'speech-line' : 'speech-options',
                    ),
                    alignment: Alignment(cardX, 0),
                    heightFactor: 1,
                    child: SizedBox(
                      width: cardWidth,
                      child: _speechCard(
                        choices,
                        tail: Alignment(tailX, 0),
                        above: above,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _speechSwitcher(Widget? child) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final leaving = animation.status == AnimationStatus.reverse;
          final progress = leaving
              ? animation.value
              : Curves.easeOutCubic.transform(animation.value);
          return IgnorePointer(
            ignoring: leaving,
            child: ExcludeSemantics(
              excluding: leaving,
              child: Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, (1 - progress) * (leaving ? -10 : 6)),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
      child: child,
    );
  }

  Widget _speechCard(
    List<(String, VoidCallback)> choices, {
    required Alignment tail,
    bool above = true,
  }) {
    final pointer = Align(
      alignment: tail,
      child: CustomPaint(
        size: const Size(12, 7),
        painter: _BubbleTail(above ? AxisDirection.down : AxisDirection.up),
      ),
    );
    final preview = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Text(
        _sending ? '…' : _bubble,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, height: 1.25),
      ),
    );
    return Column(
      key: ValueKey(choices.isEmpty ? 'pet-speech' : 'pet-choices'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!above) pointer,
        Material(
          key: choices.isEmpty ? null : const ValueKey('pet-choice-bubble'),
          color: paper,
          borderRadius: BorderRadius.circular(15),
          elevation: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: _sending
                          ? preview
                          : Tooltip(
                              message: '대사 전체 보기',
                              child: InkWell(
                                onTap: () => _sheet<void>(
                                  '${_game.kind.label}의 말',
                                  [SelectableText(_bubble)],
                                ),
                                child: preview,
                              ),
                            ),
                    ),
                  ),
                  if (!_sending)
                    IconButton(
                      key: const ValueKey('pet-speech-close'),
                      tooltip: '말풍선 닫기',
                      onPressed: _dismissBubble,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              if (choices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final (label, action) in choices)
                        TextButton(
                          onPressed: action,
                          style: TextButton.styleFrom(
                            foregroundColor: forest,
                            backgroundColor: mint,
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(label, textAlign: TextAlign.center),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (above) pointer,
      ],
    );
  }
}

class _SpeechPlacement extends SingleChildLayoutDelegate {
  const _SpeechPlacement({
    required this.left,
    required this.width,
    required this.petEdge,
    required this.above,
  });

  final double left;
  final double width;
  final double petEdge;
  final bool above;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: width);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = above ? petEdge - childSize.height - 3 : petEdge + 3;
    return Offset(
      left,
      top.clamp(4.0, math.max(4.0, size.height - childSize.height - 4)),
    );
  }

  @override
  bool shouldRelayout(_SpeechPlacement previous) =>
      previous.left != left ||
      previous.width != width ||
      previous.petEdge != petEdge ||
      previous.above != above;
}

class _DiscPathPainter extends CustomPainter {
  const _DiscPathPainter(this.paths);

  final Map<PetDiscLane, List<Offset>> paths;

  static Color color(PetDiscLane lane) => switch (lane) {
    PetDiscLane.near => const Color(0xff245d46),
    PetDiscLane.far => const Color(0xff984923),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rim = Paint()..color = paper;
    for (final entry in paths.entries) {
      final ink = Paint()..color = color(entry.key);
      final trail = Path()
        ..moveTo(
          entry.value.first.dx * size.width,
          entry.value.first.dy * size.height,
        );
      for (final point in entry.value.skip(1)) {
        trail.lineTo(point.dx * size.width, point.dy * size.height);
      }
      for (final line in trail.computeMetrics()) {
        for (double distance = 8; distance < line.length; distance += 10) {
          final point = line.getTangentForOffset(distance)!.position;
          canvas.drawCircle(point, 3.0, rim);
          canvas.drawCircle(point, 2.0, ink);
        }
      }
      final target = entry.value.last;
      final center = Offset(target.dx * size.width, target.dy * size.height);
      canvas.drawCircle(center, 8.0, rim);
      canvas.drawCircle(center, 6.0, ink);
    }
  }

  @override
  bool shouldRepaint(_DiscPathPainter oldDelegate) =>
      oldDelegate.paths != paths;
}

class _BubbleTail extends CustomPainter {
  const _BubbleTail(this.direction);

  final AxisDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final points = switch (direction) {
      AxisDirection.up => [Offset(0, h), Offset(w / 2, 0), Offset(w, h)],
      _ => [Offset.zero, Offset(w / 2, h), Offset(w, 0)],
    };
    canvas.drawPath(Path()..addPolygon(points, true), Paint()..color = paper);
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) =>
      direction != oldDelegate.direction;
}
