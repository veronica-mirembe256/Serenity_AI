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
  Stream<JournalStreamEvent> streamJournalEntry({
    required String text,
    int? moodScore,
  }) async* {
    print('📡 [STREAM] Starting streamJournalEntry...');
    print('📡 [STREAM] Text length: ${text.length}');
    print('📡 [STREAM] Mood score: $moodScore');

    final token = await _storage.getToken();
    print('📡 [STREAM] Token present: ${token != null && token.isNotEmpty}');

    if (token == null || token.isEmpty) {
      print('❌ [STREAM] No token found');
      yield const JournalStreamEvent(
        status: JournalStreamStatus.error,
        errorMessage: 'Session expired. Please log in again.',
      );
      return;
    }

    final uri = Uri.parse('${AppConstants.baseUrl}/journal/stream');
    print('📡 [STREAM] URL: $uri');

    final request = http.Request('POST', uri)
      ..headers['Authorization']  = 'Bearer $token'
      ..headers['Content-Type']   = 'application/json'
      ..headers['Accept']         = 'text/event-stream'
      ..headers['Cache-Control']  = 'no-cache'
      ..body = jsonEncode({'text': text, 'mood_score': moodScore});

    print('📡 [STREAM] Request body: ${request.body}');

    http.StreamedResponse response;
    try {
      final client = http.Client();
      response = await client.send(request);
      print('📡 [STREAM] Response status: ${response.statusCode}');
    } catch (e) {
      print('❌ [STREAM] Connection error: $e');
      yield JournalStreamEvent(
        status: JournalStreamStatus.error,
        errorMessage: 'Could not connect to server. Please try again.',
      );
      return;
    }

    if (response.statusCode != 200) {
      print('❌ [STREAM] Non-200 response: ${response.statusCode}');
      yield JournalStreamEvent(
        status: JournalStreamStatus.error,
        errorMessage: 'Server error (${response.statusCode}). Please try again.',
      );
      return;
    }

    // Parse the SSE stream - using a buffer to handle partial events
    String buffer = '';
    int eventCount = 0;

    print('📡 [STREAM] Starting to parse SSE stream...');

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      print('📡 [STREAM] Chunk received, length: ${chunk.length}');
      buffer += chunk;

      // Process complete events in the buffer
      while (buffer.contains('\n\n')) {
        final eventEnd = buffer.indexOf('\n\n');
        final eventBlock = buffer.substring(0, eventEnd);
        buffer = buffer.substring(eventEnd + 2);

        if (eventBlock.trim().isEmpty) continue;

        print('📡 [STREAM] Processing event block: "${eventBlock.substring(0, eventBlock.length > 100 ? 100 : eventBlock.length)}..."');

        String? eventType;
        String? eventData;

        for (final line in eventBlock.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          if (trimmed.startsWith('event:')) {
            eventType = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            eventData = trimmed.substring(5).trim();
          }
        }

        if (eventType != null && eventData != null) {
          eventCount++;
          print('📡 [STREAM] Event #$eventCount: type="$eventType"');

          if (eventType == 'status') {
            final status = _parseStatus(eventData);
            print('📡 [STREAM] Status: $status');
            yield JournalStreamEvent(status: status);
          } else if (eventType == 'result') {
            print('📡 [STREAM] ✅ RESULT EVENT RECEIVED!');
            try {
              final json = jsonDecode(eventData) as Map<String, dynamic>;
              print('📡 [STREAM] JSON parsed: ${json.keys}');
              print('📡 [STREAM] Emotion: ${json['detected_emotion']}');
              print('📡 [STREAM] Risk: ${json['relapse_risk_level']}');

              final result = JournalResponse.fromJson(json);
              print('✅ [STREAM] JournalResponse created');

              yield JournalStreamEvent(
                status: JournalStreamStatus.done,
                result: result,
              );
              print('✅ [STREAM] Done event yielded');
            } catch (e, stack) {
              print('❌ [STREAM] Failed to parse result: $e');
              print('❌ [STREAM] Stack: $stack');
              print('❌ [STREAM] Raw data: $eventData');
              yield const JournalStreamEvent(
                status: JournalStreamStatus.error,
                errorMessage: 'Could not parse AI response.',
              );
            }
          } else if (eventType == 'error') {
            print('❌ [STREAM] Error event: $eventData');
            yield JournalStreamEvent(
              status: JournalStreamStatus.error,
              errorMessage: eventData,
            );
          }
        }
      }
    }

    // Process any remaining data in the buffer
    if (buffer.trim().isNotEmpty) {
      print('📡 [STREAM] Processing remaining buffer: "$buffer"');
      // Try to parse any remaining events
      final lines = buffer.split('\n');
      String? eventType;
      String? eventData;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.startsWith('event:')) {
          eventType = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          eventData = trimmed.substring(5).trim();
        }
      }

      if (eventType == 'result' && eventData != null) {
        print('📡 [STREAM] Processing final result event');
        try {
          final json = jsonDecode(eventData) as Map<String, dynamic>;
          final result = JournalResponse.fromJson(json);
          yield JournalStreamEvent(
            status: JournalStreamStatus.done,
            result: result,
          );
        } catch (e) {
          print('❌ [STREAM] Failed to parse final result: $e');
        }
      }
    }

    print('📡 [STREAM] Stream ended. Total events processed: $eventCount');
  }

  JournalStreamStatus _parseStatus(String data) {
    print('📡 [STREAM] Parsing status: "$data"');
    switch (data) {
      case 'reflecting':  return JournalStreamStatus.reflecting;
      case 'supporting':  return JournalStreamStatus.supporting;
      case 'finalising':  return JournalStreamStatus.finalising;
      default:            return JournalStreamStatus.analysing;
    }
  }
}