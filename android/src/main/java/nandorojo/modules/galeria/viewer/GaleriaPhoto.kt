package nandorojo.modules.galeria.viewer

/**
 * Single media entry passed to [GaleriaMediaPagerDialog]. The pager renders
 * an image cell for `isVideo == false` and a video cell otherwise.
 */
data class GaleriaPhoto(
    val id: Long,
    val uri: String,
    val poster: String?,
    val muted: Boolean,
    val isVideo: Boolean,
)
