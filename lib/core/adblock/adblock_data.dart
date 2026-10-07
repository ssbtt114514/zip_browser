/// 内置广告/跟踪域名与广告元素选择器。
///
/// 域名列表是手工维护的常见广告、跟踪与弹窗联盟域名（含中英文互联网常用项），
/// 匹配采用「主域后缀」规则（`h == d || h.endsWith('.d')`），避免误伤同站主服务。
/// 用户可在设置页追加自定义域名；白名单域名同样可配置。
library;

/// 内置广告/跟踪域名（约 160 条，按生态分组，全部采用小写主域）
const List<String> kAdBlockDomains = [
  // —— Google / 国际广告与跟踪联盟 ——
  'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
  'googletagservices.com', 'google-analytics.com', 'googletagmanager.com',
  'adservice.google.com', 'adservice.google.nl', 'adservice.google.co.uk',
  'googleads.g.doubleclick.net', 'pagead2.googlesyndication.com',
  'fundingchoices.google.com', 'amazon-adsystem.com', 'a2dcp.io',
  'serving-sys.com', 'media.net', 'taboola.com', 'outbrain.com',
  'advertising.com', 'adnxs.com', 'adform.net', 'adtechus.com',
  'criteo.com', 'criteo.net', 'pubmatic.com', 'rubiconproject.com',
  'openx.net', 'smartadserver.com', 'spotxchange.com', 'spotx.tv',
  'springserve.com', 'teads.tv', 'trustx.org', 'yieldmo.com', 'zedo.com',
  'adcolony.com', 'inmobi.com', 'mopub.com', 'unityads.unity3d.com',
  'applovin.com', 'bytedance.com', 'pangle.io', 'indexww.com',
  'sovrn.com', 'lijit.com', 'sharethrough.com', 'triplelift.com',
  'undertone.com', 'unrulymedia.com', 'yavli.com',

  // —— 中文广告联盟 / 统计 / 弹窗 ——
  'pos.baidu.com', 'cpro.baidu.com', 'cbjs.baidu.com', 'cpro2.baidu.com',
  'posapi.baidu.com', 'nsclick.baidu.com', 'pcookie.baidu.com',
  'hm.baidu.com', 'tongji.baidu.com', 'bdimg.com',
  'union.360.cn', 'push.360.cn', 'pstatp.com', 'ttw.hzcn.com',
  'ads.qq.com', 'adview.qq.com', 'gdt.qq.com', 'coral.qq.com',
  'trace.play.cn', 'ugdtimg.com', 'om.qq.com', 'adsame.com',
  'admaster.com.cn', 'cnzz.com', '51.la', 'umeng.com', 'umengcloud.com',
  'wrating.com', 'ad.mi.com', 'tracker.miui.com',
  'data.huya.com', 'analytics.suning.com', 'report.91.com',
  'union.uc.cn', 'upapi.com', 'cm.uc.cn', 'svn.uc.cn',
  'adx.xiaomi.com', 'dup.aliapp.com', 'sycm.taobao.com', 'yqall01.com',
  'log.mmstat.com', 'mmstat.com', 'nbshare.io', 'click.simba.taobao.com',
  'acookie.alimama.com', 'mclick.zmjd.com', 'alimama.com', 'tanx.com',
  'admarket.360.cn', 'puvod.360.cn', 'mota.360.cn', 'stat.360safe.com',
  'st.qiyi.com', 'data.video.qiyi.com', 'vali.cp31.ott.cibntv.net',
  'api.union.video.qq.com', 'r10086.com', 'adcd.net', 'adksh.com',
  'aoyunwang.com', 'chaochaobao.com', 'd0.haoyunhui.com', 'pjyw8.com',

  // —— 常见弹窗 / 强制跳转 / 短链广告 ——
  'popads.net', 'propellerads.com', 'onclck.com', 'clickadu.com',
  'adsterra.com', 'exoclick.com', 'juicyads.com', 'adcash.com',
  'adf.ly', 'shorte.st', 'bc.vc', 'ouo.io', 'ity.im', 'dwz.cn',
  't.cn', 'goo.gl', 'bit.ly', 'tinyurl.com', 'migre.me',
  'ad-maven.com', 'hilltopads.net', 'trafficjunky.net', 'reklamstore.com',
  'adsrvmedia.com', 'adikteev.com', 'plugins.live',
  'clickfraudnetwork.com', 'cdn.ampproject.org', 'imasdk.googleapis.com',
  'pagead.l.google.com', 'adsafeprotected.com', 'moatads.com',

  // —— 视频 / 游戏站常见植入 ——
  'adn.insightexpressai.com', 'ads.playground.xyz', 'gads.pubmatic.com',
  'vast.ad.tv', 'v.fwmrm.net', '2mdn.net', 'adk2x.com', 'flurry.com',
  'loopme.me', 'nend.net', 'pubads.g.doubleclick.net', 'secure-dcr.imrworldwide.com',
  'tpc.googlesyndication.com', 'www-googletagmanager.com', 'adplxmd.com',
];

/// 内置广告元素隐藏选择器（保守清单，避免误伤正常内容）
const List<String> kAdBlockSelectors = [
  '.ad-banner', '.advertisement', '.advert', '.advertising', '.ad-box',
  '.ad-container', '.ad-slot', '.ad-wrapper', '.ads-wrap', '.adsense',
  '.adsbygoogle', 'ins.adsbygoogle', '.banner-ad', '.sponsored',
  '.sponsor', '.promo-ad', '.promoted', '.taboola', '.outbrain',
  '#ad', '#ads', '#advert', '#ad-container', '#ad-banner',
  '[id^="google_ads_"]', '.google-ads', '.dfp-ad', '.ad-placeholder',
  '.ad-section', '.ad-row', '.ad-unit', '.ad-label', '.ad-text',
  '.ad_250', '.ad_300', '.ad_336', '.ad_728', '.masthead-ad',
  '.in-feed-ad', '.native-ad', '.recommend-ad', '.advertorial',
  '.adhesion-unit', '.prebid-block', '.popup-ad', '.modal-ad',
  '.ad-overlay', '.ad-sticky', '.ad-fixed', '.video-ad', '.preroll-ad',
  '.midroll-ad', '.postroll-ad', '.side-ad', '.top-ad', '.bottom-ad',
  '.content-ad', '.widget-ad', '.ad-badge', '.ad-callout', '.ad-tag',
];

/// 用户白名单（默认空）。白名单优先于拦截规则：
/// 条目按「主机后缀」匹配（`h == w || h.endsWith('.w')`），用于放行被误拦的站点。
const List<String> kAdBlockAllowDomains = [];
