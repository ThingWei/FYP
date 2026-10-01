abstract final class BackendMode {
  // Live API/MongoDB mode is the application default. Mock mode is retained
  // only as an explicit opt-in for isolated UI previews and tests.
  static const useMocks =
      bool.fromEnvironment('USE_MOCKS', defaultValue: false);
}
