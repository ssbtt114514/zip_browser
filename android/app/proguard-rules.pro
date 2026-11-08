# R8 混淆规则（Zip Browser）

# google_mlkit_text_recognition 在初始化方法里引用全部脚本识别器选项类，
# 但本项目只引入中文识别库（text-recognition-chinese），因此 R8 会报告
# 其他脚本（天城文 / 日文 / 韩文）类缺失。运行时不会走这些分支，忽略告警即可。
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
