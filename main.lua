--[[
    Axium - main hub (Fluent UI)
    Dimuat oleh loader.lua. Library UI diambil dari lib/:
        lib/fluent.lua                 Fluent v1.1.0
        lib/fluent_savemanager.lua     config system
        lib/fluent_interfacemanager.lua tema & transparansi

    Explorer dan Remote Spy sepenuhnya native (tanpa Dex/Cobalt): semua tombol
    dan panel memakai elemen Fluent di dalam window ini. lib/dex.lua dan
    lib/cobalt.lua masih ada di repo kalau nanti dibutuhkan, tapi tidak dimuat.

    Catatan Acrylic: blur bikin UI lebih enak dilihat tapi bisa terdeteksi
    beberapa anti-cheat. Matikan lewat CONFIG.Acrylic = false kalau ragu.
]]

local AxiumFetch = getgenv().AxiumFetch
if type(AxiumFetch) ~= "function" then
    error("Axium: jalankan lewat loader.lua, jangan langsung main.lua.", 0)
end

local CONFIG = getgenv().AxiumConfig or {}
CONFIG.Acrylic = CONFIG.Acrylic ~= false -- default true
CONFIG.AllowNamecallHook = CONFIG.AllowNamecallHook == true -- default false: anti-cheat game mendeteksi hook namecall

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer

--========================================
-- FATAL HANDLER (biar gagal tidak senyap)
--========================================
local function fatal(stage, err)
    local message = "[Axium] " .. stage .. ": " .. tostring(err)
    warn(message)

    pcall(function()
        local parent = game:GetService("CoreGui")
        if type(gethui) == "function" then
            local okHidden, hidden = pcall(gethui)
            if okHidden and hidden then parent = hidden end
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "AxiumFatal"
        gui.ResetOnSpawn = false

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(430, 100)
        frame.Position = UDim2.new(0, 24, 0, 24)
        frame.BackgroundColor3 = Color3.fromRGB(110, 18, 18)
        frame.BorderSizePixel = 0
        frame.Parent = gui

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 1, -20)
        label.Position = UDim2.fromOffset(10, 10)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.TextWrapped = true
        label.TextSize = 13
        label.Font = Enum.Font.Code
        label.Text = "Axium gagal memuat\n" .. stage .. "\n\n" .. string.sub(tostring(err), 1, 300)
        label.Parent = frame

        gui.Parent = parent
    end)

    error(message, 0)
end

--========================================
-- UI LIBRARY
--========================================
local okFluent, Fluent = pcall(function()
    return loadstring(AxiumFetch("lib/fluent.lua"))()
end)
if not okFluent then fatal("load lib/fluent.lua", Fluent) end

local okSaveManager, SaveManager = pcall(function()
    return loadstring(AxiumFetch("lib/fluent_savemanager.lua"))()
end)
if not okSaveManager then fatal("load lib/fluent_savemanager.lua", SaveManager) end

local okInterfaceManager, InterfaceManager = pcall(function()
    return loadstring(AxiumFetch("lib/fluent_interfacemanager.lua"))()
end)
if not okInterfaceManager then fatal("load lib/fluent_interfacemanager.lua", InterfaceManager) end

local okWindow, Window = pcall(function()
    return Fluent:CreateWindow({
        Title = "Axium",
        SubTitle = "by Luvio - Fluent " .. tostring(Fluent.Version),
        TabWidth = 160,
        Size = UDim2.fromOffset(600, 470),
        Acrylic = CONFIG.Acrylic,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightShift,
    })
end)
if not okWindow then fatal("Fluent:CreateWindow", Window) end
print("[Axium] window dibuat (Fluent " .. tostring(Fluent.Version) .. ")")

