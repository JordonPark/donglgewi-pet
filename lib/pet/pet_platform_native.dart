import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../kanana.dart';
import '../model_store.dart';
import 'pet_voice.dart';

bool get petNativeModelAvailable => Platform.isAndroid || Platform.isIOS;

Future<Directory> _appDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory.fromUri(support.uri.resolve('Donglgewi/'))
    ..createSync(recursive: true);
}

Future<File> _stateFile() async =>
    File.fromUri((await _appDirectory()).uri.resolve('pet-prototype.json'));

Future<String?> readPetSnapshot() async {
  final file = await _stateFile();
  return await file.exists() ? file.readAsString() : null;
}

Future<void> savePetSnapshot(String value) async {
  final file = await _stateFile();
  final temp = await File('${file.path}.tmp').writeAsString(value, flush: true);
  await temp.rename(file.path);
}

Future<PetVoice?> openPetVoice() async {
  if (!petNativeModelAvailable) return null;
  final store = ModelStore(await _appDirectory());
  if (!await store.isInstalled()) return null;
  return _NativeVoice(await Kanana.load(store.model.path));
}

Future<void> installPetModel(void Function(double) progress) async {
  final store = ModelStore(await _appDirectory());
  await store.acceptDownload();
  if (!await store.isInstalled()) {
    await store.download(
      onProgress: (bytes) => progress(bytes / ModelStore.bytes),
      onVerify: () => progress(1),
    );
  }
}

class _NativeVoice implements PetVoice {
  _NativeVoice(this._engine);
  final Kanana _engine;
  Future<({String text, int tokens})>? _pending;

  @override
  Future<({String text, int tokens})?> reply(
    String state,
    String message,
    int limit,
  ) async {
    if (_pending != null) return null;
    final pending = _engine.petReply(
      state: state,
      message: message,
      limit: limit,
    );
    _pending = pending;
    try {
      return await pending;
    } finally {
      _pending = null;
    }
  }

  @override
  void cancel() => _engine.stop();

  @override
  Future<void> dispose() async {
    await _pending?.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await _engine.dispose();
  }
}
