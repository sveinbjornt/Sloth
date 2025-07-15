mkdir SlothIcon.iconset
sips -z 16 16     SlothIcon.png --out SlothIcon.iconset/icon_16x16.png
sips -z 32 32     SlothIcon.png --out SlothIcon.iconset/icon_16x16@2x.png
sips -z 32 32     SlothIcon.png --out SlothIcon.iconset/icon_32x32.png
sips -z 64 64     SlothIcon.png --out SlothIcon.iconset/icon_32x32@2x.png
sips -z 128 128   SlothIcon.png --out SlothIcon.iconset/icon_128x128.png
sips -z 256 256   SlothIcon.png --out SlothIcon.iconset/icon_128x128@2x.png
sips -z 256 256   SlothIcon.png --out SlothIcon.iconset/icon_256x256.png
sips -z 512 512   SlothIcon.png --out SlothIcon.iconset/icon_256x256@2x.png
sips -z 512 512   SlothIcon.png --out SlothIcon.iconset/icon_512x512.png
cp SlothIcon.png SlothIcon.iconset/icon_512x512@2x.png
# Optimize with ImageOptim
# ./createicns PlatypusAppIcon.iconset
# iconutil -c icns PlatypusAppIcon.iconset
