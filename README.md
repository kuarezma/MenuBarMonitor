# MenuBarMonitor

MenuBarMonitor, macOS için hafif bir menü çubuğu sistem monitörüdür.  
Üst barda CPU, RAM, termal durum ve bellek yoğunluğu vekilini canlı gösterir; sol tıkla detay paneli, sağ tıkla hızlı menü açılır.

![MenuBarMonitor Preview](assets/menubar-preview.png)

## Özellikler

- Menü çubuğunda canlı kısa gösterim: `Cxx Ryy n M~zz`
- Renkli durum noktaları (yük durumuna göre)
- Sol tık: kompakt detay paneli
- Sağ tık: `Otomatik açıl` (login item) ve `Çık`
- Çekirdek yükleri: E/P çekirdekleri ayrı görünüm
- Ölçüm periyodu: 3 saniye

## Ekran Gösterimi

Menü çubuğu etiketi:

- `C`: toplam CPU yüzde
- `R`: RAM kullanım yüzde
- `n/f/s/k`: termal durum (nominal/fair/serious/critical)
- `M~`: bellek yoğunluğu vekili (gerçek bellek bant genişliği değildir)

## Gereksinimler

- macOS 14+
- Xcode (tam kurulum)

## Kurulum (Kaynak Koddan)

```bash
git clone <repo-url>
cd MenuBarMonitor
xcodebuild -project "MenuBarMonitor.xcodeproj" \
  -scheme "MenuBarMonitor" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64,name=My Mac" \
  -derivedDataPath "/tmp/MenuBarMonitor-DD" build
```

Derlenen uygulama:

- `/tmp/MenuBarMonitor-DD/Build/Products/Release/MenuBarMonitor.app`

İsterseniz masaüstüne kopyalayın:

```bash
rm -rf "$HOME/Desktop/MenuBarMonitor.app"
ditto "/tmp/MenuBarMonitor-DD/Build/Products/Release/MenuBarMonitor.app" "$HOME/Desktop/MenuBarMonitor.app"
open "$HOME/Desktop/MenuBarMonitor.app"
```

## Kullanım

- Sol tık: detay panelini aç/kapat
- Sağ tık: `Otomatik açıl` seçeneğini aç/kapat, uygulamayı kapat

## Notlar

- Uygulama `LSUIElement` olarak çalışır; Dock’ta görünmez.
- Apple Silicon’da kullanıcı alanından güvenilir çekirdek frekansı (MHz/GHz) alınamadığı için frekans uydurulmaz.
- Termal gösterim derece (°C) değil, sistemin termal durum bilgisidir.
