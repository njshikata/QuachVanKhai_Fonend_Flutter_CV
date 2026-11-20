# Báo cáo: Tối ưu hóa bộ nhớ và giao diện khi xử lý dữ liệu trên ứng dụng di động

Ứng dụng: **QLPT – Quản lý phòng trọ** (Flutter, Android) · backend Spring Boot.

---

## 0. Cách trình bày "chưa tối ưu" và "đã tối ưu"

Mọi kỹ thuật đều có **công tắc** trong `lib/Source/perf/PerfFlags.dart`. Code thật của app đọc thẳng các
công tắc này, nên tắt một công tắc thì **toàn app** chạy theo cách chưa tối ưu tương ứng. Không có bản code demo riêng.

| Cách dùng | Làm thế nào |
|---|---|
| **2 bản APK riêng** | `run_frontend.bat` → mục **6**. Ra 2 file `apk\app_chua_toi_uu.apk` (mặc định TẮT hết) và `apk\app_toi_uu.apk` (mặc định BẬT hết). Cài lên 2 máy hoặc 2 giả lập, mở cùng màn hình để so sánh trực tiếp. Tiêu đề màn "Hiệu năng & Demo" ghi rõ đang là bản nào. |
| Bật/tắt từng kỹ thuật trong app | Hồ sơ → **Hiệu năng & Demo** → các công tắc. Có thể bật bảng FPS/RAM nổi trên mọi màn hình. |
| **ĐO TRÊN APP THẬT (cách chính)** | Hiệu năng & Demo → **SO SÁNH TRÊN APP THẬT**. Đo trên chính các màn hình của app, với dữ liệu thật trong database. Có 2 cách: **tự động** (app tự mở từng màn ở cả 2 chế độ và tự cuộn) và **thủ công** (chọn chế độ, bấm "Bắt đầu ghi", tự thao tác, bấm ■ STOP). Kết quả ghép thành cặp CHƯA/ĐÃ tối ưu kèm **biểu đồ cột, biểu đồ đường FPS/RAM theo thời gian** và bảng số liệu. Chạy tự động từ PC: `run_frontend.bat` → mục **9**. |
| **TẮT HẲN APP RỒI BẬT LẠI (trực quan nhất)** | SO SÁNH TRÊN APP THẬT → thẻ cam **"0. TẮT HẲN APP RỒI BẬT LẠI"**. App tự tắt hẳn (process bị kill, mất toàn bộ RAM), tự bật lại, tự vào màn cần đo, đo từ lúc bấm tới khi **thấy dữ liệu**, rồi tự cuộn. Bấm "Tự động" để chạy 4 màn × 2 chế độ (8 lần tắt/bật), hoặc chọn 1 màn và bấm "Tắt/bật – CHƯA/ĐÃ tối ưu". Xem mục 1a. |
| Tool test từng kỹ thuật (phụ) | Hiệu năng & Demo → **Bộ test từng kỹ thuật T1–T8**. Đo tách riêng từng kỹ thuật trong điều kiện kiểm soát. `run_frontend.bat` → mục **7**. |
| Biểu đồ RAM/FPS cho báo cáo | Flutter DevTools, xem [HUONG_DAN_DEVTOOLS.md](HUONG_DAN_DEVTOOLS.md). |

Bản build: `flutter build apk --profile --dart-define=API_HOST=<ip> --dart-define=PERF_MODE=chua_toi_uu|toi_uu`.
`PERF_MODE` chỉ đổi giá trị mặc định của công tắc (`PerfFlags.buildOptimized`); hai bản dùng chung một bộ code.

---

## 1. Kết quả đo trên APP THẬT, dữ liệu thật

**Cách đo:** `integration_test/real_app_test.dart` (hoặc nút "Chạy tự động" trong app) mở **đúng ứng dụng** (`MyApp`),
đăng nhập tài khoản chủ trọ, rồi với mỗi màn hình:
1. Chạy 1 lượt khởi động không tính điểm ở mỗi chế độ, để lượt đo đầu tiên không bị chậm hơn vì app vừa mở.
2. Ở mỗi chế độ (ĐÃ tối ưu, rồi CHƯA tối ưu): xóa cache RAM và dữ liệu cục bộ, mở màn hình, đo thời gian tới khi danh sách hiện,
   tự cuộn 10 giây với tốc độ cố định, ghi FPS/RAM mỗi giây.

