import type { motion } from 'framer-motion'
import type { ComponentProps } from 'react'
import type { Image, NativeSyntheticEvent } from 'react-native'
import { ViewStyle } from 'react-native'
import type { SFSymbol } from 'sf-symbols-typescript'

export type ChangeEventPayload = {
  value: string
}

export type GaleriaImageAssetSource = Parameters<
  typeof Image.resolveAssetSource
>[0]

export type GaleriaImageSource = string | GaleriaImageAssetSource

export type GaleriaVideoSource = {
  uri: string
  type: 'video'
  /**
   * Image used for the inline trigger and shared-element transition. Strongly
   * recommended — without it the transition falls back to whatever child view
   * the trigger renders.
   */
  poster?: string | GaleriaImageAssetSource
  /** Defaults to true. */
  muted?: boolean
}

export type GaleriaSource = GaleriaImageSource | GaleriaVideoSource

export const isGaleriaVideoSource = (
  source: GaleriaSource,
): source is GaleriaVideoSource =>
  typeof source === 'object' &&
  source !== null &&
  (source as { type?: unknown }).type === 'video'

export type GaleriaVideoErrorPayload = {
  index: number
  message: string
}

export type GaleriaVideoErrorEvent = NativeSyntheticEvent<GaleriaVideoErrorPayload>

type GaleriaIndexChangedPayload = {
  currentIndex: number
}

export type GaleriaIndexChangedEvent =
  NativeSyntheticEvent<GaleriaIndexChangedPayload>

export type GaleriaLongPressEvent = NativeSyntheticEvent<Record<string, never>>
export type GaleriaRightNavItemPressedEvent =
  NativeSyntheticEvent<{ index: number }>
export type GaleriaDismissEvent = NativeSyntheticEvent<Record<string, never>>

export interface GaleriaViewProps {
  index?: number
  id?: string
  children: React.ReactElement
  closeIconName?: SFSymbol
  rightNavItemIconName?: SFSymbol
  __web?: ComponentProps<(typeof motion)['div']>
  style?: ViewStyle
  dynamicAspectRatio?: boolean
  edgeToEdge?: boolean
  onIndexChange?: (event: GaleriaIndexChangedEvent) => void
  /** Fired on long-press of the inline trigger image, before the viewer opens. */
  onLongPress?: (event: GaleriaLongPressEvent) => void
  onPressRightNavItemIcon?: (event: GaleriaRightNavItemPressedEvent) => void
  onDismiss?: (event: GaleriaDismissEvent) => void
  hideBlurOverlay?: boolean
  hidePageIndicators?: boolean
  /** Per-trigger override for the muted state of a video entry. */
  videoMuted?: boolean
  onVideoError?: (event: GaleriaVideoErrorEvent) => void
}
