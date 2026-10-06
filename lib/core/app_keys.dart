import 'package:flutter/material.dart';

/// 全局导航 / 信使 key，供事件回调（长按菜单、分享、下载）在
/// 不持有 widget context 的情况下打开弹层、显示提示。
final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