**Dữ liệu thật trong database:** 50 khu trọ · 4.000 phòng · 2.833 khách thuê · 67.992 hóa đơn · 2.833 thẻ · 424.950 lượt quẹt thẻ.

Đo ngày 20/11/2026 trên giả lập LDPlayer (Android x86_64), bản profile, backend trên laptop qua wifi.
Trong app (Hiệu năng & Demo → SO SÁNH TRÊN APP THẬT), mỗi màn có biểu đồ cột cho từng chỉ số, biểu đồ đường FPS và RAM theo thời gian,
và biểu đồ tổng quan cho cả 4 màn. Chụp màn hình phần đó để đưa vào slide.

| Màn hình (kỹ thuật) | Chỉ số | Chưa tối ưu | Đã tối ưu | Kết quả |
|---|---|---|---|---|
| **Dịch vụ** · 4.000 phòng (gộp request, ETag/SQLite, SliverList, Isolate) | Thời gian mở màn | 88.856 ms | 532 ms | ×167 |
| | Dữ liệu tải qua mạng | 3.561 KB | 1.474 KB | ×2,4 |
| | Khung hình giật | 15,6 % | 4,3 % | ×3,6 |
| **Người dùng** · 2.833 khách (ListView.builder) | Thời gian mở màn | 2.620 ms | 354 ms | ×7,4 |
| | FPS trung bình khi cuộn | 9 | 55 | ×6,3 |
| | Khung hình chậm nhất | 1.580 ms | 26 ms | ×62 |
| | RAM cao nhất (RSS) | 668 MB | 300 MB | ×2,2 |
| | Số dòng phải build | 2.842 | 269 | ×11 |
| **Thẻ cư dân** · 2.833 thẻ (ListView.builder, phân trang, ValueNotifier) | Thời gian mở màn | 6.538 ms | 116 ms | ×56 |
| | FPS trung bình khi cuộn | 10 | 54 | ×5,3 |
| | Khung hình chậm nhất | 1.879 ms | 41 ms | ×45 |
| | RAM cao nhất (RSS) | 739 MB | 353 MB | ×2,1 |
| | Số dòng phải build | 2.835 | 426 | ×6,7 |
| **Nhà trọ** · 50 khu, 4.000 phòng (một ListView.builder phẳng) | FPS thấp nhất | 14 | 30 | ×2,1 |
| | Khung hình giật | 12,6 % | 4,8 % | ×2,6 |
| | Khung hình chậm nhất | 169 ms | 26 ms | ×6,5 |

**Phân tích khi trình bày:**
- **Dịch vụ:** bản chưa tối ưu gọi 1 request cho **mỗi phòng** (4.000 request) để lấy trạng thái hóa đơn, nên mất gần 1,5 phút mới mở xong.
  Bản tối ưu gộp thành 1 request `billing-status`, giải mã JSON trong Isolate, và hiện danh sách phòng ngay khi chưa có hóa đơn.
- **Người dùng / Thẻ:** `Column` tạo widget cho cả ~2.830 dòng cùng lúc, nên RAM vượt 650 MB và mỗi khung hình đứng tới 1,5–1,9 giây.
  `ListView.builder` chỉ build các dòng đang thấy trên màn hình, cộng một vùng đệm.
- **RAM ảnh = 0:** dữ liệu thật hiện **chưa có ảnh**. Thẻ có `photoAvailable=false`, chỉ có 4 ảnh công tơ. Vì vậy các kỹ thuật ảnh
  (cache, memCacheWidth) được chứng minh bằng bài T2/T4 và màn "Ảnh công tơ".
