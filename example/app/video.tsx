import { Image } from 'expo-image'
import { Galeria, GaleriaSource, isGaleriaVideoSource } from 'galeria'
import { Dimensions, StyleSheet, Text, View } from 'react-native'

const itemWidth = Dimensions.get('window').width / 3

const videoUri =
  'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4'

const items: GaleriaSource[] = [
  {
    uri: videoUri,
    type: 'video',
    poster:
      'https://d33wubrfki0l68.cloudfront.net/dd23708ebc4053551bb33e18b7174e73b6e1710b/dea24/static/images/wallpapers/shared-colors@2x.png',
  },
  'https://d33wubrfki0l68.cloudfront.net/49de349d12db851952c5556f3c637ca772745316/cfc56/static/images/wallpapers/bridge-02@2x.png',
  {
    uri: videoUri,
    type: 'video',
    poster:
      'https://d33wubrfki0l68.cloudfront.net/594de66469079c21fc54c14db0591305a1198dd6/3f4b1/static/images/wallpapers/bridge-01@2x.png',
  },
  'https://raw.githubusercontent.com/michaelhenry/MHFacebookImageViewer/master/Example/Demo/Assets.xcassets/cat1.imageset/cat1.jpg',
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
            const isVideo = isGaleriaVideoSource(item)
            const TriggerComponent = isVideo ? Galeria.Video : Galeria.Image
            return (
              <View key={index} style={styles.tileWrapper}>
                <TriggerComponent
                  index={index}
                  style={styles.tile}
                  onVideoError={(e) => {
                    console.log(
                      '[Galeria.Video]',
                      e.nativeEvent.index,
                      e.nativeEvent.message,
                    )
                  }}
                >
                  <Image
                    source={{ uri: sourceUri(item) }}
                    style={{ width: itemWidth, height: itemWidth }}
                  />
                </TriggerComponent>
                {isVideo && (
                  <View style={styles.playBadge} pointerEvents="none">
                    <Text style={styles.playGlyph}>▶</Text>
                  </View>
                )}
              </View>
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
  tileWrapper: {
    position: 'relative',
  },
  tile: {
    backgroundColor: 'black',
  },
  playBadge: {
    position: 'absolute',
    inset: 0,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.18)',
  },
  playGlyph: {
    color: 'white',
    fontSize: 36,
    textShadowColor: 'rgba(0,0,0,0.6)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 4,
    marginLeft: 4,
  },
})

