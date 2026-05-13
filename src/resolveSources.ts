import { Image } from 'react-native'

import {
  GaleriaImageAssetSource,
  GaleriaSource,
  isGaleriaVideoSource,
} from './Galeria.types'

export type ResolvedGaleriaSources = {
  urls: string[]
  mediaTypes: ('image' | 'video')[]
  posters: string[]
  mutedFlags: boolean[]
}

const resolveAssetUri = (
  source: string | GaleriaImageAssetSource | undefined,
): string => {
  if (!source) return ''
  if (typeof source === 'string') return source
  return Image.resolveAssetSource(source)?.uri ?? ''
}

export const resolveGaleriaSources = (
  sources: GaleriaSource[] | undefined,
): ResolvedGaleriaSources => {
  if (!sources)
    return { urls: [], mediaTypes: [], posters: [], mutedFlags: [] }

  const urls: string[] = []
  const mediaTypes: ('image' | 'video')[] = []
  const posters: string[] = []
  const mutedFlags: boolean[] = []

  for (const source of sources) {
    if (isGaleriaVideoSource(source)) {
      urls.push(source.uri)
      mediaTypes.push('video')
      posters.push(resolveAssetUri(source.poster))
      mutedFlags.push(source.muted ?? true)
    } else {
      urls.push(resolveAssetUri(source))
      mediaTypes.push('image')
      posters.push('')
      mutedFlags.push(true)
    }
  }

  return { urls, mediaTypes, posters, mutedFlags }
}
