# Hướng dẫn đo RAM / FPS bằng Flutter DevTools trên điện thoại thật

Mục tiêu: chụp **biểu đồ Memory** và **biểu đồ Performance (FPS)** cho hai trường hợp **chưa tối ưu** và **đã tối ưu**
để đưa vào báo cáo.

> Luôn chạy ở chế độ **profile**. Chế độ debug chạy chậm hơn nhiều lần, nên FPS và RAM đo được là SAI.
> Giả lập trên PC cũng cho số "đẹp" hơn máy thật vì CPU của PC mạnh.

## 1. Chuẩn bị điện thoại
1. Bật **Tùy chọn nhà phát triển**: Cài đặt → Thông tin điện thoại → bấm 7 lần vào "Số hiệu bản tạo".
2. Bật **Gỡ lỗi USB**, cắm cáp, rồi bấm "Cho phép" trên điện thoại.
3. Chạy backend (`run_backend.bat`).

## 2. Chạy app và mở DevTools
1. Mở `run_frontend.bat` và chọn **8. DevTools trên điện thoại thật**.
   - Lệnh này gọi `adb reverse tcp:8080 tcp:8080` để điện thoại gọi backend qua cáp USB,
     rồi chạy `flutter run --profile`.
2. Khi app đã chạy, bấm phím **`v`** trong cửa sổ đó. DevTools sẽ mở trên trình duyệt.
   Nếu không mở, copy dòng `The Flutter DevTools debugger and profiler ... is available at: http://127.0.0.1:...`
   vào trình duyệt.
3. Đăng nhập tài khoản chủ trọ có dữ liệu thật (hiện có 50 khu, 4.000 phòng, 2.833 khách thuê và thẻ).

## 3. Chụp biểu đồ RAM (tab **Memory**)
Làm hai lượt: lượt 1 TẮT hết tối ưu, lượt 2 BẬT hết. Dùng nút "Tắt hết" / "Bật hết" trong màn Hiệu năng & Demo,
hoặc cài bản `apk\app_chua_toi_uu.apk` rồi `apk\app_toi_uu.apk`.

1. Mở tab **Memory** và bấm **GC** (thùng rác) để có mốc ban đầu sạch.
2. Trên điện thoại, mở một màn thật: **Người dùng** (2.833 khách), **Thẻ cư dân**, **Dịch vụ** hoặc **Nhà trọ**, rồi cuộn khoảng 15 giây.
   Cách nhanh nhất: Hiệu năng & Demo → SO SÁNH TRÊN APP THẬT → "Chạy tự động". App tự mở và cuộn từng màn ở cả 2 chế độ,
   DevTools chỉ cần ghi lại.
3. Biểu đồ có các đường:
   - **RSS**: tổng RAM tiến trình. Đây là con số đưa vào báo cáo.
   - **Dart Heap**: dữ liệu Dart (danh sách, JSON).
   - **Raster cache / Native**: bitmap ảnh. Khi tắt `memCacheWidth`, đường này tăng vọt.
4. Chụp màn hình biểu đồ (Win + Shift + S). Đặt tên `ram_chua_toi_uu.png` / `ram_toi_uu.png`.

Gợi ý: ở bảng **Diff Snapshots**, chụp snapshot trước và sau khi mở danh sách để thấy số object `ListTile` hoặc
`_ImageGrid`. Bản Column có hàng nghìn object; bản ListView.builder chỉ khoảng 10–20.

## 4. Chụp biểu đồ FPS (tab **Performance**)
1. Mở tab **Performance**.
2. Trên điện thoại, cuộn nhanh danh sách hoặc lưới ảnh khoảng 5–10 giây.
3. Biểu đồ **Flutter frames**:
   - Mỗi cột là một khung hình. Cột vượt vạch **16 ms** (màu đỏ) là khung hình bị giật (jank).
   - Mỗi cột có hai phần: **UI** (build/layout trên Dart) và **Raster** (vẽ lên GPU).
