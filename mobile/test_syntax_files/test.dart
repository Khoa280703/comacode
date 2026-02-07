// Dart sample file - Flutter advanced patterns with modern Dart 3.x features
// This file demonstrates comprehensive Dart/Flutter patterns including:
// - Dart 3.x patterns (records, patterns, sealed classes)
// - Result and Option types using sealed classes
// - User entity with validation
// - Repository pattern
// - Event system with Stream
// - Service layer with caching
// - Async utilities (Future, Stream patterns)
// - Extensions
// - Mixins
// - Riverpod providers
// - Custom exceptions
// - Flutter widget examples

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// PART 1: CUSTOM EXCEPTIONS
// ============================================================================

/// Base exception for all application-specific errors
sealed class AppException implements Exception {
  String get message;
  String? get code;
  StackTrace? get stackTrace;

  const AppException();

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// Network-related exceptions
final class NetworkException extends AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final StackTrace? stackTrace;
  final int? statusCode;
  final String? url;

  const NetworkException({
    required this.message,
    this.code,
    this.stackTrace,
    this.statusCode,
    this.url,
  });

  factory NetworkException.timeout(String url) => NetworkException(
        message: 'Request timeout',
        code: 'NETWORK_TIMEOUT',
        url: url,
      );

  factory NetworkException.noConnection() => const NetworkException(
        message: 'No internet connection',
        code: 'NO_CONNECTION',
      );

  factory NetworkException.serverError(int statusCode, String? body) =>
      NetworkException(
        message: 'Server error: $statusCode',
        code: 'SERVER_ERROR',
        statusCode: statusCode,
      );
}

/// Validation-related exceptions
final class ValidationException extends AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final StackTrace? stackTrace;
  final Map<String, List<String>> fieldErrors;

  const ValidationException({
    required this.message,
    this.code = 'VALIDATION_ERROR',
    this.stackTrace,
    this.fieldErrors = const {},
  });

  factory ValidationException.single(String field, String error) =>
      ValidationException(
        message: 'Validation failed for $field',
        fieldErrors: {
          field: [error]
        },
      );

  factory ValidationException.multiple(Map<String, List<String>> errors) =>
      ValidationException(
        message: 'Multiple validation errors',
        fieldErrors: errors,
      );

  bool hasErrorFor(String field) => fieldErrors.containsKey(field);
  List<String> errorsFor(String field) => fieldErrors[field] ?? [];
}

/// Authentication-related exceptions
final class AuthException extends AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final StackTrace? stackTrace;
  final AuthErrorType type;

  const AuthException({
    required this.message,
    required this.type,
    this.code,
    this.stackTrace,
  });

  factory AuthException.invalidCredentials() => const AuthException(
        message: 'Invalid email or password',
        type: AuthErrorType.invalidCredentials,
        code: 'INVALID_CREDENTIALS',
      );

  factory AuthException.tokenExpired() => const AuthException(
        message: 'Session expired. Please login again.',
        type: AuthErrorType.tokenExpired,
        code: 'TOKEN_EXPIRED',
      );

  factory AuthException.unauthorized() => const AuthException(
        message: 'You are not authorized to perform this action',
        type: AuthErrorType.unauthorized,
        code: 'UNAUTHORIZED',
      );
}

enum AuthErrorType {
  invalidCredentials,
  tokenExpired,
  unauthorized,
  accountLocked,
  accountNotFound,
  emailNotVerified,
}

/// Cache-related exceptions
final class CacheException extends AppException {
  @override
  final String message;
  @override
  final String? code;
  @override
  final StackTrace? stackTrace;

  const CacheException({
    required this.message,
    this.code = 'CACHE_ERROR',
    this.stackTrace,
  });

  factory CacheException.notFound(String key) => CacheException(
        message: 'Cache entry not found: $key',
        code: 'CACHE_NOT_FOUND',
      );

  factory CacheException.expired(String key) => CacheException(
        message: 'Cache entry expired: $key',
        code: 'CACHE_EXPIRED',
      );

  factory CacheException.writeError(String key, Object? error) =>
      CacheException(
        message: 'Failed to write cache: $key - $error',
        code: 'CACHE_WRITE_ERROR',
      );
}

