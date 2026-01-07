// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$connectionStateHash() => r'779a64f9b5e74ab58f4f6108d6581fd05f98c297';

/// Riverpod provider for connection state
///
/// Phase 06: Refactor từ ChangeNotifier sang Riverpod
/// Dùng @riverpod annotation với code generation
///
/// Copied from [ConnectionState].
@ProviderFor(ConnectionState)
final connectionStateProvider =
    AutoDisposeNotifierProvider<ConnectionState, ConnectionModel>.internal(
      ConnectionState.new,
      name: r'connectionStateProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$connectionStateHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ConnectionState = AutoDisposeNotifier<ConnectionModel>;
String _$terminalOutputHash() => r'2de553c7ef0d3a03b6e25f03cdd55ff34ae504dd';

/// Riverpod provider for terminal output
///
/// Stores terminal output lines
///
/// Copied from [TerminalOutput].
@ProviderFor(TerminalOutput)
final terminalOutputProvider =
    AutoDisposeNotifierProvider<TerminalOutput, TerminalOutputModel>.internal(
      TerminalOutput.new,
      name: r'terminalOutputProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$terminalOutputHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$TerminalOutput = AutoDisposeNotifier<TerminalOutputModel>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
