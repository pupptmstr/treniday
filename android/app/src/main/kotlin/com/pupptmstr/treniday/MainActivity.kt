package com.pupptmstr.treniday

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant

// FlutterFragmentActivity extends FragmentActivity → ComponentActivity,
// which is required by the health plugin (cachet.plugins.health.HealthPlugin).
class MainActivity : FlutterFragmentActivity() {
    private val scope = MainScope()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "treniday/health")
            .setMethodCallHandler { call, result ->
                if (call.method != "exerciseSessions") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val start = call.argument<Number>("start")!!.toLong()
                val end = call.argument<Number>("end")!!.toLong()
                scope.launch { result.success(exerciseSessions(start, end)) }
            }
    }

    /**
     * The start and end (epoch ms) of every exercise session in Health Connect
     * between [start] and [end], or null when they cannot be read (HealthService
     * then adds nothing). Only the sessions themselves: the health plugin also
     * reads each session's distance, energy and steps, which needs read
     * permissions TreniDay does not ask for. With READ_EXERCISE the sessions of
     * every app; without it, those TreniDay wrote.
     */
    private suspend fun exerciseSessions(start: Long, end: Long): List<List<Long>>? = try {
        val client = HealthConnectClient.getOrCreate(this)
        val spans = mutableListOf<List<Long>>()
        var pageToken: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = ExerciseSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(
                        Instant.ofEpochMilli(start),
                        Instant.ofEpochMilli(end),
                    ),
                    pageToken = pageToken,
                )
            )
            for (session in response.records) {
                spans.add(listOf(session.startTime.toEpochMilli(), session.endTime.toEpochMilli()))
            }
            pageToken = response.pageToken
        } while (pageToken != null)
        spans
    } catch (e: Exception) {
        null
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
