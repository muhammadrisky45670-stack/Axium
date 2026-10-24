--[[
    Axium Loader
    Titik masuk kecil. Semua kode besar diambil dari GitHub saat dibutuhkan.

    Alur:
        loader.lua  ->  main.lua  ->  lib/fluent*.lua     (saat start)
                                  ->  lib/dex.lua         (saat toggle Dex)
                                  ->  lib/cobalt.lua      (saat toggle Cobalt)

    Cara pakai:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/muhammadrisky45670-stack/Axium/main/loader.lua"))()

    Catatan penting soal cache:
        Cache hanya menerima file yang benar-benar bisa dikompilasi. Kalau
        suatu URL mengembalikan halaman error (HTML/teks 400/404), isinya
        dibuang, tidak disimpan. Cache juga dipisah per repo+branch, jadi
        salah isi CONFIG.Repo tidak bisa lagi merusak cache repo yang benar.
]]

local CONFIG = {
    Repo = "muhammadrisky45670-stack/Axium",
    Branch = "main",
    SubPath = "", -- file ada di root repo
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
-- HTTP
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

--========================================
-- CACHE
--========================================

local function cachePath(path)
    -- ikut repo + branch + subpath, supaya repo salah tidak menimpa cache repo benar
    local scope = (CONFIG.Repo .. "_" .. tostring(CONFIG.Branch) .. "_" .. tostring(CONFIG.SubPath or ""))
        :gsub("[^%w]", "_")
    return CONFIG.CacheFolder .. "/" .. scope .. "__" .. (path:gsub("[/\\]", "_")) .. ".cache"
end

local function deleteCache(path)
    pcall(function()
        if typeof(isfile) == "function" and typeof(delfile) == "function" then
            local file = cachePath(path)
            if isfile(file) then delfile(file) end
        end
    end)
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

-- buang cache lama (format sebelum repo ikut di nama file), karena bisa berisi
-- halaman error dari percobaan sebelumnya
pcall(function()
    if typeof(isfile) ~= "function" or typeof(delfile) ~= "function" then return end
    local legacy = {
        "main.lua.cache",
        "loader.lua.cache",
        "lib_windui.lua.cache",
        "lib_dex.lua.cache",
        "lib_cobalt.lua.cache",
        "lib_fluent.lua.cache",
    }
    for _, name in ipairs(legacy) do
        local file = CONFIG.CacheFolder .. "/" .. name
        if isfile(file) then delfile(file) end
    end
end)

function getgenv().AxiumClearCache()
    pcall(function()
        for _, name in ipairs({ "main.lua", "loader.lua", "lib/windui.lua", "lib/dex.lua", "lib/cobalt.lua", "lib/fluent.lua", "lib/fluent_savemanager.lua", "lib/fluent_interfacemanager.lua" }) do
            deleteCache(name)
        end
    end)
end

--========================================
-- FETCH (validasi: harus bisa dikompilasi)
--========================================

local function fetchSource(path, force)
    if not force then
        local cached = readCache(path)
        if cached and #cached > 0 then
            local chunk = loadstring(cached)
            if chunk then
                return cached, "cache", chunk
            end
            -- cache rusak / berisi halaman error: hapus, ambil ulang dari internet
            deleteCache(path)
        end
    end

    local relative = path
    if CONFIG.SubPath and CONFIG.SubPath ~= "" then
        relative = CONFIG.SubPath:gsub("/+$", "") .. "/" .. path
    end

    local problems = {}
    for _, template in ipairs(CONFIG.Mirrors) do
        local url = string.format(template, CONFIG.Repo, CONFIG.Branch, relative)
        local ok, body = pcall(httpGet, url)

        if ok and typeof(body) == "string" and #body > 0 and not body:find("404: Not Found", 1, true) then
            local chunk, compileError = loadstring(body)
            if chunk then
                writeCache(path, body)
                return body, url, chunk
            end
            problems[#problems + 1] = url .. "  ->  " .. tostring(compileError)
        else
            problems[#problems + 1] = url .. "  ->  " .. tostring(ok and "body kosong / 404" or body)
        end
    end

    error(
        "Axium loader: tidak ada mirror yang mengembalikan Lua valid untuk '" .. path .. "'\n"
        .. table.concat(problems, "\n"),
        0
    )
end

getgenv().AxiumFetch = fetchSource

--========================================
-- RUN
--========================================

if getgenv().AxiumLoaded then
    warn("[Axium] Sudah pernah dimuat di sesi ini. Execute ulang setelah reload UI.")
end

local source, origin, chunk = fetchSource(CONFIG.Entry)
if not chunk then chunk = loadstring(source) end
if not chunk then
    error("Axium loader: " .. CONFIG.Entry .. " tidak bisa dikompilasi.", 0)
end

getgenv().AxiumLoaded = true
getgenv().AxiumOrigin = origin
return chunk()