// ============================================================================
// PART 2: RESULT TYPE (Functional Error Handling)
// ============================================================================

/// A sealed class representing the result of an operation that can either
/// succeed with a value or fail with an error.
sealed class Result<T> {
  const Result();

  /// Creates a successful result with the given [data].
  factory Result.success(T data) = Success<T>;

  /// Creates a failed result with the given [message] and optional [exception].
  factory Result.failure(String message, [AppException? exception]) =
      Failure<T>;

  /// Whether this result is a success.
  bool get isSuccess => this is Success<T>;

  /// Whether this result is a failure.
  bool get isFailure => this is Failure<T>;

  /// Transforms the result into a new result using the provided functions.
  Result<R> map<R>(R Function(T data) transform) => switch (this) {
        Success(:final data) => Result.success(transform(data)),
        Failure(:final message, :final exception) =>
          Result.failure(message, exception),
      };

  /// Transforms the result into a new result using the provided async function.
  Future<Result<R>> mapAsync<R>(Future<R> Function(T data) transform) async {
    return switch (this) {
      Success(:final data) => Result.success(await transform(data)),
      Failure(:final message, :final exception) =>
        Result.failure(message, exception),
    };
  }

  /// Chains multiple operations that return Results.
  Result<R> flatMap<R>(Result<R> Function(T data) transform) => switch (this) {
        Success(:final data) => transform(data),
        Failure(:final message, :final exception) =>
          Result.failure(message, exception),
      };

  /// Chains multiple async operations that return Results.
  Future<Result<R>> flatMapAsync<R>(
      Future<Result<R>> Function(T data) transform) async {
    return switch (this) {
      Success(:final data) => transform(data),
      Failure(:final message, :final exception) =>
        Result.failure(message, exception),
    };
  }
}

/// Represents a successful result containing [data].
final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  String toString() => 'Success($data)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> && runtimeType == other.runtimeType && data == other.data;

  @override
  int get hashCode => data.hashCode;
}

/// Represents a failed result with an error [message] and optional [exception].
final class Failure<T> extends Result<T> {
  final String message;
  final AppException? exception;
  const Failure(this.message, [this.exception]);

  @override
  String toString() => 'Failure($message, $exception)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T> &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;
}

/// Extension methods for Result type
extension ResultExtension<T> on Result<T> {
  /// Pattern matches on the result, calling the appropriate function.
  R when<R>({
    required R Function(T data) success,
    required R Function(String message, AppException? exception) failure,
  }) {
    return switch (this) {
      Success(:final data) => success(data),
      Failure(:final message, :final exception) => failure(message, exception),
    };
  }

  /// Returns the data if successful, otherwise returns null.
  T? getOrNull() => switch (this) {
        Success(:final data) => data,
        Failure() => null,
      };

  /// Returns the data if successful, otherwise returns [defaultValue].
  T getOrElse(T defaultValue) => switch (this) {
        Success(:final data) => data,
        Failure() => defaultValue,
      };

  /// Returns the data if successful, otherwise computes a default.
  T getOrCompute(T Function() compute) => switch (this) {
        Success(:final data) => data,
        Failure() => compute(),
      };

  /// Throws the exception if this is a failure, otherwise returns the data.
  T getOrThrow() => switch (this) {
        Success(:final data) => data,
        Failure(:final message, :final exception) =>
          throw exception ?? Exception(message),
      };

  /// Executes [action] if this is a success.
  Result<T> onSuccess(void Function(T data) action) {
    if (this case Success(:final data)) {
      action(data);
    }
    return this;
  }

  /// Executes [action] if this is a failure.
  Result<T> onFailure(
      void Function(String message, AppException? exception) action) {
    if (this case Failure(:final message, :final exception)) {
      action(message, exception);
    }
    return this;
  }

  /// Recovers from a failure by trying an alternative operation.
  Result<T> recover(Result<T> Function(String message) recovery) =>
      switch (this) {
        Success() => this,
        Failure(:final message) => recovery(message),
      };
}

/// Extension for Future<Result<T>>
extension FutureResultExtension<T> on Future<Result<T>> {
  /// Awaits and pattern matches on the result.
  Future<R> whenComplete<R>({
    required R Function(T data) success,
    required R Function(String message, AppException? exception) failure,
  }) async {
    final result = await this;
    return result.when(success: success, failure: failure);
  }

