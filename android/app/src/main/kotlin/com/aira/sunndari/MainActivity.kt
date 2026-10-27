package com.aira.sunndari

import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dart side: lib/services/deep_link_service.dart (_checkInstallReferrer)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sunndari/install_referrer")
            .setMethodCallHandler { call, result ->
                if (call.method == "get") readInstallReferrer(result) else result.notImplemented()
            }
    }

    /** Returns the Play Store "referrer" text (e.g. "slug=priya-sheoran-e4c2de") or null. */
    private fun readInstallReferrer(result: MethodChannel.Result) {
        var replied = false
        fun reply(value: String?) {
            if (replied) return
            replied = true
            runOnUiThread { result.success(value) }
        }

        val client = InstallReferrerClient.newBuilder(this).build()
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    try {
                        if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                            reply(client.installReferrer.installReferrer)
                        } else {
                            reply(null)
                        }
                    } catch (e: Exception) {
                        reply(null)
                    } finally {
                        try { client.endConnection() } catch (e: Exception) { }
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    reply(null)
                }
            })
        } catch (e: Exception) {
            reply(null)
        }
    }
}