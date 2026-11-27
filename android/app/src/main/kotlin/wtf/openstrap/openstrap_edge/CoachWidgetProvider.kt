package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Edge+: what the coach says about today — the Android sibling of
 * OpenStrapCoachWidget.swift.
 *
 * The Recovery dial (its band colour, the coach's sparkle inside), the band
 * over the first plan item (`coach_line`), and the reason under it
 * (`coach_detail`) when the widget is two rows tall. One row by default:
 * this is the widget to put under a clock.
 */
class CoachWidgetProvider : HomeWidgetProvider() {

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

    private fun render(context: Context, manager: AppWidgetManager, id: Int, prefs: SharedPreferences) {
        val views = StrapWidgets.tallOrLine(manager, id, SizeF(180f, 90f)) { line ->
            build(context, prefs, line)
        }
        manager.updateAppWidget(id, views)
    }

    private fun build(context: Context, prefs: SharedPreferences, line: Boolean): RemoteViews {
        val w = StrapWidgets
        val pal = w.pal(prefs)
        if (!w.fresh(prefs)) return w.noData(context, pal, line)

        val r = w.ring(prefs, "recovery")
        val tier = w.readInt(prefs, "readiness_tier", -1)
        val band = prefs.getString("readiness_band", "") ?: ""
        val title = prefs.getString("coach_line", "") ?: ""
        val detail = prefs.getString("coach_detail", "") ?: ""
        val tint = r.color(w.tierColor(tier, pal), pal)

        val views = RemoteViews(context.packageName, R.layout.widget_coach)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.routeIntent(context, "/today"))
        views.setImageViewBitmap(
            R.id.dial,
            w.dialBitmap(
                context, 36, 4.5f, pal.track, tint, r.frac,
                R.drawable.ic_widget_coach, iconScale = 0.46f,
            ),
        )
        views.setContentDescription(R.id.dial, "Recovery")
        // "TODAY · 72 GOOD TO GO" when scored; plain "TODAY" when not.
        val cap = if (r.measured && band.isNotEmpty()) "TODAY · ${r.value} ${band.uppercase()}" else "TODAY"
        views.setTextViewText(R.id.cap, cap)
        views.setTextColor(R.id.cap, pal.inkMuted)
        views.setTextViewText(R.id.title, title.ifEmpty { "No plan yet" })
        views.setTextColor(R.id.title, if (title.isEmpty()) pal.ink2 else pal.ink)
        views.setInt(R.id.title, "setMaxLines", if (line) 1 else 2)

        val body = if (title.isEmpty()) "Open OpenStrap for today's coaching." else detail
        val showDetail = !line && body.isNotEmpty()
        views.setViewVisibility(R.id.detail, if (showDetail) View.VISIBLE else View.GONE)
        if (showDetail) {
            views.setTextViewText(R.id.detail, body)
            views.setTextColor(R.id.detail, pal.inkMuted)
        }
        return views
    }
}
