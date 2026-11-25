import 'dart:convert';
import 'dart:math' as math;

const hour = Duration(hours: 1);
const recoveryInterval = Duration(minutes: 30);

String petDay(DateTime date) => '${date.year}-${date.month}-${date.day}';

int petDayDifference(DateTime later, DateTime earlier) => DateTime.utc(
  later.year,
  later.month,
  later.day,
).difference(DateTime.utc(earlier.year, earlier.month, earlier.day)).inDays;

enum PetActivity { care, play, bond }

enum PetRoomSpot {
  window('창가'),
  rug('러그 옆');

  const PetRoomSpot(this.label);
  final String label;
}

enum PetParkRoute { bench, shortcut }

enum PetDiscLane {
  near('가까운 잔디'),
  far('벤치 너머');

  const PetDiscLane(this.label);
  final String label;
}

enum PetSearchSpot {
  bench('벤치 옆', '앉아서 쉬던 자리 근처야.'),
  tree('나무 밑', '큰 그늘이 있는 쪽이야.'),
  path('길가', '산책길 가장자리를 봐!'),
  grove('나무 뒤 풀밭', '돌을 넘어온 길 끝에 풀이 흔들려!');

  const PetSearchSpot(this.label, this.hint);
  final String label;
  final String hint;
}

enum PetParkIdea { disc, search, walk, rest }

typedef MealPreview = ({
  int fullness,
  int waste,
  DateTime hungryAt,
  DateTime? nextWaste,
  DateTime unattendedDeadline,
  String risk,
});

enum PetEnding {
  lastDisc('마지막 원반', '작은 원반', '네가 가르쳐 준 대로 기다렸다가, 마지막 원반을 받아왔어.'),
  pinecone('우리가 찾은 솔방울', '작은 솔방울', '네가 찾아보라고 했던 곳에 다시 와 봤어.'),
  stars('우리 별자리', '별 장식', '우리 창가에서 찾은 세 별이 다시 떠올랐어.'),
  window('창가의 오후', '작은 발자국', '함께 지낸 방에 내 작은 발자국을 남길게.');

  const PetEnding(this.title, this.keepsake, this.line);

  final String title;
  final String keepsake;
  final String line;
}

typedef PetKeepsake = ({PetKind from, PetEnding ending});

enum PetStage { baby, young, adult }

enum PetKind {
  dongle('동글귀', '살구색 둥근 귀와 폭신한 꼬리'),
  leaf('잎귀', '새싹 귀와 연두색 몸'),
  star('별꼬리', '남색 몸과 금빛 별 꼬리');

  const PetKind(this.label, this.description);

  final String label;
  final String description;

  static PetKind fromName(Object? value) =>
      values.where((kind) => kind.name == value).firstOrNull ?? dongle;
}

enum PetPlay {
  disc('원반 던지기', 32),
  walk('산책하기', 16);

  const PetPlay(this.label, this.cost);

  final String label;
  final int cost;
}

typedef PetPlayResult = ({
  double energyPercent,
  Map<String, int> gains,
  bool discBroke,
  bool repeated,
});

enum PetTalk { question, encouragement, concern }

typedef PetTalkResult = ({
  double energyPercent,
  Map<String, int> changes,
  bool bored,
  bool repeated,
});

class PetDisc {
  const PetDisc(this.maximum, this.remaining, {this.origin, this.id});

  final int maximum;
  final int remaining;
  final String? origin;
  final int? id;

  Map<String, Object> toJson() => {
    'maximum': maximum,
    'remaining': remaining,
    'origin': ?origin,
    'id': ?id,
  };
}

class PetMemory {
  const PetMemory(this.title, this.at, {this.discId, this.discLane});
  final String title;
  final DateTime at;
  final int? discId;
  final PetDiscLane? discLane;

  String get key =>
      '${at.toIso8601String()}:${discId ?? ''}:${discLane?.name ?? ''}:$title';

  Map<String, Object> toJson() => {
    'title': title,
    'at': at.toIso8601String(),
    'discId': ?discId,
    'discLane': ?discLane?.name,
  };
}

class PetPersonality {
  const PetPersonality(this.bits);

  final int bits;

  bool get active => (bits & 2) != 0;
  bool get curious => (bits & 4) != 0;
  String get code => [
    (bits & 1) != 0 ? 'E' : 'I',
    (bits & 4) != 0 ? 'N' : 'S',
    (bits & 8) != 0 ? 'F' : 'T',
    active ? 'P' : 'J',
  ].join();

