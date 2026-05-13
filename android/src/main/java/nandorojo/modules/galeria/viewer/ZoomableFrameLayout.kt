package nandorojo.modules.galeria.viewer

import android.content.Context
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.ViewGroup
import android.widget.FrameLayout

/**
 * Single-touch pan + two-touch pinch zoom container.
 *
 * Wraps either an image or an ExoPlayer `PlayerView`. The page swipe gesture
 * provided by `ViewPager2` is suppressed while zoomed > 1.0 via
 * `requestDisallowInterceptTouchEvent`, matching the pattern used elsewhere
 * in the Android ecosystem for zoom containers inside horizontal pagers.
 */
class ZoomableFrameLayout @JvmOverloads constructor(
    context: Context,
    private val minScale: Float = 1f,
    private val maxScale: Float = 4f,
) : FrameLayout(context) {

    interface VerticalDragListener {
        fun onDragStart()
        fun onDrag(dyTotal: Float)
        fun onDragEnd(dyTotal: Float)
        fun onDragCancel()
    }

    var verticalDragListener: VerticalDragListener? = null

    private var currentScale = 1f
    private var translationXValue = 0f
    private var translationYValue = 0f
    private var dragStartY = 0f
    private var draggingVertically = false
    private val touchSlop = android.view.ViewConfiguration.get(context).scaledTouchSlop

    private val scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            currentScale = (currentScale * detector.scaleFactor).coerceIn(minScale, maxScale)
            applyTransform()
            return true
        }
    })

    private val gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
            if (currentScale > minScale + 0.001f) {
                translationXValue -= distanceX
                translationYValue -= distanceY
                clampTranslation()
                applyTransform()
                return true
            }
            return false
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            currentScale = if (currentScale > minScale + 0.001f) minScale else maxScale * 0.75f
            translationXValue = 0f
            translationYValue = 0f
            animate()
                .scaleX(currentScale)
                .scaleY(currentScale)
                .translationX(0f)
                .translationY(0f)
                .setDuration(180)
                .start()
            return true
        }
    })

    init {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }

    val isZoomed: Boolean get() = currentScale > minScale + 0.001f

    fun resetZoom() {
        currentScale = minScale
        translationXValue = 0f
        translationYValue = 0f
        scaleX = 1f
        scaleY = 1f
        translationX = 0f
        translationY = 0f
    }

    private fun applyTransform() {
        scaleX = currentScale
        scaleY = currentScale
        translationX = translationXValue
        translationY = translationYValue
    }

    private fun clampTranslation() {
        val extraX = (width * (currentScale - 1f)) / 2f
        val extraY = (height * (currentScale - 1f)) / 2f
        translationXValue = translationXValue.coerceIn(-extraX, extraX)
        translationYValue = translationYValue.coerceIn(-extraY, extraY)
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        // Always pass touches to children first; we only consume in onTouchEvent.
        if (isZoomed) {
            parent?.requestDisallowInterceptTouchEvent(true)
        }
        return super.onInterceptTouchEvent(ev)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(event)
        gestureDetector.onTouchEvent(event)

        if (!isZoomed && event.pointerCount == 1) {
            handleVerticalDrag(event)
        }

        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
            if (!isZoomed) {
                parent?.requestDisallowInterceptTouchEvent(false)
            }
        }
        return true
    }

    private fun handleVerticalDrag(event: MotionEvent) {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                dragStartY = event.rawY
                draggingVertically = false
            }
            MotionEvent.ACTION_MOVE -> {
                val dy = event.rawY - dragStartY
                if (!draggingVertically && kotlin.math.abs(dy) > touchSlop) {
                    draggingVertically = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                    verticalDragListener?.onDragStart()
                }
                if (draggingVertically) {
                    verticalDragListener?.onDrag(dy)
                }
            }
            MotionEvent.ACTION_UP -> {
                if (draggingVertically) {
                    verticalDragListener?.onDragEnd(event.rawY - dragStartY)
                }
                draggingVertically = false
            }
            MotionEvent.ACTION_CANCEL -> {
                if (draggingVertically) verticalDragListener?.onDragCancel()
                draggingVertically = false
            }
        }
    }
}
