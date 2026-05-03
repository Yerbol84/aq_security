// pkgs/aq_security/lib/src/client/field_encryption_service.dart
//
// Сервис шифрования чувствительных полей.
// Использует AES-256-GCM для шифрования.
//
// Карта шифрования должна быть в модели данных:
// - Если карты нет → шифрование не применяется
// - Если карта есть → шифруются только указанные поля

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Конфигурация шифрования для коллекции.
///
/// Определяет какие поля нужно шифровать и как.
final class EncryptionConfig {
  const EncryptionConfig({
    required this.fields,
    this.algorithm = 'AES-256-GCM',
  });

  /// Список полей для шифрования
  final List<String> fields;

  /// Алгоритм шифрования (по умолчанию AES-256-GCM)
  final String algorithm;

  factory EncryptionConfig.fromJson(Map<String, dynamic> json) {
    return EncryptionConfig(
      fields: (json['fields'] as List<dynamic>).cast<String>(),
      algorithm: json['algorithm'] as String? ?? 'AES-256-GCM',
    );
  }

  Map<String, dynamic> toJson() => {
        'fields': fields,
        'algorithm': algorithm,
      };
}

/// Сервис шифрования полей.
///
/// ## Использование
///
/// ```dart
/// final service = FieldEncryptionService(encryptionKey: 'secret-key-32-bytes-long-string');
///
/// // Шифрование
/// final encrypted = await service.encryptFields(
///   data: {'email': 'user@example.com', 'password': 'secret'},
///   config: EncryptionConfig(fields: ['password']),
/// );
/// // Результат: {'email': 'user@example.com', 'password': 'encrypted:base64...'}
///
/// // Расшифрование
/// final decrypted = await service.decryptFields(
///   data: encrypted,
///   config: EncryptionConfig(fields: ['password']),
/// );
/// // Результат: {'email': 'user@example.com', 'password': 'secret'}
/// ```
final class FieldEncryptionService {
  FieldEncryptionService({
    required this.encryptionKey,
  }) {
    if (encryptionKey.length < 32) {
      throw ArgumentError('Encryption key must be at least 32 characters');
    }
  }

  final String encryptionKey;

  /// Префикс для зашифрованных значений
  static const String _encryptedPrefix = 'encrypted:';

  /// Зашифровать чувствительные поля.
  ///
  /// Если [config] == null, возвращает данные без изменений.
  /// Шифрует только поля из [config.fields].
  Future<Map<String, dynamic>> encryptFields({
    required Map<String, dynamic> data,
    EncryptionConfig? config,
  }) async {
    if (config == null || config.fields.isEmpty) {
      return data;
    }

    final result = Map<String, dynamic>.from(data);

    for (final field in config.fields) {
      if (result.containsKey(field)) {
        final value = result[field];
        if (value != null && value is String && !value.startsWith(_encryptedPrefix)) {
          result[field] = await _encrypt(value);
        }
      }
    }

    return result;
  }

  /// Расшифровать чувствительные поля.
  ///
  /// Если [config] == null, возвращает данные без изменений.
  /// Расшифровывает только поля из [config.fields].
  Future<Map<String, dynamic>> decryptFields({
    required Map<String, dynamic> data,
    EncryptionConfig? config,
  }) async {
    if (config == null || config.fields.isEmpty) {
      return data;
    }

    final result = Map<String, dynamic>.from(data);

    for (final field in config.fields) {
      if (result.containsKey(field)) {
        final value = result[field];
        if (value != null && value is String && value.startsWith(_encryptedPrefix)) {
          try {
            result[field] = await _decrypt(value);
          } catch (e) {
            // Если не удалось расшифровать, оставляем как есть
            // (может быть старый формат или повреждённые данные)
          }
        }
      }
    }

    return result;
  }

  /// Зашифровать строку с использованием AES-256-GCM.
  Future<String> _encrypt(String plaintext) async {
    try {
      // Генерировать случайный IV (12 байт для GCM)
      final iv = _generateIV();

      // Получить ключ (32 байта для AES-256)
      final key = _deriveKey(encryptionKey);

      // Создать cipher
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true, // encrypt
          AEADParameters(
            KeyParameter(key),
            128, // tag length in bits
            iv,
            Uint8List(0), // additional data
          ),
        );

      // Зашифровать
      final plaintextBytes = utf8.encode(plaintext);
      final ciphertext = cipher.process(Uint8List.fromList(plaintextBytes));

      // Объединить IV + ciphertext
      final ivLen = iv.length as int;
      final cipherLen = ciphertext.length as int;
      final totalLength = ivLen + cipherLen;
      final combined = Uint8List(totalLength)
        ..setRange(0, ivLen, iv)
        ..setRange(ivLen, totalLength, ciphertext);

      // Вернуть с префиксом
      return '$_encryptedPrefix${base64Url.encode(combined)}';
    } catch (e) {
      throw EncryptionException('Encryption failed: $e');
    }
  }

  /// Расшифровать строку.
  Future<String> _decrypt(String encrypted) async {
    try {
      // Убрать префикс
      if (!encrypted.startsWith(_encryptedPrefix)) {
        throw const EncryptionException('Invalid encrypted format');
      }

      final encoded = encrypted.substring(_encryptedPrefix.length);
      final combined = base64Url.decode(encoded);

      // Извлечь IV и ciphertext
      final iv = Uint8List.sublistView(combined, 0, 12);
      final ciphertext = Uint8List.sublistView(combined, 12);

      // Получить ключ
      final key = _deriveKey(encryptionKey);

      // Создать cipher
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false, // decrypt
          AEADParameters(
            KeyParameter(key),
            128,
            iv,
            Uint8List(0),
          ),
        );

      // Расшифровать
      final plaintext = cipher.process(ciphertext);

      return utf8.decode(plaintext);
    } catch (e) {
      throw EncryptionException('Decryption failed: $e');
    }
  }

  /// Генерировать случайный IV (12 байт для GCM).
  Uint8List _generateIV() {
    final random = FortunaRandom();
    final seed = Uint8List.fromList(
      List.generate(32, (i) => DateTime.now().millisecondsSinceEpoch % 256),
    );
    random.seed(KeyParameter(seed));

    final iv = Uint8List(12);
    for (var i = 0; i < iv.length; i++) {
      iv[i] = random.nextUint8();
    }
    return iv;
  }

  /// Получить ключ шифрования (32 байта для AES-256).
  Uint8List _deriveKey(String password) {
    // Использовать SHA-256 для получения 32-байтового ключа
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }
}

/// Исключение при шифровании/расшифровании.
final class EncryptionException implements Exception {
  const EncryptionException(this.message);

  final String message;

  @override
  String toString() => 'EncryptionException: $message';
}
