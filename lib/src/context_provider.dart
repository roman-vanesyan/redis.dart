import 'package:redis/src/executor.dart';
import 'package:redis/src/pubsub_context.dart';
import 'package:redis/src/scripting_context.dart';
import 'package:redis/src/strings_context.dart';

mixin ContextProvider on Executor {
  PubSubContext _pubSubContext;
  ScriptingContext _scriptingContext;
  StringsContext _stringsContext;

  PubSubContext get pubSub => _pubSubContext ??= PubSubContext(this);

  StringsContext get strings => _stringsContext ??= StringsContext(this);

  ScriptingContext get scripting =>
      _scriptingContext ??= ScriptingContext(this);
}
