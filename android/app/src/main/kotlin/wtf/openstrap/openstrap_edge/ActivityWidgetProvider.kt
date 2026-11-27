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
 * Edge+: today's movement — the Android sibling of OpenStrapActivityWidget.swift.
 *
 * Steps against the goal Home's steps card uses (WidgetService publishes the
 * goal with its default already applied, so the arc and the phone agree),
 * plus active energy and movement minutes. 2x2 by default, and down to one
 * row (widget_activity_line). A count of -1 is "no count", which is a word
 * on the widget, never a 0 that reads as a lazy day.
 */
class ActivityWidgetProvider : HomeWidgetProvider() {

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

        val steps = w.readInt(prefs, "steps", -1)
        val goal = w.readInt(prefs, "step_goal", -1)
        val kcal = w.readInt(prefs, "active_kcal", -1)
        val minutes = w.readInt(prefs, "active_min", -1)
        val measured = steps >= 0
        val frac = if (measured && goal > 0) steps.toDouble() / goal else -1.0
        val tint = if (measured) pal.good else pal.inkMuted

        val views = RemoteViews(
            context.packageName,
            if (line) R.layout.widget_activity_line else R.layout.widget_activity,
        )
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.routeIntent(context, "/today/steps"))
        views.setImageViewBitmap(
            R.id.dial,
            w.dialBitmap(
                context, if (line) 30 else 52, if (line) 3.5f else 7f, pal.track, tint, frac,
                R.drawable.ic_widget_steps, iconScale = if (line) 0.5f else 0.42f,
            ),
        )
        views.setContentDescription(R.id.dial, "Steps")
        if (!line) {
            views.setTextViewText(R.id.cap, "STEPS")
            views.setTextColor(R.id.cap, pal.inkMuted)
        }
        views.setTextViewText(R.id.value, if (measured) w.grouped(steps) else "No steps")
        views.setTextColor(R.id.value, if (measured) pal.ink else pal.ink2)
        views.setTextViewText(
            R.id.sub,
            when {
                !measured -> "Nothing counted yet today"
                goal > 0 -> "of ${w.grouped(goal)}"
                else -> "steps"
            },
        )
        views.setTextColor(R.id.sub, pal.inkMuted)

        // Energy and minutes, each only when there is one — never a dash.
        val foot = listOfNotNull(
            if (kcal >= 0) "$kcal kcal" else null,
            if (minutes >= 0) "$minutes min active" else null,
        ).joinToString(if (line) "\n" else " · ")
        views.setViewVisibility(R.id.foot, if (foot.isEmpty()) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.foot, foot)
        views.setTextColor(R.id.foot, pal.inkMuted)
        if (line) views.setInt(R.id.foot, "setMaxLines", 2)
        return views
    }
}