  List<String> get traits => [
    (bits & 1) != 0 ? '먼저 제안하기' : '이야기에 호응하기',
    active ? '활발하게 놀기' : '느긋하게 쉬기',
    (bits & 4) != 0 ? '새로운 것을 좋아함' : '익숙한 것을 좋아함',
    (bits & 8) != 0 ? '상상해서 표현하기' : '솔직하게 표현하기',
  ];
}

class PetGame {
  static const hungerGrace = Duration(hours: 18);
  static const shortReplyCost = 8;
  static const starNames = ['반짝별', '꼬리별', '쌍둥이별'];
  static const benchRecovery = 32;
  static const benchInterval = Duration(minutes: 10);

  PetGame(
    DateTime now, {
    this.kind = PetKind.dongle,
    PetPersonality? personality,
  }) : at = now,
       born = now,
       nextHunger = now.add(hour * 6),
       personality = personality ?? PetPersonality(math.Random().nextInt(16)) {
    suppliedDay = petDay(now);
    raisedKinds.add(kind);
  }

  final PetKind kind;
  final PetPersonality personality;
  final Set<PetKind> raisedKinds = {};
  DateTime at;
  DateTime born;
  DateTime? nextHunger;
  DateTime? hungerDeadline;
  DateTime? hygieneDeadline;
  DateTime? lastWaste;
  DateTime? nextRecovery;
  DateTime? lastBenchRest;
  DateTime? waitTaughtAt;
  DateTime? waitRecalledAt;
  String? waitOrigin;
  int? waitDiscId;
  int _discSerial = 0;
  DateTime? searchTaughtAt;
  DateTime? searchRecalledAt;
  DateTime? lastSearchAt;
  PetSearchSpot? lastSearchSpot;
  PetSearchSpot? taughtSearchSpot;
  DateTime? lastMainSearchAt;
  DateTime? lastShortcutSearchAt;
  PetParkRoute parkRoute = PetParkRoute.bench;
  bool shortcutGuided = false;
  bool searchUnlocked = false;
  PetRoomSpot? pineconeSpot;
  final Map<PetRoomSpot, String> roomOfferDays = {};
  bool keepsakeUsed = false;
  PetEnding? ending;
  PetKeepsake? keepsake;
  final Set<String> starDays = {};
  final List<String> starTitles = [];
  final List<String> recentReplies = [];
  final List<DateTime> digestion = [];
  final List<PetMemory> memories = [];
  final List<PetDisc> discs = [];
  final Set<PetActivity> activities = {};
  final Set<String> _practicedToday = {};
  final Map<String, int> _talkCounts = {};
  String _practiceDay = '';
  String _talkDay = '';
  bool _boredToday = false;
  String suppliedDay = '';
  String affectionDay = '';
  String greetingDay = '';
  String greeting = '';
  String lastMemory = '';
  String lastWarning = '';
  String death = '';
  int fullness = 2;
  int waste = 0;
  int affection = 0;
  int mood = 5;
  int confidence = 5;
  int agility = 0;
  int curiosity = 0;
  int level = 1;
  int energy = 384;
  int apples = 0;
  int pantry = 3;
  int plays = 0;
  int timeOffsetMs = 0;
  bool inPark = false;
  bool demoClock = false;

  bool get alive => death.isEmpty;
  bool get disc => discs.isNotEmpty;
  bool get healthy => alive && hungerDeadline == null && waste < 3;
  bool get canTalk => healthy && energy >= shortReplyCost;
  int get maxFullness => level < 3
      ? 3
      : level < 5
      ? 4
      : 5;
  int get maxEnergy => 320 + 64 * level;
  bool get canRecoverAtBench =>
      alive &&
      inPark &&
      energy < maxEnergy &&
      (lastBenchRest == null || at.difference(lastBenchRest!) >= benchInterval);
  double energyPercent(int amount) => amount * 100 / maxEnergy;
  int get nextAffection => level < 3 ? 3 : 5;
  DateTime? get nextStageAt => switch (level) {
    < 3 => born.add(hour * math.max(18, 24 - (math.max(affection, 3) - 3) * 3)),
    < 5 => born.add(hour * 48),
    _ => null,
  };
  PetStage get growthStage => switch (level) {
    < 3 => PetStage.baby,
    < 5 => PetStage.young,
    _ => PetStage.adult,
  };
  String get stage => switch (growthStage) {
    PetStage.baby => '아기',
    PetStage.young => '꼬마',
    PetStage.adult => '성체',
  };
  String get moodLabel => mood >= 7
      ? '신나요'
      : mood >= 4
      ? '좋아요'
      : '시무룩해요';
  String get healthLabel => !alive
      ? '지난 펫'
      : hungerDeadline != null && waste >= 3
      ? '먹이와 청소가 필요해요'
      : hungerDeadline != null
      ? '배고파요'
      : waste >= 3
      ? '청소가 필요해요'
      : '건강해요';

