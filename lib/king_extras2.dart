class KingExtrasPage extends StatefulWidget {
  /// Optional: pre-fill the share/UUID box with e.g. the currently selected
  /// server's link(s), so the caller does not have to know this widget's
  /// internals — just pass the text you already have.
  final String initialShareText;
  const KingExtrasPage({super.key, this.initialShareText = ''});

  @override
  State<KingExtrasPage> createState() => _KingExtrasPageState();
}
