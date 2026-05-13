package nandorojo.modules.galeria


import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.annotation.Keep
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStoreOwner
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.facebook.react.views.image.ReactImageView
import com.github.iielse.imageviewer.ImageViewerActionViewModel
import com.github.iielse.imageviewer.ImageViewerBuilder
import com.github.iielse.imageviewer.ImageViewerDialogFragment
import com.github.iielse.imageviewer.R
import com.github.iielse.imageviewer.core.ImageLoader
import com.github.iielse.imageviewer.core.Photo
import com.github.iielse.imageviewer.core.SimpleDataProvider
import com.github.iielse.imageviewer.core.Transformer
import com.github.iielse.imageviewer.core.ViewerCallback
import com.github.iielse.imageviewer.utils.Config
import expo.modules.kotlin.viewevent.EventDispatcher
import nandorojo.modules.galeria.viewer.GaleriaMediaPagerDialog
import nandorojo.modules.galeria.viewer.GaleriaPhoto as MediaPhoto


/**
 * iielse `Photo` adapter used for the image-only path. Carries only the URL.
 */
class StringPhoto(private val id: Long, private val data: String) : Photo {
    override fun id(): Long = id
    override fun itemType(): Int = 1
    override fun extra(): Any = data
}

fun convertToPhotos(urls: Array<String>): List<Photo> {
    return urls.mapIndexed { index, data ->
        StringPhoto(index.toLong(), data)
    }
}


@Keep
class GaleriaView(context: Context) : ViewGroup(context) {
    private lateinit var viewer: ImageViewerBuilder
    lateinit var urls: Array<String>
    var mediaTypes: Array<String>? = null
    var posters: Array<String>? = null
    var mutedFlags: Array<Boolean>? = null
    val onIndexChange by EventDispatcher()
    val onLongPress by EventDispatcher()
    val onDismiss by EventDispatcher()
    val onVideoError by EventDispatcher()
    var theme: Theme = Theme.Dark
    var initialIndex: Int = 0
    var disableHiddenOriginalImage = false
    var edgeToEdge = false
    var transitionOffsetY: Int? = null
    var transitionOffsetX: Int? = 0
    val viewModel: ImageViewerActionViewModel by lazy {
        ViewModelProvider(getViewModelOwner(context)).get(ImageViewerActionViewModel::class.java)
    }

    private var activeMediaDialog: GaleriaMediaPagerDialog? = null

    fun dismiss() {
        viewModel.dismiss()
        activeMediaDialog?.dismiss()
    }

    private fun getViewModelOwner(context: Context): ViewModelStoreOwner {
        val activity = getActivity(context)
            ?: throw IllegalStateException("The provided context ${context.javaClass.name} is not associated with an activity.")
        return activity as ViewModelStoreOwner
    }

    private fun getActivity(context: Context): Activity {
        var ctx = context
        while (ctx is ContextWrapper) {
            if (ctx is Activity) {
                return ctx
            }
            ctx = ctx.baseContext
        }
        throw IllegalStateException("Context does not contain an activity.")
    }

    @SuppressLint("DiscouragedApi", "InternalInsetResource")
    fun getStatusBarHeight(): Int {
        var statusBarHeight = 0
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        if (resourceId > 0) {
            statusBarHeight = resources.getDimensionPixelSize(resourceId)
        }
        return statusBarHeight
    }

    private fun hasAnyVideo(): Boolean =
        mediaTypes?.any { it == "video" } == true

    private fun buildMediaPhotos(): List<MediaPhoto> {
        val types = mediaTypes
        val postersArr = posters
        val mutedArr = mutedFlags
        return urls.mapIndexed { i, uri ->
            val isVideo = types?.getOrNull(i) == "video"
            MediaPhoto(
                id = i.toLong(),
                uri = uri,
                poster = postersArr?.getOrNull(i)?.takeIf { it.isNotEmpty() },
                muted = mutedArr?.getOrNull(i) ?: true,
                isVideo = isVideo,
            )
        }
    }


