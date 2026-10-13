/// Draft slots never infer the back as the front after removal.
class MykadDraft {
  String? front, back;
  int generation = 0;
  bool pairChecked = false;
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
    if (side == 'front') {
      front = reference;
      pairChecked = false;
    } else {
      back = reference;
      pairChecked = matched;
    }
    generation++;
    return true;
  }

  void remove(String reference) {
    if (reference == front) front = null;
    if (reference == back) back = null;
    pairChecked = false;
    generation++;
  }

  void clear() {
    front = back = null;
    pairChecked = false;
    generation++;
  }
}