  /// Awaits and returns the data or null.
  Future<T?> getOrNullAsync() async => (await this).getOrNull();

  /// Awaits and returns the data or default value.
  Future<T> getOrElseAsync(T defaultValue) async =>
      (await this).getOrElse(defaultValue);
}

// ============================================================================
// PART 3: OPTION TYPE (Null Safety Enhancement)
// ============================================================================

/// A sealed class representing an optional value.
sealed class Option<T> {
  const Option();

  /// Creates a Some with the given [value].
  factory Option.some(T value) = Some<T>;

  /// Creates a None representing absence of value.
  factory Option.none() = None<T>;

  /// Creates an Option from a nullable value.
  factory Option.fromNullable(T? value) =>
      value != null ? Option.some(value) : Option.none();

  /// Whether this option contains a value.
  bool get isSome => this is Some<T>;

  /// Whether this option is empty.
  bool get isNone => this is None<T>;

  /// Transforms the value if present.
  Option<R> map<R>(R Function(T value) transform) => switch (this) {
        Some(:final value) => Option.some(transform(value)),
        None() => Option.none(),
      };

  /// Chains operations that return Options.
  Option<R> flatMap<R>(Option<R> Function(T value) transform) => switch (this) {
        Some(:final value) => transform(value),
        None() => Option.none(),
      };

  /// Filters the value based on a predicate.
  Option<T> filter(bool Function(T value) predicate) => switch (this) {
        Some(:final value) when predicate(value) => this,
        _ => Option.none(),
      };
}

/// Represents the presence of a value.
final class Some<T> extends Option<T> {
  final T value;
  const Some(this.value);

  @override
  String toString() => 'Some($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Some<T> && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Represents the absence of a value.
final class None<T> extends Option<T> {
  const None();

  @override
  String toString() => 'None';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is None<T> && runtimeType == other.runtimeType;

  @override
  int get hashCode => 0;
}

/// Extension methods for Option type
extension OptionExtension<T> on Option<T> {
  /// Pattern matches on the option.
  R when<R>({
    required R Function(T value) some,
    required R Function() none,
  }) {
    return switch (this) {
      Some(:final value) => some(value),
      None() => none(),
    };
  }

  /// Returns the value or null.
  T? getOrNull() => switch (this) {
        Some(:final value) => value,
        None() => null,
      };

  /// Returns the value or a default.
  T getOrElse(T defaultValue) => switch (this) {
        Some(:final value) => value,
        None() => defaultValue,
      };

  /// Converts to a Result, using the message for None case.
  Result<T> toResult(String noneMessage) => switch (this) {
        Some(:final value) => Result.success(value),
        None() => Result.failure(noneMessage),
      };

  /// Executes action if Some.
  Option<T> onSome(void Function(T value) action) {
    if (this case Some(:final value)) {
      action(value);
    }
    return this;
  }

