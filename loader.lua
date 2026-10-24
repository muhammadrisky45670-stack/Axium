--[[
    Axium Loader
    Titik masuk kecil (~100 baris). Semua kode besar diambil dari GitHub saat
    dibutuhkan, jadi yang di-paste ke executor cuma file ini.

    Alur:
        loader.lua  ->  main.lua  ->  lib/windui.lua        (saat start)
                                  ->  lib/dex.lua           (saat toggle Dex)
                                  ->  lib/cobalt.lua        (saat toggle Cobalt)

    Cara pakai:
        1. Ganti CONFIG.Repo jadi "username/repo" GitHub kamu (repo public).
        2. Push folder ini apa adanya: loader.lua, main.lua, lib/.
        3. Jalankan loader.lua saja:
               loadstring(game:HttpGet("https://raw.githubusercontent.com/<user>/<repo>/main/loader.lua"))()

    Catatan: Dex (466 KB) dan Cobalt (456 KB) tidak pernah diunduh kalau
    toggle-nya tidak dipakai — ini yang bikin start jadi ringan.
]]

local CONFIG = {
    Repo = "Axium", -- TODO: ganti dengan repo kamu
    Branch = "main",
    Entry = "main.lua",

    CacheTTL = 300, -- detik; 0 = cache dimatikan
    CacheFolder = "LuvioHub/AxiumCache",

    Mirrors = {
        "https://raw.githubusercontent.com/%s/%s/%s",
        "https://cdn.jsdelivr.net/gh/%s@%s/%s",
        "https://raw.githack.com/%s/%s/%s",
    },
}

getgenv().AxiumConfig = CONFIG

--========================================
-- HTTP & CACHE
--========================================

local function httpGet(url)
    if typeof(syn) == "table" and syn.request then
        local ok, response = pcall(syn.request, { Url = url, Method = "GET" })
        if ok and response and response.Body then return response.Body end
    end
    if typeof(request) == "function" then
        local ok, response = pcall(request, { Url = url, Method = "GET" })
        if ok and response and response.Body then return response.Body end
    end
    if typeof(http) == "table" and http.request then
        local ok, response = pcall(http.request, { Url = url, Method = "GET" })
        if ok and response and response.Body then return response.Body end
    end
    return game:HttpGet(url, true)
end

local function cachePath(path)
    return CONFIG.CacheFolder .. "/" .. (path:gsub("[/\\]", "_")) .. ".cache"
end

local function readCache(path)
    if CONFIG.CacheTTL <= 0 then return nil end
    local ok, data = pcall(function()
        local file = cachePath(path)
        if typeof(isfile) == "function" and typeof(readfile) == "function" and isfile(file) then
            local age = 0
            if typeof(getfiletimestamp) == "function" then
                age = os.time() - getfiletimestamp(file)
            end
            if age <= CONFIG.CacheTTL then return readfile(file) end
        end
        return nil
    end)
    return ok and data or nil
end

local function writeCache(path, body)
    if CONFIG.CacheTTL <= 0 then return end
    pcall(function()
        if typeof(isfolder) == "function" and typeof(makefolder) == "function" then
            if not isfolder("LuvioHub") then makefolder("LuvioHub") end
            if not isfolder(CONFIG.CacheFolder) then makefolder(CONFIG.CacheFolder) end
        end
        if typeof(writefile) == "function" then writefile(cachePath(path), body) end
    end)
end

--========================================
-- FETCH
--========================================

local function fetchSource(path, force)
    if not force then
        local cached = readCache(path)
        if cached and #cached > 0 then return cached, "cache" end
    end

    local tried = {}
    for _, template in ipairs(CONFIG.Mirrors) do
        local url = string.format(template, CONFIG.Repo, CONFIG.Branch, path)
        local ok, body = pcall(httpGet, url)
        if ok and typeof(body) == "string" and #body > 0 and not body:find("404: Not Found", 1, true) then
            writeCache(path, body)
            return body, url
        end
        tried[#tried + 1] = url
    end

    error("Axium loader: gagal mengambil '" .. path .. "'\n" .. table.concat(tried, "\n"), 0)
end

-- dipakai main.lua untuk ambil lib/*.lua belakangan (lazy load)
getgenv().AxiumFetch = fetchSource

--========================================
-- RUN
--========================================

if getgenv().AxiumLoaded then
    warn("[Axium] Sudah pernah dimuat di sesi ini. Stop/execute ulang kalau mau reload.")
end

local source, origin = fetchSource(CONFIG.Entry)
local chunk, compileError = loadstring(source)
if not chunk then
    error("Axium loader: " .. CONFIG.Entry .. " gagal dikompilasi: " .. tostring(compileError), 0)
end

getgenv().AxiumLoaded = true
getgenv().AxiumOrigin = origin
return chunk()
