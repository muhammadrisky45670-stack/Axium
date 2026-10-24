# Axium — repo layout (Fluent UI)

Dipecah dari `Axium By Luvio.lua` (41.282 baris / 1,2 MB) supaya ringan:
executor cuma menjalankan `loader.lua`, sisanya diambil dari GitHub saat dibutuhkan.

```
Axium/
├─ loader.lua                      ~130 baris            entry point
├─ main.lua                        ~440 baris            UI + semua fitur (Fluent)
└─ lib/
   ├─ fluent.lua                   127 KB   Fluent v1.1.0
   ├─ fluent_savemanager.lua         8 KB   config system
   ├─ fluent_interfacemanager.lua    3 KB   tema & transparansi
   ├─ dex.lua                      467 KB   Dex Explorer   (lazy)
   ├─ cobalt.lua                   456 KB   Cobalt Spy     (lazy)
   └─ windui.lua                   268 KB   cadangan kalau mau balik ke WindUI
```

## Cara pakai

1. Buat repo GitHub **public**, misalnya `username/axium`.
2. Push isi folder ini apa adanya (jaga struktur `lib/`).
3. Di `loader.lua`, ganti:

   ```lua
   Repo = "USERNAME/REPO",  -->  "username/axium"
   ```

4. Jalankan di executor:

   ```lua
   loadstring(game:HttpGet("https://raw.githubusercontent.com/username/axium/main/loader.lua"))()
   ```

## Alur unduhan

| Tahap | File | Ukuran | Kapan |
|---|---|---|---|
| 1 | `main.lua` | ~15 KB | saat loader dijalankan |
| 2 | `lib/fluent.lua` + 2 addon | ~138 KB | saat main.lua start |
| 3 | `lib/dex.lua` | 467 KB | hanya saat toggle Dex ON |
| 4 | `lib/cobalt.lua` | 456 KB | hanya saat toggle Cobalt ON |

Start cuma ± 150 KB. Dex + Cobalt (± 920 KB) tidak pernah diunduh kalau tidak dipakai.

## Mirror & cache

`loader.lua` mencoba tiga URL berurutan: `raw.githubusercontent.com` →
`cdn.jsdelivr.net` → `raw.githack.com`. Hasil unduhan di-cache di
`LuvioHub/AxiumCache/` selama `CacheTTL` detik (default 300).

Paksa versi terbaru: `getgenv().AxiumFetch("main.lua", true)`.

## Catatan Acrylic

`main.lua` memakai `Acrylic = true` (blur). Blur bisa terdeteksi sebagian
anti-cheat; matikan dengan:

```lua
getgenv().AxiumConfig.Acrylic = false
```

sebelum `loader.lua` dijalankan.

## Ganti UI lagi nanti

Semua pemanggilan UI ada di `main.lua`, lib-nya file terpisah di `lib/`.
Kalau mau pindah library: ganti `lib/fluent*.lua` + blok
`CreateWindow` / `AddTab` / `AddButton` / `AddToggle` / `AddInput` /
`AddParagraph` di `main.lua`. `loader.lua` tidak perlu disentuh.

## Lisensi pihak ketiga

- Fluent — dawid-scripts (MIT)
- Dex — Moon / LorekeeperZinnia, modifikasi Infinite Yield
- Cobalt — deivid, upio (notpoiu/cobalt)
- WindUI — Footagesus (MIT), hanya cadangan