- **Đo trên app thật đã phát hiện 2 lỗi mà bài đo riêng lẻ không thấy:**
  1. Màn Nhà trọ từng dùng `CustomScrollView` với 100 sliver (mỗi khu 1 header + 1 SliverGrid). Lần đo đầu cho thấy bản "tối ưu"
     **giật hơn** bản cũ (34 % so với 3 %): viewport phải layout lại cả 100 sliver ở mỗi khung hình, và cả 50 header đều bị build
     ngay khi mở màn. Đã sửa thành **một `ListView.builder` phẳng** (dòng header + dòng 3 phòng). Kết quả ở bảng trên.
  2. `SyncedApi._persist` gửi cây JSON đã giải mã (4.000 phòng) vào `compute()`. Dart phải copy cây đó ngay trên luồng UI,
     nên có 1 khung hình treo 544 ms. Đã sửa: gửi **mảng byte gốc** sang Isolate (copy 1 khối nhanh), Isolate tự giải mã.
- **Ghi thủ công:** chọn chế độ → chọn màn → "Bắt đầu ghi" → tự cuộn/bấm như người dùng → ■ STOP. Làm lại ở chế độ còn lại.
- **Chỉ hiện lần đo MỚI NHẤT, không lưu lịch sử:** bấm đo tự động là kết quả cũ bị xóa sạch; đo thủ công 1 màn thì chỉ giữ cặp
  CHƯA/ĐÃ của đúng màn đó. Đo xong là có ngay để trình bày.
- **Phân tích tự động** (`BenchAnalysis.dart`): trên cùng là thẻ **KẾT LUẬN** (mỗi màn 1 câu: nhanh hơn bao nhiêu lần, hết đứng hình,
  RAM giảm bao nhiêu). Mỗi màn có mục **PHÂN TÍCH**: Tốc độ → Độ mượt → Bộ nhớ → Mạng (diễn giải bằng lời từ đúng số vừa đo),
  rồi **"Vì sao bản CHƯA tối ưu chậm"** và **"Bản ĐÃ tối ưu làm gì"** (cơ chế + file code). Chỉ số nào không tốt hơn cũng được nói rõ lý do.
- Menu ⋮ trong màn so sánh: **Copy bảng + phân tích (Markdown)** (dán vào báo cáo), **Copy CSV** FPS/RAM theo giây (dán vào Excel).

---

## 1a. Bài đo TẮT HẲN APP RỒI BẬT LẠI (ưu tiên TỐC ĐỘ)

**Mục tiêu:** giống hệt người dùng vuốt tắt app rồi bấm icon mở lại. Người xem thấy app biến mất, hiện lại, tự vào màn hình
và tự cuộn, còn dải đen dưới cùng ghi rõ lượt đo và số ms.

**Cách hoạt động** (`lib/Source/perf/real/RestartBench.dart`, `android/.../MainActivity.kt`, `RestartActivity.kt`):
1. Bấm nút: app lưu "kế hoạch đo" (màn, chế độ, thời điểm bấm) vào SharedPreferences, đếm ngược 3 giây.
2. Gọi MethodChannel `qlpt/app` → `restart`. `RestartActivity` (process riêng `:restart`) **kill process app**, chờ 1,5 s cho máy
   thu hồi RAM, rồi mở lại app bằng đúng intent của icon. Khoảng chờ 1,5 s cố định này được **trừ** khỏi số đo.
3. `main()` đọc kế hoạch (`prepareBoot`), bật/tắt các kỹ thuật theo chế độ của lượt, rồi `resumeAfterBoot` tự mở màn và đo:
   - **Bật lại app tới khung hình đầu** (ms)
   - **Tắt/bật app tới khi THẤY DỮ LIỆU** (ms): con số chính, ưu tiên tốc độ
   - Khung hình chậm nhất, FPS, % giật khi tự cuộn; RAM; dữ liệu tải qua mạng
4. Lưu kết quả, chuyển sang lượt kế. Hết kế hoạch thì về màn chính và mở màn biểu đồ. Bảng Markdown cũng được in ra logcat (`[REAL]`).
5. **So sánh công bằng:** thứ tự CHƯA/ĐÃ tối ưu đảo luân phiên giữa các màn. Trước khi đo, mỗi màn được mở 1 lần ở bản tối ưu
   (không tính điểm) để máy có dữ liệu lưu trong SQLite, như người dùng đã từng mở app.

