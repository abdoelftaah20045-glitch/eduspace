#!/bin/sh
# Writes MainActivity.kt with FLAG_SECURE on by default (screenshots, screen
# recording and the app-switcher preview are blocked) plus a channel the app
# uses to switch it off when the admin turns screen protection off.
set -e
F=$(find android/app/src/main -name MainActivity.kt | head -1)
[ -n "$F" ] || { echo "MainActivity.kt not found"; exit 1; }
PKG=$(grep -m1 '^package ' "$F" | sed 's/package //')
cat > "$F" <<KT
package $PKG

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "deki/secure")
            .setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    val on = call.arguments as? Boolean ?: true
                    runOnUiThread {
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
KT
cat "$F" | head -5
