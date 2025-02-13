import 'package:async/async.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:http/http.dart' as http;
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/crashlytics.dart';
import 'package:lichess_mobile/src/model/auth/auth_client.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/utils/json.dart';
import 'package:logging/logging.dart';
import 'package:result_extensions/result_extensions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'correspondence_challenge.dart';
import 'game_seek.dart';

part 'lobby_repository.g.dart';

@Riverpod(keepAlive: true)
LobbyRepository lobbyRepository(LobbyRepositoryRef ref) {
  // lobbyRepository gets its own httpClient because we need to be able to
  // close it independently from the rest of the app to be able to cancel a seek.
  // See [CreateGameService] for more details.
  final httpClient = http.Client();
  final crashlytics = ref.watch(crashlyticsProvider);
  final logger = Logger('LobbyAuthClient');
  final authClient = AuthClient(
    httpClient,
    ref,
    logger,
    crashlytics,
  );
  ref.onDispose(() {
    httpClient.close();
  });
  return LobbyRepository(
    authClient: authClient,
    logger: Logger('LobbyRepository'),
  );
}

@riverpod
Future<IList<CorrespondenceChallenge>> correspondenceChallenges(
  CorrespondenceChallengesRef ref,
) {
  final lobbyRepository = ref.watch(lobbyRepositoryProvider);
  return Result.release(lobbyRepository.getCorrespondenceChallenges());
}

class LobbyRepository {
  const LobbyRepository({
    required this.authClient,
    required Logger logger,
  }) : _log = logger;

  final AuthClient authClient;
  final Logger _log;

  FutureResult<void> createSeek(GameSeek seek, {required String sri}) {
    return authClient.post(
      Uri.parse(
        '$kLichessHost/api/board/seek?sri=$sri',
      ),
      body: seek.requestBody,
    );
  }

  FutureResult<IList<CorrespondenceChallenge>> getCorrespondenceChallenges() {
    return authClient.get(
      Uri.parse('$kLichessHost/lobby/seeks'),
      headers: {'Accept': 'application/vnd.lichess.v5+json'},
    ).flatMap(
      (response) => readJsonListOfObjectsFromResponse(
        response,
        mapper: _correspondenceSeekFromJson,
        logger: _log,
      ),
    );
  }
}

CorrespondenceChallenge _correspondenceSeekFromJson(Map<String, dynamic> json) {
  return _correspondenceSeekFromPick(pick(json).required());
}

CorrespondenceChallenge _correspondenceSeekFromPick(RequiredPick pick) {
  return CorrespondenceChallenge(
    id: pick('id').asGameIdOrThrow(),
    username: pick('username').asStringOrThrow(),
    title: pick('title').asStringOrNull(),
    rating: pick('rating').asIntOrThrow(),
    variant: pick('variant').asVariantOrThrow(),
    perf: pick('perf').asPerfOrThrow(),
    rated: pick('mode').asIntOrThrow() == 1,
    days: pick('days').asIntOrNull(),
    side: pick('color').asSideOrNull(),
    provisional: pick('provisional').asBoolOrNull(),
  );
}
