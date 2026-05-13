import { Image } from 'expo-image'
import { Galeria, GaleriaSource, isGaleriaVideoSource } from 'galeria'
import { Dimensions, StyleSheet, View } from 'react-native'

const itemWidth = Dimensions.get('window').width / 3

const items: GaleriaSource[] = [
  {
    uri: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    type: 'video',
    poster:
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
  },
  'https://d33wubrfki0l68.cloudfront.net/dd23708ebc4053551bb33e18b7174e73b6e1710b/dea24/static/images/wallpapers/shared-colors@2x.png',
  {
    uri: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    type: 'video',
    poster:
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg',
  },
  'https://d33wubrfki0l68.cloudfront.net/49de349d12db851952c5556f3c637ca772745316/cfc56/static/images/wallpapers/bridge-02@2x.png',
]

const sourceUri = (item: GaleriaSource): string => {
  if (typeof item === 'string') return item
  if (isGaleriaVideoSource(item)) {
    return typeof item.poster === 'string'
      ? item.poster
      : item.poster
        ? (item.poster as { uri: string }).uri
        : item.uri
  }
  return ''
}

export default function VideoScreen() {
  return (
    <View style={styles.container}>
      <Galeria urls={items}>
        <View style={styles.grid}>
          {items.map((item, index) => {
            const TriggerComponent = isGaleriaVideoSource(item)
              ? Galeria.Video
              : Galeria.Image
            return (
              <TriggerComponent
                index={index}
                key={index}
                style={{ backgroundColor: 'black' }}
              >
                <Image
                  source={{ uri: sourceUri(item) }}
                  style={{ width: itemWidth, height: itemWidth }}
                />
              </TriggerComponent>
            )
          })}
        </View>
      </Galeria>
    </View>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: 8,
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
})