  DateTime now() => DateTime.now().add(Duration(milliseconds: timeOffsetMs));

  DateTime? _growthAt() {
    if (!healthy) return null;
    return switch (level) {
      1 when affection >= 1 => born,
      2 when affection >= 3 => nextStageAt,
      3 when affection >= 5 => born.add(hour * 36),
      4 when affection >= 5 => nextStageAt,
      _ => null,
    };
  }

  void _grow() {
    while (true) {
      final next = _growthAt();
      if (next == null || next.isAfter(at)) return;
      level++;
      energy += 64;
    }
  }

  void advance(DateTime target) {
    if (target.isBefore(at) || !alive) return;
    _grow();
    while (alive) {
      final events = [
        ?nextHunger,
        ?hungerDeadline,
        ?hygieneDeadline,
        ?nextRecovery,
        if (digestion.isNotEmpty) digestion.first,
        if (_growthAt() case final DateTime time) time,
      ]..sort();
      if (events.isEmpty || events.first.isAfter(target)) break;
      at = events.first;
      if (at == hungerDeadline || at == hygieneDeadline) {
        death = at == hungerDeadline ? '굶주림' : '위생 악화';
        return;
      }
      if (at == nextHunger) {
        fullness--;
        nextHunger = fullness == 0 ? null : at.add(hour * 6);
        if (fullness == 0) hungerDeadline = at.add(hungerGrace);
      }
      if (digestion.isNotEmpty && at == digestion.first) {
        digestion.removeAt(0);
        lastWaste = at;
        if (waste < 3) {
          waste++;
          final candidate = at.add(hour * [48, 24, 8][waste - 1]);
          final shortened = hygieneDeadline?.subtract(hour * 2);
          hygieneDeadline = shortened != null && shortened.isBefore(candidate)
              ? shortened
              : candidate;
          if (!hygieneDeadline!.isAfter(at)) {
            death = '위생 악화';
            return;
          }
        }
      }
      _grow();
      if (at == nextRecovery) {
        energy = math.min(maxEnergy, energy + 64);
        nextRecovery = energy < maxEnergy ? at.add(recoveryInterval) : null;
      }
      if (energy >= maxEnergy) nextRecovery = null;
    }
    at = target;
    if (suppliedDay != petDay(at)) {
      suppliedDay = petDay(at);
      pantry = math.max(pantry, maxFullness);
    }
    memories.removeWhere((memory) => petDayDifference(at, memory.at) > 30);
  }

  void mark(PetActivity activity) {
    if (!alive) return;
    if (affectionDay != petDay(at)) {
      affectionDay = petDay(at);
      activities.clear();
    }
    if (activities.add(activity)) affection++;
    _grow();
  }

  MealPreview? previewMeal({required bool apple, int portions = 1}) {
    if (portions < 1) return null;
    final preview = PetGame.decode(encode());
    for (var i = 0; i < portions; i++) {
      if (!preview.feed(apple: apple)) return null;
    }
    final fullness = preview.fullness;
    final waste = math.min(3, preview.waste + preview.digestion.length);
    final nextWaste = preview.digestion.firstOrNull;
    final hungryAt = preview.at.add(hour * (6 * fullness));
    preview.advance(hungryAt.add(hungerGrace));
    return (
      fullness: fullness,
      waste: waste,
      hungryAt: hungryAt,
      nextWaste: nextWaste,
      unattendedDeadline: preview.at,
      risk: preview.death,
    );
  }

  bool feed({required bool apple}) {
    if (!alive || inPark || fullness >= maxFullness) return false;
    if (apple ? apples == 0 : pantry == 0 && (fullness != 0 || apples > 0)) {
      return false;
    }
    if (apple) {
      apples--;
    } else if (pantry > 0) {
      pantry--;
    }
    fullness++;
    hungerDeadline = null;
    nextHunger = at.add(hour * 6);
    final delay = switch (maxFullness - fullness) {
      0 => 2,
      1 => 4,
      _ => 6,
    };
    var next = at.add(hour * delay);
    if (digestion.isNotEmpty && digestion.first.isBefore(next)) {
      next = digestion.first;
    }
    final previous = lastWaste?.add(hour * 3);
    if (previous != null && previous.isAfter(next)) next = previous;
    final count = digestion.length + 1;
    digestion
      ..clear()
      ..addAll(List.generate(count, (index) => next.add(hour * (3 * index))));
    mark(PetActivity.care);
    return true;
  }

  bool clean() {
    if (!alive || inPark || waste == 0) return false;
    waste = 0;
    hygieneDeadline = null;
    mark(PetActivity.care);
    return true;
  }

