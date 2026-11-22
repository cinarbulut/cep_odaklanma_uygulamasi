CEP KEY — başlangıç prototipi

Kurulum:
1. Mevcut Flutter projenin kök klasöründe pubspec.yaml dosyasını bu pakettekiyle karşılaştır.
   Proje adını değiştirmek istemiyorsan mevcut pubspec.yaml içindeki name alanını koruyabilirsin.
2. lib/main.dart dosyasını bu paketteki lib/main.dart ile değiştir.
3. VS Code terminalinde proje kök klasöründe çalıştır:
   flutter pub get
4. Android cihaz/emülatör için:
   flutter run
   Chrome'da yalnızca arayüz/prototip denemesi için:
   flutter run -d chrome

ÖNEMLİ GÜVENLİK NOTLARI:
- Bu, eğitim ve geliştirme amaçlı başlangıç prototipidir; bağımsız güvenlik denetiminden geçmemiştir.
- Gerçek hesap şifrelerini henüz taşımayın veya kullanmayın.
- Ana parola unutulursa kurtarma/şifre sıfırlama mekanizması yoktur; veri kaybı yaşanabilir.
- Kod PBKDF2-HMAC-SHA256 ile anahtarı türetir ve AES-256-GCM ile kasayı şifreler.
- Android/iOS'ta anahtar türetme ve şifreli kasa verisi uygulamanın güvenli depolama eklentisi üzerinden saklanır. Web tarayıcısı güvenli depolama davranışı platforma göre farklıdır; Chrome önizlemesini gerçek cihaz güvenliği gibi değerlendirmeyin.
- Üretim sürümünden önce hata yönetimi, uygulama arka plana gidince kilitleme, clipboard temizleme, ekran görüntüsü politikası, güvenli yedekleme/kurtarma, platform izinleri, bağımlılık güncellemeleri ve uzman güvenlik denetimi gereklidir.
- Bu prototip, kayıtlı sitelerdeki şifreleri otomatik olarak değiştirmez ve iOS AutoFill/Passkeys entegrasyonu içermez.
