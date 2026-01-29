// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionCommand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SessionCommand()';
}


}

/// @nodoc
class $SessionCommandCopyWith<$Res>  {
$SessionCommandCopyWith(SessionCommand _, $Res Function(SessionCommand) __);
}


/// Adds pattern-matching-related methods to [SessionCommand].
extension SessionCommandPatterns on SessionCommand {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionCommand_Create value)?  create,TResult Function( SessionCommand_Switch value)?  switch_,TResult Function( SessionCommand_Close value)?  close,TResult Function( SessionCommand_List value)?  list,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionCommand_Create() when create != null:
return create(_that);case SessionCommand_Switch() when switch_ != null:
return switch_(_that);case SessionCommand_Close() when close != null:
return close(_that);case SessionCommand_List() when list != null:
return list(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionCommand_Create value)  create,required TResult Function( SessionCommand_Switch value)  switch_,required TResult Function( SessionCommand_Close value)  close,required TResult Function( SessionCommand_List value)  list,}){
final _that = this;
switch (_that) {
case SessionCommand_Create():
return create(_that);case SessionCommand_Switch():
return switch_(_that);case SessionCommand_Close():
return close(_that);case SessionCommand_List():
return list(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionCommand_Create value)?  create,TResult? Function( SessionCommand_Switch value)?  switch_,TResult? Function( SessionCommand_Close value)?  close,TResult? Function( SessionCommand_List value)?  list,}){
final _that = this;
switch (_that) {
case SessionCommand_Create() when create != null:
return create(_that);case SessionCommand_Switch() when switch_ != null:
return switch_(_that);case SessionCommand_Close() when close != null:
return close(_that);case SessionCommand_List() when list != null:
return list(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String projectPath,  String projectName)?  create,TResult Function( String sessionId)?  switch_,TResult Function( String sessionId)?  close,TResult Function()?  list,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionCommand_Create() when create != null:
return create(_that.projectPath,_that.projectName);case SessionCommand_Switch() when switch_ != null:
return switch_(_that.sessionId);case SessionCommand_Close() when close != null:
return close(_that.sessionId);case SessionCommand_List() when list != null:
return list();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String projectPath,  String projectName)  create,required TResult Function( String sessionId)  switch_,required TResult Function( String sessionId)  close,required TResult Function()  list,}) {final _that = this;
switch (_that) {
case SessionCommand_Create():
return create(_that.projectPath,_that.projectName);case SessionCommand_Switch():
return switch_(_that.sessionId);case SessionCommand_Close():
return close(_that.sessionId);case SessionCommand_List():
return list();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String projectPath,  String projectName)?  create,TResult? Function( String sessionId)?  switch_,TResult? Function( String sessionId)?  close,TResult? Function()?  list,}) {final _that = this;
switch (_that) {
case SessionCommand_Create() when create != null:
return create(_that.projectPath,_that.projectName);case SessionCommand_Switch() when switch_ != null:
return switch_(_that.sessionId);case SessionCommand_Close() when close != null:
return close(_that.sessionId);case SessionCommand_List() when list != null:
return list();case _:
  return null;

}
}

}

/// @nodoc


class SessionCommand_Create extends SessionCommand {
  const SessionCommand_Create({required this.projectPath, required this.projectName}): super._();
  

 final  String projectPath;
 final  String projectName;

/// Create a copy of SessionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCommand_CreateCopyWith<SessionCommand_Create> get copyWith => _$SessionCommand_CreateCopyWithImpl<SessionCommand_Create>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCommand_Create&&(identical(other.projectPath, projectPath) || other.projectPath == projectPath)&&(identical(other.projectName, projectName) || other.projectName == projectName));
}


@override
int get hashCode => Object.hash(runtimeType,projectPath,projectName);

@override
String toString() {
  return 'SessionCommand.create(projectPath: $projectPath, projectName: $projectName)';
}


}

