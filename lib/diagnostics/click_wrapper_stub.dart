// TEMPORARY A/B DIAGNOSTICS - non-web no-op.

/// There is no `HTMLInputElement` outside the browser.
class ClickWrapper {
  bool get isInstalled => false;

  /// Why [install] did not install anything (shown in the A/B marker).
  String? get problem => null;

  void install() {}

  void uninstall() {}
}
