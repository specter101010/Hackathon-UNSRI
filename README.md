# QUANTPASS DualGuard - Diagram Blok Sistem dan Rincian Modul RTL

Rancangan prototipe riset untuk deteksi serangan presentasi (PAD) wajah dan dokumen. Disusun berdasarkan DualGuard_Analisis_v3.pdf serta tiga diagram referensi,Oktober 2026. Bukan pembuktian keaslian kriptografis paspor atau pencocokan identitas. 

UNSRI TEAM
KETUA     : MOCHAMMAD RANDY SURYA BACHRI.
ANGGOTA 1 : SACHIO AJI.
ANGGOTA 2 : YASYIR MASY'AL.
ANGGOTA 3 : ZINNIARETHIE ANDARI KOSTIENE.

## Paket
- `figures/Diagram_Blok_Sistem.png`: pembagian kamera, ARM HPS, DDR3, FPGA, keputusan.
- `figures/Arsitektur_Modul_RTL.png`: modul dan jalur data yang sesuai dengan kode.
- `figures/FSM_Tile.png`: kendali tile dan backpressure.
- `docs/DualGuard_Diagram_dan_RTL.pdf`: uraian teknis, register, validasi dan lampiran seluruh RTL.
- `rtl/`: lima modul Verilog-2005, tidak memakai IP tertutup.
- `tb/`: testbench mandiri (testbench CSR memakai SystemVerilog).
- `Makefile`: kompilasi dan simulasi dengan Icarus Verilog.

## 3.1 Solusi dan Arsitektur Sistem
DualGuard mengimplementasikan satu mesin komputasi CNN INT8 yang digunakan bergantian untuk MiniFASNetV2 pada pemeriksaan face anti-spoofing dan MobileNetV2 pada pemeriksaan dokumen. ARM Cortex-A9 pada HPS mengelola akuisisi kamera, deteksi ROI, crop, resize atau patch, pemeriksaan kualitas, kuantisasi, penjadwalan layer/tile, serta agregasi skor antar-frame. Bobot kedua model berada di DDR3 HPS. Bobot tile terpilih disalin ke bank memori FPGA melalui jembatan HPS-FPGA. Penggantian model dilakukan dengan memuat bobot dan parameter baru setelah semua keluaran pekerjaan sebelumnya selesai dikonsumsi; bitstream datapath tetap.

Di FPGA, aktivasi INT8 dibaca dari buffer sinkron lalu disiarkan ke jalur MAC. Setiap jalur memiliki bank bobot sendiri, pengali signed 8x8 dan akumulator signed INT32. Mesin melakukan dot product untuk beberapa kanal keluaran dari satu posisi spasial. Requantizer bersama mengubah hasil INT32 menjadi INT8 secara berurutan. Hasil menyertakan nomor jalur dan identitas mode untuk mencegah pertukaran hasil antarmodel. ARM mengolah keluaran layer menjadi logits/skor melalui head model dan operator yang belum didukung; hasil tile bukan otomatis skor PAD.

Skor wajah dan dokumen dikalibrasi terpisah. Dalam sesi yang mewajibkan dua pemeriksaan, status lolos PAD hanya diterbitkan jika kedua cabang memenuhi ambang validasi dan kualitas gambar memadai. Skor meragukan atau kualitas buruk memicu ambil ulang, sedangkan hasil di bawah ambang memicu pemeriksaan manual. Jumlah frame, patch dan ambang ditetapkan pada validasi, bukan diubah berdasarkan data uji.

## Batas implementasi yang harus disampaikan saat presentasi
Kode ini adalah accelerator tile konvolusi/dot-product dan register kontrol, bukan CNN lengkap siap membaca kamera. Kamera, Linux driver, graph runtime, model terlatih, DMA DDR3, clock/reset board, pin assignment, Platform Designer dan Quartus project belum disertakan. Baseline memakai programmed I/O (PIO); DMA dan double buffering adalah pengembangan untuk menekan waktu transfer. Tidak ada klaim latensi, akurasi, daya atau penggunaan DSP hasil board.

