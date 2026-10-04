// TEMPORARY A/B DIAGNOSTICS - non-web no-op.

/// There is no `HTMLInputElement` outside the browser.
class ClickWrapper {
  ClickWrapper({this.withListeners = false, this.retainInputs = false});

  final bool withListeners;
  final bool retainInputs;

  bool get isInstalled => false;

  /// Why [install] did not install anything (shown in the A/B marker).
  String? get problem => null;

  /// Test-only observation hooks (the browser tests need them to type-check).
  int get retainedCount => 0;

  bool isRetained(Object input) => false;

  void install() {}

  void uninstall() {}
}