**Kết quả** (LDPlayer, tài khoản chủ trọ thật: 50 khu, 4.000 phòng, 2.833 khách, 67.992 hóa đơn):

| Màn hình | Chỉ số | CHƯA tối ưu | ĐÃ tối ưu | Kết quả |
|---|---|---|---|---|
| **Dịch vụ** | Tắt/bật tới khi THẤY DỮ LIỆU | 83.388 ms | 1.423 ms | nhanh hơn ×59 |
| | Khung hình giật | 46,5 % | 1,2 % | ×38 |
| | Dữ liệu tải qua mạng | 3.567 KB | 642 KB | ×5,6 |
| **Người dùng** | Tắt/bật tới khi THẤY DỮ LIỆU | 5.108 ms | 1.675 ms | nhanh hơn ×3,0 |
| | Khung hình chậm nhất (đứng hình) | 3.559 ms | 77 ms | ×46 |
| | FPS trung bình | 11 | 54 | ×4,9 |
| | RAM cao nhất | 642 MB | 199 MB | ×3,2 |
| **Thẻ cư dân** | Tắt/bật tới khi THẤY DỮ LIỆU | 6.128 ms | 1.451 ms | nhanh hơn ×4,2 |
| | Khung hình chậm nhất | 1.295 ms | 38 ms | ×34 |
| | FPS trung bình | 14 | 53 | ×3,9 |
| | RAM cao nhất | 689 MB | 198 MB | ×3,5 |
| **Nhà trọ** | Tắt/bật tới khi THẤY DỮ LIỆU | 1.588–1.748 ms | 1.501–1.858 ms | tương đương |
| | Khung hình giật khi cuộn | 8,1–23,5 % | 0,5–1,6 % | mượt hơn rõ |
| Mọi màn | Bật lại app tới khung hình đầu | ~1.150–1.250 ms | ~1.180–1.320 ms | tương đương |

Thời gian tới khung hình đầu gần như bằng nhau ở hai chế độ, vì các kỹ thuật tối ưu không làm app khởi động chậm đi.
Khác biệt nằm ở **thời gian thấy dữ liệu** và **độ mượt**.

**Bài đo này phát hiện và đã sửa thêm 4 vấn đề về tốc độ:**
1. **Dịch vụ quay vòng mãi** (bản chưa tối ưu): tải hóa đơn từng phòng một, khoảng 2.833 request nối tiếp, mất khoảng 85 giây, không báo gì,
   và vẫn tải tiếp sau khi đã rời màn. Đã sửa: hiện tiến độ "x / 2.833 phòng" và dừng ngay khi rời màn (`if (!mounted) break`).
   Bản tối ưu (1 request gộp + dữ liệu lưu SQLite) hiện dữ liệu sau khoảng 1,4 giây.
2. **Đọc trùng dữ liệu lưu khi mở lại app:** màn hình gọi cùng lúc `peek()` (vẽ ngay bản cũ) và `getJson()` (hỏi server, nhận 304).
   Trước đây mỗi bên tự đọc SQLite và giải mã 642 KB JSON riêng, rồi dựng lại 4.000 đối tượng phòng 2 lần. Đã sửa: dùng chung
   1 Future (`SyncedApi._diskRow/_diskData`), và `PropertyAPI` không parse lại khi JSON không đổi.
3. **Nhà trọ giật khi cuộn ở bản tối ưu** (29–39 % so với 8 %): mỗi dòng 3 phòng là 1 item, nên khi cuộn `ListView` phải tạo item mới
   gần như mỗi khung hình. Đã sửa: **mỗi item gộp 4 dòng (12 phòng)**, vẫn chỉ build phần đang thấy. Giật giảm còn 0,5–1,6 %.
4. **Lệch do thứ tự đo:** lượt "đã tối ưu" luôn chạy ngay sau lượt "chưa tối ưu" (lượt đó vừa dùng 600–700 MB RAM), nên bị chậm oan
   khi khởi động. Đã sửa: chờ 1,5 s sau khi kill (không tính vào số đo) và đảo thứ tự luân phiên.

