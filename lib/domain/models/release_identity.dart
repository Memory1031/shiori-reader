import 'value_model.dart';

enum UpdateChannel { stable, beta }

/// The beta sequence labels a release; build orders installations globally.
final class ReleaseIdentity extends ValueModel {
  ReleaseIdentity({
    required this.tag,
    required this.version,
    required this.build,
    required this.commit,
  }) {
    final match = RegExp(
      r'^v((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))(?:-beta\.([1-9]\d*))?$',
    ).firstMatch(tag);
    if (match == null ||
        match[1] != version ||
        build < 1 ||
        build > 2100000000 ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      throw const FormatException('Invalid release identity');
    }
    channel = match[2] == null ? UpdateChannel.stable : UpdateChannel.beta;
  }

  final String tag;
  final String version;
  final int build;
  final String commit;
  late final UpdateChannel channel;

  bool canReplace(ReleaseIdentity current, UpdateChannel selectedChannel) {
    if (build <= current.build ||
        (selectedChannel == UpdateChannel.stable &&
            channel != UpdateChannel.stable)) {
      return false;
    }
    final proposed = version.split('.').map(int.parse).toList();
    final installed = current.version.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (proposed[i] != installed[i]) return proposed[i] > installed[i];
    }
    return true;
  }

  @override
  List<Object?> get values => [tag, version, build, commit];
}
