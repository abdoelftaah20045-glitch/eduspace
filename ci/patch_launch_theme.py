import os
res = 'android/app/src/main/res'
bg = '<?xml version="1.0" encoding="utf-8"?><layer-list xmlns:android="http://schemas.android.com/apk/res/android"><item><shape android:shape="rectangle"><solid android:color="#FFEFF6FF"/></shape></item></layer-list>'
for d in ('drawable', 'drawable-v21'):
    os.makedirs(f'{res}/{d}', exist_ok=True)
    open(f'{res}/{d}/launch_background.xml', 'w').write(bg)
st = '<?xml version="1.0" encoding="utf-8"?><resources><style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar"><item name="android:windowBackground">@drawable/launch_background</item><item name="android:windowSplashScreenBackground">#FFEFF6FF</item><item name="android:forceDarkAllowed">false</item><item name="android:windowFullscreen">false</item></style><style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar"><item name="android:windowBackground">?android:colorBackground</item></style></resources>'
for d in ('values', 'values-night'):
    os.makedirs(f'{res}/{d}', exist_ok=True)
    open(f'{res}/{d}/styles.xml', 'w').write(st)
print('launch theme patched')