> Lưu ý giả lập: trên LDPlayer, lần mở đầu tiên ngay sau khi cài APK đôi khi bị màn hình trắng, và từng có 1 lần crash ở luồng
> raster (`1.raster`, lỗi GPU giả lập). Mở lại app thì bình thường. Thỉnh thoảng có 1 lượt khởi động chậm bất thường (6,5 s),
> nên đo lại lượt đó bằng nút thủ công.

---

## 1b. Bộ test từng kỹ thuật T1–T8 (bài đo riêng lẻ, điều kiện kiểm soát)

Phần này đo tách riêng từng kỹ thuật bằng dữ liệu được tạo ra trong bài test (danh sách 3.000 dòng, ảnh 1600 px...),
để thấy rõ tác dụng của **một** kỹ thuật mà các yếu tố khác không ảnh hưởng. Kết quả chính để trình bày là mục 1.

Đo ngày 20/11/2026 trên giả lập LDPlayer (Android x86_64), bản profile. Backend chạy trên laptop, kết nối qua wifi.

| Test | Kỹ thuật | Chỉ số chính | Chưa tối ưu | Đã tối ưu | Cải thiện |
|---|---|---|---|---|---|
| T1 | ListView.builder / SliverList | Thời gian mở danh sách 3.000 dòng | 5.958 ms | 47 ms | ×127 |
| | | Số dòng phải build khi mở | 3.000 | 13 | ×231 |
| | | FPS khi cuộn / khung hình giật | 11 FPS / 88 % | 63 FPS / 0 % | ×5,6 |
| T2 | cached_network_image | Request mạng khi mở lại 24 ảnh | 24 | 0 | tuyệt đối |
| T3 | Chính sách lưu ảnh 3 tháng / đổi chủ / phiên bản | Kiểm tra chức năng | – | 6/6 đúng | – |
| T4 | memCacheWidth / memCacheHeight | RAM ảnh đã giải mã (12 ảnh 1600px) | 87,9 MB | 8,7 MB | ×10 |
| | | RAM toàn app tăng thêm | 91,2 MB | 36,7 MB | ×2,5 |
| T5 | ScrollController + phân trang | Dữ liệu tải lúc mở (5.000 phần tử) | 1.816 KB | 7 KB | ×253 |
| | | Thời gian hiện dữ liệu đầu tiên | 403 ms | 48 ms | ×8,4 |
| | | Số phần tử giữ trong RAM | 5.000 | 20 | ×250 |
| T6 | compute() / Isolate | Giao diện đứng hình lâu nhất khi parse JSON 1,8 MB | 31 ms | 9 ms | ×3,4 |
| T7 | ValueNotifier từng item | Số dòng build lại sau 30 lần bấm | 390 | 0* | tuyệt đối |
| | | Tổng thời gian build | 55,5 ms | 25,3 ms | ×2,2 |
| T8 | ETag 304 + SQLite (bổ sung) | Dữ liệu tải ở lần mở thứ 2 | 724,7 KB | 0 KB | tuyệt đối |

\* T7: `PerfCounters.itemBuilds` đếm số lần hàm build của **cả dòng** chạy. Với ValueNotifier, hàm này không chạy lại;
chỉ phần bên trong `ValueListenableBuilder` của đúng dòng được bấm build lại.

**Phân tích các con số khi trình bày:**
- **T6:** parse bằng compute() **tổng thời gian dài hơn một chút** (23 → 30 ms) vì phải copy dữ liệu sang
  Isolate khác. Đổi lại, giao diện **không bị đứng**. Mục tiêu của kỹ thuật này là giữ UI mượt, không phải parse nhanh hơn.
- **T2:** ở lần 1, bản có cache chậm hơn một chút vì còn phải ghi file ra đĩa. Lần mở lại thì
  không tốn request nào. Trong mạng LAN, thời gian hai bản gần bằng nhau. Trên 4G hoặc mạng yếu, bản không cache chậm hẳn,
  và khi mất mạng thì không hiện được ảnh.
- **FPS trên giả lập:** CPU của PC mạnh nên chênh lệch FPS nhỏ hơn điện thoại thật. Nên đo lại bằng DevTools trên máy thật
  để đưa vào báo cáo.

---

## 2. Chi tiết từng kỹ thuật