  /// Executes action if None.
  Option<T> onNone(void Function() action) {
    if (this is None<T>) {
      action();
    }
    return this;
  }
}

// ============================================================================
// PART 4: DART 3.X RECORDS AND PATTERNS
// ============================================================================

/// Type aliases for common record patterns
typedef Coordinates = ({double latitude, double longitude});
typedef Range<T extends num> = ({T start, T end});
typedef Pair<A, B> = (A, B);
typedef Triple<A, B, C> = (A, B, C);

/// Pagination result using records
typedef PaginatedResult<T> = ({
  List<T> items,
  int page,
  int pageSize,
  int totalItems,
  int totalPages,
  bool hasNextPage,
  bool hasPreviousPage,
});

/// API response using records
typedef ApiResponse<T> = ({
  T? data,
  String? error,
  int statusCode,
  Map<String, String> headers,
  Duration responseTime,
});

/// Extension on records for common operations
extension CoordinatesExtension on Coordinates {
  double distanceTo(Coordinates other) {
    const earthRadius = 6371.0; // km
    final lat1 = latitude * math.pi / 180;
    final lat2 = other.latitude * math.pi / 180;
    final dLat = (other.latitude - latitude) * math.pi / 180;
    final dLon = (other.longitude - longitude) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  String toGeoString() => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

extension RangeExtension<T extends num> on Range<T> {
  bool contains(T value) => value >= start && value <= end;
  T get size => (end - start) as T;
  bool overlaps(Range<T> other) =>
      contains(other.start as T) || contains(other.end as T) ||
      other.contains(start) || other.contains(end);
}

/// Pattern matching examples with sealed classes
sealed class Shape {
  const Shape();
  double get area;
  double get perimeter;
}

final class Circle extends Shape {
  final double radius;
  const Circle(this.radius);

  @override
  double get area => math.pi * radius * radius;

  @override
  double get perimeter => 2 * math.pi * radius;
}

final class Rectangle extends Shape {
  final double width;
  final double height;
  const Rectangle(this.width, this.height);

  @override
  double get area => width * height;

  @override
  double get perimeter => 2 * (width + height);
}

final class Triangle extends Shape {
  final double a;
  final double b;
  final double c;
  const Triangle(this.a, this.b, this.c);

  @override
  double get area {
    final s = perimeter / 2;
    return math.sqrt(s * (s - a) * (s - b) * (s - c));
  }

  @override
  double get perimeter => a + b + c;
}

/// Pattern matching helper for shapes
String describeShape(Shape shape) => switch (shape) {
      Circle(radius: final r) when r > 100 => 'Large circle with radius $r',
      Circle(radius: final r) => 'Circle with radius $r',
      Rectangle(width: final w, height: final h) when w == h => 'Square of side $w',
      Rectangle(:final width, :final height) => 'Rectangle ${width}x$height',
      Triangle(a: final a, b: final b, c: final c) when a == b && b == c =>
        'Equilateral triangle with side $a',
      Triangle(:final a, :final b, :final c) => 'Triangle with sides $a, $b, $c',
    };

// ============================================================================
// PART 5: ENTITY CLASSES WITH VALIDATION
// ============================================================================

/// Validation result for entity fields
sealed class FieldValidation {
  const FieldValidation();
}

final class ValidField extends FieldValidation {
  const ValidField();
}

final class InvalidField extends FieldValidation {
  final String error;
  const InvalidField(this.error);
}

/// Email value object with validation
@immutable
class Email {
  final String value;

  const Email._(this.value);

  static Result<Email> create(String value) {
    final trimmed = value.trim().toLowerCase();

    if (trimmed.isEmpty) {
      return Result.failure('Email cannot be empty');
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(trimmed)) {
      return Result.failure('Invalid email format');
    }

    return Result.success(Email._(trimmed));
  }

  String get domain => value.split('@').last;
  String get localPart => value.split('@').first;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Email && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Password value object with validation
@immutable
class Password {
  final String _hashedValue;

  const Password._(this._hashedValue);

  static Result<Password> create(String plainText) {
    if (plainText.length < 8) {
      return Result.failure('Password must be at least 8 characters');
    }

    if (!RegExp(r'[A-Z]').hasMatch(plainText)) {
      return Result.failure('Password must contain at least one uppercase letter');
    }

    if (!RegExp(r'[a-z]').hasMatch(plainText)) {
      return Result.failure('Password must contain at least one lowercase letter');
    }

    if (!RegExp(r'[0-9]').hasMatch(plainText)) {
      return Result.failure('Password must contain at least one digit');
    }

    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(plainText)) {
      return Result.failure('Password must contain at least one special character');
    }

    // In real app, use proper hashing like bcrypt
    final hashed = base64Encode(utf8.encode(plainText));
    return Result.success(Password._(hashed));
  }

  bool verify(String plainText) {
    final hashed = base64Encode(utf8.encode(plainText));
    return hashed == _hashedValue;
  }

  @override
  String toString() => '********';
}

/// User roles as an enhanced enum
enum UserRole {
  admin('Administrator', ['read', 'write', 'delete', 'manage']),
  moderator('Moderator', ['read', 'write', 'delete']),
  user('User', ['read', 'write']),
  guest('Guest', ['read']);

  final String displayName;
  final List<String> permissions;

  const UserRole(this.displayName, this.permissions);

  bool hasPermission(String permission) => permissions.contains(permission);
  bool get canWrite => hasPermission('write');
  bool get canDelete => hasPermission('delete');
  bool get canManage => hasPermission('manage');
}

/// User status as an enhanced enum
enum UserStatus {
  active('Active', true),
  inactive('Inactive', false),
  suspended('Suspended', false),
  pendingVerification('Pending Verification', false),
  deleted('Deleted', false);

  final String displayName;
  final bool canLogin;

  const UserStatus(this.displayName, this.canLogin);
}

/// Address value object
@immutable
class Address {
  final String street;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final Coordinates? coordinates;

  const Address({
    required this.street,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    this.coordinates,
  });

  Address copyWith({
    String? street,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    Coordinates? coordinates,
  }) {
    return Address(
      street: street ?? this.street,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      coordinates: coordinates ?? this.coordinates,
    );
  }

  String get formatted => '$street\n$city, $state $postalCode\n$country';

  Map<String, dynamic> toJson() => {
        'street': street,
        'city': city,
        'state': state,
        'postal_code': postalCode,
        'country': country,
        if (coordinates != null)
          'coordinates': {
            'latitude': coordinates!.latitude,
            'longitude': coordinates!.longitude,
          },
      };

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      street: json['street'] as String,
      city: json['city'] as String,
      state: json['state'] as String,
      postalCode: json['postal_code'] as String,
      country: json['country'] as String,
      coordinates: json['coordinates'] != null
          ? (
              latitude: json['coordinates']['latitude'] as double,
              longitude: json['coordinates']['longitude'] as double,
            )
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Address &&
          runtimeType == other.runtimeType &&
          street == other.street &&
          city == other.city &&
          state == other.state &&
          postalCode == other.postalCode &&
          country == other.country;

  @override
  int get hashCode => Object.hash(street, city, state, postalCode, country);
}

/// User entity with comprehensive validation
@immutable
class User {
  final String id;
  final String name;
  final Email email;
  final UserRole role;
  final UserStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;
  final Address? address;
  final List<String> tags;
  final Map<String, dynamic> metadata;
  final String? avatarUrl;
  final String? phoneNumber;
  final bool emailVerified;
  final bool twoFactorEnabled;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.role = UserRole.user,
    this.status = UserStatus.active,
    required this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
    this.address,
    this.tags = const [],
    this.metadata = const {},
    this.avatarUrl,
    this.phoneNumber,
    this.emailVerified = false,
    this.twoFactorEnabled = false,
  });