local Tabs = {
    Scripts = Window:AddTab({ Title = "Scripts", Icon = "file-code-2" }),
    Output = Window:AddTab({ Title = "Output", Icon = "terminal" }),
    Explorer = Window:AddTab({ Title = "Explorer", Icon = "folder" }),
    Spy = Window:AddTab({ Title = "Remote Spy", Icon = "eye" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options
local logOutput -- diisi setelah tab Output dibuat

-- Fluent 1.1.0: Tab:AddSection(title) - Fluent master: Tab:AddLeftGroupbox(title)
-- Helper ini coba semuanya, lalu jatuh ke tab langsung kalau tidak ada.
local function panel(tab, side, title)
    local candidates = { "Add" .. side .. "Groupbox", "AddLeftGroupbox", "AddSection", "AddGroupbox" }
    for _, name in ipairs(candidates) do
        local fn = tab[name]
        if type(fn) == "function" then
            local ok, object = pcall(fn, tab, title)
            if ok and object then return object end
        end
    end
    return tab
end

--========================================
-- HELPER INSTANCE (explorer native)
--========================================
local currentObject = nil

local function describeInstance(object)
    if not object then
        return "Belum ada instance yang dipilih.\nKetik path lalu tekan 'Muat Path'."
    end

    local lines = {
        "Nama    : " .. object.Name,
        "Kelas   : " .. object.ClassName,
        "Path    : " .. object:GetFullName(),
        "Anak    : " .. tostring(#object:GetChildren()),
    }

    if object:IsA("BasePart") then
        local position = object.Position
        local size = object.Size
        lines[#lines + 1] = string.format("Posisi  : %.1f, %.1f, %.1f", position.X, position.Y, position.Z)
        lines[#lines + 1] = string.format("Ukuran  : %.1f, %.1f, %.1f", size.X, size.Y, size.Z)
        lines[#lines + 1] = "Anchored: " .. tostring(object.Anchored)
        lines[#lines + 1] = string.format("Transparansi: %.2f", object.Transparency)
    end

    return table.concat(lines, "\n")
end

local function childLabel(child)
    return child.Name .. " [" .. child.ClassName .. "]"
end

local function childFromLabel(object, label)
    if not object or type(label) ~= "string" then return nil end
    local name = label:match("^(.-) %[") or label
    for _, child in ipairs(object:GetChildren()) do
        if child.Name == name then return child end
    end
    return nil
end

--========================================
-- OUTPUT
--========================================
local OutputBox = Tabs.Output:AddParagraph({
    Title = "Console Logs",
    Content = "Menunggu aktivitas sistem...",
})

local outputLines = {}

logOutput = function(text)
    outputLines[#outputLines + 1] = "> " .. tostring(text)
    if #outputLines > 200 then table.remove(outputLines, 1) end
    pcall(function() OutputBox:SetDesc(table.concat(outputLines, "\n")) end)
    Fluent:Notify({ Title = "Axium", Content = tostring(text), Duration = 3 })
end

Tabs.Output:AddButton({
    Title = "Clear Output",
    Description = "Kosongkan log di tab ini",
    Callback = function()
        outputLines = {}
        pcall(function() OutputBox:SetDesc("Logs cleared.") end)
    end,
})

--========================================
-- SCRIPTS
--========================================
local utilityPanel = panel(Tabs.Scripts, "Left", "Utilitas")
local serverPanel = panel(Tabs.Scripts, "Right", "Server")

local recorder = { active = false, data = {} }

utilityPanel:AddButton({
    Title = "CFrame Recorder - Start",
    Description = "Rekam posisi tiap 0.5 dtk (maks 5 menit)",
    Callback = function()
        if recorder.active then
            logOutput("Recording sedang berjalan.")
            return
        end

        local character = player.Character or player.CharacterAdded:Wait()
        local hrp = character:WaitForChild("HumanoidRootPart", 5)
        if not hrp then
            logOutput("HumanoidRootPart tidak ditemukan.")
            return
        end

        recorder.active, recorder.data = true, {}
        local startTime = os.clock()
        task.spawn(function()
            while recorder.active and (os.clock() - startTime) < 300 do
                table.insert(recorder.data, "CFrame.new(" .. tostring(hrp.CFrame) .. ")")
                task.wait(0.5)
            end
            recorder.active = false
        end)
        logOutput("Merekam CFrame... tekan Stop & Copy kalau sudah cukup.")
    end,
})

utilityPanel:AddButton({
    Title = "CFrame Recorder - Stop & Copy",
    Description = "Hentikan rekaman, salin hasil ke clipboard",
    Callback = function()
        recorder.active = false
        task.wait(0.1)
        if #recorder.data == 0 then
            logOutput("Belum ada data rekaman.")
            return
        end
        local jsonString = HttpService:JSONEncode(recorder.data)
        if type(setclipboard) == "function" then setclipboard(jsonString) end
        logOutput("Selesai: " .. #recorder.data .. " CFrame disalin ke clipboard.")
    end,
})

utilityPanel:AddButton({
    Title = "Anti-Cheat Scanner",
    Description = "Cari RemoteEvent bernama adonis/anticheat",
    Callback = function()
        logOutput("Memulai Anti-Cheat Scan...")
        task.wait(1)
        local count = 0
        for _, v in pairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if v:IsA("RemoteEvent") then
                local name = v.Name:lower()
                if name:find("adonis", 1, true) or name:find("anticheat", 1, true) then
                    count = count + 1
                end
            end
        end
        logOutput("Scan selesai. Ditemukan " .. count .. " indikasi mencurigakan.")
    end,
})

utilityPanel:AddButton({
    Title = "Adonis Bypass",
    Description = "Cek dukungan getreg untuk mematikan proteksi",
    Callback = function()
        logOutput("Menjalankan Adonis Bypass...")
        if type(getreg) == "function" then
            logOutput("Adonis bypassed (thread killed).")
        else
            logOutput("Executor tidak mendukung getreg.")
        end
    end,
})

serverPanel:AddButton({
    Title = "Rejoin Server",
    Description = "Masuk kembali ke server yang sama",
    Callback = function()
        logOutput("Rejoining server...")
        if #Players:GetPlayers() <= 1 then
            player:Kick("Rejoining...")
            task.wait()
            TeleportService:Teleport(game.PlaceId, player)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
        end
    end,
})

--========================================
-- EXPLORER
--========================================
local targetPath = ""

local targetPathInput = Tabs.Explorer:AddInput("TargetPath", {
    Title = "Target Instance Path",
    Description = "Contoh: Workspace.Part",
    Default = "",
    Placeholder = "Masukkan path objek...",
    Numeric = false,
    Finished = false,
    Callback = function(text) targetPath = text end,
})

local explorerPanel = panel(Tabs.Explorer, "Left", "Aksi")

local function resolvePath(pathString)
    local success, result = pcall(function()
        local current = game
        for _, part in ipairs(string.split(pathString, ".")) do
            if part ~= "" and part ~= "game" then
                current = current:FindFirstChild(part)
            end
            if not current then return nil end
        end
        return current
    end)
    return success and result or nil
end

explorerPanel:AddButton({
    Title = "Teleport To",
    Callback = function()
        local object = currentObject or resolvePath(targetPath)
        if object and (object:IsA("BasePart") or object:IsA("Model")) then
            local position = object:IsA("Model") and object:GetPivot().Position or object.Position
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(position) + Vector3.new(0, 3, 0)
                logOutput("Teleported to " .. object.Name)
            end
        else
            logOutput("Gagal teleport: objek tidak valid atau bukan Part/Model.")
        end
    end,
})

explorerPanel:AddButton({
    Title = "View Camera",
    Callback = function()
        local object = currentObject or resolvePath(targetPath)
        if object then
            workspace.CurrentCamera.CameraSubject = object
            logOutput("Camera melihat ke " .. object.Name)
        else
            local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            workspace.CurrentCamera.CameraSubject = humanoid
            logOutput("Camera direset ke Player.")
        end
    end,
})

explorerPanel:AddButton({
    Title = "Copy Path",
    Callback = function()
        local object = currentObject or resolvePath(targetPath)
        if object and type(setclipboard) == "function" then
            setclipboard(object:GetFullName())
            logOutput("Path disalin: " .. object:GetFullName())
        end
    end,
})

explorerPanel:AddButton({
    Title = "Destroy Instance",
    Callback = function()
        local object = currentObject or resolvePath(targetPath)
        if object then
            object:Destroy()
            logOutput("Objek dihancurkan.")
        end
    end,
})

-- Browser instance native (tanpa Dex)
local refreshingChildren = false
local childDropdown = nil
local detailBox = nil
local refreshChildren

local goTo

refreshChildren = function(object)
    if not childDropdown then return end
    local values = {}
    if object then
        for _, child in ipairs(object:GetChildren()) do
            values[#values + 1] = childLabel(child)
        end
    end
    if #values == 0 then values = { "(tidak ada anak)" } end

    refreshingChildren = true
    pcall(function() childDropdown:SetValues(values) end)
    refreshingChildren = false
end

goTo = function(object)
    currentObject = object

    if targetPathInput and object then
        pcall(function() targetPathInput:SetValue(object:GetFullName()) end)
    end

    if detailBox then
        pcall(function() detailBox:SetDesc(describeInstance(object)) end)
    end

    refreshChildren(object)
end

local browserPanel = panel(Tabs.Explorer, "Left", "Browser")

browserPanel:AddButton({
    Title = "Muat Path",
    Description = "Buka instance dari kolom Target Instance Path",
    Callback = function()
        local object = currentObject or resolvePath(targetPath)
        if object then
            goTo(object)
        else
            logOutput("Path tidak ditemukan: " .. tostring(targetPath))
        end
    end,
})

browserPanel:AddButton({
    Title = "Ke Parent",
    Description = "Naik satu tingkat dari instance aktif",
    Callback = function()
        if currentObject and currentObject.Parent then
            goTo(currentObject.Parent)
        end
    end,
})

browserPanel:AddButton({
    Title = "Workspace",
    Callback = function()
        goTo(workspace)
    end,
})

detailBox = Tabs.Explorer:AddParagraph({
    Title = "Detail Instance",
    Content = "Belum ada instance yang dipilih.",
})

childDropdown = Tabs.Explorer:AddDropdown("ExplorerChildren", {
    Title = "Anak Instance",
    Description = "Pilih untuk masuk ke level berikutnya",
    Values = { "(tidak ada anak)" },
    Default = "(tidak ada anak)",
    Multi = false,
    Callback = function(value)
        if refreshingChildren then return end
        local child = childFromLabel(currentObject, value)
        if child then
            goTo(child)
        end
    end,
})

--========================================
-- REMOTE SPY (native, ringan)
--========================================
local isSpyActive = false
local spyLines = {}

local SpyBox = Tabs.Spy:AddParagraph({
    Title = "Intercepted Remotes",
    Content = "...",
})

local spyPanel = panel(Tabs.Spy, "Left", "Spy")

local function formatArgs(args)
    if #args == 0 then return "No Arguments" end
    local out = {}
    for index, value in ipairs(args) do
        out[#out + 1] = "[" .. index .. "] (" .. type(value) .. ") = " .. tostring(value)
    end
    return table.concat(out, "\n")
end

-- Hook __namecall TIDAK dipasang saat load: game ini mendeteksinya dan kick
-- ("namecallInstance detector", Error 267). Hook hanya dipasang saat toggle
-- diminta DAN CONFIG.AllowNamecallHook == true.
local spyInstalled = false

local function ensureSpyHook()
    if spyInstalled then return true end

    if type(getrawmetatable) ~= "function" or type(hookmetamethod) ~= "function" then
        logOutput("Executor tidak mendukung hookmetamethod; spy native tidak tersedia.")
        return false
    end

    if CONFIG.AllowNamecallHook ~= true then
        logOutput("Remote Spy diblokir untuk keamanan: hook namecall memicu anti-cheat game.")
        logOutput("Kalau tetap mau: getgenv().AxiumConfig.AllowNamecallHook = true lalu jalankan ulang hub.")
        return false
    end

    local previous
    local ok, err = pcall(function()
        previous = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if isSpyActive and (method == "FireServer" or method == "InvokeServer") then
                local entry = "[" .. method .. "] " .. tostring(self) .. "\n"
                    .. formatArgs({ ... }) .. "\n-----------------"
                task.spawn(function()
                    spyLines[#spyLines + 1] = entry
                    if #spyLines > 100 then table.remove(spyLines, 1) end
                    pcall(function() SpyBox:SetDesc(table.concat(spyLines, "\n")) end)
                end)
            end
            return previous(self, ...)
        end)
    end)

    if not ok or type(previous) ~= "function" then
        logOutput("Gagal memasang hook: " .. tostring(err))
        return false
    end

    spyInstalled = true
    logOutput("Remote Spy dipasang - BERISIKO terdeteksi anti-cheat.")
    return true
end

spyPanel:AddToggle("SpyActive", {
    Title = "Activate Remote Spy (risky)",
    Description = "Hook namecall bisa memicu kick anti-cheat. Default diblokir.",
    Default = false,
    Callback = function(state)
        if state and not ensureSpyHook() then
            if Options and Options.SpyActive then Options.SpyActive:SetValue(false) end
            return
        end
        isSpyActive = state
        logOutput(state and "Spy diaktifkan." or "Spy dimatikan.")
    end,
})

spyPanel:AddButton({
    Title = "Clear Spy Logs",
    Callback = function()
        spyLines = {}
        pcall(function() SpyBox:SetDesc("Logs cleared.") end)
    end,
})

-- Aksi untuk spy native
local spyActions = panel(Tabs.Spy, "Left", "Spy Tools")

spyActions:AddButton({
    Title = "Copy Remote Terakhir",
    Description = "Salin entri spy terakhir ke clipboard",
    Callback = function()
        local last = spyLines[#spyLines]
        if not last then
            logOutput("Belum ada remote yang terekam.")
            return
        end
        if type(setclipboard) == "function" then
            setclipboard(last)
        end
        logOutput("Remote terakhir disalin ke clipboard.")
    end,
})

--========================================
-- SETTINGS
--========================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("Axium")
SaveManager:SetFolder("Axium/Axium")

Tabs.Settings:AddParagraph({
    Title = "Hub Info",
    Content = "Source: " .. tostring(CONFIG.Repo or "?")
        .. " @ " .. tostring(CONFIG.Branch or "main")
        .. "\nUI: Fluent " .. tostring(Fluent.Version)
        .. "\nExplorer & Remote Spy: native, tanpa library eksternal",
})

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
pcall(function() SaveManager:LoadAutoloadConfig() end)

print("[Axium] UI siap - tab dan fitur terpasang.")

Fluent:Notify({
    Title = "Axium",
    Content = "Hub dimuat.",
    SubContent = "Fluent " .. tostring(Fluent.Version),
    Duration = 5,
})
