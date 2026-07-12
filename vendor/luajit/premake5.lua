-- Determine the bit-width a given target compiler triplet builds for, by
-- inspecting its name (e.g. "i686-linux-gnu-gcc-10" -> 32, "aarch64-linux-gnu-gcc-10" -> 64).
local function target_bits(cc)
	if cc:find("i686") or cc:find("i386") or cc:find("i586") then
		return 32
	elseif cc:find("x86_64") or cc:find("amd64") then
		return 64
	elseif cc:find("aarch64") or cc:find("arm64") then
		return 64
	elseif cc:find("arm") then
		return 32
	end
	return nil
end

-- The machine actually running this build (as opposed to BUILD_ARCHITECTURE,
-- the target LuaJIT is being cross-compiled for).
local function host_machine()
	local out = os.outputof("uname -m")
	if out then
		out = out:gsub("%s+", "")
	end
	return out
end

-- True if the first word of `candidate` resolves to an executable on PATH.
local function cc_available(candidate)
	local bin = candidate:match("^%S+")
	if not bin then
		return false
	end
	local out = os.outputof("command -v " .. bin .. " 2>/dev/null")
	return out ~= nil and out:gsub("%s+", "") ~= ""
end

local function pick_cc(candidates)
	for _, candidate in ipairs(candidates) do
		if cc_available(candidate) then
			return candidate
		end
	end
	return nil
end

-- minilua/buildvm are built and executed as part of LuaJIT's own build
-- process, so the host compiler must produce a binary that runs natively on
-- the machine doing the build, sized to the bit-width the target (LUAJIT_CC)
-- needs -- not necessarily the host's own native bit-width.
--
-- Prefer a dedicated cross-compiler package (e.g. i686-linux-gnu-gcc-N), but
-- fall back to the native gcc with -m32/-m64 for hosts that only have
-- gcc-multilib installed instead. There's no such multilib equivalent
-- between arm and aarch64 (different instruction sets), so those always
-- need a real cross-compiler.
local function default_host_cc(bits, gcc_version)
	local host = host_machine()
	if host == "x86_64" or host == "amd64" then
		if bits == 32 then
			return pick_cc {
				"i686-linux-gnu-gcc-" .. gcc_version .. " -m32",
				"i686-linux-gnu-gcc -m32",
				"gcc-" .. gcc_version .. " -m32",
				"gcc -m32",
			}
		else
			return pick_cc {
				"x86_64-linux-gnu-gcc-" .. gcc_version .. " -m64",
				"x86_64-linux-gnu-gcc -m64",
				"gcc-" .. gcc_version .. " -m64",
				"gcc -m64",
			}
		end
	elseif host == "aarch64" or host == "arm64" then
		if bits == 32 then
			return pick_cc {
				"arm-linux-gnueabihf-gcc-" .. gcc_version,
				"arm-linux-gnueabihf-gcc",
			}
		else
			return pick_cc {
				"aarch64-linux-gnu-gcc-" .. gcc_version,
				"aarch64-linux-gnu-gcc",
				"gcc-" .. gcc_version,
				"gcc",
			}
		end
	end
	return nil
end

local luajit_make = "@+${MAKE} -C ../vendor/luajit BUILDMODE=static XCFLAGS=-fPIC TARGET_T=libluajit.a"

-- LUAJIT_CC controls the compiler LuaJIT's build uses for its target objects
-- and for auto-detecting its own target architecture (it runs $(TARGET_CC)
-- -E lj_arch.h). Default it to the same cross compiler used for the rest of
-- the build (CC), so it doesn't fall back to the plain host gcc.
local luajit_cc = os.getenv("LUAJIT_CC") or os.getenv("CC")
if luajit_cc then
	luajit_make = luajit_make .. " CC=\"" .. luajit_cc .. "\""
end

local luajit_host_cc = os.getenv("LUAJIT_HOST_CC")
if not luajit_host_cc and os.host() == "linux" and luajit_cc then
	local bits = target_bits(luajit_cc)
	if bits then
		luajit_host_cc = default_host_cc(bits, os.getenv("GCC_VERSION") or "10")
	end
end
if luajit_host_cc then
	luajit_make = luajit_make .. " HOST_CC=\"" .. luajit_host_cc .. "\""
end

project "LuaJIT"
	kind "Makefile"

	buildcommands {
		luajit_make .. " clean",
		luajit_make
	}
	rebuildcommands {
		luajit_make .. " clean",
		luajit_make
	}
	cleancommands { luajit_make .. " clean" }
