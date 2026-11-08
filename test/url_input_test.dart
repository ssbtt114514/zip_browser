import 'package:flutter_test/flutter_test.dart';
import 'package:zip_browser/core/tab/url_utils.dart';

/// 链接识别与地址解析的回归测试。
///
/// 这些场景对应实际使用中的常见输入：聊天软件复制来的带包裹符号链接、
/// 大写 scheme、本机开发地址、带端口的域名、中文域名、以及普通句子。
void main() {
  const template = 'https://search.example/?q={q}';

  String resolve(String input) => UrlInput.resolve(
        input,
        searchEngineTemplate: template,
        homeDataUri: 'about:home',
      );

  group('UrlInput.resolve 地址补全', () {
    test('scheme 大小写不敏感', () {
      expect(resolve('HTTPS://Example.COM/Path'), 'HTTPS://Example.COM/Path');
      expect(resolve('Http://a.com'), 'Http://a.com');
    });

    test('裸域名补 https，带端口与查询串', () {
      expect(resolve('example.com'), 'https://example.com');
      expect(resolve('sub.example.co.uk/a?b=1#c'),
          'https://sub.example.co.uk/a?b=1#c');
      expect(resolve('example.com:8080'), 'https://example.com:8080');
      expect(resolve('example.com?q=1'), 'https://example.com?q=1');
    });

    test('协议相对地址补 https', () {
      expect(resolve('//example.com/x'), 'https://example.com/x');
    });

    test('本机与 IPv4 补 http', () {
      expect(resolve('localhost'), 'http://localhost');
      expect(resolve('localhost:3000/a'), 'http://localhost:3000/a');
      expect(resolve('127.0.0.1:8080'), 'http://127.0.0.1:8080');
      expect(resolve('192.168.1.1/x'), 'http://192.168.1.1/x');
      expect(resolve('[::1]:8080'), 'http://[::1]:8080');
    });

    test('非法 IP 与纯数字不当作地址', () {
      expect(resolve('999.1.1.1'), startsWith('https://search.example'));
      expect(resolve('12345'), startsWith('https://search.example'));
    });

    test('中文域名', () {
      expect(resolve('中文.中国'), 'https://中文.中国');
    });

    test('粘贴清洗：包裹符号、多行、全角句末标点', () {
      expect(resolve('「example.com」'), 'https://example.com');
      expect(resolve('<https://a.com/x>'), 'https://a.com/x');
      expect(resolve('https://a.com\n后面的文字'), 'https://a.com');
      expect(resolve('https://a.com。'), 'https://a.com');
      expect(resolve('example.com。'), 'https://example.com');
    });

    test('链接后带说明文字：按首个空白截断', () {
      expect(resolve('https://a.com 复制这段链接'), 'https://a.com');
    });

    test('查询串里的空格编码保留', () {
      expect(resolve('https://a.com/s?q=hello world'),
          'https://a.com/s?q=hello%20world');
    });

    test('普通文本与中文句子走搜索', () {
      expect(resolve('flutter widget 教程'),
          'https://search.example/?q=flutter+widget+%E6%95%99%E7%A8%8B');
      expect(resolve('hello'), 'https://search.example/?q=hello');
    });

    test('空输入回主页，about: 回主页，about:blank 保留', () {
      expect(resolve('   '), 'about:home');
      expect(resolve('about:config'), 'about:home');
      expect(resolve('about:blank'), 'about:blank');
    });

    test('搜索模板缺少 {q} 时追加查询参数，避免关键词丢失', () {
      final url = UrlInput.resolve(
        '测试词',
        searchEngineTemplate: 'https://search.example/find',
        homeDataUri: 'about:home',
      );
      expect(url, startsWith('https://search.example/find?q='));
      expect(url, contains('%E6%B5%8B'));
    });
  });

  group('UrlInput.tryResolveUrl / isLikelyUrl', () {
    test('只接受确实像地址的输入', () {
      expect(UrlInput.tryResolveUrl('example.com'), 'https://example.com');
      expect(UrlInput.tryResolveUrl('localhost:5173'), 'http://localhost:5173');
      expect(UrlInput.tryResolveUrl('一段普通文字'), isNull);
      expect(UrlInput.tryResolveUrl('hello world'), isNull);
      expect(UrlInput.tryResolveUrl(''), isNull);
    });

    test('isLikelyUrl 与 resolve 判定一致', () {
      for (final s in [
        'https://a.com',
        'HTTPS://A.COM',
        'example.com:8080/x',
        'localhost:8080',
        '192.168.0.1',
        '//example.com',
      ]) {
        expect(UrlInput.isLikelyUrl(s), isTrue, reason: s);
      }
      for (final s in ['flutter', 'hello world', '999.1.1.1', '']) {
        expect(UrlInput.isLikelyUrl(s), isFalse, reason: s);
      }
    });
  });

  group('UrlInput.firstUrlIn 剪贴板文本', () {
    test('从句子中提取第一个地址', () {
      expect(
        UrlInput.firstUrlIn('看这个 https://example.com/a?x=1 挺好用的'),
        'https://example.com/a?x=1',
      );
      expect(
        UrlInput.firstUrlIn('链接：https://example.com/a。复制打开'),
        'https://example.com/a',
      );
      expect(UrlInput.firstUrlIn('（https://example.com）'), 'https://example.com');
    });

    test('www. 与裸域名', () {
      expect(UrlInput.firstUrlIn('访问 www.example.com 看看'),
          'http://www.example.com');
      expect(UrlInput.firstUrlIn('example.com'), 'https://example.com');
      expect(UrlInput.firstUrlIn('example.com/a?b=1'), 'https://example.com/a?b=1');
    });

    test('普通句子不误报', () {
      expect(UrlInput.firstUrlIn('今天去公园散步'), isNull);
      expect(UrlInput.firstUrlIn('hello world'), isNull);
    });
  });
}
