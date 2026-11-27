package wtf.openstrap.openstrap_edge

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.content.ContextCompat

/**
 * Shared bits for the home-screen widgets — the palette, readers for the
 * home_widget snapshot, the freshness rule, and the dial renderer. The Kotlin
 * half of ios/OpenStrapWidget/StrapWidgetKit.swift, so the two platforms read
 * as the same product.
 *
 * WHAT THIS SIDE DECIDES: layout, and nothing else. Whether a ring is a
 * reading, calibration progress or an absence — and what any of them SAY —
 * arrives already resolved from `WidgetService.push`, which mirrors `RingTrio`
 * on Home. The rule used to live in Dart AND Swift AND here, and the three
 * copies disagreed about the same day.
 *
 * Dials are pre-rendered as bitmaps because RemoteViews cannot draw arcs.
 */
internal object StrapWidgets {

    // ── lib/ui2/theme.dart (mirrors SW.Pal in StrapWidgetKit.swift) ────────
    // A widget is a card, so surfaces are `P.card` over a `P.track` ring track,
    // `P.ink` numerals and `P.ink3` captions.
    class Pal(
        val bgRes: Int,
        val ink: Int,
        val ink2: Int,
        val inkMuted: Int,
        val track: Int,
        val good: Int,
        val warn: Int,
        val bad: Int,
        val sleep: Int,
        val move: Int,
    )

    // `P.on(accent)` per brightness — ui2 nudges an accent toward the page ink
    // until it clears WCAG AA 4.5:1 on the worst surface it can land on, and a
    // ring spends that solved value for BOTH its arc and its number (see
    // `_RingState.arc` / `.ink` in home_screen.dart). Recomputing these means
    // running P.on's binary search, not eyeballing a hex.
    private val LIGHT = Pal(
        R.drawable.widget_bg_paper,
        0xFF0F172A.toInt(), 0xFF475569.toInt(), 0xFF627188.toInt(), 0xFFE2E8F0.toInt(),
        0xFF1A7A48.toInt(), 0xFFA5521D.toInt(), 0xFFB9393E.toInt(),
        0xFF2F66C0.toInt(), 0xFF734FCF.toInt(),
    )
    private val DARK = Pal(
        R.drawable.widget_bg_char,
        0xFFF1F5F9.toInt(), 0xFF94A3B8.toInt(), 0xFF7F8DA0.toInt(), 0xFF232D3B.toInt(),
        0xFF22C55E.toInt(), 0xFFF87E28.toInt(), 0xFFF07374.toInt(),
        0xFF689EF7.toInt(), 0xFFA988F7.toInt(),
    )

    // Raw pigment — `C` in lib/ui2/theme.dart. Arcs and fills only.
    const val GREEN = 0xFF22C55E.toInt()
    const val ORANGE = 0xFFF97316.toInt()
    const val RED = 0xFFEF4444.toInt()
    const val BLUE = 0xFF3B82F6.toInt()      // sleep
    const val PURPLE = 0xFF8B5CF6.toInt()    // strain / movement
    const val N400 = 0xFF94A3B8.toInt()

    /**
     * How old the snapshot may be before the widget stops presenting it as
     * today's answer. `has_data` is a bool frozen when Dart pushed it, so on a
     * phone that stops syncing it stays true forever and a week-old readiness
     * sits on the home screen looking like this morning's; the age of
     * `updated_at` is what actually answers the question, and RemoteViews are
     * rebuilt on every broadcast so this is genuinely a render-time check.
     *
     * 26 h = one whole missed wake cycle plus grace. Same value and reasoning as
     * `kStaleAfter` in ios/OpenStrapWidget/OpenStrapWidget.swift.
     */
    private const val STALE_AFTER_SEC = 26L * 3600

    /** The three home rings, in Home's order. */
    val RING_KEYS = listOf("recovery", "strain", "sleep")

    /** Is the published snapshot still today's answer? */
    fun fresh(prefs: SharedPreferences): Boolean {
        if (!prefs.getBoolean("has_data", false)) return false
        // A snapshot written by an app version older than the rings has every
        // ring value empty, which draws circles with nothing in them. It heals
        // on the first push (the app publishes on every foreground); until then
        // the no-data state is the honest picture.
        if (RING_KEYS.all { prefs.getString("ring_${it}_value", "").isNullOrEmpty() }) return false
        val at = readLong(prefs, "updated_at", 0)
        // An unknown timestamp is not a claim of staleness (matching
        // WidgetService.isStale); a snapshot never pushed has has_data false.
        if (at <= 0L) return true
        return System.currentTimeMillis() / 1000 - at <= STALE_AFTER_SEC
    }

    /**
     * Readiness tier -> its accent, arc and numeral alike. The THRESHOLDS are
     * not here: Dart publishes `readiness_tier` (see `readinessBand` in
     * lib/ui2/screens/home_screen.dart) so the phone, the widget, the watch and
     * Siri cannot disagree about what a score of 65 means. Never re-derive a
     * band from the raw number.
     */
    fun tierColor(tier: Int, pal: Pal): Int = when (tier) {
        3, 2 -> pal.good
        1 -> pal.warn
        0 -> pal.bad
        else -> pal.inkMuted
    }