  void moodChange(int change) => mood = (mood + change).clamp(0, 10);

  bool canPlay(PetPlay activity) =>
      healthy &&
      inPark &&
      energy >= activity.cost &&
      switch (activity) {
        PetPlay.disc => disc,
        PetPlay.walk => true,
      };

  bool canWalkRoute(PetParkRoute route) =>
      canPlay(PetPlay.walk) && (route == PetParkRoute.bench || level >= 3);

  bool canThrowLane(PetDiscLane lane) =>
      canPlay(PetPlay.disc) && (lane == PetDiscLane.near || level >= 4);

  bool get canPlacePinecone =>
      healthy && !inPark && level >= 2 && lastSearchAt != null;

  PetRoomSpot? takeRoomOffer() {
    final spot = pineconeSpot;
    final day = petDay(at);
    if (!healthy || inPark || spot == null || roomOfferDays[spot] == day) {
      return null;
    }
    roomOfferDays[spot] = day;
    return spot;
  }

  bool placePinecone(PetRoomSpot spot) {
    if (!canPlacePinecone || pineconeSpot == spot) return false;
    pineconeSpot = spot;
    return true;
  }

  PetPlayResult? play(
    PetPlay activity, {
    bool teachWait = false,
    PetParkRoute route = PetParkRoute.bench,
    PetDiscLane lane = PetDiscLane.near,
  }) {
    final available = switch (activity) {
      PetPlay.disc => canThrowLane(lane),
      PetPlay.walk => canWalkRoute(route),
    };
    if (!available) return null;
    final percent = energyPercent(activity.cost);
    _useEnergy(activity.cost);
    final beforeMood = mood;
    final beforeConfidence = confidence;
    final beforeAgility = agility;
    final beforeCuriosity = curiosity;
    final day = petDay(at);
    if (_practiceDay != day) {
      _practiceDay = day;
      _practicedToday.clear();
    }
    final practiced = _practicedToday.add(
      activity == PetPlay.disc ? activity.name : route.name,
    );
    var discBroke = false;
    if (practiced) moodChange(1);
    switch (activity) {
      case PetPlay.disc:
        parkRoute = PetParkRoute.bench;
        final used = discs.first;
        final id = used.id ?? (used.origin == null ? null : ++_discSerial);
        discBroke = used.remaining == 1;
        if (discBroke) {
          discs.removeAt(0);
        } else {
          discs[0] = PetDisc(
            used.maximum,
            used.remaining - 1,
            origin: used.origin,
            id: id,
          );
        }
        if (used.origin case final title?) {
          memories.add(PetMemory(title, at, discId: id, discLane: lane));
        }
        plays++;
        if (practiced) {
          confidence = math.min(10, confidence + 1);
          agility = math.min(10, agility + 1);
        }
        mark(PetActivity.play);
        if (teachWait && canLearnLesson) {
          waitTaughtAt = at;
          waitOrigin = used.origin;
          waitDiscId = id;
          mark(PetActivity.bond);
        }
      case PetPlay.walk:
        parkRoute = route;
        searchUnlocked = true;
        if (practiced) curiosity = math.min(10, curiosity + 1);
        walk();
    }
    return (
      energyPercent: percent,
      discBroke: discBroke,
      repeated: !practiced,
      gains: {
        if (mood > beforeMood) '기분': mood - beforeMood,
        if (confidence > beforeConfidence) '자신감': confidence - beforeConfidence,
        if (agility > beforeAgility) '민첩': agility - beforeAgility,
        if (curiosity > beforeCuriosity) '호기심': curiosity - beforeCuriosity,
      },
    );
  }

  bool get canLearnLesson => waitTaughtAt == null && searchTaughtAt == null;

  bool _canRecall(DateTime? taught, DateTime? recalled) =>
      healthy &&
      inPark &&
      taught != null &&
      recalled == null &&
      petDayDifference(at, taught) >= 1;

  bool recallWait() {
    if (!_canRecall(waitTaughtAt, waitRecalledAt)) return false;
    waitRecalledAt = at;
    return true;
  }

  bool recallSearch() {
    if (!_canRecall(searchTaughtAt, searchRecalledAt)) return false;
    searchRecalledAt = at;
    return true;
  }

  bool get canFindPinecone {
    final previous = parkRoute == PetParkRoute.shortcut
        ? lastShortcutSearchAt
        : lastMainSearchAt;
    return healthy &&
        inPark &&
        searchUnlocked &&
        (previous == null || petDayDifference(at, previous) > 0);
  }

