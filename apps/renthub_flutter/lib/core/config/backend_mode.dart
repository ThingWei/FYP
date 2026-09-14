abstract final class BackendMode {
  static const useMocks =
      bool.fromEnvironment('USE_MOCKS', defaultValue: true);
}