### 2.1. ListView.builder / SliverList: chỉ render phần tử trong khung nhìn (T1)

**Vấn đề:** `Column` trong `SingleChildScrollView` tạo widget cho **tất cả** dòng ngay khi mở màn hình.
Với 3.000 dòng, app mất gần 6 giây mới hiện và tốn thêm ~350 MB RAM.

**Giải pháp:** `ListView.builder` (hoặc `SliverList.builder` trong `CustomScrollView`) chỉ gọi `itemBuilder` cho
các dòng đang hiện, cộng một vùng đệm nhỏ. Dòng cuộn ra khỏi màn hình bị hủy để giải phóng RAM. `itemExtent` cố định
giúp Flutter không phải đo chiều cao từng dòng.

```dart
// CHƯA tối ưu: build tất cả dòng ngay lập tức
SingleChildScrollView(child: Column(children: [
  for (var i = 0; i < _items.length; i++) _buildItem(context, i),
]))

// ĐÃ tối ưu: chỉ build dòng đang hiện
ListView.builder(
  itemExtent: widget.itemExtent,
  itemCount: count,
  itemBuilder: (context, index) => _buildItem(context, index),
)
```

**Code:**
- `lib/Source/scr/Common/PagedListView.dart`: dòng ~194 là nhánh chưa tối ưu, dòng ~206 là `ListView.builder`. Widget danh sách
  dùng chung cho các màn: thẻ, hóa đơn, lịch sử…
- `lib/Source/scr/HomePage/landlady/ServiceRoom/ServiceRoomScreen.dart` ~1012: `SliverList.builder` cho từng khu trọ trong tab Dịch vụ.
- `lib/Source/scr/HomePage/landlady/Tab/room/Dashboard_Properti_Screen.dart`: `_buildSliverList`, làm phẳng mọi khu trọ thành **một**
  `ListView.builder` (dòng header + dòng 3 phòng). Xem mục 1 để biết vì sao không dùng 100 sliver.
- `lib/Source/scr/HomePage/landlady/Tab/TabUser/Manage_User_Screen.dart`: danh sách khách thuê (Column ↔ ListView.builder).

### 2.2. cached_network_image và chính sách lưu ảnh (T2, T3)

**Giải pháp:** mọi ảnh lấy từ API đều đi qua một widget duy nhất là `AppNetworkImage`
(`lib/Source/cache/AppNetworkImage.dart`). Widget này dùng `CachedNetworkImage` với cache manager riêng (`AppCacheManager`).
Ảnh tải một lần rồi lưu thành file trong máy; lần sau đọc từ đĩa, không tốn mạng.

| Chưa tối ưu (`imageDiskCache = false`) | Đã tối ưu |
|---|---|
| `Image.network(url)`: chỉ cache trong RAM, tắt app là mất, mở lại phải tải lại | `CachedNetworkImage(cacheManager: AppCacheManager.instance, cacheKey: key, …)` |

**Ép ảnh nhỏ lại:**
- Ảnh công tơ chụp hoặc chọn từ thư viện được thu xuống tối đa 1600px, chất lượng JPEG 80 trước khi upload:
  `picker.pickImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 80)` trong `ServiceRoomScreen.dart` ~765/780.
- Ảnh trong lưới hoặc danh sách dùng bản thu nhỏ của server (`?w=300`, ~6 KB thay vì ~60 KB của bản gốc).

**Lưu trên máy tối đa 3 tháng** (`lib/Source/cache/AppCacheManager.dart`):
- `stalePeriod: 90 ngày`: file không được dùng lại trong 90 ngày sẽ bị xóa. Cần xem lại thì tự tải lại từ server.
- `maxNrOfCacheObjects: 400`: chặn trên số file để bộ nhớ máy không phình vô hạn.
- `MediaCachePolicy` còn tự quét: ảnh nào đã ghi nhận quá 90 ngày thì xóa cả file lẫn chỉ mục.

**Server giữ ảnh 1–2 năm:**
- `BackEnd/.../Config/Media/MediaRetentionJob.java` xóa ảnh không được cập nhật quá `app.media.retention-days`
  (mặc định 730 ngày).