/// @nodoc
abstract mixin class $SessionCommand_CreateCopyWith<$Res> implements $SessionCommandCopyWith<$Res> {
  factory $SessionCommand_CreateCopyWith(SessionCommand_Create value, $Res Function(SessionCommand_Create) _then) = _$SessionCommand_CreateCopyWithImpl;
@useResult
$Res call({
 String projectPath, String projectName
});




}
/// @nodoc
class _$SessionCommand_CreateCopyWithImpl<$Res>
    implements $SessionCommand_CreateCopyWith<$Res> {
  _$SessionCommand_CreateCopyWithImpl(this._self, this._then);

  final SessionCommand_Create _self;
  final $Res Function(SessionCommand_Create) _then;

/// Create a copy of SessionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? projectPath = null,Object? projectName = null,}) {
  return _then(SessionCommand_Create(
projectPath: null == projectPath ? _self.projectPath : projectPath // ignore: cast_nullable_to_non_nullable
as String,projectName: null == projectName ? _self.projectName : projectName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SessionCommand_Switch extends SessionCommand {
  const SessionCommand_Switch({required this.sessionId}): super._();
  

 final  String sessionId;

/// Create a copy of SessionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCommand_SwitchCopyWith<SessionCommand_Switch> get copyWith => _$SessionCommand_SwitchCopyWithImpl<SessionCommand_Switch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCommand_Switch&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId);

@override
String toString() {
  return 'SessionCommand.switch_(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $SessionCommand_SwitchCopyWith<$Res> implements $SessionCommandCopyWith<$Res> {
  factory $SessionCommand_SwitchCopyWith(SessionCommand_Switch value, $Res Function(SessionCommand_Switch) _then) = _$SessionCommand_SwitchCopyWithImpl;
@useResult
$Res call({
 String sessionId
});




}
/// @nodoc
class _$SessionCommand_SwitchCopyWithImpl<$Res>
    implements $SessionCommand_SwitchCopyWith<$Res> {
  _$SessionCommand_SwitchCopyWithImpl(this._self, this._then);

  final SessionCommand_Switch _self;
  final $Res Function(SessionCommand_Switch) _then;

/// Create a copy of SessionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(SessionCommand_Switch(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SessionCommand_Close extends SessionCommand {
  const SessionCommand_Close({required this.sessionId}): super._();
  

 final  String sessionId;

/// Create a copy of SessionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCommand_CloseCopyWith<SessionCommand_Close> get copyWith => _$SessionCommand_CloseCopyWithImpl<SessionCommand_Close>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCommand_Close&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId);

@override
String toString() {
  return 'SessionCommand.close(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $SessionCommand_CloseCopyWith<$Res> implements $SessionCommandCopyWith<$Res> {
  factory $SessionCommand_CloseCopyWith(SessionCommand_Close value, $Res Function(SessionCommand_Close) _then) = _$SessionCommand_CloseCopyWithImpl;
@useResult
$Res call({
 String sessionId
});




}
/// @nodoc
class _$SessionCommand_CloseCopyWithImpl<$Res>
    implements $SessionCommand_CloseCopyWith<$Res> {
  _$SessionCommand_CloseCopyWithImpl(this._self, this._then);

  final SessionCommand_Close _self;
  final $Res Function(SessionCommand_Close) _then;

/// Create a copy of SessionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(SessionCommand_Close(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SessionCommand_List extends SessionCommand {
  const SessionCommand_List(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCommand_List);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SessionCommand.list()';
}


}




/// @nodoc
mixin _$VibeInput {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VibeInput);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'VibeInput()';
}


}

/// @nodoc
class $VibeInputCopyWith<$Res>  {
$VibeInputCopyWith(VibeInput _, $Res Function(VibeInput) __);
}


/// Adds pattern-matching-related methods to [VibeInput].
extension VibeInputPatterns on VibeInput {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( VibeInput_Text value)?  text,TResult Function( VibeInput_Key value)?  key,TResult Function( VibeInput_Raw value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case VibeInput_Text() when text != null:
return text(_that);case VibeInput_Key() when key != null:
return key(_that);case VibeInput_Raw() when raw != null:
return raw(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( VibeInput_Text value)  text,required TResult Function( VibeInput_Key value)  key,required TResult Function( VibeInput_Raw value)  raw,}){
final _that = this;
switch (_that) {
case VibeInput_Text():
return text(_that);case VibeInput_Key():
return key(_that);case VibeInput_Raw():
return raw(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( VibeInput_Text value)?  text,TResult? Function( VibeInput_Key value)?  key,TResult? Function( VibeInput_Raw value)?  raw,}){
final _that = this;
switch (_that) {
case VibeInput_Text() when text != null:
return text(_that);case VibeInput_Key() when key != null:
return key(_that);case VibeInput_Raw() when raw != null:
return raw(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String prompt)?  text,TResult Function( String keyCode)?  key,TResult Function( Uint8List data)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case VibeInput_Text() when text != null:
return text(_that.prompt);case VibeInput_Key() when key != null:
return key(_that.keyCode);case VibeInput_Raw() when raw != null:
return raw(_that.data);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String prompt)  text,required TResult Function( String keyCode)  key,required TResult Function( Uint8List data)  raw,}) {final _that = this;
switch (_that) {
case VibeInput_Text():
return text(_that.prompt);case VibeInput_Key():
return key(_that.keyCode);case VibeInput_Raw():
return raw(_that.data);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String prompt)?  text,TResult? Function( String keyCode)?  key,TResult? Function( Uint8List data)?  raw,}) {final _that = this;
switch (_that) {
case VibeInput_Text() when text != null:
return text(_that.prompt);case VibeInput_Key() when key != null:
return key(_that.keyCode);case VibeInput_Raw() when raw != null:
return raw(_that.data);case _:
  return null;

}
}

}

/// @nodoc


class VibeInput_Text extends VibeInput {
  const VibeInput_Text({required this.prompt}): super._();
  

 final  String prompt;

/// Create a copy of VibeInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VibeInput_TextCopyWith<VibeInput_Text> get copyWith => _$VibeInput_TextCopyWithImpl<VibeInput_Text>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VibeInput_Text&&(identical(other.prompt, prompt) || other.prompt == prompt));
}


@override
int get hashCode => Object.hash(runtimeType,prompt);

@override
String toString() {
  return 'VibeInput.text(prompt: $prompt)';
}


}

