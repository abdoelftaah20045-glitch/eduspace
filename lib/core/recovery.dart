import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// True while the user arrived from a password-recovery email and still has
/// to choose a new password. The auth gate shows the set-new-password screen
/// for as long as this is true.
final ValueNotifier<bool> recoveryMode = ValueNotifier<bool>(false);
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

const _kFlag = 'recovery_requested_ms';
StreamSubscription<AuthState>? _sub;

/// Remembered when the user asks for a reset email, so a recovery link that
/// opens the app (even from a cold start, before any listener exists) is
/// recognised as a recovery and not as a normal sign-in.
Future<void> markRecoveryRequested() async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(_kFlag, DateTime.now().millisecondsSinceEpoch);
}

Future<void> clearRecovery() async {
  recoveryMode.value = false;
  final p = await SharedPreferences.getInstance();
  await p.remove(_kFlag);
}

void _enter() {
  recoveryMode.value = true;
  rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
}

Map<String, dynamic>? _claims(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// Heuristic for a session that was created by a link after the reset was
/// requested (not by a password login).
Future<bool> _looksLikeRecovery(Session? s) async {
  if (s == null) return false;
  final p = await SharedPreferences.getInstance();
  final flag = p.getInt(_kFlag);
  if (flag == null) return false;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - flag > 60 * 60 * 1000) return false;
  final c = _claims(s.accessToken);
  if (c == null) return false;
  final iat = (c['iat'] as num?)?.toInt() ?? 0;
  if (iat * 1000 < flag - 5000) return false;
  final amr = c['amr'];
  if (amr is List && amr.isNotEmpty) {
    final last = amr.first;
    final method = last is Map ? last['method'] : last;
    if (method == 'password') return false;
  }
  return true;
}

/// Call once after Supabase.initialize.
Future<void> initRecoveryListener() async {
  await _sub?.cancel();
  final auth = Supabase.instance.client.auth;
  _sub = auth.onAuthStateChange.listen((st) async {
    if (st.event == AuthChangeEvent.passwordRecovery) {
      _enter();
    } else if (st.event == AuthChangeEvent.signedIn &&
        await _looksLikeRecovery(st.session)) {
      _enter();
    }
  });
  // The link that launched the app may already have been exchanged before
  // the listener existed.
  if (await _looksLikeRecovery(auth.currentSession)) {
    recoveryMode.value = true;
  }
}