  List<PetSearchSpot> get reachableSearchSpots =>
      parkRoute == PetParkRoute.shortcut
      ? const [PetSearchSpot.grove]
      : const [PetSearchSpot.bench, PetSearchSpot.tree, PetSearchSpot.path];

  PetSearchSpot get searchSpot {
    final day = petDayDifference(at, DateTime(2000));
    final spots = reachableSearchSpots;
    return spots[(day + personality.bits) % spots.length];
  }

  bool findPinecone(PetSearchSpot spot, {bool teach = false}) {
    if (!canFindPinecone || spot != searchSpot) return false;
    lastSearchAt = at;
    lastSearchSpot = spot;
    if (parkRoute == PetParkRoute.shortcut) {
      lastShortcutSearchAt = at;
    } else {
      lastMainSearchAt = at;
    }
    curiosity = math.min(10, curiosity + 1);
    memories.add(PetMemory('${spot.label}에서 찾은 솔방울', at));
    mark(PetActivity.play);
    if (teach && canLearnLesson) {
      searchTaughtAt = at;
      taughtSearchSpot = spot;
      mark(PetActivity.bond);
    }
    return true;
  }

  PetParkIdea get parkIdea {
    if (personality.active && confidence >= 5 && canPlay(PetPlay.disc)) {
      return PetParkIdea.disc;
    }
    if ((personality.curious || personality.active) && canFindPinecone) {
      return PetParkIdea.search;
    }
    if (personality.active && canPlay(PetPlay.walk)) return PetParkIdea.walk;
    return PetParkIdea.rest;
  }

  bool get canUseKeepsakeAtHome =>
      healthy && !inPark && !keepsakeUsed && ending == null && keepsake != null;

  bool get canUseKeepsake =>
      canUseKeepsakeAtHome &&
      (keepsake?.ending == PetEnding.lastDisc ||
          keepsake?.ending == PetEnding.pinecone);

  bool useKeepsakeAtHome() {
    if (!canUseKeepsakeAtHome) return false;
    final item = keepsake!.ending;
    keepsakeUsed = true;
    switch (item) {
      case PetEnding.lastDisc:
        agility = math.min(10, agility + 1);
      case PetEnding.pinecone || PetEnding.stars:
        curiosity = math.min(10, curiosity + 1);
      case PetEnding.window:
        moodChange(1);
    }
    memories.add(PetMemory('우리 방에서 만난 ${item.keepsake}', at));
    mark(PetActivity.bond);
    return true;
  }

  bool useKeepsake() {
    if (!canUseKeepsake) return false;
    keepsakeUsed = true;
    if (keepsake?.ending == PetEnding.lastDisc) {
      discs.insert(0, const PetDisc(1, 1));
    } else {
      searchUnlocked = true;
    }
    return true;
  }

  bool get canFindStar =>
      healthy &&
      !inPark &&
      starDays.length < starNames.length &&
      !starDays.contains(petDay(at));

  String? findStar({String name = ''}) {
    if (!canFindStar) return null;
    final clean = name.trim();
    final title = clean.isEmpty ? starNames[starDays.length] : clean;
    starDays.add(petDay(at));
    starTitles.add(title);
    memories.add(PetMemory('창가의 $title', at));
    mark(PetActivity.play);
    return title;
  }

  List<PetEnding> get availableEndings {
    if (!healthy || level < 5) return const [];
    return [
      if (waitRecalledAt != null) PetEnding.lastDisc,
      if (searchRecalledAt != null) PetEnding.pinecone,
      if (starDays.length == starNames.length) PetEnding.stars,
      PetEnding.window,
    ];
  }

  bool finish(PetEnding choice) {
    if (ending != null || !availableEndings.contains(choice)) return false;
    ending = choice;
    keepsake = (from: kind, ending: choice);
    return true;
  }

  PetDisc? addFinds(
    String title, {
    required bool apple,
    required bool frisbee,
    math.Random? random,
  }) {
    if (!alive) return null;
    if (apple) apples++;
    PetDisc? found;
    if (frisbee) {
      final roll = (random ?? math.Random()).nextInt(100);
      final durability = switch (roll) {
        < 10 => 1,
        < 30 => 2,
        < 65 => 3,
        < 90 => 4,
        _ => 5,
      };
      found = PetDisc(
        durability,
        durability,
        origin: title.isEmpty ? null : title,
        id: ++_discSerial,
      );
      discs.add(found);
    }
    if (title.isNotEmpty) memories.add(PetMemory(title, at));
    return found;
  }

  void walk() {
    if (!healthy) return;
    final title = parkRoute == PetParkRoute.shortcut ? '나무 샛길 산책' : '공원 산책';
    if (!memories.any((m) => m.title == title && petDay(m.at) == petDay(at))) {
      memories.add(PetMemory(title, at));
    }
    mark(PetActivity.play);
  }

