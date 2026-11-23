import 'package:web/web.dart';

import 'pet_voice.dart';

const _key = 'donglgewi.pet.v1';

bool get petNativeModelAvailable => false;
Future<String?> readPetSnapshot() async => window.localStorage.getItem(_key);
Future<void> savePetSnapshot(String value) async =>
    window.localStorage.setItem(_key, value);
Future<PetVoice?> openPetVoice() async => null;
Future<void> installPetModel(void Function(double) progress) async {}
