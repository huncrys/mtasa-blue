local luajit_make = "@+${MAKE} -C ../vendor/luajit BUILDMODE=static XCFLAGS=-fPIC TARGET_T=libluajit.a"
if os.getenv("LUAJIT_CC") then
	luajit_make = luajit_make .. " CC=\"" .. os.getenv("LUAJIT_CC") .. "\""
end
if os.getenv("LUAJIT_HOST_CC") then
	luajit_make = luajit_make .. " HOST_CC=\"" .. os.getenv("LUAJIT_HOST_CC") .. "\""
end
if _OPTIONS["gccprefix"] then
	luajit_make = luajit_make .. " CROSS=\"" .. _OPTIONS["gccprefix"] .. "\""
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
