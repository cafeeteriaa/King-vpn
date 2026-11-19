import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'king_local_ai.dart';
import 'king_voice_output.dart';

class _ChatLine {
  const _ChatLine(this.text, this.king, {this.error = false});
  final String text;
  final bool king;
  final bool error;
}

class KingChatPage extends StatefulWidget {
  const KingChatPage({super.key});
  @override
  State<KingChatPage> createState() => _KingChatPageState();
}

class _KingChatPageState extends State<KingChatPage> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = stt.SpeechToText();
  final _ai = KingLocalAi.instance;
  final List<_ChatLine> _messages = [];
  bool _busy = false, _listening = false, _speechReady = false;
  bool _speechBusy = false, _speak = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages.add(const _ChatLine(
      'سلام! من کینگ هستم. می‌توانی با من گپ بزنی، سؤال بپرسی یا از من راهنمایی بخواهی. برای گفت‌وگوی هوشمند آفلاین، مدل محلی را از بخش هوش مصنوعی بارگذاری کن. سؤال‌های آب‌وهوا را با اینترنت می‌توانم حتی بدون مدل پاسخ بدهم.',
      true,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.cancel());
    unawaited(KingVoiceOutput.instance.stop());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _listening) {
      unawaited(_speech.cancel());
      if (mounted) setState(() => _listening = false);
    }
  }

  String _norm(String value) => value.toLowerCase()
      .replaceAll('ي', 'ی').replaceAll('ك', 'ک')
      .replaceAll('‌', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _weatherIntent(String text) {
    final q = _norm(text);
    return (q.contains('هوا') || q.contains('آب و هوا') || q.contains('weather')) &&
        RegExp(r'(چطوره|چجوریه|چطوریه|وضعیت|دما|باران|بارون|برف|weather)').hasMatch(q);
  }

  String? _city(String text) {
    final q = _norm(text);
    final m = RegExp(r'(?:آب و هوای|هوای|وضعیت هوای|weather in|weather for)\s+([^؟?!,.،]+)').firstMatch(q);
    if (m != null) {
      final name = m.group(1)!.replaceAll(RegExp(r'\s+(چطوره|چجوریه|چطوریه|الان|امروز|فردا)$'), '').trim();
      if (name.isNotEmpty) return name;
    }
    const aliases = {
      'شیراز':'Shiraz', 'تهران':'Tehran', 'اصفهان':'Isfahan',
      'مشهد':'Mashhad', 'تبریز':'Tabriz', 'کرج':'Karaj',
      'اهواز':'Ahvaz', 'رشت':'Rasht', 'باکو':'Baku'
    };
    for (final e in aliases.entries) {
      if (q.contains(e.key)) return e.value;
    }
    return null;
  }

  Future<String> _weather(String city) async {
    final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name':city, 'count':'1', 'language':'fa', 'format':'json'});
    final gr = await http.get(geoUri).timeout(const Duration(seconds: 12));
    if (gr.statusCode != 200) throw Exception('سرویس مکان‌یابی پاسخ نداد.');
    final geo = jsonDecode(gr.body) as Map<String,dynamic>;
    final results = geo['results'] as List?;
    if (results == null || results.isEmpty) throw Exception('این شهر پیدا نشد؛ نام شهر را دقیق‌تر بگو.');
    final place = results.first as Map<String,dynamic>;
    final name = (place['name'] ?? city).toString();
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude':(place['latitude'] as num).toString(),
      'longitude':(place['longitude'] as num).toString(),
      'current':'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m',
      'timezone':'auto'
    });
    final wr = await http.get(uri).timeout(const Duration(seconds: 12));
    if (wr.statusCode != 200) throw Exception('دریافت وضعیت هوا ناموفق بود.');
    final data = jsonDecode(wr.body) as Map<String,dynamic>;
    final current = data['current'] as Map<String,dynamic>?;
    if (current == null) throw Exception('اطلاعات فعلی هوا موجود نیست.');
    final code = (current['weather_code'] as num?)?.toInt() ?? -1;
    final description = code == 0 ? 'صاف' :
        code <= 3 && code >= 1 ? 'کمی تا نیمه‌ابری' :
        code == 45 || code == 48 ? 'مه‌آلود' :
        code >= 51 && code <= 57 ? 'نم‌نم باران' :
        code >= 61 && code <= 67 ? 'بارانی' :
        code >= 71 && code <= 77 ? 'برفی' :
        code >= 80 && code <= 82 ? 'رگبار باران' :
        code >= 85 && code <= 86 ? 'رگبار برف' :
        code >= 95 ? 'رعدوبرق' : 'نامشخص';
    final temp = current['temperature_2m'] ?? '?';
    final feels = current['apparent_temperature'] ?? '?';
    final humidity = current['relative_humidity_2m'] ?? '?';
    final wind = current['wind_speed_10m'] ?? '?';
    return 'آب‌وهوای فعلی $name: $description. دما $temp درجه و دمای احساسی $feels درجه سانتی‌گراد است. رطوبت $humidity درصد و سرعت باد $wind کیلومتر بر ساعت است. این اطلاعات زنده از سرویس هواشناسی آنلاین دریافت شده است.';
  }

  Future<String> _answer(String question) async {
    final q = _norm(question);
    if (RegExp(r'(اسمت چیه|اسم تو چیه|نامت چیست|تو کی هستی)').hasMatch(q)) {
      return 'من کینگ هستم؛ دستیار هوشمند فارسی King VPN. می‌توانی با من گفت‌وگو کنی و برای برنامه یا موضوعات عمومی سؤال بپرسی.';
    }
    if (_weatherIntent(question)) {
      final city = _city(question);
      if (city == null) return 'حتماً! اسم شهر را هم بگو؛ مثلاً آب‌وهوای شیراز چطوره؟';
      return _weather(city);
    }
    if (_ai.isLoaded) {
      final recent = _messages.length > 8 ? _messages.sublist(_messages.length - 8) : _messages;
      final history = recent.map((m) => (m.king ? 'کینگ: ' : 'کاربر: ') + m.text).join('\n');
      return _ai.ask('گفت‌وگوی اخیر:\n$history\n\nپیام تازه کاربر: $question\nبه پیام تازه پاسخ بده و زمینه گفت‌وگو را حفظ کن.', maxTokens:640);
    }
    if (RegExp(r'(سلام|درود|خوبی|حالت چطوره)').hasMatch(q)) {
      return 'سلام! خوشحالم با هم گپ می‌زنیم. هر موضوعی دوست داری بپرس؛ برای پاسخ‌های عمومی هوشمندتر، مدل محلی کینگ را از بخش هوش مصنوعی بارگذاری کن.';
    }
    if (q.contains('حوصله') || q.contains('خسته')) {
      return 'بیا یک گپ خودمونی بزنیم! دوست داری درباره فیلم و موسیقی حرف بزنیم یا یک موضوع جالب برات تعریف کنم؟';
    }
    return 'برای گفت‌وگوی آزاد، مدل محلی کینگ هنوز بارگذاری نشده است. از منوی برنامه وارد «هوش مصنوعی مهندس محلی» شو و مدل حدود ۱٫۱ گیگابایتی را بارگذاری کن. آب‌وهوا با اینترنت حتی بدون مدل قابل پاسخ است.';
  }

  Future<void> _send([String? raw]) async {
    final text = (raw ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() { _messages.add(_ChatLine(text, false)); _busy = true; });
    _scrollEnd();
    try {
      final answer = await _answer(text);
      if (!mounted) return;
      setState(() => _messages.add(_ChatLine(answer, true)));
      _scrollEnd();
      if (_speak) {
        try { await KingVoiceOutput.instance.speakPersian(answer); }
        catch (e) {
          if (mounted) setState(() => _messages.add(_ChatLine('پاسخ متنی آماده است، اما صدای فارسی گوشی آماده نیست: $e', true, error:true)));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _messages.add(_ChatLine('پاسخ دریافت نشد: \${e.toString().replaceFirst('Exception: ', '')}', true, error:true)));
    } finally {
      if (mounted) { setState(() => _busy = false); _scrollEnd(); }
    }
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds:250), curve: Curves.easeOut);
    });
  }

  Future<void> _toggleMic() async {
    if (_speechBusy) return;
    if (_listening || _speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _speechBusy = true);
    try {
      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onStatus: (_) { if (mounted) setState(() => _listening = _speech.isListening); },
          onError: (e) {
            if (mounted) setState(() {
              _listening = false;
              _messages.add(_ChatLine('تشخیص گفتار خطا داد: \${e.errorMsg}. سرویس گفتار گوشی یا اتصال اینترنت را بررسی کن.', true, error:true));
            });
          },
        );
      }
      if (!_speechReady) {
        setState(() => _messages.add(const _ChatLine('سرویس تشخیص گفتار روی گوشی نصب یا فعال نیست. سرویس Speech Recognition و بسته زبان فارسی را فعال کن.', true, error:true)));
        return;
      }
      final locales = await _speech.locales();
      final fa = locales.where((l) => l.localeId.toLowerCase().replaceAll('_','-').startsWith('fa')).toList();
      await _speech.listen(
        localeId: fa.isNotEmpty ? fa.first.localeId : 'fa-IR',
        onDevice: fa.isNotEmpty,
        listenFor: const Duration(seconds:45),
        pauseFor: const Duration(seconds:5),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!mounted) return;
          _input.value = TextEditingValue(text:result.recognizedWords,
              selection:TextSelection.collapsed(offset:result.recognizedWords.length));
          if (result.finalResult) { setState(() => _listening = false); _send(result.recognizedWords); }
        },
      );
      if (mounted) setState(() => _listening = _speech.isListening);
    } catch (e) {
      if (mounted) setState(() { _listening=false; _messages.add(_ChatLine('شروع میکروفون ناموفق بود: $e',true,error:true)); });
    } finally {
      if (mounted) setState(() => _speechBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Row(children:[Icon(Icons.psychology_alt_rounded,color:Color(0xFF70D9FF)),SizedBox(width:8),Text('گفت‌وگو با کینگ')]),
        actions:[IconButton(tooltip:_speak?'خاموش‌کردن پاسخ صوتی':'پاسخ صوتی',
          onPressed:()=>setState(()=>_speak=!_speak),
          icon:Icon(_speak?Icons.volume_up:Icons.volume_off))],
      ),
      body:Column(children:[
        Container(
          width:double.infinity, margin:const EdgeInsets.fromLTRB(12,10,12,6),
          padding:const EdgeInsets.all(12),
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(18),
            gradient:const LinearGradient(colors:[Color(0xFF172D45),Color(0xFF20243B)]),
            border:Border.all(color:const Color(0x5579DFFF))),
          child:Row(children:[
            const Icon(Icons.auto_awesome,size:34,color:Color(0xFF9BEAFF)),
            const SizedBox(width:10),
            Expanded(child:Text(_ai.isLoaded
              ? 'کینگ آماده گفت‌وگوی محلی است • پاسخ صوتی \${_speak?'روشن':'خاموش'}'
              : 'گفت‌وگوی پایه فعال است • برای پاسخ آزاد مدل محلی را بارگذاری کن',
              style:const TextStyle(color:Colors.white,fontSize:12))),
          ]),
        ),
        Expanded(child:ListView.builder(
          controller:_scroll, padding:const EdgeInsets.all(12),
          itemCount:_messages.length+(_busy?1:0),
          itemBuilder:(context,index){
            if(index==_messages.length) return const Align(alignment:Alignment.centerRight,child:Padding(padding:EdgeInsets.all(12),child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2))));
            final m=_messages[index];
            return Align(
              alignment:m.king?Alignment.centerRight:Alignment.centerLeft,
              child:Container(
                constraints:BoxConstraints(maxWidth:MediaQuery.of(context).size.width*.86),
                margin:const EdgeInsets.symmetric(vertical:5),
                padding:const EdgeInsets.symmetric(horizontal:14,vertical:11),
                decoration:BoxDecoration(
                  color:m.king?(m.error?Colors.red.withValues(alpha:.12):const Color(0xFF1B2B3C)):const Color(0xFF254B68),
                  borderRadius:BorderRadius.circular(17),
                  border:Border.all(color:m.king?const Color(0x4479DFFF):const Color(0x444EBAFF))),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(m.king?'کینگ':'شما',style:TextStyle(fontSize:10,color:m.king?const Color(0xFF83DFFF):Colors.white70)),
                  const SizedBox(height:5),
                  SelectableText(m.text,style:const TextStyle(height:1.55,color:Colors.white)),
                  if(m.king&&!m.error) Align(alignment:Alignment.centerLeft,
                    child:IconButton(visualDensity:VisualDensity.compact,tooltip:'پخش پاسخ',
                      onPressed:()=>KingVoiceOutput.instance.speakPersian(m.text),
                      icon:const Icon(Icons.volume_up_outlined,size:18))),
                ]),
              ),
            );
          },
        )),
        SafeArea(top:false,child:Padding(
          padding:const EdgeInsets.fromLTRB(10,6,10,10),
          child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
            IconButton.filledTonal(onPressed:_speechBusy?null:_toggleMic,
              icon:Icon(_listening?Icons.stop:Icons.mic,color:_listening?Colors.redAccent:null),
              tooltip:_listening?'پایان صحبت':'صحبت با کینگ'),
            Expanded(child:TextField(controller:_input,minLines:1,maxLines:5,
              textInputAction:TextInputAction.send,onSubmitted:(_)=>_send(),
              decoration:const InputDecoration(hintText:'با کینگ صحبت کن...',border:OutlineInputBorder(),isDense:true))),
            const SizedBox(width:6),
            IconButton.filled(onPressed:_busy?null:()=>_send(),icon:const Icon(Icons.send_rounded)),
          ]),
        )),
      ]),
    ),
  );
}
