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
      this.reachedLimit = false});

  final List<Map<String, dynamic>> items;
  final int limit;
  final int? nextLimit;
  final bool refreshNeeded, stale, providerAvailable, reachedLimit;

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
          'reachedLimit'
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
    );
  }
}
