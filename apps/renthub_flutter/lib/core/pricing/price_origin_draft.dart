/// A declaration, never independent market evidence or a review decision.
class PriceOriginDraft {
  PriceOriginDraft(
      {this.origin = 'unknown', this.suggestedAmount, this.modelVersion});
  String origin;
  double? suggestedAmount;
  String? modelVersion;

  void edited() {
    origin = origin == 'ai_suggested' || origin == 'ai_edited'
        ? 'ai_edited'
        : 'owner_entered';
  }

  void useSuggestion(double amount, String? version) {
    origin = 'ai_suggested';
    suggestedAmount = amount;
    modelVersion = version;
  }

  Map<String, dynamic> toJson() => {
        'origin': origin,
        if (suggestedAmount != null) 'suggestedAmount': suggestedAmount,
        if (modelVersion != null) 'modelVersion': modelVersion,
      };
}
