package nandorojo.modules.galeria.viewer

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.viewpager2.widget.ViewPager2
import com.github.iielse.imageviewer.R
import nandorojo.modules.galeria.Theme

/**
 * Full-screen pager dialog backing the video-aware Galeria experience. Uses
 * a raw [Dialog] (not a fragment) to keep state handling simple — the host
 * `GaleriaView` owns the dialog's lifetime alongside the user's React
 * components.
 *
 * Responsibilities:
 *  - Page between mixed image + video entries via [ViewPager2].
 *  - Animate the inline trigger view to the dialog's bounds on open,
 *    and reverse on dismiss (poster-based shared-element transition).
 *  - Page-change autoplay: pauses departed video, starts the new one.
 *  - Audio focus: requests transient focus while a video is playing,
 *    pauses on transient loss, abandons on dismiss.
 *  - Back button (or system back gesture) reverses the enter animation.
 */
class GaleriaMediaPagerDialog(
    activity: Activity,
    private val sourceView: ImageView,
    private val photos: List<GaleriaPhoto>,
    private val initialIndex: Int,
    private val theme: Theme,
    private val isAppearanceLightSystemBars: Boolean?,
    private val onDismissCallback: () -> Unit,
    private val onIndexChange: (Int) -> Unit,
    private val onVideoError: (Int, String) -> Unit,
) : Dialog(activity, R.style.Theme_FullScreenDialog) {

    private lateinit var rootLayout: FrameLayout
    private lateinit var background: View
    private lateinit var pager: ViewPager2
    private lateinit var adapter: GaleriaPagerAdapter
    private var audioFocusRequest: AudioFocusRequest? = null
    private val audioManager: AudioManager? = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private var currentPage = initialIndex
    private var hasRequestedFocus = false

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> adapter.pauseAll()
            else -> Unit
        }
    }

    private val dragListener = object : ZoomableFrameLayout.VerticalDragListener {
        override fun onDragStart() {
            pager.animate().cancel()
            background.animate().cancel()
        }

        override fun onDrag(dyTotal: Float) {
            pager.translationY = dyTotal
            background.alpha = 1f - (kotlin.math.abs(dyTotal) / pager.height.coerceAtLeast(1))
                .coerceIn(0f, 0.85f)
        }

        override fun onDragEnd(dyTotal: Float) {
            if (pager.height > 0 && kotlin.math.abs(dyTotal) > pager.height * 0.22f) {
                playClosingTransitionAndDismiss()
            } else {
                pager.animate().translationY(0f).setDuration(180).start()
                background.animate().alpha(1f).setDuration(180).start()
            }
        }

        override fun onDragCancel() {
            pager.animate().translationY(0f).setDuration(180).start()
            background.animate().alpha(1f).setDuration(180).start()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        setCanceledOnTouchOutside(false)
        setupWindow()
        buildContent()
        setOnDismissListener {
            adapter.releaseAll()
            abandonAudioFocus()
            onDismissCallback()
        }
        playEnterTransition()
    }

    private fun setupWindow() {
        val window = window ?: return
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
        )
        WindowCompat.setDecorFitsSystemWindows(window, false)
        isAppearanceLightSystemBars?.let { light ->
            WindowInsetsControllerCompat(window, window.decorView).apply {
                isAppearanceLightStatusBars = light
                isAppearanceLightNavigationBars = light
            }
        }
    }

    private fun buildContent() {
        rootLayout = FrameLayout(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(Color.TRANSPARENT)
        }

        background = View(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(theme.toImageViewerTheme())
            alpha = 0f
        }
        rootLayout.addView(background)

        adapter = GaleriaPagerAdapter(photos, onVideoError, dragListener)
        pager = ViewPager2(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            this.adapter = this@GaleriaMediaPagerDialog.adapter
            offscreenPageLimit = 1
            registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
                override fun onPageSelected(position: Int) {
                    super.onPageSelected(position)
                    currentPage = position
                    onIndexChange(position)
                    handlePageSelected(position)
                }
            })
            setCurrentItem(initialIndex, false)
        }
        rootLayout.addView(pager)

        setContentView(rootLayout)

        rootLayout.viewTreeObserver.addOnGlobalLayoutListener(object : android.view.ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                rootLayout.viewTreeObserver.removeOnGlobalLayoutListener(this)
                handlePageSelected(initialIndex)
            }
        })

    }

    private fun handlePageSelected(position: Int) {
        val photo = photos.getOrNull(position) ?: return
        if (photo.isVideo) {
            ensureAudioFocus()
            pager.post { adapter.playOnly(position) }
        } else {
            adapter.pauseAll()
        }
    }

    private fun playEnterTransition() {
        rootLayout.post {
            val sourceRect = locateSource()
            val targetRect = locateTarget()
            if (sourceRect == null || targetRect == null) {
                background.alpha = 1f
                return@post
            }
            pager.scaleX = sourceRect.width().toFloat() / targetRect.width()
            pager.scaleY = sourceRect.height().toFloat() / targetRect.height()
            pager.translationX = (sourceRect.centerX() - targetRect.centerX()).toFloat()
            pager.translationY = (sourceRect.centerY() - targetRect.centerY()).toFloat()
            pager.alpha = 0.95f

            sourceView.alpha = 0f

            AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(pager, View.SCALE_X, 1f),
                    ObjectAnimator.ofFloat(pager, View.SCALE_Y, 1f),
                    ObjectAnimator.ofFloat(pager, View.TRANSLATION_X, 0f),
                    ObjectAnimator.ofFloat(pager, View.TRANSLATION_Y, 0f),
                    ObjectAnimator.ofFloat(pager, View.ALPHA, 1f),
                    ObjectAnimator.ofFloat(background, View.ALPHA, 1f),
                )
                duration = 260
                start()
            }
        }
    }

    override fun onBackPressed() {
        playClosingTransitionAndDismiss()
    }

    private fun playClosingTransitionAndDismiss() {
        val sourceRect = locateSource()
        val targetRect = locateTarget()
        if (sourceRect == null || targetRect == null) {
            sourceView.alpha = 1f
            dismiss()
            return
        }
        val scaleX = sourceRect.width().toFloat() / targetRect.width()
        val scaleY = sourceRect.height().toFloat() / targetRect.height()
        val tx = (sourceRect.centerX() - targetRect.centerX()).toFloat()
        val ty = (sourceRect.centerY() - targetRect.centerY()).toFloat()
        AnimatorSet().apply {
            playTogether(
                ObjectAnimator.ofFloat(pager, View.SCALE_X, scaleX),
                ObjectAnimator.ofFloat(pager, View.SCALE_Y, scaleY),
                ObjectAnimator.ofFloat(pager, View.TRANSLATION_X, tx),
                ObjectAnimator.ofFloat(pager, View.TRANSLATION_Y, ty),
                ObjectAnimator.ofFloat(pager, View.ALPHA, 0f),
                ObjectAnimator.ofFloat(background, View.ALPHA, 0f),
            )
            duration = 240
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    sourceView.alpha = 1f
                    dismiss()
                }
            })
            start()
        }
    }

    private fun locateSource(): android.graphics.Rect? {
        if (!sourceView.isAttachedToWindow) return null
        val loc = IntArray(2)
        sourceView.getLocationOnScreen(loc)
        return android.graphics.Rect(loc[0], loc[1], loc[0] + sourceView.width, loc[1] + sourceView.height)
    }

    private fun locateTarget(): android.graphics.Rect? {
        if (pager.width == 0 || pager.height == 0) return null
        val loc = IntArray(2)
        pager.getLocationOnScreen(loc)
        return android.graphics.Rect(loc[0], loc[1], loc[0] + pager.width, loc[1] + pager.height)
    }

    private fun ensureAudioFocus() {
        if (hasRequestedFocus) return
        val am = audioManager ?: return
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                )
                .setOnAudioFocusChangeListener(audioFocusListener)
                .build()
            audioFocusRequest = request
            am.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        hasRequestedFocus = granted
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        if (!hasRequestedFocus) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(audioFocusListener)
        }
        hasRequestedFocus = false
    }

}
