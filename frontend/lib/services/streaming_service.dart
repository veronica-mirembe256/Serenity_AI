import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:serenity/core/constants/app_constants.dart';
import 'package:serenity/models/app_models.dart';
import 'package:serenity/services/secure_storage_service.dart';

/// Possible states emitted during a streaming journal submission.
/// The UI listens to a Stream<JournalStreamEvent> and updates accordingly.
enum JournalStreamStatus { analysing, reflecting, supporting, finalising, done, error }

class JournalStreamEvent {
  final JournalStreamStatus status;
  final JournalResponse? result;   // only set when status == done
  final String? errorMessage;      // only set when status == error

  const JournalStreamEvent({
    required this.status,
    this.result,
    this.errorMessage,
  });
}

class StreamingService {
  final SecureStorageService _storage;
  StreamingService(this._storage);

  /// Submits a journal entry to POST /journal/stream and returns a stream
  /// of [JournalStreamEvent]s that the UI can listen to.
  ///
  /// The backend sends SSE events in this order:
  ///   event: status  data: analysing
  ///   event: status  data: reflecting
  ///   event: status  data: supporting
  ///   event: status  data: finalising
  ///   event: result  data: { ...full payload }
  ///
  /// This method parses each event and maps it to a [JournalStreamEvent].
  Stream<JournalStreamEvent> streamJournalEntry({
    required String text,
    int? moodScore,
  }) async* {
    final token = await _storage.getToken();
    if (token == null || token.isEmpty) {
      yield const JournalStreamEvent(
        status: JournalStreamStatus.error,
        errorMessage: 'Session expired. Please log in again.',
      );
      return;
    }

    final uri = Uri.parse('${AppConstants.baseUrl}/journal/stream');
    final request = http.Request('POST', uri)
      ..headers['Authorization']  = 'Bearer $token'
      ..headers['Content-Type']   = 'application/json'
      ..headers['Accept']         = 'text/event-stream'
      ..headers['Cache-Control']  = 'no-cache'
      ..body = jsonEncode({'text': text, 'mood_score': moodScore});

    http.StreamedResponse response;
    try {
      final client = http.Client();
      response = await client.send(request);
    } catch (e) {
      yield JournalStreamEvent(
        status: JournalStreamStatus.error,
        errorMessage: 'Could not connect to server. Please try again.',
      );
      return;
    }

    if (response.statusCode != 200) {
      yield JournalStreamEvent(
        status: JournalStreamStatus.error,
        errorMessage: 'Server error (${response.statusCode}). Please try again.',
      );
      return;
    }

    // Parse the SSE stream line by line
    String currentEvent = '';
    String currentData  = '';

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      // SSE can deliver multiple lines per chunk — split and process each
      for (final line in chunk.split('\n')) {
        final trimmed = line.trim();

        if (trimmed.startsWith('event:')) {
          currentEvent = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          currentData = trimmed.substring(5).trim();
        } else if (trimmed.isEmpty && currentEvent.isNotEmpty) {
          // Blank line = end of this SSE event — process it
          if (currentEvent == 'status') {
            yield JournalStreamEvent(status: _parseStatus(currentData));
          } else if (currentEvent == 'result') {
            try {
              final json = jsonDecode(currentData) as Map<String, dynamic>;
              yield JournalStreamEvent(
                status: JournalStreamStatus.done,
                result: JournalResponse.fromJson(json),
              );
            } catch (_) {
              yield const JournalStreamEvent(
                status: JournalStreamStatus.error,
                errorMessage: 'Could not parse AI response.',
              );
            }
          } else if (currentEvent == 'error') {
            yield JournalStreamEvent(
              status: JournalStreamStatus.error,
              errorMessage: currentData,
            );
          }
          // Reset for next event
          currentEvent = '';
          currentData  = '';
        }
      }
    }
  }

  JournalStreamStatus _parseStatus(String data) {
    switch (data) {
      case 'reflecting':  return JournalStreamStatus.reflecting;
      case 'supporting':  return JournalStreamStatus.supporting;
      case 'finalising':  return JournalStreamStatus.finalising;
      default:            return JournalStreamStatus.analysing;
    }
  }
}