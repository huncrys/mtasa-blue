-- Add buildactions to path
premake.path = premake.path..";utils/buildactions"
require "compose_files"
require "install_data"
require "install_resources"
require "install_cef"
require "install_unifont"
require "install_discord"

-- Set CI Build global
local ci = os.getenv("CI")
if ci and ci:lower() == "true" then
	CI_BUILD = true
else
	CI_BUILD = false
end
GLIBC_COMPAT = os.getenv("GLIBC_COMPAT") == "true"
MTA_MAETRO = os.getenv("MTA_MAETRO") == "true"

newoption {
	trigger     = "gccprefix",
	value       = "PREFIX",
	description = "Prefix to be prepended to commands used by the GCC toolchain (for cross-building)",
}

newoption {
	trigger     = "lua",
	value       = "VM",
	description = "Lua VM the server scripting runs on (default: jit; forced to stock on Windows)",
	allowed     = {
		{ "jit",   "LuaJIT 2.1" },
		{ "stock", "MTA-patched Lua 5.1 (upstream)" },
	},
}

newoption {
	trigger     = "stock",
	description = "Build the stock upstream flavor: --lua defaults to stock and all --fork-* toggles to off (explicit values still win)",
}

newoption {
	trigger     = "function-acl",
	value       = "on|off",
	description = "Enforce acl.xml function.* rights on script calls (default: on). Applies to both Lua VMs; --stock does not affect it",
	allowed     = { { "on" }, { "off" } },
}

newoption {
	trigger     = "fork-hidden-commands",
	value       = "on|off",
	description = "Remove built-in account/chat console commands (msg, nick, login, ...) (default: on, off with --stock)",
	allowed     = { { "on" }, { "off" } },
}

newoption {
	trigger     = "fork-open-http-login",
	value       = "on|off",
	description = "Skip the serial/IP check on HTTP logins (default: on, off with --stock)",
	allowed     = { { "on" }, { "off" } },
}

newoption {
	trigger     = "fork-raised-maxplayers",
	value       = "on|off",
	description = "Let setMaxPlayers raise the player limit up to MAX_PLAYER_COUNT (default: on, off with --stock)",
	allowed     = { { "on" }, { "off" } },
}

newoption {
	trigger     = "fork-setservername",
	value       = "on|off",
	description = "Add the setServerName scripting function (default: on, off with --stock)",
	allowed     = { { "on" }, { "off" } },
}

-- Resolve the Lua VM and fork feature toggles into globals consumed by
-- Server/mods/deathmatch/premake5.lua and the vendor include list below.
local stock = _OPTIONS["stock"] ~= nil

LUA_VM = _OPTIONS["lua"] or (stock and "stock" or "jit")
if os.target() == "windows" and LUA_VM ~= "stock" then
	print("Warning: LuaJIT is not supported on Windows targets, forcing --lua=stock")
	LUA_VM = "stock"
end

local function forkFeature(trigger)
	local value = _OPTIONS[trigger]
	if value == nil then
		return not stock
	end
	return value == "on"
end

FORK_DEFINES = {}
if LUA_VM == "jit" then
	table.insert(FORK_DEFINES, "MTA_FORK_LUAJIT")
end
-- Opt out only, and deliberately not tied to forkFeature: enforcing acl.xml function
-- rights is upstream behavior, so --stock must not switch it off. The define states
-- the unsafe case so that a build with no defines at all still enforces.
if _OPTIONS["function-acl"] == "off" then
	print("Warning: acl.xml function rights will not be enforced (--function-acl=off)")
	table.insert(FORK_DEFINES, "MTA_NO_FUNCTION_ACL")
elseif LUA_VM == "jit" then
	-- The patched stock VM enforces from its pre call hook. LuaJIT has no such hook,
	-- so it enforces through LUAJIT_MODE_WRAPCFUNC instead.
	table.insert(FORK_DEFINES, "MTA_FUNCTION_ACL_WRAPPER")
end
if forkFeature("fork-hidden-commands") then
	table.insert(FORK_DEFINES, "MTA_FORK_HIDDEN_COMMANDS")
end
if forkFeature("fork-open-http-login") then
	table.insert(FORK_DEFINES, "MTA_FORK_OPEN_HTTP_LOGIN")
end
if forkFeature("fork-raised-maxplayers") then
	table.insert(FORK_DEFINES, "MTA_FORK_RAISED_MAXPLAYERS")
end
if forkFeature("fork-setservername") then
	table.insert(FORK_DEFINES, "MTA_FORK_SETSERVERNAME")
end