MiniFASNetV2 wajah 80x80 dan MobileNetV2 width 0.5 dokumen atau CNN patch 64x64 adalah kandidat proposal, belum merupakan model yang terintegrasi. Audit graph aktual wajib dilakukan: depthwise convolution, PReLU, residual add, pooling, SE, FC dan softmax tidak otomatis tersedia dalam RTL ini. ARM menangani operator tersebut pada baseline. Depthwise dapat dipetakan satu jalur per pekerjaan dengan packing ulang, tetapi utilisasinya rendah; engine depthwise khusus diperlukan bila bottleneck besar.

## Kontrak komputasi
Untuk jalur j dan panjang K:

`acc[j] = bias[j] + sum(a[k] * w[j][k], k=0..K-1)`

`q[j] = clamp_INT8(round_away_from_zero(acc[j] * multiplier[j] / 2^shift[j]))`

Jika ReLU aktif, nilai negatif dijepit ke 0 sebelum saturasi INT8. Kuantisasi baseline simetris dengan zero-point aktivasi, bobot dan keluaran semuanya 0. Multiplier adalah integer positif/nonnegatif INT32 (0..2147483647), shift 0..62, bias memakai skala accumulator. Multiplier dan shift per kanal mewakili rasio skala input*bobot/output. Ini kontrak fixed point khusus, **bukan requantization TFLite bit-exact**. Model wajib dievaluasi ulang dengan golden model integer ini. Spesifikasi TFLite mengizinkan zero-point aktivasi nonnol dan bobot per kanal; model semacam itu tidak dapat langsung dipakai tanpa konversi tervalidasi atau ekstensi RTL.

Bias harus berada dalam rentang -2^30..2^30-1 untuk DEPTH=256; setiap penjumlahan akhir harus muat INT32. Tidak ada deteksi overflow runtime. Untuk bobot/aktivasi signed INT8, batas absolut konservatif dot product tanpa bias adalah K*16384 (4,194,304 untuk K=256). RAM tidak direset: host wajib mengisi semua alamat aktif sebelum START dan tidak membaca hasil sebelum VALID.

Konfigurasi implementasi final memakai LANES=64 dan DEPTH=256. Fitter Cyclone V 5CSEBA6U23I7 berhasil dengan 3.954 ALM, 6.669 register, 65 RAM block dan 67 dari 112 DSP. Konfigurasi 128 lane gagal ditempatkan karena kebutuhan DSP melebihi kapasitas perangkat. FETCH dan MAC bergantian, sehingga fase hitung mengeluarkan LANES MAC per 2 clock.

## Pemetaan konvolusi
ARM membentuk `a[k]` dari jendela input untuk satu (y,x), dengan k=((ky*Kw+kx)*Cin+ci), termasuk padding nol. Untuk output channel j, `w[j][k]` memakai urutan yang sama. Setiap lane menghasilkan satu kanal output pada posisi itu. Pointwise 1x1 berarti K=Cin. Jika Cout>LANES, ulangi per kelompok kanal; lane yang tidak terpakai diisi bobot/bias nol dan hasilnya diabaikan. Bobot dapat dipakai ulang untuk posisi spasial berikutnya, hanya aktivasi diganti.

Jika K>DEPTH, bagi k menjadi segmen. Bias hanya disertakan di segmen pertama, bias segmen lain nol. ARM menjumlahkan keluaran RAW_ACC seluruh segmen dalam integer lebar, lalu menerapkan requantization **satu kali setelah seluruh segmen**. Jangan menjumlahkan hasil INT8 yang telah disaturasi. Versi sekarang tidak mempertahankan partial sum antartile di FPGA. Pengembangan scheduler + partial-sum SRAM perlu dilakukan untuk inferensi efisien.

## Rincian Modul RTL
| Modul | Fungsi | Data/antarmuka | Catatan implementasi |
|---|---|---|---|
| dg_csr_top | Register dan handshake HPS | Avalon-MM 32-bit | readLatency=0, waitrequest=0, byte address, full-word writes |
| dg_tile_core | FSM, parameter kanal, mode, serialisasi hasil | start/busy/done/error; valid/ready | Mode dikunci saat START; bukan pemilih bobot otomatis |
| dg_tile_ram | Buffer sinkron aktivasi/bobot | INT8, alamat 16-bit | Satu bank aktivasi + LANES bank bobot; M10K hint bukan jaminan inference |
| dg_mac_lane | Multiply-accumulate per kanal | signed INT8xINT8 -> INT16 -> INT32 | Output-stationary; clear memuat bias |
| dg_requant | Pengali skala, pembulatan, ReLU, saturasi | INT32xINT32 -> INT64 -> INT8 | Satu unit bersama; critical path perlu evaluasi timing |

