abstract interface class PetVoice {
  Future<({String text, int tokens})?> reply(
    String state,
    String message,
    int limit,
  );
  void cancel();
  Future<void> dispose();
}
