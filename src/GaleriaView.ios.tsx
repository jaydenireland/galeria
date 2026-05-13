import { requireNativeView } from 'expo'

import { useContext } from 'react'
import type { SFSymbol } from 'sf-symbols-typescript'
import { GaleriaContext } from './context'
import {
  GaleriaIndexChangedEvent,
  GaleriaSource,
  GaleriaVideoErrorEvent,
  GaleriaViewProps,
  isGaleriaVideoSource,
} from './Galeria.types'
import { resolveGaleriaSources } from './resolveSources'

const NativeImage = requireNativeView<
  GaleriaViewProps & {
    urls?: string[]
    mediaTypes?: ('image' | 'video')[]
    posters?: string[]
    mutedFlags?: boolean[]
    closeIconName?: SFSymbol
    theme: 'dark' | 'light'
    onIndexChange?: (event: GaleriaIndexChangedEvent) => void
    onVideoError?: (event: GaleriaVideoErrorEvent) => void
    hideBlurOverlay?: boolean
    hidePageIndicators?: boolean
  }
>('Galeria')

const noop = () => {}

const Galeria = Object.assign(
  function Galeria({
    children,
    closeIconName,
    urls,
    theme = 'dark',
    ids,
    hideBlurOverlay = false,
    hidePageIndicators = false,
  }: {
    children: React.ReactNode
  } & Partial<
    Pick<GaleriaContext, 'theme' | 'ids' | 'urls' | 'closeIconName' | 'hideBlurOverlay' | 'hidePageIndicators'>
  >) {
    return (
      <GaleriaContext.Provider
        value={{
          closeIconName,
          urls,
          theme,
          initialIndex: 0,
          open: false,
          src: '',
          setOpen: noop,
          ids,
          hideBlurOverlay,
          hidePageIndicators,
        }}
      >
        {children}
      </GaleriaContext.Provider>
    )
  },
  {
    Image(props: GaleriaViewProps) {
      const { theme, urls, initialIndex, closeIconName, hideBlurOverlay, hidePageIndicators } =
        useContext(GaleriaContext)
      const bridge = resolveGaleriaSources(urls)
      return (
        <NativeImage
          onIndexChange={props.onIndexChange}
          onVideoError={props.onVideoError}
          closeIconName={closeIconName}
          theme={theme}
          hideBlurOverlay={props.hideBlurOverlay ?? hideBlurOverlay}
          hidePageIndicators={props.hidePageIndicators ?? hidePageIndicators}
          urls={bridge.urls}
          mediaTypes={bridge.mediaTypes}
          posters={bridge.posters}
          mutedFlags={bridge.mutedFlags}
          index={initialIndex}
          {...props}
        />
      )
    },
    Video(props: GaleriaViewProps) {
      const { theme, urls, initialIndex, closeIconName, hideBlurOverlay, hidePageIndicators } =
        useContext(GaleriaContext)
      const bridge = resolveGaleriaSources(urls)
      return (
        <NativeImage
          onIndexChange={props.onIndexChange}
          onVideoError={props.onVideoError}
          closeIconName={closeIconName}
          theme={theme}
          hideBlurOverlay={props.hideBlurOverlay ?? hideBlurOverlay}
          hidePageIndicators={props.hidePageIndicators ?? hidePageIndicators}
          urls={bridge.urls}
          mediaTypes={bridge.mediaTypes}
          posters={bridge.posters}
          mutedFlags={
            props.videoMuted != null && props.index != null
              ? bridge.mutedFlags.map((m, i) =>
                  i === props.index ? props.videoMuted! : m,
                )
              : bridge.mutedFlags
          }
          index={initialIndex}
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

export type GaleriaIosSource = GaleriaSource

export default Galeria
