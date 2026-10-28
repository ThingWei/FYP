import '../../core/network/api_client.dart';

typedef CatalogPageLoader = Future<CatalogPage> Function(String query,
    {required int limit, required bool refresh, required bool preferCache});

class CatalogPage {
  const CatalogPage(
      {required this.items,
      this.limit = 12,
      this.nextLimit,
      this.refreshNeeded = false,
      this.stale = false,
      this.providerAvailable = true,
      this.reachedLimit = false,
      this.evidenceLed = false,
      this.scanLimited = false});

  final List<Map<String, dynamic>> items;
  final int limit;
  final int? nextLimit;
  final bool refreshNeeded, stale, providerAvailable, reachedLimit;
  final bool evidenceLed, scanLimited;

  CatalogPage mergeCatalogue(CatalogPage other) {
    String normalized(Object? value) => '${value ?? ''}'
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-]+'), ' ');
    String key(Map<String, dynamic> row) => [
          'brand',
          'model',
          'variant',
          'edition',
          'isbn',
          'packageType',
          'includedLens'
        ].map((name) => normalized(row[name])).join('|');
    final merged = <String, Map<String, dynamic>>{};
    for (final row in items) {
      merged[key(row)] = row;
    }
    for (final row in other.items) {
      final saved = merged[key(row)];
      merged[key(row)] = saved == null
          ? {...row, 'selectionSource': 'catalogue'}
          : {
              ...row,
              ...saved,
              'canonicalProductId':
                  saved['canonicalProductId'] ?? row['canonicalProductId'],
              'catalogBrandId':
                  saved['catalogBrandId'] ?? row['catalogBrandId'],
              'catalogSource': saved['catalogSource'] ?? row['catalogSource'],
            };
    }
    final more =
        merged.length > limit || nextLimit != null || other.nextLimit != null;
    return CatalogPage(
        items: merged.values.take(limit).toList(),
        limit: limit,
        nextLimit: more && limit < 120 ? (limit + 12).clamp(1, 120) : null,
        providerAvailable: other.providerAvailable,
        stale: other.stale,
        reachedLimit: limit == 120 && more,
        evidenceLed: true,
        scanLimited: scanLimited || other.scanLimited);
  }

  factory CatalogPage.fromEnvelope(Map<String, dynamic> envelope,
      {int requestedLimit = 12}) {
    final data = envelope['data'];
    final rawMeta = envelope['meta'];
    if (data is! List ||
        data.any((item) => item is! Map) ||
        rawMeta != null && rawMeta is! Map) {
      throw ApiException(502, 'Unexpected catalogue response',
          code: 'INVALID_RESPONSE');
    }
    final meta = rawMeta is Map ? rawMeta : const {};
    final limit = meta['limit'] ?? requestedLimit;
    final next = meta['nextLimit'];
    if (limit is! int ||
        limit < 1 ||
        limit > 120 ||
        next != null && (next is! int || next <= limit || next > 120) ||
        [
          'hasMore',
          'refreshNeeded',
          'stale',
          'providerAvailable',
          'reachedLimit',
          'scanLimited'
        ].any((key) => meta[key] != null && meta[key] is! bool)) {
      throw ApiException(502, 'Unexpected catalogue response',
          code: 'INVALID_RESPONSE');
    }
    if (meta['hasMore'] == true && next == null || data.length > 120) {
      throw ApiException(502, 'Unexpected catalogue response',
          code: 'INVALID_RESPONSE');
    }
    return CatalogPage(
      items:
          data.map((item) => Map<String, dynamic>.from(item as Map)).toList(),
      limit: limit,
      nextLimit: meta['hasMore'] == true ? next as int? : null,
      refreshNeeded: meta['refreshNeeded'] == true,
      stale: meta['stale'] == true,
      providerAvailable: meta['providerAvailable'] != false,
      reachedLimit: meta['reachedLimit'] == true,
      evidenceLed: meta['mode'] == 'evidence',
      scanLimited: meta['scanLimited'] == true,
    );
  }
}
