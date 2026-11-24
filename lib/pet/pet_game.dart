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
});

class PetDisc {
  const PetDisc(this.maximum, this.remaining);

  final int maximum;
  final int remaining;

  Map<String, int> toJson() => {'maximum': maximum, 'remaining': remaining};
}

class PetMemory {
  const PetMemory(this.title, this.at);
  final String title;
  final DateTime at;

  Map<String, Object> toJson() => {'title': title, 'at': at.toIso8601String()};
}

class PetGame {
  PetGame(DateTime now, {this.kind = PetKind.dongle})
    : at = now,
      born = now,
      nextHunger = now.add(hour * 6) {
    suppliedDay = petDay(now);
    raisedKinds.add(kind);
  }

  final PetKind kind;
  final Set<PetKind> raisedKinds = {};
  DateTime at;
  DateTime born;
  DateTime? nextHunger;
  DateTime? hungerDeadline;
  DateTime? hygieneDeadline;
  DateTime? lastWaste;
  DateTime? nextRecovery;
  final List<DateTime> digestion = [];
  final List<PetMemory> memories = [];
  final List<PetDisc> discs = [];
  final Set<PetActivity> activities = {};
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
  int get maxFullness => level < 3
      ? 3
      : level < 5
      ? 4
      : 5;
  int get maxEnergy => 320 + 64 * level;
  double energyPercent(int amount) => amount * 100 / maxEnergy;
  int get nextAffection => level < 3 ? 3 : 8;
  String get stage => level < 3
      ? '아기'
      : level < 5
      ? '꼬마'
      : '성체';
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
      2 when affection >= 3 => born.add(
        hour * math.max(24, 30 - (affection - 3) * 3),
      ),
      3 when affection >= 5 => born.add(hour * 36),
      4 when affection >= 8 => born.add(
        hour * math.max(72, 96 - (affection - 8) * 6),
      ),
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
        if (fullness == 0) hungerDeadline = at.add(hour * 12);
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
      energy >= activity.cost &&
      switch (activity) {
        PetPlay.disc => disc,
        PetPlay.walk => inPark,
      };

  PetPlayResult? play([PetPlay activity = PetPlay.disc]) {
    if (!canPlay(activity)) return null;
    final percent = energyPercent(activity.cost);
    _useEnergy(activity.cost);
    final beforeMood = mood;
    final beforeConfidence = confidence;
    final beforeAgility = agility;
    final beforeCuriosity = curiosity;
    var discBroke = false;
    moodChange(1);
    switch (activity) {
      case PetPlay.disc:
        final used = discs.first;
        discBroke = used.remaining == 1;
        if (discBroke) {
          discs.removeAt(0);
        } else {
          discs[0] = PetDisc(used.maximum, used.remaining - 1);
        }
        plays++;
        confidence = math.min(10, confidence + 1);
        agility = math.min(10, agility + 1);
        mark(PetActivity.play);
      case PetPlay.walk:
        curiosity = math.min(10, curiosity + 1);
        walk();
    }
    return (
      energyPercent: percent,
      discBroke: discBroke,
      gains: {
        if (mood > beforeMood) '기분': mood - beforeMood,
        if (confidence > beforeConfidence) '자신감': confidence - beforeConfidence,
        if (agility > beforeAgility) '민첩': agility - beforeAgility,
        if (curiosity > beforeCuriosity) '호기심': curiosity - beforeCuriosity,
      },
    );
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
      found = PetDisc(durability, durability);
      discs.add(found);
    }
    if (title.isNotEmpty) memories.add(PetMemory(title, at));
    return found;
  }

  void walk() {
    if (!healthy) return;
    if (!memories.any(
      (m) => m.title == '공원 산책' && petDay(m.at) == petDay(at),
    )) {
      memories.add(PetMemory('공원 산책', at));
    }
    mark(PetActivity.play);
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

  PetMemory? get nextMemory {
    final candidates = memories.reversed.where((memory) {
      final age = petDayDifference(at, memory.at);
      return age > 0 && age <= 30;
    }).toList();
    return candidates
            .where((m) => m.at.toIso8601String() != lastMemory)
            .firstOrNull ??
        candidates.firstOrNull;
  }

  String encode() => jsonEncode({
    'kind': kind.name,
    'raisedKinds': raisedKinds.map((kind) => kind.name).toList(),
    'at': at.toIso8601String(),
    'born': born.toIso8601String(),
    'nextHunger': nextHunger?.toIso8601String(),
    'hungerDeadline': hungerDeadline?.toIso8601String(),
    'hygieneDeadline': hygieneDeadline?.toIso8601String(),
    'lastWaste': lastWaste?.toIso8601String(),
    'nextRecovery': nextRecovery?.toIso8601String(),
    'digestion': digestion.map((time) => time.toIso8601String()).toList(),
    'memories': memories.map((memory) => memory.toJson()).toList(),
    'activities': activities.map((activity) => activity.name).toList(),
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
    final game = PetGame(date('at')!, kind: PetKind.fromName(json['kind']))
      ..born = date('born')!
      ..nextHunger = date('nextHunger')
      ..hungerDeadline = date('hungerDeadline')
      ..hygieneDeadline = date('hygieneDeadline')
      ..lastWaste = date('lastWaste')
      ..nextRecovery = date('nextRecovery')
      ..suppliedDay = string('suppliedDay')
      ..affectionDay = string('affectionDay')
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
    if (json['raisedKinds'] case final List kinds) {
      game.raisedKinds.addAll(
        PetKind.values.where((kind) => kinds.contains(kind.name)),
      );
    }
    if (json['discs'] case final List items) {
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final maximum = (item['maximum'] as int? ?? 3).clamp(1, 5);
        final remaining = (item['remaining'] as int? ?? 0).clamp(0, maximum);
        if (remaining > 0) game.discs.add(PetDisc(maximum, remaining));
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
        ),
      );
    }
    for (final name in (json['activities'] as List).cast<String>()) {
      game.activities.add(PetActivity.values.byName(name));
    }
    return game;
  }
}