FSM: IDLE menerima START valid dan mengisi acc=bias. FETCH membaca RAM sinkron. MAC menambahkan produk ke seluruh jalur. Jika belum akhir k, kembali FETCH. FINISH memberi satu siklus setelah update accumulator terakhir. EMIT mempertahankan hasil dan tag hingga POP dari host; setelah lane terakhir dikonsumsi, DONE berdenyut dan status sticky diperbarui pada clock berikutnya. START saat busy menghasilkan error; perubahan konfigurasi ketika busy ditolak. Error tidak membatalkan komputasi aktif.

Tidak diperlukan adder tree antarlane karena setiap lane mengakumulasi kanal keluaran berbeda. Bila nanti paralelisme diarahkan pada dimensi k, barulah tree reduction dibutuhkan.

## Register map (offset byte dari base address komponen)
| Offset | Register | Akses / isi |
|---|---|---|
| 0x00 | CONTROL | W: bit0 START; bit1 clear status; bit2 POP hasil. Gunakan satu perintah per write. |
| 0x04 | STATUS | R: bit0 BUSY, bit1 VALID, bit2 DONE sticky, bit3 ERROR sticky |
| 0x08 | LENGTH | RW: K, 1..DEPTH |
| 0x0C | CONFIG | RW: bit0 model_id (0 wajah,1 dokumen), bit1 ReLU |
| 0x10 | INDEX | RW: indeks aktivasi/bobot, 0..DEPTH-1 |
| 0x14 | LANE | RW: bank bobot/parameter, 0..LANES-1 |
| 0x18 | ACT_DATA | W: signed INT8 pada bit7:0, alamat INDEX |
| 0x1C | WEIGHT_DATA | W: signed INT8 pada bit7:0, alamat INDEX dan LANE |
| 0x20 | BIAS | W: signed INT32 untuk LANE |
| 0x24 | MULTIPLIER | W: integer 0..2^31-1 untuk LANE |
| 0x28 | SHIFT | W: 0..62 untuk LANE |
| 0x30 | RESULT_Q | R: INT8 sign-extended, valid hanya ketika VALID=1 |
| 0x34 | RESULT_ACC | R: INT32 sebelum requantization, valid ketika VALID=1 |
| 0x38 | RESULT_META | R: lane pada bit15:0; model_id pada bit16 |
| 0x3C | CYCLES | R: jumlah clock BUSY, termasuk waktu tunggu host/POP |
| 0x40 | LANES | R: parameter hardware |
| 0x44 | DEPTH | R: parameter hardware |

CSR harus didaftarkan sebagai agent Avalon-MM sederhana nonburst, addressUnits=SYMBOLS (byte), readLatency=0, dengan akses 32-bit selaras. Read dan write tidak dilakukan sekaligus oleh host. Base address disalin dari Platform Designer, tidak dihardcode. Semua port berada pada satu clock; reset rst_n sinkron aktif rendah harus disinkronkan sebelum masuk. Jembatan HPS-FPGA menangani domain clock menurut konfigurasi sistem. IRQ aktif ketika DONE atau ERROR sticky; CLEAR menghapusnya. Nilai konfigurasi invalid ditolak dan nilai lama dipertahankan; driver wajib berhenti jika ERROR dan memperbaiki transaksi sebelum START.