workspace "MTASA"
	configurations {"Debug", "Release", "Nightly"}

	if os.host() == "macosx" then
		platforms { "x64", "arm64" }
	elseif os.host() == "windows" then
		platforms { "x86", "x64", "arm64" }
	else
		platforms { "x86", "x64", "arm", "arm64" }
	end

	if _OPTIONS["gccprefix"] then
		gccprefix(_OPTIONS["gccprefix"])
	end

	targetprefix ""

	location "Build"
	startproject "Client Launcher"

	cppdialect "C++17"
	characterset "MBCS"
	pic "On"
	symbols "On"
	flags "MultiProcessorCompile"

	dxdir = os.getenv("DXSDK_DIR") or ""
	includedirs {
		"vendor",
	}

	defines {
		"_CRT_SECURE_NO_WARNINGS",
		"_SCL_SECURE_NO_WARNINGS",
		"_CRT_NONSTDC_NO_DEPRECATE",
		"NOMINMAX",
		"_TIMESPEC_DEFINED"
	}

	if MTA_MAETRO then
		defines { "MTA_MAETRO" }
	end

	-- Helper function for output path
	buildpath = function(p) return "%{wks.location}/../Bin/"..p.."/" end
	copy = function(p) return "{COPY} %{cfg.buildtarget.abspath} \"%{wks.location}../Bin/"..p.."/\"" end

	if GLIBC_COMPAT then
		filter { "system:linux", "platforms:x86 or x64" }
			includedirs "/compat"
			linkoptions "-static-libstdc++ -static-libgcc"
			forceincludes  { "glibc_version.h" }
		filter { "system:linux", "platforms:x86" }
			libdirs { "/compat/x86" }
		filter { "system:linux", "platforms:x64" }
			libdirs { "/compat/x64" }
	end

	filter "platforms:x86"
		architecture "x86"
	filter "platforms:x64"
		architecture "x86_64"
	filter "platforms:arm"
		architecture "ARM"
	filter "platforms:arm64"
		architecture "ARM64"

	filter "configurations:Debug"
		defines { "MTA_DEBUG" }
		targetsuffix "_d"

	filter "configurations:Release"
		defines { "MTA_RELEASE" }

	filter "configurations:Nightly"
		defines { "MTA_NIGHTLY" }

	filter "configurations:Release or configurations:Nightly"
		optimize "Speed"	-- "On"=MS:/Ox GCC:/O2  "Speed"=MS:/O2 GCC:/O3  "Full"=MS:/Ox GCC:/O3

	if CI_BUILD then
		filter {}
			defines { "CI_BUILD=1" }

		filter { "system:linux" }
			linkoptions { "-s" }
	else
		filter "system:windows"
			defaultplatform "x86"
	end

	filter { "system:macosx", "platforms:arm64" }
		includedirs { "/opt/homebrew/include" }
		libdirs { "/opt/homebrew/lib" }

	filter {"system:windows", "configurations:Nightly", "kind:not StaticLib"}
		symbolspath "$(SolutionDir)Symbols\\$(Configuration)_$(Platform)\\$(ProjectName).pdb"

	filter "system:windows"
		toolset "v143"
		preferredtoolarchitecture "x86_64"
		staticruntime "On"
		defines { "WIN32", "_WIN32", "_WIN32_WINNT=0x601", "_MSC_PLATFORM_TOOLSET=$(PlatformToolsetVersion)" }
		buildoptions { "/Zc:__cplusplus" }
		includedirs {
			path.join(dxdir, "Include")
		}
		libdirs {
			path.join(dxdir, "Lib/x86")
		}

	filter {"system:windows", "configurations:Debug"}
		runtime "Release" -- Always use Release runtime
		defines { "DEBUG" } -- Using DEBUG as _DEBUG is not available with /MT

	filter { "system:linux or macosx", "configurations:not Debug" }
		buildoptions { "-fvisibility=hidden" }

	filter { "system:linux or macosx", "configurations:not Debug", "files:*.cpp" }
		buildoptions { "-fvisibility-inlines-hidden" }

	filter { "system:linux", "platforms:x86 or x64" }
		vectorextensions "SSE2"

	-- Only build the client on Windows
	if os.target() == "windows" then
		group "Client"
		include "Client/ceflauncher"
		include "Client/ceflauncher_DLL"
		include "Client/cefweb"
		include "Client/core"
		include "Client/game_sa"
		include "Client/sdk"
		include "Client/gui"
		include "Client/launch"
		include "Client/loader"
		include "Client/loader-proxy"
		include "Client/multiplayer_sa"
		include "Client/mods/deathmatch"

		group "Client/CEGUI"
		include "vendor/cegui-0.4.0-custom/src/renderers/directx9GUIRenderer"
		include "vendor/cegui-0.4.0-custom/WidgetSets/Falagard"
		include "vendor/cegui-0.4.0-custom"

		group "Vendor"
		include "vendor/portaudio"
		include "vendor/cef3"
		include "vendor/discord-rpc"
		include "vendor/freetype"
		include "vendor/jpeg-9f"
		include "vendor/ksignals"
		include "vendor/libpng"
		include "vendor/tinygettext"
		include "vendor/pthreads"
		include "vendor/libspeex"
		include "vendor/detours"
		include "vendor/lunasvg"
	end

	filter {}
		group "Server"
		include "Server/core"
		include "Server/dbconmy"
		include "Server/launcher"
		include "Server/mods/deathmatch"
		include "Server/sdk"

		group "Shared"
		include "Shared"
		include "Shared/XML"

		group "Vendor"
		include "vendor/bcrypt"
		include "vendor/cryptopp"
		include "vendor/curl"
		include "vendor/ehs"
		include "vendor/google-breakpad"
		include "vendor/json-c"
		-- Only one of the two VMs is ever linked. vendor/lua also carries the
		-- Lua_Client project, but the client is Windows-only and LUA_VM is forced to
		-- stock there, so gating on the VM never starves the client build.
		if LUA_VM == "jit" then
			include "vendor/luajit"
		else
			include "vendor/lua"
		end
		include "vendor/mbedtls"
		include "vendor/pcre"
		include "vendor/pme"
		include "vendor/sqlite"
		include "vendor/tinyxml"
		include "vendor/unrar"
		include "vendor/zip"
		include "vendor/zlib"
		include "vendor/glob"