  /// Creates a new user with validation
  static Result<User> create({
    required String id,
    required String name,
    required String email,
    UserRole role = UserRole.user,
    Address? address,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    // Validate name
    if (name.trim().isEmpty) {
      return Result.failure('Name cannot be empty');
    }
    if (name.length < 2) {
      return Result.failure('Name must be at least 2 characters');
    }
    if (name.length > 100) {
      return Result.failure('Name cannot exceed 100 characters');
    }

    // Validate email
    final emailResult = Email.create(email);
    if (emailResult.isFailure) {
      return Result.failure((emailResult as Failure).message);
    }

    return Result.success(User(
      id: id,
      name: name.trim(),
      email: (emailResult as Success<Email>).data,
      role: role,
      createdAt: DateTime.now(),
      address: address,
      tags: tags ?? [],
      metadata: metadata ?? {},
    ));
  }

  User copyWith({
    String? id,
    String? name,
    Email? email,
    UserRole? role,
    UserStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
    Address? address,
    List<String>? tags,
    Map<String, dynamic>? metadata,
    String? avatarUrl,
    String? phoneNumber,
    bool? emailVerified,
    bool? twoFactorEnabled,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      address: address ?? this.address,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      emailVerified: emailVerified ?? this.emailVerified,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
    );
  }

  /// Updates the last login timestamp
  User recordLogin() => copyWith(lastLoginAt: DateTime.now());

  /// Verifies the email
  User verifyEmail() => copyWith(emailVerified: true);

  /// Enables two-factor authentication
  User enableTwoFactor() => copyWith(twoFactorEnabled: true);

  /// Disables two-factor authentication
  User disableTwoFactor() => copyWith(twoFactorEnabled: false);

  /// Adds a tag
  User addTag(String tag) {
    if (tags.contains(tag)) return this;
    return copyWith(tags: [...tags, tag]);
  }

  /// Removes a tag
  User removeTag(String tag) {
    return copyWith(tags: tags.where((t) => t != tag).toList());
  }

  /// Checks if user has a specific tag
  bool hasTag(String tag) => tags.contains(tag);

  /// Gets initials from name
  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, math.min(2, name.length)).toUpperCase();
  }