  String _talkKey(PetTalk choice, String topic) => '${choice.name}:$topic';

  bool willBeBored(PetTalk choice, String topic) =>
      choice != PetTalk.concern &&
      _talkDay == petDay(at) &&
      !_boredToday &&
      _talkCounts[_talkKey(choice, topic)] == (personality.curious ? 2 : 3);

  PetTalkResult? replyTo(
    PetTalk choice,
    String topic, {
    int? shownTokens,
    math.Random? random,
  }) {
    if (!canTalk) return null;
    final bored = willBeBored(choice, topic);
    final cost = bored ? shortReplyCost : shownTokens ?? shortReplyCost;
    if (cost <= 0 || cost > energy) return null;
    final day = petDay(at);
    if (_talkDay != day) {
      _talkDay = day;
      _talkCounts.clear();
      _boredToday = false;
    }
    final key = _talkKey(choice, topic);
    final repeated = (_talkCounts[key] ?? 0) > 0;
    _talkCounts[key] = math.min(4, (_talkCounts[key] ?? 0) + 1);
    final beforeMood = mood;
    final beforeConfidence = confidence;

    var change = 0;
    if (bored) {
      _boredToday = true;
      moodChange(-1);
    } else if (choice == PetTalk.concern ||
        (choice == PetTalk.encouragement && !repeated)) {
      final likely = (random ?? math.Random()).nextInt(100) < 70;
      change = switch (choice) {
        PetTalk.concern when repeated => likely ? -2 : -1,
        PetTalk.concern => likely ? -1 : 0,
        _ => likely ? 1 : 0,
      };
      if (personality.active) {
        confidence = (confidence + change).clamp(0, 10);
      } else {
        moodChange(change);
      }
    }
    final percent = energyPercent(cost);
    if (choice == PetTalk.concern || bored) {
      _useEnergy(cost);
    } else {
      spend(cost);
    }
    return (
      energyPercent: percent,
      bored: bored,
      repeated: repeated,
      changes: {
        if (mood != beforeMood) '기분': mood - beforeMood,
        if (confidence != beforeConfidence)
          '자신감': confidence - beforeConfidence,
      },
    );
  }

  void spend(int tokens) {
    if (!alive || tokens <= 0) return;
    _useEnergy(tokens);
    mark(PetActivity.bond);
  }

  void _useEnergy(int amount) {
    energy = math.max(0, energy - amount);
    nextRecovery = at.add(recoveryInterval);
  }

  int recoverAtBench() {
    if (!canRecoverAtBench) return 0;
    final recovered = math.min(benchRecovery, maxEnergy - energy);
    lastBenchRest = at;
    energy += recovered;
    if (energy == maxEnergy) nextRecovery = null;
    return recovered;
  }

  PetMemory? get waitMemory => memories.reversed
      .where(
        (memory) =>
            waitDiscId != null &&
            memory.discId == waitDiscId &&
            memory.at == waitTaughtAt,
      )
      .firstOrNull;

  bool hasMemoryDisc(PetMemory memory) =>
      memory.discId != null && discs.any((disc) => disc.id == memory.discId);

  bool selectPhotoDisc(int id) {
    final index = discs.indexWhere((disc) => disc.id == id);
    if (index < 0) return false;
    if (index > 0) discs.insert(0, discs.removeAt(index));
    return true;
  }

  PetMemory? get nextMemory {
    final candidates = memories.reversed.where((memory) {
      final age = petDayDifference(at, memory.at);
      return age > 0 && age <= 30;
    }).toList();
    final unused = candidates.where(
      (memory) =>
          memory.key != lastMemory && memory.at.toIso8601String() != lastMemory,
    );
    final latest = unused.firstOrNull ?? candidates.firstOrNull;
    if (latest == null) return null;
    final available = unused.isEmpty ? candidates : unused;
    return available
            .where(
              (memory) =>
                  petDayDifference(latest.at, memory.at) == 0 &&
                  memory.discLane != null,
            )
            .firstOrNull ??
        latest;
  }

