package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen metrics widget — the Android sibling of OpenStrapWidget.swift.
 *
 * IT IS THE SAME THREE RINGS AS HOME: Recovery · Strain · Sleep, in that order,
 * the icon inside the dial and the number under it. It used to be four rings
 * (Ready · Strain · Sleep · HRV) with the number inside, which was the previous
 * design system's home screen; HRV stopped being one of Home's rings in the
 * rebuild and lives on OvernightWidgetProvider instead.
 *
 * Renders the snapshot WidgetService.push() writes through home_widget; the app
 * broadcasts an update after every derive and every foreground. There is no
 * network on this side — updatePeriodMillis only re-renders the cached snapshot
 * so the theme and the staleness rule stay honest when the app hasn't run.
 *
 * Four faces sharing every id so there is one render path: three rows (2x2),
 * three columns (4x2), and — Edge+ — a single row (4x1/3x1: dial + number per
 * ring) and a narrow single row (2x1: Recovery alone with its band). On
 * Android 12+ the launcher picks by live size; below that we choose from the
 * widget's min width and height.
 */
class OpenStrapWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        prefs: SharedPreferences,
    ) {
        val views: RemoteViews = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The launcher takes the closest size that FITS; on a tie the
            // first entry wins, so the two-row faces come first. 90dp, not
            // 110: some launchers report two rows a little under 110, and
            // those must not drop to the one-row face.
            RemoteViews(
                linkedMapOf(
                    SizeF(110f, 90f) to build(context, prefs, Face.SMALL),
                    SizeF(250f, 90f) to build(context, prefs, Face.WIDE),
                    SizeF(180f, 40f) to build(context, prefs, Face.LINE),
                    SizeF(110f, 40f) to build(context, prefs, Face.LINE_NARROW),
                ),
            )
        } else {
            val opts = manager.getAppWidgetOptions(id)
            val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val minH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            val face = when {
                minH in 1..89 -> if (minW in 1..179) Face.LINE_NARROW else Face.LINE
                minW in 1..249 -> Face.SMALL
                else -> Face.WIDE
            }
            build(context, prefs, face)
        }
        manager.updateAppWidget(id, views)
    }

    /** Which face. Same ids in every layout; only what is shown differs. */
    private enum class Face(val layout: Int, val dialDp: Int, val strokeDp: Float) {
        WIDE(R.layout.widget_openstrap, 44, 6f),
        SMALL(R.layout.widget_openstrap_small, 30, 4.5f),
        LINE(R.layout.widget_openstrap_line, 28, 3.5f),
        LINE_NARROW(R.layout.widget_openstrap_line, 28, 3.5f);

        val line: Boolean get() = this == LINE || this == LINE_NARROW
    }

    /** One ring's three views and the icon that goes in its dial. */
    private class Slot(
        val key: String,
        val label: String,
        val iconRes: Int,
        val dial: Int,
        val cap: Int,
        val value: Int,
        val sub: Int,
    )

    private val slots = listOf(
        Slot("recovery", "RECOVERY", R.drawable.ic_widget_recovery,
            R.id.dial_recovery, R.id.cap_recovery, R.id.val_recovery, R.id.sub_recovery),
        Slot("strain", "STRAIN", R.drawable.ic_widget_strain,
            R.id.dial_strain, R.id.cap_strain, R.id.val_strain, R.id.sub_strain),
        Slot("sleep", "SLEEP", R.drawable.ic_widget_sleep,
            R.id.dial_sleep, R.id.cap_sleep, R.id.val_sleep, R.id.sub_sleep),
    )

    private fun build(context: Context, prefs: SharedPreferences, face: Face): RemoteViews {
        val w = StrapWidgets
        val pal = w.pal(prefs)

        // `has_data` alone was never enough: it is frozen when the app pushes,
        // so a phone that stops syncing keeps a week-old readiness on the home
        // screen looking exactly like this morning's. StrapWidgets.fresh() ages
        // `updated_at` here, on every render.
        if (!w.fresh(prefs)) return buildNoData(context, pal, face.line)

        val views = RemoteViews(context.packageName, face.layout)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.openAppIntent(context))

        // Recovery wears its band's colour (from the published tier — the
        // cut-offs are never re-derived here), the other two their domain accent.
        val tier = w.readInt(prefs, "readiness_tier", -1)
        var gap: Pair<String, String>? = null

        for (slot in slots) {
            // The narrow row is Recovery alone: the other two slots go.
            if (face == Face.LINE_NARROW && slot.key != "recovery") {
                views.setViewVisibility(slotContainer(slot.key), View.GONE)
                continue
            }
            val r = w.ring(prefs, slot.key)
            val accent = when (slot.key) {
                "recovery" -> w.tierColor(tier, pal)
                "strain" -> pal.move
                else -> pal.sleep
            }
            val tint = r.color(accent, pal)
            views.setImageViewBitmap(
                slot.dial,
                w.dialBitmap(
                    context, face.dialDp, face.strokeDp, pal.track, tint, r.frac, slot.iconRes,
                    iconScale = if (face.line) 0.5f else 0.42f,
                ),
            )
            views.setContentDescription(slot.dial, slot.label)
            if (!face.line) {
                views.setTextViewText(slot.cap, slot.label)
                views.setTextColor(slot.cap, pal.inkMuted)
            }
            // The absence takes the SENTENCE colour rather than the numeral
            // one, because it is a sentence: "No sleep" in full-weight ink
            // would read as a score.
            views.setTextViewText(slot.value, r.value)
            views.setTextColor(slot.value, if (r.measured) pal.ink else pal.ink2)
            if (face == Face.WIDE || (face == Face.LINE_NARROW && r.sub.isNotEmpty())) {
                views.setViewVisibility(slot.sub, View.VISIBLE)
                views.setTextViewText(slot.sub, r.sub)
                views.setTextColor(slot.sub, pal.inkMuted)
            }
            if (gap == null && r.why.isNotEmpty()) gap = slot.label to r.why
        }

        // The first ring that is missing and said why. One line is what a
        // widget can afford; the rest is one tap away in the app.
        if (face == Face.WIDE) {
            val g = gap
            if (g == null) {
                views.setViewVisibility(R.id.gap_row, View.GONE)
            } else {
                views.setViewVisibility(R.id.gap_row, View.VISIBLE)
                views.setTextViewText(R.id.gap_row, "${g.first} · ${g.second}")
                views.setTextColor(R.id.gap_row, pal.inkMuted)
            }
        }
        return views
    }

    private fun slotContainer(key: String): Int = when (key) {
        "strain" -> R.id.slot_strain
        else -> R.id.slot_sleep
    }

    private fun buildNoData(context: Context, pal: StrapWidgets.Pal, line: Boolean): RemoteViews =
        StrapWidgets.noData(context, pal, line)
}