- Khi đó API ảnh trả **204 (rỗng)** (`SmartCardController.java` ~66) và app hiện ảnh mặc định.

**Trường hợp đặc biệt** (`lib/Source/cache/MediaCachePolicy.dart`):
- **Phiên bản:** khóa cache có version, ví dụ `card-photo:12:v3`. Khi tải version mới, các version cũ cùng nhóm bị xóa ngay,
  nên app không bao giờ hiện ảnh CCCD hay ảnh thẻ cũ sau khi đã cập nhật thông tin.
- **Phòng đổi chủ:** `onRoomOwner(roomId, currentOwnerId, previousOwnerId, ownerChangedAt)` ghi nhận thời điểm đổi chủ.
  **30 ngày** sau đó, mọi ảnh thuộc chủ cũ của phòng (CCCD, ảnh thẻ…) bị xóa khỏi máy. Ảnh của chủ mới giữ nguyên.

**T3** kiểm tra cả ba luật bằng cách tua nhanh đồng hồ của chính sách (`MediaCachePolicy.clock`), không phải chờ thật:

| Kiểm tra | Kết quả |
|---|---|
| Ảnh 89 ngày tuổi vẫn giữ | ✅ |
| Ảnh 91 ngày tuổi bị xóa (file + chỉ mục) | ✅ |
| Đổi chủ 29 ngày: ảnh chủ cũ còn giữ | ✅ |
| Đổi chủ 31 ngày: ảnh chủ cũ bị xóa | ✅ |
| Ảnh của chủ mới không bị xóa | ✅ |
| Có phiên bản mới thì bản cũ bị xóa ngay | ✅ |

### 2.3. memCacheWidth / memCacheHeight: giảm độ phân giải trước khi đưa vào RAM (T4)

**Vấn đề:** ảnh JPEG 60 KB trên đĩa sau khi giải mã thành bitmap tốn `rộng × cao × 4 byte`.
Ảnh 1600×1200 tốn khoảng 7,3 MB RAM, dù chỉ hiện trong ô 100dp.

**Giải pháp:** truyền `memCacheWidth = kích thước hiển thị × devicePixelRatio`. Flutter giải mã thẳng ra bitmap đúng cỡ ô,
khoảng 0,7 MB.

```dart
// AppNetworkImage.dart ~140–186
memW = (widget.width! * dpr).round();          // ô 100dp, dpr 2.75 -> 275px
...
CachedNetworkImage(..., memCacheWidth: memW, memCacheHeight: memH)
// Chưa tối ưu (imageResize = false): memW = memH = null -> giải mã nguyên ảnh gốc
```

Đo được: 12 ảnh tốn **87,9 MB → 8,7 MB** RAM ảnh, RAM toàn app tăng **91 → 37 MB**.

### 2.4. ScrollController: tải thêm khi cuộn gần cuối (T5)

**Giải pháp:** chỉ tải trang đầu (20 phần tử). `ScrollController` lắng nghe vị trí cuộn; còn cách cuối khoảng 400px thì gọi API
trang kế tiếp.

```dart
// PagedListView.dart ~116
void _onScroll() {
  final pos = _controller.position;
  if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) _loadMore(); // _loadMoreThreshold = 400
}
```

| Chưa tối ưu (`paging = false`) | Đã tối ưu |
|---|---|
| Gọi API một lần lấy cả 5.000 phần tử (1,8 MB). Phải chờ tải và parse xong mới hiện, cả 5.000 phần tử nằm trong RAM. | Trang 20 phần tử (7 KB) hiện sau 48 ms; cuộn tới đâu tải tới đó. |

### 2.5. compute() / Isolate cho jsonDecode (T6)

**Vấn đề:** `jsonDecode` chạy trên UI thread. JSON lớn làm giao diện đứng hình, mất khung hình.

**Giải pháp:** một hàm duy nhất là `JsonIsolate.decode()` (`lib/Source/api/JsonIsolate.dart`). Response lớn hơn 16 KB thì parse
bằng `compute()` ở Isolate nền; response nhỏ thì parse luôn, vì tạo Isolate cũng tốn thời gian. Mọi file trong `lib/Source/api/`
gọi hàm này thay cho `json.decode`.