  /// Checks if the user is active
  bool get isActive => status == UserStatus.active;

  /// Checks if the user can perform admin actions
  bool get isAdmin => role == UserRole.admin;

  /// Gets the age of the account in days
  int get accountAgeDays => DateTime.now().difference(createdAt).inDays;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      email: Email.create(json['email'] as String).getOrThrow(),
      role: UserRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => UserRole.user,
      ),
      status: UserStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => UserStatus.active,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      address: json['address'] != null
          ? Address.fromJson(json['address'] as Map<String, dynamic>)
          : null,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      avatarUrl: json['avatar_url'] as String?,
      phoneNumber: json['phone_number'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      twoFactorEnabled: json['two_factor_enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email.value,
        'role': role.name,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (lastLoginAt != null) 'last_login_at': lastLoginAt!.toIso8601String(),
        if (address != null) 'address': address!.toJson(),
        'tags': tags,
        'metadata': metadata,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        'email_verified': emailVerified,
        'two_factor_enabled': twoFactorEnabled,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          email == other.email &&
          role == other.role &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, name, email, role, status);

  @override
  String toString() =>
      'User(id: $id, name: $name, email: $email, role: ${role.name}, status: ${status.name})';
}

// ============================================================================
// PART 6: REPOSITORY PATTERN
// ============================================================================

/// Base repository interface with CRUD operations
abstract class Repository<T, ID> {
  Future<Result<T>> findById(ID id);
  Future<Result<List<T>>> findAll();
  Future<Result<PaginatedResult<T>>> findAllPaginated({
    int page = 1,
    int pageSize = 20,
  });
  Future<Result<T>> create(T entity);
  Future<Result<T>> update(T entity);
  Future<Result<bool>> delete(ID id);
  Future<Result<bool>> exists(ID id);
  Future<Result<int>> count();
}

/// Query specification for filtering
abstract class Specification<T> {
  bool isSatisfiedBy(T entity);
}

/// User specifications
class UserByRoleSpec implements Specification<User> {
  final UserRole role;
  const UserByRoleSpec(this.role);

  @override
  bool isSatisfiedBy(User entity) => entity.role == role;
}

class UserByStatusSpec implements Specification<User> {
  final UserStatus status;
  const UserByStatusSpec(this.status);

  @override
  bool isSatisfiedBy(User entity) => entity.status == status;
}

class ActiveUsersSpec implements Specification<User> {
  const ActiveUsersSpec();

  @override
  bool isSatisfiedBy(User entity) =>
      entity.status == UserStatus.active && entity.emailVerified;
}

/// Extended repository interface with specifications
abstract class SpecificationRepository<T, ID> extends Repository<T, ID> {
  Future<Result<List<T>>> findBySpec(Specification<T> spec);
  Future<Result<int>> countBySpec(Specification<T> spec);
}

/// In-memory user repository implementation
class InMemoryUserRepository implements SpecificationRepository<User, String> {
  final Map<String, User> _storage = {};
  final StreamController<RepositoryEvent<User>> _eventController =
      StreamController<RepositoryEvent<User>>.broadcast();

  Stream<RepositoryEvent<User>> get events => _eventController.stream;

  @override
  Future<Result<User>> findById(String id) async {
    await Future.delayed(const Duration(milliseconds: 50)); // Simulate latency
    final user = _storage[id];
    if (user == null) {
      return Result.failure('User not found', CacheException.notFound(id));
    }
    return Result.success(user);
  }

  @override
  Future<Result<List<User>>> findAll() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return Result.success(_storage.values.toList());
  }

  @override
  Future<Result<PaginatedResult<User>>> findAllPaginated({
    int page = 1,
    int pageSize = 20,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));

    final allUsers = _storage.values.toList();
    final totalItems = allUsers.length;
    final totalPages = (totalItems / pageSize).ceil();
    final startIndex = (page - 1) * pageSize;
    final endIndex = math.min(startIndex + pageSize, totalItems);
