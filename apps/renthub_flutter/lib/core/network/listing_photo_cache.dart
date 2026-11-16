import 'dart:typed_data';

/// Bounded, account-scoped photo bytes shared by listing cards and galleries.
class ListingPhotoCache {
  ListingPhotoCache(this.download,
      {this.maxBytes = 24 * 1024 * 1024, this.maxEntries = 64});

  final Future<Uint8List> Function(String) download;
  final int maxBytes, maxEntries;
  final _photos = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List>>{};
  int _size = 0, _generation = 0;

  Uint8List? peek(String reference) {
    final bytes = _photos.remove(reference);
    if (bytes != null) _photos[reference] = bytes;
    return bytes;
  }

  Future<Uint8List> load(String reference) {
    final saved = peek(reference);
    if (saved != null) return Future.value(saved);
    return _pending.putIfAbsent(reference, () {
      final generation = _generation;
      return Future<Uint8List>.sync(() => download(reference)).then((bytes) {
        if (generation == _generation && bytes.lengthInBytes <= maxBytes) {
          while (_photos.isNotEmpty &&
              (_photos.length >= maxEntries ||
                  _size + bytes.lengthInBytes > maxBytes)) {
            _size -= _photos.remove(_photos.keys.first)!.lengthInBytes;
          }
          _photos[reference] = bytes;
          _size += bytes.lengthInBytes;
        }
        return bytes;
      }).whenComplete(() {
        if (generation == _generation) _pending.remove(reference);
      });
    });
  }

  void clear() {
    _generation++;
    _photos.clear();
    _pending.clear();
    _size = 0;
  }
}
