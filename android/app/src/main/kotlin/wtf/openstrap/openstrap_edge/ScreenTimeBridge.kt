package wtf.openstrap.openstrap_edge

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Edge+: screen time per app and unlocks, the numbers Digital Wellbeing shows.
 *
 * Digital Wellbeing has no public API, but it reads the same UsageStatsManager
 * event log this does. Needs PACKAGE_USAGE_STATS, which only the user grants
 * (Settings > Usage access); nothing here asks at runtime.
 *
 * ponytail: Android keeps the event log for about a week, so history beyond
 * that exists only for days the app already copied (lib/screentime). The
 * launcher and this app are not counted, as Digital Wellbeing does not.
 */
object ScreenTimeBridge {
    private const val CHANNEL = "edgeplus/screen_time"
    private val io = Executors.newSingleThreadExecutor()

    fun register(engine: FlutterEngine, app: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(hasAccess(app))
                    "openSettings" -> {
                        val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        result.success(runCatching { app.startActivity(i) }.isSuccess)
                    }
                    "day" -> {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        if (!hasAccess(app) || end <= start) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        io.execute {
                            val out = runCatching { day(app, start, end) }.getOrNull()
                            android.os.Handler(android.os.Looper.getMainLooper())
                                .post { result.success(out) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        } else {
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** {apps: {package: ms}, labels: {package: name}, unlocks: n} for [start, end). */
    private fun day(ctx: Context, start: Long, end: Long): Map<String, Any> {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = ctx.packageManager
        val home = pm.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0
        )?.activityInfo?.packageName
        val skip = setOf(ctx.packageName, home, "com.android.systemui")

        // Start a little early so an app already open at midnight is caught
        // when it resumed; every interval is clipped to [start, end).
        val events = usm.queryEvents(start - 3 * 3600_000L, end)
        val open = HashMap<String, MutableSet<String>>() // package -> open activities
        val since = HashMap<String, Long>()
        val total = HashMap<String, Long>()
        var unlocks = 0
        fun close(pkg: String, at: Long) {
            val s = since.remove(pkg) ?: return
            val ms = minOf(at, end) - maxOf(s, start)
            if (ms > 0) total[pkg] = (total[pkg] ?: 0L) + ms
        }
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val t = e.timeStamp
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    val set = open.getOrPut(e.packageName) { HashSet() }
                    if (set.isEmpty()) since[e.packageName] = t
                    set.add(e.className ?: "")
                }
                UsageEvents.Event.ACTIVITY_PAUSED, 23 /* ACTIVITY_STOPPED */ -> {
                    val set = open[e.packageName] ?: continue
                    set.remove(e.className ?: "")
                    if (set.isEmpty()) close(e.packageName, t)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    for (p in since.keys.toList()) close(p, t)
                    open.clear()
                }
                18 /* KEYGUARD_HIDDEN, API 28 */ -> if (t >= start) unlocks++
            }
        }
        for (p in since.keys.toList()) close(p, minOf(end, System.currentTimeMillis()))

        val apps = HashMap<String, Long>()
        val labels = HashMap<String, String>()
        for ((pkg, ms) in total) {
            if (pkg in skip || ms < 60_000L) continue
            apps[pkg] = ms
            labels[pkg] = try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                pkg
            }
        }
        return mapOf("apps" to apps, "labels" to labels, "unlocks" to unlocks)
    }
}
