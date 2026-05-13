package nandorojo.modules.galeria.viewer

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide

private const val TYPE_IMAGE = 1
private const val TYPE_VIDEO = 2

internal class GaleriaPagerAdapter(
    private val photos: List<GaleriaPhoto>,
    private val onVideoError: (index: Int, message: String) -> Unit,
    private val verticalDragListener: ZoomableFrameLayout.VerticalDragListener,
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private val activeVideoHolders = mutableSetOf<VideoPageViewHolder>()

    override fun getItemCount(): Int = photos.size

    override fun getItemViewType(position: Int): Int =
        if (photos[position].isVideo) TYPE_VIDEO else TYPE_IMAGE

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return if (viewType == TYPE_VIDEO) {
            VideoPageViewHolder.create(parent.context)
        } else {
            ImagePageViewHolder.create(parent.context)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val photo = photos[position]
        when (holder) {
            is ImagePageViewHolder -> {
                holder.bind(photo)
                holder.zoomContainer.verticalDragListener = verticalDragListener
            }
            is VideoPageViewHolder -> {
                holder.bind(photo, position, onVideoError)
                holder.zoomContainer.verticalDragListener = verticalDragListener
                activeVideoHolders.add(holder)
            }
        }
    }

    override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
        super.onViewRecycled(holder)
        if (holder is VideoPageViewHolder) {
            holder.release()
            activeVideoHolders.remove(holder)
        } else if (holder is ImagePageViewHolder) {
            holder.zoomContainer.resetZoom()
        }
    }

    fun pauseAll() {
        activeVideoHolders.forEach { it.pause() }
    }

    fun playOnly(position: Int) {
        for (holder in activeVideoHolders) {
            if (holder.bindingAdapterPosition == position) holder.play() else holder.pause()
        }
    }

    fun releaseAll() {
        activeVideoHolders.forEach { it.release() }
        activeVideoHolders.clear()
    }
}

internal class ImagePageViewHolder private constructor(
    val zoomContainer: ZoomableFrameLayout,
    private val imageView: ImageView,
) : RecyclerView.ViewHolder(zoomContainer) {

    fun bind(photo: GaleriaPhoto) {
        zoomContainer.resetZoom()
        Glide.with(imageView).load(photo.uri).into(imageView)
    }

    companion object {
        @SuppressLint("ResourceType")
        fun create(context: Context): ImagePageViewHolder {
            val container = ZoomableFrameLayout(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
            }
            val image = ImageView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                )
                scaleType = ImageView.ScaleType.FIT_CENTER
            }
            container.addView(image)
            return ImagePageViewHolder(container, image)
        }
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class VideoPageViewHolder private constructor(
    val zoomContainer: ZoomableFrameLayout,
    private val playerView: PlayerView,
    private val posterView: ImageView,
) : RecyclerView.ViewHolder(zoomContainer) {

    private var exoPlayer: ExoPlayer? = null
    private var boundPhotoUri: String? = null

    fun bind(photo: GaleriaPhoto, position: Int, onVideoError: (Int, String) -> Unit) {
        zoomContainer.resetZoom()
        boundPhotoUri = photo.uri
        posterView.alpha = 1f

        val context = itemView.context
        if (!photo.poster.isNullOrEmpty()) {
            Glide.with(posterView).load(photo.poster).into(posterView)
        } else {
            posterView.setImageDrawable(null)
        }

        release()
        val player = ExoPlayer.Builder(context).build()
        player.setMediaItem(MediaItem.fromUri(photo.uri))
        player.volume = if (photo.muted) 0f else 1f
        player.playWhenReady = false
        player.prepare()
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY) {
                    posterView.animate().alpha(0f).setDuration(120).start()
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                onVideoError(position, error.localizedMessage ?: error.message ?: "Unknown playback error")
            }
        })
        playerView.player = player
        exoPlayer = player
    }

    fun play() {
        exoPlayer?.playWhenReady = true
    }

    fun pause() {
        exoPlayer?.playWhenReady = false
    }

    fun release() {
        exoPlayer?.release()
        exoPlayer = null
        playerView.player = null
    }

    companion object {
        @SuppressLint("ResourceType")
        @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
        fun create(context: Context): VideoPageViewHolder {
            val container = ZoomableFrameLayout(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
            }
            val playerView = PlayerView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                )
                useController = true
                controllerAutoShow = false
                resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
            }
            val poster = ImageView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER,
                )
                scaleType = ImageView.ScaleType.FIT_CENTER
            }
            container.addView(playerView)
            container.addView(poster)
            return VideoPageViewHolder(container, playerView, poster)
        }
    }
}