4. Bấm vào một cột đỏ, xem **Timeline Events** để biết hàm nào tốn thời gian (ví dụ `jsonDecode` khi tắt compute()).
5. Chụp `fps_chua_toi_uu.png` / `fps_toi_uu.png`.

## 5. Đo đúng đoạn của từng bài test
Bộ test (Hiệu năng & Demo → BỘ TEST TỐI ƯU) đánh dấu mỗi lượt đo trên Timeline với tên dạng:

```
QLPT T1 ListView.builder / SliverList [CHƯA tối ưu]
QLPT T1 ListView.builder / SliverList [ĐÃ tối ưu]
QLPT T6 compute() / Isolate cho jsonDecode [CHƯA tối ưu]
...
```

Mở tab Performance → bấm **Record** (hoặc bật "Timeline" trong Performance settings) → trên điện thoại bấm "Chạy" một bài test
→ dừng record. Trên timeline, gõ `QLPT` vào ô tìm kiếm để nhảy đúng đoạn trước/sau. Riêng T6, đoạn [CHƯA tối ưu] có một khối
`jsonDecode` dài nằm trên luồng UI; đoạn [ĐÃ tối ưu] thì khối đó nằm ở Isolate khác.

## 6. Biểu đồ ngay trong app (không cần DevTools)
Hiệu năng & Demo → **SO SÁNH TRÊN APP THẬT**: app tự vẽ biểu đồ so sánh CHƯA/ĐÃ tối ưu cho từng màn thật
(biểu đồ cột các chỉ số, biểu đồ đường FPS và RAM theo giây, biểu đồ tổng quan 4 màn). Có thể đo **tự động** hoặc **thủ công**
(bấm "Bắt đầu ghi", tự dùng app, bấm ■ STOP). Nên dùng DevTools và biểu đồ trong app **song song**:
DevTools cho biểu đồ chi tiết từng khung hình, màn so sánh cho bảng tổng hợp.

**Trực quan nhất khi trình bày:** thẻ cam **"0. TẮT HẲN APP RỒI BẬT LẠI"**. App tự tắt hẳn rồi bật lại, tự vào màn,
dải đen dưới cùng hiện "THẤY DỮ LIỆU sau ... ms", rồi tự cuộn. Bấm "Tự động" để chạy 4 màn × 2 chế độ (khoảng 3 phút), hoặc chọn 1 màn
và bấm "Tắt/bật – CHƯA tối ưu" rồi "Tắt/bật – ĐÃ tối ưu" để người xem thấy rõ từng bên. Bấm "Hủy" ở dải đen để dừng.
Kết quả có thêm 2 chỉ số **"Bật lại app tới khung hình đầu"** và **"Tắt/bật app tới khi THẤY DỮ LIỆU"**, kèm bảng in ra logcat:
`adb logcat | findstr REAL`.

Không có máy thật:
- `run_frontend.bat` mục **9** đo tự động trên LDPlayer và in bảng Markdown. Kết quả cũng được lưu vào app, mục 1 để cài lại app rồi xem biểu đồ.
- `run_frontend.bat` mục 7 chạy bộ test từng kỹ thuật T1–T8.
- `flutter run --profile -d emulator-5554` trên LDPlayer rồi bấm `v`. DevTools vẫn dùng được, nhưng phải ghi rõ trong báo cáo
  là số liệu đo trên giả lập.

## 7. Bảng tổng hợp nên có trong báo cáo
| Màn hình | RAM (RSS) chưa tối ưu | RAM tối ưu | FPS chưa tối ưu | FPS tối ưu | % khung giật |
|---|---|---|---|---|---|
| Người dùng (2.833 khách) | | | | | |
| Thẻ cư dân (2.833 thẻ) | | | | | |
| Dịch vụ (4.000 phòng) | | | | | |
| Nhà trọ (50 khu, 4.000 phòng) | | | | | |
