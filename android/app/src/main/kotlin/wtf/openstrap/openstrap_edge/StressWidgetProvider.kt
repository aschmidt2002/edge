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
 * Edge+: today's stress — the Android sibling of OpenStrapStressWidget.swift.
 *
 * The day's score in its dial, the band IN WORDS, and how the worn time split
 * between calm, balanced and stressed as one bar. The band and its index
 * (`stress_tier`) arrive from Dart (StressData.band / .tier); this side only
 * picks a colour per index and never re-derives the cut-offs.
 */
class StressWidgetProvider : HomeWidgetProvider() {

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
        val views = StrapWidgets.tallOrLine(manager, id, SizeF(110f, 90f)) { line ->
            build(context, prefs, line)
        }
        manager.updateAppWidget(id, views)
    }

    private fun build(context: Context, prefs: SharedPreferences, line: Boolean): RemoteViews {
        val w = StrapWidgets
        val pal = w.pal(prefs)
        if (!w.fresh(prefs)) return w.noData(context, pal, line)

        val score = w.readInt(prefs, "stress_score", -1)
        val tier = w.readInt(prefs, "stress_tier", -1)
        val band = prefs.getString("stress_band", "") ?: ""
        val calm = w.readInt(prefs, "stress_calm_min", -1)
        val balanced = w.readInt(prefs, "stress_balanced_min", -1)
        val stressed = w.readInt(prefs, "stress_stressed_min", -1)
        val measured = score >= 0
        val tint = if (!measured) pal.inkMuted else when (tier) {
            0 -> pal.good
            1 -> pal.sleep
            2 -> pal.warn
            else -> pal.bad
        }

        val views = RemoteViews(
            context.packageName,
            if (line) R.layout.widget_stress_line else R.layout.widget_stress,
        )
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.routeIntent(context, "/heart"))
        views.setImageViewBitmap(
            R.id.dial,
            w.dialBitmap(
                context, if (line) 30 else 48, if (line) 3.5f else 6.5f, pal.track, tint,
                if (measured) score / 100.0 else -1.0,
                R.drawable.ic_widget_stress, iconScale = if (line) 0.5f else 0.42f,
            ),
        )
        views.setContentDescription(R.id.dial, "Stress")
        if (!line) {
            views.setTextViewText(R.id.cap, "STRESS")
            views.setTextColor(R.id.cap, pal.inkMuted)
        }
        views.setTextViewText(R.id.value, if (measured) "$score" else "No score")
        views.setTextColor(R.id.value, if (measured) pal.ink else pal.ink2)
        views.setTextViewText(R.id.sub, if (measured) band else "Wear the band to see today's")
        views.setTextColor(R.id.sub, pal.inkMuted)

        val total = listOf(calm, balanced, stressed).filter { it > 0 }.sum()
        if (measured && total > 0) {
            views.setViewVisibility(R.id.bar, View.VISIBLE)
            views.setImageViewBitmap(
                R.id.bar,
                w.barBitmap(
                    context, if (line) 120 else 110, 6, pal.track,
                    listOf(
                        calm.coerceAtLeast(0).toDouble() / total to pal.good,
                        balanced.coerceAtLeast(0).toDouble() / total to pal.sleep,
                        stressed.coerceAtLeast(0).toDouble() / total to pal.warn,
                    ),
                ),
            )
            views.setViewVisibility(R.id.foot, View.VISIBLE)
            views.setTextViewText(
                R.id.foot,
                "Calm ${w.hm(calm.coerceAtLeast(0))} · Stressed ${w.hm(stressed.coerceAtLeast(0))}",
            )
            views.setTextColor(R.id.foot, pal.inkMuted)
        } else {
            views.setViewVisibility(R.id.bar, View.GONE)
            views.setViewVisibility(R.id.foot, View.GONE)
        }
        return views
    }
}
