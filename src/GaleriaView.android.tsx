import { requireNativeView } from 'expo'

import { useContext } from 'react'
import {
  controlEdgeToEdgeValues,
  isEdgeToEdge,
} from 'react-native-is-edge-to-edge'
import { GaleriaContext } from './context'
import {
  GaleriaIndexChangedEvent,
  GaleriaSource,
  GaleriaVideoErrorEvent,
  GaleriaViewProps,
  isGaleriaVideoSource,
} from './Galeria.types'
import { resolveGaleriaSources } from './resolveSources'

const EDGE_TO_EDGE = isEdgeToEdge()

const NativeImage = requireNativeView<
  GaleriaViewProps & {
    edgeToEdge: boolean
    urls?: string[]
    mediaTypes?: ('image' | 'video')[]
    posters?: string[]
    mutedFlags?: boolean[]
    theme: 'dark' | 'light'
    onIndexChange?: (event: GaleriaIndexChangedEvent) => void
    onVideoError?: (event: GaleriaVideoErrorEvent) => void
  }
>('Galeria')

const noop = () => {}

const Galeria = Object.assign(
  function Galeria({
    children,
    urls,
    theme = 'dark',
    ids,
  }: {
    children: React.ReactNode
  } & Partial<Pick<GaleriaContext, 'theme' | 'ids' | 'urls'>>) {
    return (
      <GaleriaContext.Provider
        value={{
          hideBlurOverlay: false,
          hidePageIndicators: false,
          closeIconName: undefined,
          urls,
          theme,
          initialIndex: 0,
          open: false,
          src: '',
          setOpen: noop,
          ids,
        }}
      >
        {children}
      </GaleriaContext.Provider>
    )
  },
  {
    Image({ edgeToEdge, ...props }: GaleriaViewProps) {
      const { theme, urls } = useContext(GaleriaContext)

      if (__DEV__) {
        controlEdgeToEdgeValues({ edgeToEdge })
      }

      const bridge = resolveGaleriaSources(urls)

      return (
        <NativeImage
          onIndexChange={props.onIndexChange}
          onVideoError={props.onVideoError}
          edgeToEdge={EDGE_TO_EDGE || (edgeToEdge ?? false)}
          theme={theme}
          urls={bridge.urls}
          mediaTypes={bridge.mediaTypes}
          posters={bridge.posters}
          mutedFlags={bridge.mutedFlags}
          {...props}
        />
      )
    },
    Video({ edgeToEdge, ...props }: GaleriaViewProps) {
      const { theme, urls } = useContext(GaleriaContext)

      if (__DEV__) {
        controlEdgeToEdgeValues({ edgeToEdge })
      }

      const bridge = resolveGaleriaSources(urls)
      const mutedFlags =
        props.videoMuted != null && props.index != null
          ? bridge.mutedFlags.map((m, i) =>
              i === props.index ? props.videoMuted! : m,
            )
          : bridge.mutedFlags

      return (
        <NativeImage
          onIndexChange={props.onIndexChange}
          onVideoError={props.onVideoError}
          edgeToEdge={EDGE_TO_EDGE || (edgeToEdge ?? false)}
          theme={theme}
          urls={bridge.urls}
          mediaTypes={bridge.mediaTypes}
          posters={bridge.posters}
          mutedFlags={mutedFlags}
          {...props}
        />
      )
    },
    Popup: (() => null) as React.FC<{
      disableTransition?: 'web'
    }>,
    isVideoSource: isGaleriaVideoSource,
  },
)

export type GaleriaAndroidSource = GaleriaSource

export default Galeria