    /// The app mirrors its in-app appearance into `theme_dark` (see
    /// WidgetService.setThemeDark) — same source of truth as the iOS widgets.
    fun pal(prefs: SharedPreferences): Pal =
        if (prefs.getBoolean("theme_dark", false)) DARK else LIGHT

    // ── home_widget snapshot readers ─────────────────────────────────────────
    // home_widget's Android store isn't type-stable across Dart types: Dart ints
    // arrive as Int, but Dart doubles are stored as RAW LONG BITS
    // (putLong(doubleToRawLongBits)) — see HomeWidgetPlugin.saveWidgetData. Read
    // through `all[key]` and coerce, so a type drift never crashes a widget.

    fun readInt(prefs: SharedPreferences, key: String, def: Int): Int =
        when (val v = prefs.all[key]) {
            is Int -> v
            is Long -> v.toInt()
            is Float -> v.toInt()
            else -> def
        }

    /** Epoch seconds. Read as Long: coerced through Int these overflow negative
     *  in 2038, and a negative timestamp reads as infinitely stale. */
    fun readLong(prefs: SharedPreferences, key: String, def: Long): Long =
        when (val v = prefs.all[key]) {
            is Long -> v
            is Int -> v.toLong()
            is Float -> v.toLong()
            else -> def
        }

    fun readDouble(prefs: SharedPreferences, key: String, def: Double): Double =
        when (val v = prefs.all[key]) {
            is Long -> Double.fromBits(v) // Dart double → raw bits (see above)
            is Float -> v.toDouble()
            is Int -> v.toDouble()
            else -> def
        }

    // ── the resolved rings ───────────────────────────────────────────────────
    /** One home ring exactly as Dart published it. */
    class RingData(
        /** 0 measured · 1 calibrating · 2 absent. */
        val state: Int,
        /** The number, or the absence IN WORDS — never a dash. */
        val value: String,
        /** What it is out of, the readiness band, or the nights banked. */
        val sub: String,
        /** The pipeline's own reason. Absent rings only. */
        val why: String,
        /** What to sweep, 0..1 — negative when there is nothing honest to sweep. */
        val frac: Double,
    ) {
        val measured: Boolean get() = state == 0

        /** Arc and numeral share one colour, and the colour IS the signal that
         *  this is not a reading. */
        fun color(accent: Int, pal: Pal): Int = if (measured) accent else pal.inkMuted
    }

    fun ring(prefs: SharedPreferences, key: String): RingData = RingData(
        readInt(prefs, "ring_${key}_state", 2),
        prefs.getString("ring_${key}_value", "") ?: "",
        prefs.getString("ring_${key}_sub", "") ?: "",
        prefs.getString("ring_${key}_why", "") ?: "",
        readDouble(prefs, "ring_${key}_frac", -1.0),
    )

    // ── formatting ───────────────────────────────────────────────────────────
    /** "45m" / "7h 05m" — the phone's own `hm()` (lib/ui2/screens/home_screen.dart),
     *  so the same night reads identically on the phone, the widget and iOS.
     *  Empty for "no measurement": never a bare dash. */
    fun hm(min: Int): String {
        if (min < 0) return ""
        if (min < 60) return "${min}m"
        // Locale.ROOT: default-locale %d emits localized digit shapes (ar/fa/bn),
        // diverging from the plain "$x" templates beside it — two digit systems
        // on one widget. The iOS sibling formats invariantly.
        return String.format(java.util.Locale.ROOT, "%dh %02dm", min / 60, min % 60)
    }