```dart
// Chưa tối ưu:  var data = json.decode(utf8.decode(response.bodyBytes));
// Đã tối ưu:
static Future<dynamic> decode(Uint8List bytes) async {
  if (!PerfFlags.isolateJson.value || bytes.length < isolateThresholdBytes) return _decode(bytes);
  return compute(_decode, bytes);   // chạy ở Isolate khác, UI thread vẫn vẽ khung hình
}
```

### 2.6. ValueNotifier cho từng item (T7)

**Vấn đề:** dùng `setState()` để cập nhật một dòng thì cả danh sách build lại.

**Giải pháp:** mỗi phần tử được bọc trong một `ValueNotifier<T>`, và mỗi dòng dùng `ValueListenableBuilder`. Đổi
`item.value = …` thì chỉ đúng dòng đó vẽ lại.

```dart
// PagedListView.dart ~92–100
ValueNotifier<T> _wrap(T e) {
  final n = ValueNotifier<T>(e);
  if (!_useItemNotifier) n.addListener(_rebuildAll);   // Chưa tối ưu: setState() cả danh sách
  return n;
}
// Dòng: ValueListenableBuilder(valueListenable: item, builder: (_, v, __) => ListTile(...))
```

### 2.7. Bổ sung: ETag + database phụ SQLite, gộp request (T8)

- `lib/Source/api/SyncedApi.dart`: gửi `If-None-Match`. Nếu dữ liệu không đổi, server trả 304 không có body và app dùng bản lưu
  trong SQLite (`lib/Source/local/LocalDb.dart`). Mở lại màn hình thì hiện ngay bản trong máy, rồi mới hỏi server.
- Tab Dịch vụ gộp N request (mỗi phòng một request) thành một request `billing-status`, và hiện danh sách phòng trước khi
  trạng thái hóa đơn về.

---

## 3. Sơ đồ file liên quan

```
lib/Source/
├── perf/
│   ├── PerfFlags.dart              công tắc từng kỹ thuật + PERF_MODE (2 bản APK)
│   ├── PerfMonitor.dart            đo FPS / jank / RAM / ảnh trong RAM / mạng
│   ├── PerfOverlay.dart            bảng FPS-RAM nổi trên mọi màn hình
│   ├── PerfLabScreen.dart          màn "Hiệu năng & Demo"
│   ├── MeterGalleryScreen.dart     lưới 1.000 ảnh công tơ + "Tự so sánh"
│   ├── DemoFeedScreen.dart         danh sách demo 5.000–20.000 dòng có ảnh
│   ├── real/                       ĐO TRÊN APP THẬT (cách chính)
│   │   ├── RealBench.dart          tự động / thủ công, lưu kết quả, ghép cặp, Markdown/CSV/JSON
│   │   ├── RealCompareScreen.dart  màn "So sánh trên app thật"
│   │   ├── BenchAnalysis.dart      KẾT LUẬN + PHÂN TÍCH tự viết bằng lời từ số vừa đo
│   │   ├── RestartBench.dart       bài đo "tắt hẳn app rồi bật lại" + dải thông báo BenchBanner
│   │   └── BenchCharts.dart        biểu đồ cột / đường / tổng quan (vẽ bằng Flutter, không thư viện)
│   └── suite/
│       ├── OptimizationTests.dart  BỘ TEST T1–T8 (logic đo)
│       └── TestSuiteScreen.dart    màn bộ test + test tổng thể + copy Markdown
├── cache/  AppNetworkImage · AppCacheManager · MediaCachePolicy
├── api/    JsonIsolate · SyncedApi · (mọi API dùng JsonIsolate)
└── scr/Common/PagedListView.dart   ListView.builder + ScrollController + ValueNotifier
integration_test/
├── real_app_test.dart              đo tự động trên app thật, 4 màn × 2 chế độ (run_frontend.bat mục 9)
├── suite_test.dart                 bộ test T1–T8 (mục 7)
├── perf_test.dart                  đo FPS/RAM 4 màn hình thật (mục 3)
└── meter_test.dart                 tự so sánh lưới ảnh công tơ
```