## Urutan driver
1. Tunggu BUSY=0, clear status dengan CONTROL=2.
2. Konfirmasi identitas model, bentuk tensor dan checksum blob di software; mode hardware hanya tag.
3. Tulis LENGTH, CONFIG. Isi aktivasi via INDEX+ACT_DATA.
4. Untuk setiap LANE, isi bobot via INDEX+WEIGHT_DATA; isi BIAS, MULTIPLIER, SHIFT. Memori lama boleh digunakan hanya jika driver menjamin cache bobot masih sesuai.
5. Periksa ERROR; jika ada, hentikan perintah dan muat ulang data/config yang benar.
6. Tulis CONTROL=1. Poll VALID/ERROR dengan timeout.
7. Saat VALID: baca RESULT_META, RESULT_ACC dan RESULT_Q; verifikasi model/lane; tulis CONTROL=4 untuk POP. Ulangi hingga LANES hasil.
8. Poll DONE setelah POP terakhir. Periksa ERROR dan catat CYCLES.
9. Saat mode berganti, tunggu selesai, clear status dan reload seluruh bobot/parameter tile model baru. Satu bit CONFIG tidak mengganti model sendiri.

## Anggaran dan waktu
Payload RAM = DEPTH*(LANES+1) byte. Pada konfigurasi 64x256, payload logis berjumlah 16.640 byte. Alokasi fisik hasil Fitter menggunakan 133.120 block-memory bits dan 65 RAM block, karena setiap bank kecil dapat menghabiskan satu blok fisik.

Dengan konsumsi satu output setiap clock, latensi dari START diterima sampai POP terakhir adalah 2*K+1+LANES clock (tidak termasuk pemuatan PIO dan delay host). Untuk K=256 dan LANES=64: 577 clock; pada clock **asumsi** 100 MHz setara 5,77 us, bukan waktu inferensi model. Peak fase MAC rata-rata LANES*fclk/2; LANES=64 pada 100 MHz memberi 3,2 GMAC/s sebelum transfer/output/idle. Target 100 MHz tetap harus dikonfirmasi melalui TimeQuest.

Pemakaian DSP tidak dapat diasumsikan tepat tiga pengali per blok dari operator `*` Verilog. DSP packing tergantung fitter, lebar dan struktur datapath. Hitung DSP untuk MAC, requantizer dan kontrol dari report Quartus. DMA, double buffering dan burst transfer baru boleh diberi angka setelah integrasi.

## Verifikasi
Jalankan `make test`. Testbench CSR mengecek 12 tile dengan bobot di-reload, 48 dot product terhadap perhitungan independen, K=1 dan K=256, bilangan signed ekstrem, ReLU, saturasi, output yang ditahan tanpa POP, tag mode/lane, larangan perubahan konfigurasi saat busy, serta error panjang, shift, multiplier dan byteenable. Testbench requantization mengecek 10 vektor batas termasuk tie negatif dan produk INT64. Testbench CSR memakai 4 lane untuk mempercepat simulasi; top default 8 lane juga dikompilasi. Konfigurasi 8 dan 128 lane telah dielaborasi dan disimulasikan dengan satu dot product signed ekstrem pada setiap lane; kedua uji lulus. Ini tidak membuktikan kelayakan resource atau timing 128 lane. Ini pengujian fungsional, bukan coverage lengkap atau pembuktian formal.

Hasil eksplorasi resource: 8 lane berhasil, 64 lane berhasil dan dipilih sebagai konfigurasi final, sedangkan 128 lane gagal Fitter karena DSP tidak mencukupi. Uji berikutnya: Fmax/timing 100 MHz; golden tensor tiap layer; port DDR3; timeout/reset; latensi total kamera+ARM+transfer+FPGA+fusi; APCER/BPCER/ACER; dan quantization loss dibanding FP32.

## Referensi
[1] Dokumen internal tim: DualGuard_Analisis_v3.pdf dan diagram model/sistem/accelerator yang dilampirkan.
[2] Terasic, DE10-Nano documentation: https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&No=1046&PartNo=4
[3] Intel, Avalon Interface Specifications: https://cdrdv2-public.intel.com/667068/mnl_avalon_spec-683091-667068.pdf
[4] TensorFlow, 8-bit quantization specification: https://github.com/tensorflow/tensorflow/blob/master/tensorflow/lite/g3doc/performance/quantization_spec.md

Referensi [2]-[4] untuk integrasi dan format angka, bukan bukti kinerja atau akurasi rancangan ini. Kandidat model mengikuti proposal dan belum divalidasi ulang di paket ini.