/// @nodoc
abstract mixin class $VibeInput_TextCopyWith<$Res> implements $VibeInputCopyWith<$Res> {
  factory $VibeInput_TextCopyWith(VibeInput_Text value, $Res Function(VibeInput_Text) _then) = _$VibeInput_TextCopyWithImpl;
@useResult
$Res call({
 String prompt
});




}
/// @nodoc
class _$VibeInput_TextCopyWithImpl<$Res>
    implements $VibeInput_TextCopyWith<$Res> {
  _$VibeInput_TextCopyWithImpl(this._self, this._then);

  final VibeInput_Text _self;
  final $Res Function(VibeInput_Text) _then;

/// Create a copy of VibeInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? prompt = null,}) {
  return _then(VibeInput_Text(
prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VibeInput_Key extends VibeInput {
  const VibeInput_Key({required this.keyCode}): super._();
  

 final  String keyCode;

/// Create a copy of VibeInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VibeInput_KeyCopyWith<VibeInput_Key> get copyWith => _$VibeInput_KeyCopyWithImpl<VibeInput_Key>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VibeInput_Key&&(identical(other.keyCode, keyCode) || other.keyCode == keyCode));
}


@override
int get hashCode => Object.hash(runtimeType,keyCode);

@override
String toString() {
  return 'VibeInput.key(keyCode: $keyCode)';
}


}

/// @nodoc
abstract mixin class $VibeInput_KeyCopyWith<$Res> implements $VibeInputCopyWith<$Res> {
  factory $VibeInput_KeyCopyWith(VibeInput_Key value, $Res Function(VibeInput_Key) _then) = _$VibeInput_KeyCopyWithImpl;
@useResult
$Res call({
 String keyCode
});




}
/// @nodoc
class _$VibeInput_KeyCopyWithImpl<$Res>
    implements $VibeInput_KeyCopyWith<$Res> {
  _$VibeInput_KeyCopyWithImpl(this._self, this._then);

  final VibeInput_Key _self;
  final $Res Function(VibeInput_Key) _then;

/// Create a copy of VibeInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? keyCode = null,}) {
  return _then(VibeInput_Key(
keyCode: null == keyCode ? _self.keyCode : keyCode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VibeInput_Raw extends VibeInput {
  const VibeInput_Raw({required this.data}): super._();
  

 final  Uint8List data;

/// Create a copy of VibeInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VibeInput_RawCopyWith<VibeInput_Raw> get copyWith => _$VibeInput_RawCopyWithImpl<VibeInput_Raw>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VibeInput_Raw&&const DeepCollectionEquality().equals(other.data, data));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'VibeInput.raw(data: $data)';
}


}

/// @nodoc
abstract mixin class $VibeInput_RawCopyWith<$Res> implements $VibeInputCopyWith<$Res> {
  factory $VibeInput_RawCopyWith(VibeInput_Raw value, $Res Function(VibeInput_Raw) _then) = _$VibeInput_RawCopyWithImpl;
@useResult
$Res call({
 Uint8List data
});




}
/// @nodoc
class _$VibeInput_RawCopyWithImpl<$Res>
    implements $VibeInput_RawCopyWith<$Res> {
  _$VibeInput_RawCopyWithImpl(this._self, this._then);

  final VibeInput_Raw _self;
  final $Res Function(VibeInput_Raw) _then;

/// Create a copy of VibeInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? data = null,}) {
  return _then(VibeInput_Raw(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

// dart format on