  String encode() => jsonEncode({
    'kind': kind.name,
    'personality': personality.bits,
    'raisedKinds': raisedKinds.map((kind) => kind.name).toList(),
    'at': at.toIso8601String(),
    'born': born.toIso8601String(),
    'nextHunger': nextHunger?.toIso8601String(),
    'hungerDeadline': hungerDeadline?.toIso8601String(),
    'hygieneDeadline': hygieneDeadline?.toIso8601String(),
    'lastWaste': lastWaste?.toIso8601String(),
    'nextRecovery': nextRecovery?.toIso8601String(),
    'lastBenchRest': lastBenchRest?.toIso8601String(),
    'waitTaughtAt': waitTaughtAt?.toIso8601String(),
    'waitRecalledAt': waitRecalledAt?.toIso8601String(),
    'waitOrigin': waitOrigin,
    'waitDiscId': waitDiscId,
    'discSerial': _discSerial,
    'searchTaughtAt': searchTaughtAt?.toIso8601String(),
    'searchRecalledAt': searchRecalledAt?.toIso8601String(),
    'lastSearchAt': lastSearchAt?.toIso8601String(),
    'lastSearchSpot': lastSearchSpot?.name,
    'taughtSearchSpot': taughtSearchSpot?.name,
    'searchUnlocked': searchUnlocked,
    'parkRoute': parkRoute.name,
    'shortcutGuided': shortcutGuided,
    'lastMainSearchAt': lastMainSearchAt?.toIso8601String(),
    'lastShortcutSearchAt': lastShortcutSearchAt?.toIso8601String(),
    'pineconeSpot': pineconeSpot?.name,
    'roomOfferDays': roomOfferDays.map((spot, day) => MapEntry(spot.name, day)),
    'keepsakeUsed': keepsakeUsed,
    'starTitles': starTitles,
    'recentReplies': recentReplies,
    'starDays': starDays.toList(),
    'ending': ending?.name,
    if (keepsake case final item?)
      'keepsake': {'from': item.from.name, 'ending': item.ending.name},
    'digestion': digestion.map((time) => time.toIso8601String()).toList(),
    'memories': memories.map((memory) => memory.toJson()).toList(),
    'activities': activities.map((activity) => activity.name).toList(),
    'practiceDay': _practiceDay,
    'practicedToday': _practicedToday.toList(),
    'talkDay': _talkDay,
    'talkCounts': _talkCounts,
    'boredToday': _boredToday,
    'suppliedDay': suppliedDay,
    'affectionDay': affectionDay,
    'greetingDay': greetingDay,
    'greeting': greeting,
    'lastMemory': lastMemory,
    'lastWarning': lastWarning,
    'death': death,
    'fullness': fullness,
    'waste': waste,
    'affection': affection,
    'mood': mood,
    'confidence': confidence,
    'agility': agility,
    'curiosity': curiosity,
    'level': level,
    'energy': energy,
    'apples': apples,
    'pantry': pantry,
    'plays': plays,
    'timeOffsetMs': timeOffsetMs,
    'disc': disc,
    'discs': discs.map((item) => item.toJson()).toList(),
    'inPark': inPark,
    'demoClock': demoClock,
  });