    // ── ring renderer ────────────────────────────────────────────────────────
    /** Track circle + progress arc from 12 o'clock, round caps — the iOS Ring. */
    fun ringBitmap(
        context: Context,
        sizeDp: Int,
        strokeDp: Float,
        trackColor: Int,
        color: Int,
        t: Double,
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val px = (sizeDp * density).toInt().coerceAtLeast(1)
        val stroke = strokeDp * density
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }
        val inset = stroke / 2f
        val rect = RectF(inset, inset, px - inset, px - inset)
        paint.color = trackColor
        canvas.drawArc(rect, 0f, 360f, false, paint)
        val frac = t.coerceIn(0.0, 1.0)
        if (frac > 0) {
            paint.color = color
            canvas.drawArc(rect, -90f, (360.0 * frac).toFloat(), false, paint)
        }
        return bmp
    }

    /**
     * The dial: the arc with the ring's ICON at its centre, as on Home. The
     * number lives UNDER the dial, not inside it — inside is where "7h 45m"
     * overflows its own circle at the first accessibility step, and nothing
     * about that string gets shorter.
     *
     * The icon is drawn into the same bitmap rather than stacked as a second
     * RemoteViews child: one view per dial, and the tint cannot drift from the
     * arc it sits in.
     */
    fun dialBitmap(
        context: Context,
        sizeDp: Int,
        strokeDp: Float,
        trackColor: Int,
        color: Int,
        t: Double,
        iconRes: Int,
        // Edge+: 0.34 left the glyph a speck inside its arc; the Lucide
        // icons are drawn heavier now and sit a little larger.
        iconScale: Float = 0.42f,
    ): Bitmap {
        val bmp = ringBitmap(context, sizeDp, strokeDp, trackColor, color, t)
        val icon = ContextCompat.getDrawable(context, iconRes)?.mutate() ?: return bmp
        val px = bmp.width
        val side = (px * iconScale).toInt().coerceAtLeast(1)
        val left = (px - side) / 2
        icon.setBounds(left, left, left + side, left + side)
        icon.setTint(color)
        icon.draw(Canvas(bmp))
        return bmp
    }

    // ── Edge+: shared by the activity, stress, coach and quick-action widgets ─

    /** "8,412" — grouped, invariant digits (see [hm] for why ROOT). */
    fun grouped(n: Int): String = String.format(java.util.Locale.ROOT, "%,d", n)

    /**
     * A rounded horizontal bar of [segments] (fraction, colour) laid end to
     * end over a [track]-coloured pill. One bitmap, because RemoteViews has no
     * weighted drawing; a fraction sum under 1 leaves the track showing.
     */
    fun barBitmap(
        context: Context,
        widthDp: Int,
        heightDp: Int,
        track: Int,
        segments: List<Pair<Double, Int>>,
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val w = (widthDp * density).toInt().coerceAtLeast(1)
        val h = (heightDp * density).toInt().coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = h / 2f
        val clip = android.graphics.Path().apply {
            addRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), r, r, android.graphics.Path.Direction.CW)
        }
        canvas.clipPath(clip)
        paint.color = track
        canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        var x = 0f
        for ((frac, color) in segments) {
            val f = frac.coerceIn(0.0, 1.0).toFloat()
            if (f <= 0f) continue
            val end = (x + f * w).coerceAtMost(w.toFloat())
            paint.color = color
            canvas.drawRect(x, 0f, end, h.toFloat(), paint)
            x = end
        }
        return bmp
    }

    /** The shared no-data face, themed and tappable. */
    fun noData(context: Context, pal: Pal, line: Boolean = false): android.widget.RemoteViews =
        android.widget.RemoteViews(
            context.packageName,
            if (line) R.layout.widget_nodata_line else R.layout.widget_openstrap_nodata,
        ).apply {
            setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
            setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
            setTextColor(R.id.nodata_title, pal.ink)
            setTextColor(R.id.nodata_body, pal.inkMuted)
        }

    /**
     * The two-face rule the Edge+ widgets share: [tall] from [tallSize] up,
     * the one-row face below its height. Android 12+ lets the launcher pick by
     * live size; older launchers only report a min height, so we pick here.
     */
    fun tallOrLine(
        manager: android.appwidget.AppWidgetManager,
        id: Int,
        tallSize: android.util.SizeF,
        build: (line: Boolean) -> android.widget.RemoteViews,
    ): android.widget.RemoteViews =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            android.widget.RemoteViews(
                linkedMapOf(
                    tallSize to build(false),
                    android.util.SizeF(tallSize.width, 40f) to build(true),
                ),
            )
        } else {
            val minH = manager.getAppWidgetOptions(id)
                .getInt(android.appwidget.AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            build(minH in 1 until tallSize.height.toInt())
        }

    /**
     * A quick-action chip: the [iconRes] glyph in [color] over a soft disc of
     * the same colour, so four actions read as four colours at a glance.
     */
    fun chipBitmap(context: Context, sizeDp: Int, color: Int, iconRes: Int): Bitmap {
        val density = context.resources.displayMetrics.density
        val px = (sizeDp * density).toInt().coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = 0x2E
        }
        canvas.drawCircle(px / 2f, px / 2f, px / 2f, paint)
        val icon = ContextCompat.getDrawable(context, iconRes)?.mutate() ?: return bmp
        val side = (px * 0.5f).toInt().coerceAtLeast(1)
        val left = (px - side) / 2
        icon.setBounds(left, left, left + side, left + side)
        icon.setTint(color)
        icon.draw(canvas)
        return bmp
    }

    /** Intent extra MainActivity hands to `pending_route` (see [routeIntent]). */
    const val EXTRA_ROUTE = "wtf.openstrap.widget_route"

    /**
     * Tap → open the app ON [route] (a lib/notify/tap_router.dart route).
     * MainActivity copies the extra into the home_widget store's
     * `pending_route`, the same latch the iOS App Intents use, and
     * AppState.checkPendingSiriRoute consumes it on launch/resume. The data
     * URI keeps each route's PendingIntent distinct — extras alone do not.
     */
    fun routeIntent(context: Context, route: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            route.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = android.net.Uri.parse("openstrap-widget://route$route")
                putExtra(EXTRA_ROUTE, route)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /** Tap anywhere on a widget → open the app. */
    fun openAppIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
