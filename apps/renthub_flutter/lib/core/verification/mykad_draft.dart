/// Draft slots never infer the back as the front after removal.
class MykadDraft {
  String? _front, _back;
  String? get front => _front;
  String? get back => _back;
  int generation = 0;
  int? _checkedGeneration;
  bool get pairChecked =>
      front != null && back != null && _checkedGeneration == generation;
  String? get nextSide => front == null
      ? 'front'
      : back == null
          ? 'back'
          : null;
  List<String> get references =>
      [if (front != null) front!, if (back != null) back!];
  String sideOf(String reference) => reference == front ? 'front' : 'back';
  bool store(String side, String reference, int expectedGeneration,
      {bool matched = false}) {
    if (expectedGeneration != generation) return false;
    if (!['front', 'back'].contains(side) || reference.isEmpty) return false;
    if (side == 'front') {
      _front = reference;
    } else {
      _back = reference;
    }
    generation++;
    _checkedGeneration =
        side == 'back' && matched && front != null ? generation : null;
    return true;
  }

  bool confirmPair(int expectedGeneration, List<String> checkedReferences,
      {required bool matched}) {
    final current = references;
    if (expectedGeneration != generation ||
        current.length != 2 ||
        checkedReferences.length != 2 ||
        current[0] != checkedReferences[0] ||
        current[1] != checkedReferences[1]) {
      return false;
    }
    _checkedGeneration = matched ? generation : null;
    return true;
  }

  void remove(String reference) {
    if (reference == front) _front = null;
    if (reference == back) _back = null;
    _checkedGeneration = null;
    generation++;
  }

  void clear() {
    _front = _back = null;
    _checkedGeneration = null;
    generation++;
  }
}