    private fun setupImageViewer(parentView: ViewGroup) {

        val photos = convertToPhotos(urls)
        val clickedData = photos[initialIndex]
        for (i in 0 until parentView.childCount) {
            val childView = parentView.getChildAt(i)
            if (childView is ImageView) {
                var imageViewContext = childView.context
                if (childView is ReactImageView) {
                    val activityContext = getActivity(childView.context)
                    imageViewContext = activityContext
                }
                viewer = ImageViewerBuilder(
                    context = imageViewContext,
                    dataProvider = SimpleDataProvider(clickedData, photos),
                    imageLoader = SimpleImageLoader(),
                    transformer = object : Transformer {
                        override fun getView(key: Long): ImageView {
                            return fakeStartView(parentView)
                        }
                    }
                )
                viewer.setViewerFactory(object : ImageViewerDialogFragment.Factory() {
                    override fun build() = EdgeToEdgeImageViewerDialogFragment(
                        isAppearanceLightSystemBars =
                            if (edgeToEdge) theme.toAppearanceLightSystemBars() else null,
                        onDismissCallback = { onDismiss(emptyMap<String, Any>()) },
                    )
                })
                childView.setOnClickListener {
                    if (hasAnyVideo()) {
                        openMediaPager(childView, initialIndex)
                    } else {
                        setupConfig()
                        if (!disableHiddenOriginalImage) {
                            viewer.setViewerCallback(CustomViewerCallback(childView as ImageView) { index ->
                                onIndexChange(mapOf("currentIndex" to index))
                            })
                        }
                        viewer.show()
                    }
                }
                childView.setOnLongClickListener {
                    onLongPress(emptyMap<String, Any>())
                    true
                }
            } else if (childView is ViewGroup) {
                setupImageViewer(childView)
            }
        }
    }

    private fun openMediaPager(sourceView: ImageView, index: Int) {
        val activity = getActivity(context)
        val dialog = GaleriaMediaPagerDialog(
            activity = activity,
            sourceView = sourceView,
            photos = buildMediaPhotos(),
            initialIndex = index,
            theme = theme,
            isAppearanceLightSystemBars =
                if (edgeToEdge) theme.toAppearanceLightSystemBars() else null,
            onDismissCallback = {
                activeMediaDialog = null
                onDismiss(emptyMap<String, Any>())
            },
            onIndexChange = { newIndex ->
                onIndexChange(mapOf("currentIndex" to newIndex))
            },
            onVideoError = { errorIndex, message ->
                onVideoError(mapOf("index" to errorIndex, "message" to message))
            },
        )
        activeMediaDialog = dialog
        dialog.show()
    }



    private fun fakeStartView(view: View): ImageView {
        val customWidth = view.width
        val customHeight = view.height
        val customLocation = IntArray(2).also { view.getLocationOnScreen(it) }
        val customScaleType = ImageView.ScaleType.CENTER_CROP

        return ImageView(view.context).apply {
            left = 0
            right = customWidth
            top = 0
            bottom = customHeight
            scaleType = customScaleType
            setTag(R.id.viewer_start_view_location_0, customLocation[0])
            setTag(R.id.viewer_start_view_location_1, customLocation[1])
        }
    }

    private fun setupConfig() {
        Config.TRANSITION_OFFSET_Y = transitionOffsetY ?: when (edgeToEdge) {
            true -> 0
            false -> getStatusBarHeight()
        }

        Config.TRANSITION_OFFSET_X = transitionOffsetX ?: 0
        Config.VIEWER_BACKGROUND_COLOR = theme.toImageViewerTheme()
    }


    override fun onLayout(p0: Boolean, p1: Int, p2: Int, p3: Int, p4: Int) {
        setupImageViewer(this)
    }


}

class CustomViewerCallback(private val childView: ImageView, private val onIndexChange: (Int) -> Unit) : ViewerCallback {
    override fun onInit(viewHolder: RecyclerView.ViewHolder, position: Int) {
        childView.animate().alpha(0f).setDuration(180).start()

    }


    override fun onRelease(viewHolder: RecyclerView.ViewHolder, view: View) {
        Handler(Looper.getMainLooper()).postDelayed({
            childView.alpha = 1f
        }, 230)
    }

    override fun onPageSelected(position: Int, viewHolder: RecyclerView.ViewHolder) {
        onIndexChange(position)
    }
}

enum class Theme(val value: String) {
    Dark("dark"),
    Light("light");

    fun toAppearanceLightSystemBars(): Boolean {
        return when (this) {
            Dark -> false
            Light -> true
        }
    }

    fun toImageViewerTheme(): Int {
        return when (this) {
            Dark -> Color.BLACK
            Light -> Color.WHITE
        }
    }
}

class SimpleImageLoader : ImageLoader {
    override fun load(view: ImageView, data: Photo, viewHolder: RecyclerView.ViewHolder) {
        val it = data.extra() as? String
        Glide.with(view).load(it)
            .placeholder(view.drawable)
            .into(view)
    }
}
