package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Edge+: four shortcuts into the app — the Android sibling of
 * OpenStrapQuickWidget.swift. Breathing, water, alarm, workouts: the things
 * people open the app to DO rather than to read. One row.
 *
 * No snapshot and no freshness rule — a shortcut is never stale. Each button
 * is a StrapWidgets.routeIntent, so the route lands on the same
 * `pending_route` latch the iOS App Intents write.
 */
class QuickActionsWidgetProvider : HomeWidgetProvider() {

    private class Action(val key: String, val label: String, val route: String,
                         val icon: Int, val btn: Int, val img: Int, val lbl: Int)

    private val actions = listOf(
        Action("breath", "Breathe", "/breathing", R.drawable.ic_widget_breath,
            R.id.btn_breath, R.id.ic_breath, R.id.lbl_breath),
        Action("water", "Water", "/water", R.drawable.ic_widget_water,
            R.id.btn_water, R.id.ic_water, R.id.lbl_water),
        Action("alarm", "Alarm", "/alarm", R.drawable.ic_widget_alarm,
            R.id.btn_alarm, R.id.ic_alarm, R.id.lbl_alarm),
        Action("workout", "Workout", "/workouts", R.drawable.ic_widget_workout,
            R.id.btn_workout, R.id.ic_workout, R.id.lbl_workout),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val w = StrapWidgets
        val pal = w.pal(widgetData)
        val views = RemoteViews(context.packageName, R.layout.widget_quick)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        for (a in actions) {
            val color = when (a.key) {
                "breath" -> pal.good
                "water" -> pal.sleep
                "alarm" -> pal.warn
                else -> pal.move
            }
            views.setImageViewBitmap(a.img, w.chipBitmap(context, 30, color, a.icon))
            views.setTextViewText(a.lbl, a.label)
            views.setTextColor(a.lbl, pal.ink2)
            views.setContentDescription(a.btn, a.label)
            views.setOnClickPendingIntent(a.btn, w.routeIntent(context, a.route))
        }
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }
}