  static PetGame decode(String snapshot) {
    final json = jsonDecode(snapshot) as Map<String, dynamic>;
    DateTime? date(String key) => DateTime.tryParse(json[key] as String? ?? '');
    String string(String key) => json[key] as String? ?? '';
    int integer(String key, int fallback) => json[key] as int? ?? fallback;
    PetEnding? savedEnding(Object? value) =>
        PetEnding.values.where((ending) => ending.name == value).firstOrNull;
    PetSearchSpot? savedSpot(Object? value) =>
        PetSearchSpot.values.where((spot) => spot.name == value).firstOrNull;
    final born = date('born')!;
    final game =
        PetGame(
            date('at')!,
            kind: PetKind.fromName(json['kind']),
            personality: PetPersonality(
              integer(
                'personality',
                born.millisecondsSinceEpoch % 16,
              ).clamp(0, 15),
            ),
          )
          ..born = born
          ..nextHunger = date('nextHunger')
          ..hungerDeadline = date('hungerDeadline')
          ..hygieneDeadline = date('hygieneDeadline')
          ..lastWaste = date('lastWaste')
          ..nextRecovery = date('nextRecovery')
          ..lastBenchRest = date('lastBenchRest')
          ..waitTaughtAt = date('waitTaughtAt')
          ..waitRecalledAt = date('waitRecalledAt')
          ..waitOrigin = json['waitOrigin'] as String?
          ..waitDiscId = json['waitDiscId'] as int?
          .._discSerial = integer('discSerial', 0)
          ..searchTaughtAt = date('searchTaughtAt')
          ..searchRecalledAt = date('searchRecalledAt')
          ..lastSearchAt = date('lastSearchAt')
          ..lastSearchSpot = savedSpot(json['lastSearchSpot'])
          ..taughtSearchSpot = savedSpot(json['taughtSearchSpot'])
          ..searchUnlocked = json['searchUnlocked'] == true
          ..shortcutGuided = json['shortcutGuided'] == true
          ..parkRoute =
              json['parkRoute'] == PetParkRoute.shortcut.name &&
                  json['inPark'] == true &&
                  integer('level', 1) >= 3
              ? PetParkRoute.shortcut
              : PetParkRoute.bench
          ..lastMainSearchAt = json.containsKey('lastMainSearchAt')
              ? date('lastMainSearchAt')
              : date('lastSearchAt')
          ..lastShortcutSearchAt = date('lastShortcutSearchAt')
          ..pineconeSpot =
              PetRoomSpot.values
                  .where((spot) => spot.name == json['pineconeSpot'])
                  .firstOrNull ??
              (json['placedPinecone'] == true ? PetRoomSpot.rug : null)
          ..keepsakeUsed = json['keepsakeUsed'] == true
          ..ending = savedEnding(json['ending'])
          ..suppliedDay = string('suppliedDay')
          ..affectionDay = string('affectionDay')
          .._practiceDay = string('practiceDay')
          .._talkDay = string('talkDay')
          .._boredToday = json['boredToday'] == true
          ..greetingDay = string('greetingDay')
          ..greeting = string('greeting')
          ..lastMemory = string('lastMemory')
          ..lastWarning = string('lastWarning')
          ..death = string('death')
          ..fullness = integer('fullness', 2)
          ..waste = integer('waste', 0)
          ..affection = integer('affection', 0)
          ..mood = integer('mood', 5)
          ..confidence = integer('confidence', 5).clamp(0, 10)
          ..agility = integer('agility', 0).clamp(0, 10)
          ..curiosity = integer('curiosity', 0).clamp(0, 10)
          ..level = integer('level', 1)
          ..energy = integer('energy', 384)
          ..apples = integer('apples', 0)
          ..pantry = integer('pantry', 3)
          ..plays = integer('plays', 0)
          ..timeOffsetMs = integer('timeOffsetMs', 0)
          ..inPark = json['inPark'] == true
          ..demoClock = json['demoClock'] == true;
    if (json['practicedToday'] case final List played) {
      game._practicedToday.addAll(played.whereType<String>());
    }
    if (json['talkCounts'] case final Map<String, dynamic> counts) {
      for (final entry in counts.entries) {
        if (entry.value case final int count) {
          game._talkCounts[entry.key] = count.clamp(0, 4);
        }
      }
    }
    if (json['roomOfferDays'] case final Map<String, dynamic> days) {
      for (final spot in PetRoomSpot.values) {
        if (days[spot.name] case final String day) {
          game.roomOfferDays[spot] = day;
        }
      }
    }
    if (json['starDays'] case final List days) {
      game.starDays.addAll(days.whereType<String>().take(starNames.length));
    }
    if (json['recentReplies'] case final List lines) {
      game.recentReplies.addAll(lines.whereType<String>().take(6));
    }
    if (json['starTitles'] case final List names) {
      game.starTitles.addAll(
        names.whereType<String>().take(game.starDays.length),
      );
    }
    for (var i = game.starTitles.length; i < game.starDays.length; i++) {
      game.starTitles.add(starNames[i]);
    }
    if (json['keepsake'] case final Map<String, dynamic> item) {
      if (savedEnding(item['ending']) case final PetEnding scene) {
        game.keepsake = (from: PetKind.fromName(item['from']), ending: scene);
      }
    }
    if (json['raisedKinds'] case final List kinds) {
      game.raisedKinds.addAll(
        PetKind.values.where((kind) => kinds.contains(kind.name)),
      );
    }
    if (json['discs'] case final List items) {
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final maximum = (item['maximum'] as int? ?? 3).clamp(1, 5);
        final remaining = (item['remaining'] as int? ?? 0).clamp(0, maximum);
        if (remaining > 0) {
          game.discs.add(
            PetDisc(
              maximum,
              remaining,
              origin: item['origin'] as String?,
              id: item['id'] as int?,
            ),
          );
        }
      }
    } else if (json['disc'] == true) {
      game.discs.add(const PetDisc(3, 3));
    }
    game.digestion.addAll(
      (json['digestion'] as List).cast<String>().map(DateTime.parse),
    );
    for (final entry
        in (json['memories'] as List).cast<Map<String, dynamic>>()) {
      game.memories.add(
        PetMemory(
          entry['title'] as String,
          DateTime.parse(entry['at'] as String),
          discId: entry['discId'] as int?,
          discLane: PetDiscLane.values
              .where((lane) => lane.name == entry['discLane'])
              .firstOrNull,
        ),
      );
    }
    for (final name in (json['activities'] as List).cast<String>()) {
      game.activities.add(PetActivity.values.byName(name));
    }
    return game;
  }
}
